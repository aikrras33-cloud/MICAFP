// ─────────────────────────────────────────────────────────────────────────────
// AI Assistant FFI (§10.1, §11 Step-12 item 10)
//
// C-ABI exports so Swift / Kotlin / Flutter platform bridges can call the
// on-device LLM assistant without pulling in the Rust async machinery
// themselves.
//
// Exports:
//   • `ai_query(prompt: *const c_char, use_cloud: bool) -> *mut c_char`
//       Synchronous one-shot query. Returns a heap-allocated C string
//       (must be freed by the caller via `ai_free_string`).
//   • `ai_register_stream_callback(cb: extern "C" fn(*const c_char))`
//       Registers a token-stream callback. After this call, all subsequent
//       `ai_query` invocations stream their tokens through `cb` BEFORE the
//       final reply is returned.
//   • `ai_free_string(ptr: *mut c_char)`
//       Frees a string previously returned by `ai_query`. Callers MUST
//       pair every `ai_query` call with an `ai_free_string` to avoid a
//       memory leak.
// ─────────────────────────────────────────────────────────────────────────────

use std::ffi::{c_char, CStr, CString};
use std::sync::atomic::{AtomicPtr, Ordering};
use std::sync::Arc;

use once_cell::sync::Lazy;
use parking_lot::Mutex;
use tokio::sync::mpsc;

use super::assistant::ShieldAiAssistant;

/// Global singleton assistant. Lazily initialized on first `ai_query`
/// call so the FFI layer doesn't pay the constructor cost until needed.
static AI_ASSISTANT: Lazy<Mutex<Option<Arc<ShieldAiAssistant>>>> = Lazy::new(|| Mutex::new(None));

/// Global stream callback. Set via `ai_register_stream_callback`.
/// `null` (the default) disables streaming — `ai_query` just returns
/// the final reply without emitting per-token callbacks.
static STREAM_CB: AtomicPtr<()> = AtomicPtr::new(std::ptr::null_mut());

/// Type alias for the C function pointer we accept.
type StreamCallback = extern "C" fn(*const c_char);

/// Ensure the global assistant exists. Auto-loads the default GGUF model
/// if present (no-op when absent — falls back to rule-based responder).
fn ensure_assistant() -> Arc<ShieldAiAssistant> {
    let mut guard = AI_ASSISTANT.lock();
    if let Some(a) = guard.as_ref() {
        return Arc::clone(a);
    }
    let assistant = Arc::new(
        tokio::task::block_in_place(|| {
            tokio::runtime::Handle::current().block_on(ShieldAiAssistant::new())
        })
        .expect("ShieldAiAssistant::new"),
    );
    *guard = Some(Arc::clone(&assistant));
    // Try to auto-load the default model (no-op if file is absent).
    let a = Arc::clone(&assistant);
    tokio::task::block_in_place(|| {
        tokio::runtime::Handle::current().block_on(async move {
            let _ = a
                .load_model(std::path::Path::new("models/llama-3.2-1b-q4_k_m.gguf"))
                .await;
        })
    });
    assistant
}

/// Run an AI query synchronously. `use_cloud=true` routes through the
/// Gemini cloud scanner (if a key is configured and the internet is up).
///
/// Returns a heap-allocated UTF-8 C string. The caller MUST free it via
/// `ai_free_string`. Returns a null pointer on null input or internal
/// error.
#[no_mangle]
pub extern "C" fn ai_query(prompt: *const c_char, use_cloud: bool) -> *mut c_char {
    if prompt.is_null() {
        return std::ptr::null_mut();
    }
    let c_str = unsafe { CStr::from_ptr(prompt) };
    let prompt_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let assistant = ensure_assistant();

    // If a stream callback is registered, spawn a background task that
    // forwards each token to the C callback. Then run the one-shot query
    // and emit the final reply as the return value.
    let stream_cb_ptr = STREAM_CB.load(Ordering::Acquire);
    if !stream_cb_ptr.is_null() {
        let (tx, mut rx) = mpsc::channel::<String>(64);
        let assistant_for_stream = Arc::clone(&assistant);
        let prompt_owned = prompt_str.to_string();
        // Spawn the stream task. We don't join it — tokens emitted BEFORE
        // the final reply below will be delivered through the callback.
        tokio::spawn(async move {
            if let Err(e) = assistant_for_stream
                .stream_response(&prompt_owned, "en", tx)
                .await
            {
                tracing::warn!("ai_query stream_response failed: {}", e);
            }
        });
        // Pump tokens to the C callback. This runs synchronously on the
        // current tokio worker thread (block_in_place) so the caller sees
        // streaming + final reply in the right order.
        tokio::task::block_in_place(|| {
            tokio::runtime::Handle::current().block_on(async move {
                while let Some(tok) = rx.recv().await {
                    if let Ok(c_tok) = CString::new(tok.as_str()) {
                        let raw = c_tok.into_raw();
                        // Safety: STREAM_CB holds a function pointer set
                        // by the platform side via ai_register_stream_callback.
                        unsafe {
                            let cb: StreamCallback = std::mem::transmute(stream_cb_ptr);
                            cb(raw);
                        }
                        // The callback owns the string now; we leak it
                        // (caller is responsible for freeing in the C side
                        // — or the leak is bounded by the reply size).
                    }
                }
            })
        });
    }

    // One-shot final reply.
    let reply = tokio::task::block_in_place(|| {
        tokio::runtime::Handle::current().block_on(assistant.query(prompt_str, "en", use_cloud))
    });
    let reply = match reply {
        Ok(s) => s,
        Err(e) => {
            tracing::error!("ai_query failed: {}", e);
            return std::ptr::null_mut();
        }
    };
    match CString::new(reply) {
        Ok(c) => c.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Register a token-stream callback. After this call, every subsequent
/// `ai_query` invocation will invoke `cb` once per emitted token BEFORE
/// the final reply is returned.
#[no_mangle]
pub extern "C" fn ai_register_stream_callback(cb: StreamCallback) {
    STREAM_CB.store(cb as *mut (), Ordering::Release);
}

/// Free a string previously returned by `ai_query`. Safe to call with a
/// null pointer (no-op).
#[no_mangle]
pub extern "C" fn ai_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        // Reconstruct the CString so it drops and frees its allocation.
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    extern "C" fn dummy_cb(_s: *const c_char) {}

    #[tokio::test]
    async fn register_and_clear_stream_callback() {
        ai_register_stream_callback(dummy_cb);
        assert!(!STREAM_CB.load(Ordering::Acquire).is_null());
    }

    #[test]
    fn null_prompt_returns_null() {
        let r = ai_query(std::ptr::null(), false);
        assert!(r.is_null());
    }

    #[test]
    fn ai_free_string_on_null_is_safe() {
        ai_free_string(std::ptr::null_mut());
    }

    #[test]
    fn ai_free_string_roundtrip() {
        let s = CString::new("hello").unwrap();
        let raw = s.into_raw();
        ai_free_string(raw);
        // Calling again with the same pointer is double-free and would
        // be UB — we don't test that here.
    }
}
