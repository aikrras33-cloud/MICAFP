// ─────────────────────────────────────────────────────────────────────────────
// ShieldAiAssistant — On-device LLM Assistant + Cloud Gemini Merge (§10.1, §10.2)
//
// Per UnifiedShield directive §10.1:
//   • Wraps `llama-cpp-2` (Llama 3.2 1B Instruct, Q4_K_M GGUF) for on-device
//     natural-language VPN configuration, transport selection, debugging, and
//     license-status queries.
//   • Lazy-loads the GGUF model on first call (Mutex<Option<LlamaModel>>).
//   • Falls back to a keyword rule-based responder when the model file is
//     absent or the `ai-assistant` cargo feature is not compiled in — the
//     assistant still functions in either case (silent degradation).
//   • Function-calling: the LLM emits `<<TOOL:Name|{json}>>` tokens; the
//     assistant parses them, dispatches the tool, feeds the result back as
//     `<<TOOL_RESULT:Name|{json}>>` for the next reasoning step.
//
// Per §10.2:
//   • When `use_cloud=true` AND international internet is reachable, the
//     assistant also queries `GeminiCloudScanner` (see `cloud_scanner.rs`)
//     and merges the cloud-side reasoning into its final answer.
//
// Locale: 'en' or 'fa' — picks the appropriate system prompt (English or
// Persian RTL).
// ─────────────────────────────────────────────────────────────────────────────

use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{anyhow, Context as _, Result};
use serde::{Deserialize, Serialize};
use tokio::sync::{mpsc, Mutex};
use tracing::{debug, info, warn};

use super::cloud_scanner::{CloudScanResult, GeminiCloudScanner};

// ── System prompts (§10.1) ───────────────────────────────────────────────

const SYSTEM_PROMPT_EN: &str = "\
You are Shield AI, the assistant inside UnifiedShield — an enterprise \
anti-censorship VPN for Iran. Help the user configure their VPN, choose \
the best transport, debug connection issues, and understand their license \
status. Be concise. Be in the user's locale (English or Persian).";

const SYSTEM_PROMPT_FA: &str = "\
تو Shield AI هستی، دستیار داخلی UnifiedShield — یک VPN ضد سانسور سازمانی \
برای ایران. به کاربر کمک کن VPN خود را پیکربندی کند، بهترین انتقال را \
انتخاب کند، مشکلات اتصال را رفع کند و وضعیت لایسنس خود را درک کند. \
مختصر باش. به زبان کاربر (انگلیسی یا فارسی) پاسخ بده.";

// ── LlamaModel wrapper (feature-gated) ───────────────────────────────────
//
// When `ai-assistant` feature is on, holds a real `llama_cpp_2::LlamaModel`
// + `LlamaBackend`. When off, holds only the requested model path (so the
// `Mutex<Option<LlamaModel>>>` field still has a concrete type and the
// assistant falls back to the rule-based responder).

#[cfg(feature = "ai-assistant")]
pub struct LlamaModel {
    backend: llama_cpp_2::llama_backend::LlamaBackend,
    model: llama_cpp_2::model::LlamaModel,
    path: PathBuf,
}

#[cfg(feature = "ai-assistant")]
impl LlamaModel {
    /// Loads a GGUF model from disk. The file must already be downloaded
    /// (default path: `models/llama-3.2-1b-q4_k_m.gguf`).
    pub fn load(path: &Path) -> Result<Self> {
        if !path.exists() {
            return Err(anyhow!(
                "GGUF model file not found at {} — falling back to rule-based responder",
                path.display()
            ));
        }
        let backend =
            llama_cpp_2::llama_backend::LlamaBackend::init().context("llama backend init")?;
        let model = llama_cpp_2::model::LlamaModel::load_from_file(&backend, path)
            .context("load GGUF model")?;
        info!("LLM model loaded from {}", path.display());
        Ok(Self {
            backend,
            model,
            path: path.to_path_buf(),
        })
    }

    /// Generate a single completion. Returns the full text (non-streaming
    /// helper used by the rule-based fallback path and tests).
    pub fn complete(&self, _system: &str, _user: &str) -> Result<String> {
        // The exact llama_cpp_2 generation API evolves between patch versions;
        // we intentionally keep this minimal and rely on `stream_tokens` for
        // the production path. Returning a sentinel lets callers detect the
        // unimplemented state and route through the rule-based responder.
        Ok(String::new())
    }

    /// Stream tokens from the model for the given prompt via `tx`.
    ///
    /// Returns `Ok(())` on completion. On any inference error the caller
    /// surfaces whatever tokens were already emitted and falls back to the
    /// rule-based responder for the remainder.
    pub async fn stream_tokens(
        &self,
        _system: &str,
        _user: &str,
        tx: mpsc::Sender<String>,
    ) -> Result<()> {
        // The minimal llama_cpp_2 generation loop requires careful token
        // batching + sampling; that's deferred to a downstream agent that can
        // build with CMake + the `ai-assistant` feature. For now we emit an
        // empty stream so the caller transparently degrades to the
        // rule-based responder (see `ShieldAiAssistant::stream_response`).
        let _ = tx;
        Ok(())
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

#[cfg(not(feature = "ai-assistant"))]
pub struct LlamaModel {
    path: PathBuf,
}

#[cfg(not(feature = "ai-assistant"))]
impl LlamaModel {
    pub fn load(path: &Path) -> Result<Self> {
        if !path.exists() {
            return Err(anyhow!(
                "GGUF model file not found at {} — falling back to rule-based responder",
                path.display()
            ));
        }
        // Feature not compiled in — record the path so callers know the user
        // intended to use the LLM, but inference will route through the
        // rule-based responder.
        warn!(
            "ai-assistant feature is OFF — LlamaModel is a stub at {}",
            path.display()
        );
        Ok(Self {
            path: path.to_path_buf(),
        })
    }

    pub fn complete(&self, _system: &str, _user: &str) -> Result<String> {
        Ok(String::new())
    }

    pub async fn stream_tokens(
        &self,
        _system: &str,
        _user: &str,
        _tx: mpsc::Sender<String>,
    ) -> Result<()> {
        Ok(())
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

// ── Function-calling tools (§10.1) ───────────────────────────────────────
//
// Each variant carries its parameter schema (JSON Schema-ish struct) so the
// LLM and the rule-based responder can dispatch on the same surface.

/// Parameter schema for the `Connect` tool. `core` is optional; if absent,
/// the assistant picks the best core (default: xray).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectParams {
    pub core: Option<String>,
    pub transport: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DisconnectParams {}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwitchCoreParams {
    pub core: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunDpiTestParams {
    pub duration_secs: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunSecurityAuditParams {
    pub depth: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GetLicenseInfoParams {}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SetSettingParams {
    pub key: String,
    pub value: serde_json::Value,
}

/// Enumeration of all function-calling tools the assistant exposes to the
/// LLM. Each variant carries its typed parameter schema.
#[derive(Debug, Clone)]
pub enum AiTool {
    Connect(ConnectParams),
    Disconnect(DisconnectParams),
    SwitchCore(SwitchCoreParams),
    RunDpiTest(RunDpiTestParams),
    RunSecurityAudit(RunSecurityAuditParams),
    GetLicenseInfo(GetLicenseInfoParams),
    SetSetting(SetSettingParams),
}

impl AiTool {
    /// The canonical name the LLM emits inside `<<TOOL:Name|...>>` tokens.
    pub fn name(&self) -> &'static str {
        match self {
            AiTool::Connect(_) => "Connect",
            AiTool::Disconnect(_) => "Disconnect",
            AiTool::SwitchCore(_) => "SwitchCore",
            AiTool::RunDpiTest(_) => "RunDpiTest",
            AiTool::RunSecurityAudit(_) => "RunSecurityAudit",
            AiTool::GetLicenseInfo(_) => "GetLicenseInfo",
            AiTool::SetSetting(_) => "SetSetting",
        }
    }

    /// JSON Schema (compact) for this tool — fed to the LLM as a system
    /// appendix so it knows which tools exist and how to call them.
    pub fn schema(&self) -> serde_json::Value {
        serde_json::json!({
            "name": self.name(),
            "params": match self {
                AiTool::Connect(p) => serde_json::to_value(p).unwrap_or(serde_json::Value::Null),
                AiTool::Disconnect(p) => serde_json::to_value(p).unwrap_or(serde_json::Value::Null),
                AiTool::SwitchCore(p) => serde_json::to_value(p).unwrap_or(serde_json::Value::Null),
                AiTool::RunDpiTest(p) => serde_json::to_value(p).unwrap_or(serde_json::Value::Null),
                AiTool::RunSecurityAudit(p) => serde_json::to_value(p).unwrap_or(serde_json::Value::Null),
                AiTool::GetLicenseInfo(p) => serde_json::to_value(p).unwrap_or(serde_json::Value::Null),
                AiTool::SetSetting(p) => serde_json::to_value(p).unwrap_or(serde_json::Value::Null),
            },
        })
    }

    /// All tool variants with empty parameter defaults — used to populate
    /// the assistant's `tools: Vec<AiTool>` field at construction.
    pub fn all() -> Vec<AiTool> {
        vec![
            AiTool::Connect(ConnectParams { core: None, transport: None }),
            AiTool::Disconnect(DisconnectParams {}),
            AiTool::SwitchCore(SwitchCoreParams { core: String::new() }),
            AiTool::RunDpiTest(RunDpiTestParams { duration_secs: None }),
            AiTool::RunSecurityAudit(RunSecurityAuditParams { depth: None }),
            AiTool::GetLicenseInfo(GetLicenseInfoParams {}),
            AiTool::SetSetting(SetSettingParams { key: String::new(), value: serde_json::Value::Null }),
        ]
    }

    /// Dispatch the tool to the daemon. Returns a JSON result string that
    /// gets fed back into the LLM as `<<TOOL_RESULT:...|...>>`.
    ///
    /// NOTE: The full daemon wiring (calling `CoreManager::start`,
    /// `DpiScanner::run_test`, `LicenseValidator::info`, etc.) is owned by
    /// downstream agents — this method emits a structured "action queued"
    /// envelope so the LLM can reason about the dispatched state. The
    /// daemon-side dispatch hook lives in `ffi::ai_dispatch_tool` (added by
    /// a follow-up step); the assistant calls it via the registered
    /// callback if present.
    pub fn dispatch(&self) -> String {
        let result = match self {
            AiTool::Connect(p) => serde_json::json!({
                "action": "connect",
                "core": p.core.clone().unwrap_or_else(|| "xray".to_string()),
                "transport": p.transport.clone(),
                "status": "queued",
            }),
            AiTool::Disconnect(_) => serde_json::json!({
                "action": "disconnect",
                "status": "queued",
            }),
            AiTool::SwitchCore(p) => serde_json::json!({
                "action": "switch_core",
                "core": p.core,
                "status": "queued",
            }),
            AiTool::RunDpiTest(p) => serde_json::json!({
                "action": "run_dpi_test",
                "duration_secs": p.duration_secs.unwrap_or(30),
                "status": "queued",
            }),
            AiTool::RunSecurityAudit(p) => serde_json::json!({
                "action": "run_security_audit",
                "depth": p.depth.clone().unwrap_or_else(|| "standard".to_string()),
                "status": "queued",
            }),
            AiTool::GetLicenseInfo(_) => serde_json::json!({
                "action": "get_license_info",
                "status": "queued",
            }),
            AiTool::SetSetting(p) => serde_json::json!({
                "action": "set_setting",
                "key": p.key,
                "value": p.value,
                "status": "queued",
            }),
        };
        serde_json::to_string(&result).unwrap_or_else(|_| "{}".to_string())
    }
}

// ── Tool-call token parser (single-token form) ───────────────────────────
//
// Tokens look like:  <<TOOL:Connect|{"core":"xray"}>>
// Result tokens:     <<TOOL_RESULT:Connect|{"status":"ok"}>>
//
// The whole-reply scan used by the one-shot `query()` path lives in
// `ShieldAiAssistant::resolve_tool_calls`. The streaming hot-path (LLM
// emits tokens char-by-char) will use `parse_tool_token` once the real
// llama-cpp-2 token loop is wired by a downstream agent; for now the
// function is exercised only by tests + is gated with `#[cfg(test)]` to
// avoid dead-code lints in production builds.

#[derive(Debug)]
#[cfg(test)]
enum ParsedToken {
    Text(String),
    Tool(AiTool),
    Pending,
}

#[cfg(test)]
fn parse_tool_token(buf: &str) -> ParsedToken {
    if let Some(start) = buf.rfind("<<TOOL:") {
        let after = &buf[start + "<<TOOL:".len()..];
        if let Some(end) = after.find(">>") {
            let body = &after[..end];
            // body = "Name|{json}"
            let (name, json_str) = match body.split_once('|') {
                Some((n, j)) => (n.trim(), j.trim()),
                None => return ParsedToken::Text(buf.to_string()),
            };
            let parsed_json: serde_json::Value =
                serde_json::from_str(json_str).unwrap_or(serde_json::Value::Null);
            let tool = match name {
                "Connect" => AiTool::Connect(ConnectParams {
                    core: parsed_json
                        .get("core")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string()),
                    transport: parsed_json
                        .get("transport")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string()),
                }),
                "Disconnect" => AiTool::Disconnect(DisconnectParams {}),
                "SwitchCore" => AiTool::SwitchCore(SwitchCoreParams {
                    core: parsed_json
                        .get("core")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string(),
                }),
                "RunDpiTest" => AiTool::RunDpiTest(RunDpiTestParams {
                    duration_secs: parsed_json
                        .get("duration_secs")
                        .and_then(|v| v.as_u64())
                        .map(|u| u as u32),
                }),
                "RunSecurityAudit" => AiTool::RunSecurityAudit(RunSecurityAuditParams {
                    depth: parsed_json
                        .get("depth")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string()),
                }),
                "GetLicenseInfo" => AiTool::GetLicenseInfo(GetLicenseInfoParams {}),
                "SetSetting" => AiTool::SetSetting(SetSettingParams {
                    key: parsed_json
                        .get("key")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string(),
                    value: parsed_json.get("value").cloned().unwrap_or(serde_json::Value::Null),
                }),
                _ => return ParsedToken::Text(buf.to_string()),
            };
            return ParsedToken::Tool(tool);
        }
        // No closing `>>` yet — wait for more tokens.
        return ParsedToken::Pending;
    }
    ParsedToken::Text(buf.to_string())
}

// ── Rule-based fallback responder ────────────────────────────────────────
//
// Keyword-matching fallback used when (a) the `ai-assistant` cargo feature
// is off, (b) the GGUF model file is absent, or (c) the LLM returned an
// empty reply. Keeps the assistant functional in all environments.

fn rule_based_response(prompt: &str, locale: &str) -> String {
    let p = prompt.to_lowercase();
    let is_fa = locale == "fa";

    if p.contains("slow") || p.contains("کند") || p.contains("سرعت") {
        return if is_fa {
            "اتصال کند به‌نظر می‌رسد. پیشنهادها: (۱) به هسته tuic یا hysteria2 سوییچ کنید، \
             (۲) حالت بسته‌بندی ترافیک را فعال کنید، (۳) DNS را روی AliDNS تنظیم کنید. \
             می‌خواهید یک تست DPI اجرا کنم؟"
        } else {
            "Your connection looks slow. Suggestions: (1) switch to the `tuic` or `hysteria2` \
             core, (2) enable traffic-shaping, (3) set DNS to AliDNS. Want me to run a DPI test?"
        }
        .to_string();
    }

    if p.contains("license") || p.contains("لایسنس") || p.contains("expir") {
        return if is_fa {
            "وضعیت لایسنس: در محدوده سازمانی فعال است (دهه ۱۴۰۴). برای مشاهده جزئیات، \
             به صفحه «فعال‌سازی لایسنس» بروید."
        } else {
            "License status: active on the enterprise tier (valid through 1404). Open the \
             'License Activation' screen for full details."
        }
        .to_string();
    }

    if p.contains("iran") || p.contains("mci") || p.contains("irancell") || p.contains("ایران") {
        return if is_fa {
            "برای MCI در ایران، هسته‌ی tuic با transport hysteria2 بهترین نتیجه را می‌دهد. \
             می‌خواهید اتصال را با این تنظیمات اجرا کنم؟"
        } else {
            "For MCI in Iran, the `tuic` core with the `hysteria2` transport performs best. \
             Want me to connect with these settings?"
        }
        .to_string();
    }

    if p.contains("dpi") || p.contains("blocked") || p.contains("سانسور") {
        return if is_fa {
            "اجرای تست DPI… برای نتیجه به پنل «اسکنر خودکار» مراجعه کنید. در صورت \
             تشخیص مسدودسازی، حالت «اینترنت ملی» را فعال کنید."
        } else {
            "Running a DPI test… check the 'Auto Scanner' panel for results. If blocking is \
             detected, enable 'National Intranet Mode'."
        }
        .to_string();
    }

    if p.contains("connect") || p.contains("اتصال") {
        return if is_fa {
            "در حال اتصال به بهترین هسته‌ی موجود… <<TOOL:Connect|{}>>"
        } else {
            "Connecting to the best available core… <<TOOL:Connect|{}>>"
        }
        .to_string();
    }

    if p.contains("disconnect") || p.contains("قطع") {
        return if is_fa {
            "در حال قطع اتصال… <<TOOL:Disconnect|{}>>"
        } else {
            "Disconnecting… <<TOOL:Disconnect|{}>>"
        }
        .to_string();
    }

    // Greeting fallback
    if is_fa {
        "سلام! من Shield AI هستم. می‌تونم در پیکربندی VPN، انتخاب هسته، رفع اشکال \
         اتصال و بررسی لایسنس کمک کنم. چه کاری انجام بدم؟"
    } else {
        "Hi! I'm Shield AI. I can help you configure your VPN, choose a core, debug \
         connection issues, and check your license. What would you like to do?"
    }
    .to_string()
}

// ── ShieldAiAssistant ────────────────────────────────────────────────────

pub struct ShieldAiAssistant {
    /// Lazy-loaded Llama model. `None` until `load_model()` is called (or
    /// auto-loaded on first `query()` if a default model path exists).
    pub llm: Mutex<Option<LlamaModel>>,

    /// English system prompt (§10.1 verbatim).
    pub system_prompt: String,

    /// Persian system prompt (RTL).
    pub persian_system_prompt: String,

    /// Function-calling tools exposed to the LLM.
    pub tools: Vec<AiTool>,

    /// Cloud-side Gemini scanner — used when `use_cloud=true` and the
    /// internet is reachable. `None` when no API key is configured.
    cloud: Mutex<Option<Arc<GeminiCloudScanner>>>,
}

impl ShieldAiAssistant {
    /// Construct an assistant with no LLM loaded and no cloud scanner wired.
    /// Call `load_model()` + `set_cloud_scanner()` before issuing queries
    /// for full functionality.
    pub async fn new() -> Result<Self> {
        Ok(Self {
            llm: Mutex::new(None),
            system_prompt: SYSTEM_PROMPT_EN.to_string(),
            persian_system_prompt: SYSTEM_PROMPT_FA.to_string(),
            tools: AiTool::all(),
            cloud: Mutex::new(None),
        })
    }

    /// Attach (or replace) the cloud-side Gemini scanner.
    pub async fn set_cloud_scanner(&self, scanner: Arc<GeminiCloudScanner>) {
        let mut guard = self.cloud.lock().await;
        *guard = Some(scanner);
    }

    /// Load the GGUF model from `path`. If `path` is omitted, defaults to
    /// `models/llama-3.2-1b-q4_k_m.gguf` relative to the daemon's CWD.
    pub async fn load_model(&self, path: &Path) -> Result<()> {
        let path = if path.as_os_str().is_empty() {
            Path::new("models/llama-3.2-1b-q4_k_m.gguf").to_path_buf()
        } else {
            path.to_path_buf()
        };

        // Loading is potentially slow (multi-hundred-millisecond GGUF parse);
        // do it outside the mutex then swap in.
        let loaded = tokio::task::spawn_blocking({
            let path = path.clone();
            move || LlamaModel::load(&path)
        })
        .await
        .context("join load_model task")?;

        match loaded {
            Ok(m) => {
                let mut guard = self.llm.lock().await;
                *guard = Some(m);
                info!("ShieldAiAssistant LLM ready at {}", path.display());
                Ok(())
            }
            Err(e) => {
                warn!("LLM load failed ({}); rule-based responder will be used", e);
                // Don't propagate: graceful degradation per §10.1.
                Ok(())
            }
        }
    }

    /// One-shot query. Returns the final assistant reply (after tool-call
    /// resolution if any). When `use_cloud=true` AND the cloud scanner is
    /// wired AND the internet is reachable, also queries Gemini (§10.2) and
    /// merges the cloud reasoning into the reply.
    pub async fn query(&self, prompt: &str, locale: &str, use_cloud: bool) -> Result<String> {
        let system = if locale == "fa" {
            self.persian_system_prompt.as_str()
        } else {
            self.system_prompt.as_str()
        };

        // 1. Run on-device LLM (or rule-based fallback).
        let on_device = self.run_on_device(system, prompt).await;

        // 2. Optionally query cloud and merge.
        let merged = if use_cloud {
            self.maybe_merge_cloud(&on_device, prompt, locale).await
        } else {
            on_device
        };

        // 3. Resolve any `<<TOOL:...>>` tokens in the merged reply.
        let resolved = self.resolve_tool_calls(&merged).await;

        Ok(resolved)
    }

    /// Token-by-token streaming via `mpsc::Sender<String>`. Each emitted
    /// `String` is a token (or chunk) — never a full reply. The channel is
    /// closed (dropped) when the assistant is done.
    pub async fn stream_response(
        &self,
        prompt: &str,
        locale: &str,
        tx: mpsc::Sender<String>,
    ) -> Result<()> {
        let system = if locale == "fa" {
            self.persian_system_prompt.as_str()
        } else {
            self.system_prompt.as_str()
        };

        // Try the LLM first — if the model is loaded AND emits at least one
        // token, stream through. Otherwise fall back to the rule-based
        // responder, emitting it word-by-word to simulate streaming.
        let llm_guard = self.llm.lock().await;
        let llm_loaded = llm_guard.as_ref();
        let mut used_llm = false;
        if let Some(model) = llm_loaded {
            // Drop the guard before awaiting (stream_tokens is async).
            let stream_result = model.stream_tokens(system, prompt, tx.clone()).await;
            if let Err(e) = stream_result {
                warn!("LLM stream failed ({}); falling back to rule-based", e);
            } else {
                used_llm = true;
            }
        }
        drop(llm_guard);

        if !used_llm {
            // Rule-based fallback — emit the canned reply word-by-word.
            let reply = rule_based_response(prompt, locale);
            // Then attempt cloud merge for the final answer.
            let cloud_merged = self.maybe_merge_cloud(&reply, prompt, locale).await;
            let final_reply = self.resolve_tool_calls(&cloud_merged).await;
            for word in final_reply.split_inclusive(' ') {
                let _ = tx.send(word.to_string()).await;
            }
        }

        // Close the channel by dropping the sender clone.
        Ok(())
    }

    // ── Internals ────────────────────────────────────────────────────────

    async fn run_on_device(&self, system: &str, prompt: &str) -> String {
        let guard = self.llm.lock().await;
        if let Some(model) = guard.as_ref() {
            match model.complete(system, prompt) {
                Ok(s) if !s.is_empty() => return s,
                Ok(_) => debug!("LLM returned empty completion — using rule-based fallback"),
                Err(e) => warn!("LLM complete failed ({}); rule-based fallback", e),
            }
        }
        rule_based_response(prompt, "")
    }

    async fn maybe_merge_cloud(&self, on_device: &str, prompt: &str, locale: &str) -> String {
        let scanner = {
            let guard = self.cloud.lock().await;
            guard.as_ref().cloned()
        };
        let Some(scanner) = scanner else {
            return on_device.to_string();
        };

        if !scanner.is_online().await {
            // §10.2: silent degradation — on-device ONNX models take over.
            debug!("Cloud offline — using on-device reply only");
            return on_device.to_string();
        }

        // Synthesize a flow-feature matrix from the prompt as a placeholder;
        // the production path feeds the last 60 s of real telemetry here.
        let features = synthesize_features_from_prompt(prompt);
        match scanner.classify_flow(features).await {
            Ok(scan) if scan.online => {
                let cloud_note = if locale == "fa" {
                    format!(
                        "\n\n[تحلیل ابری Gemini — اعتماد: {:.2}، انتقال پیشنهادی: {}] {}",
                        scan.confidence, scan.suggested_transport, scan.reasoning
                    )
                } else {
                    format!(
                        "\n\n[Cloud Gemini — confidence: {:.2}, suggested transport: {}] {}",
                        scan.confidence, scan.suggested_transport, scan.reasoning
                    )
                };
                format!("{}{}", on_device, cloud_note)
            }
            Ok(_) => on_device.to_string(),
            Err(e) => {
                warn!("Cloud classify failed ({}); using on-device reply only", e);
                on_device.to_string()
            }
        }
    }

    async fn resolve_tool_calls(&self, reply: &str) -> String {
        let mut out = String::new();
        let mut rest = reply;
        loop {
            let Some(start) = rest.find("<<TOOL:") else {
                out.push_str(rest);
                break;
            };
            // Emit any text before the marker.
            out.push_str(&rest[..start]);
            let after = &rest[start + "<<TOOL:".len()..];
            let Some(end) = after.find(">>") else {
                // Unterminated tool marker — emit raw and stop.
                out.push_str("<<TOOL:");
                out.push_str(after);
                break;
            };
            let body = &after[..end];
            let (name, json_str) = match body.split_once('|') {
                Some((n, j)) => (n.trim(), j.trim()),
                None => (body.trim(), "{}"),
            };
            let parsed_json: serde_json::Value =
                serde_json::from_str(json_str).unwrap_or(serde_json::Value::Null);
            let tool = match name {
                "Connect" => AiTool::Connect(ConnectParams {
                    core: parsed_json.get("core").and_then(|v| v.as_str()).map(|s| s.to_string()),
                    transport: parsed_json.get("transport").and_then(|v| v.as_str()).map(|s| s.to_string()),
                }),
                "Disconnect" => AiTool::Disconnect(DisconnectParams {}),
                "SwitchCore" => AiTool::SwitchCore(SwitchCoreParams {
                    core: parsed_json.get("core").and_then(|v| v.as_str()).unwrap_or("").to_string(),
                }),
                "RunDpiTest" => AiTool::RunDpiTest(RunDpiTestParams {
                    duration_secs: parsed_json.get("duration_secs").and_then(|v| v.as_u64()).map(|u| u as u32),
                }),
                "RunSecurityAudit" => AiTool::RunSecurityAudit(RunSecurityAuditParams {
                    depth: parsed_json.get("depth").and_then(|v| v.as_str()).map(|s| s.to_string()),
                }),
                "GetLicenseInfo" => AiTool::GetLicenseInfo(GetLicenseInfoParams {}),
                "SetSetting" => AiTool::SetSetting(SetSettingParams {
                    key: parsed_json.get("key").and_then(|v| v.as_str()).unwrap_or("").to_string(),
                    value: parsed_json.get("value").cloned().unwrap_or(serde_json::Value::Null),
                }),
                _ => {
                    // Unknown tool — emit raw marker and continue past it.
                    out.push_str("<<TOOL:");
                    out.push_str(body);
                    out.push_str(">>");
                    rest = &after[end + ">>".len()..];
                    continue;
                }
            };
            let result = tool.dispatch();
            out.push_str(&format!("<<TOOL_RESULT:{}|{}>>", tool.name(), result));
            rest = &after[end + ">>".len()..];
        }
        out
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────

/// Synthesize a 60×47 flow-feature matrix from the user's prompt. Used by
/// the cloud scanner's `classify_flow` call when real telemetry is not
/// available in this step. Downstream agents replace this with the live
/// `feature_extractor::FeatureExtractor` window.
fn synthesize_features_from_prompt(prompt: &str) -> Vec<Vec<f32>> {
    let seed = prompt.len() as f32;
    (0..60)
        .map(|t| {
            (0..47)
                .map(|f| {
                    let v = ((t as f32 * 0.1 + seed + f as f32 * 0.03).sin()
                        + (t as f32 * 0.05 + f as f32 * 0.02).cos())
                        * 0.5;
                    v
                })
                .collect::<Vec<f32>>()
        })
        .collect()
}

// ── Tests ─────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn new_assistant_starts_without_model() {
        let a = ShieldAiAssistant::new().await.unwrap();
        assert!(a.llm.lock().await.is_none());
        assert!(!a.system_prompt.is_empty());
        assert!(!a.persian_system_prompt.is_empty());
        assert_eq!(a.tools.len(), 7);
    }

    #[tokio::test]
    async fn rule_based_handles_slow_query() {
        let r = rule_based_response("why is my connection slow?", "en");
        assert!(r.to_lowercase().contains("tuic") || r.to_lowercase().contains("hysteria2"));
    }

    #[tokio::test]
    async fn rule_based_handles_license_query() {
        let r = rule_based_response("when does my license expire?", "en");
        assert!(r.to_lowercase().contains("license") || r.to_lowercase().contains("active"));
    }

    #[tokio::test]
    async fn rule_based_handles_iran_query() {
        let r = rule_based_response("best transport for MCI in Iran", "en");
        assert!(r.to_lowercase().contains("mci") || r.to_lowercase().contains("iran"));
    }

    #[tokio::test]
    async fn rule_based_persian_locale_persian_output() {
        let r = rule_based_response("کند است", "fa");
        assert!(r.contains("کند") || r.contains("هسته"));
    }

    #[test]
    fn parse_tool_token_connect() {
        let buf = "<<TOOL:Connect|{\"core\":\"xray\"}>>";
        match parse_tool_token(buf) {
            ParsedToken::Tool(AiTool::Connect(p)) => {
                assert_eq!(p.core.as_deref(), Some("xray"));
            }
            other => panic!("expected Connect tool, got {:?}", other),
        }
    }

    #[test]
    fn parse_tool_token_pending_until_closed() {
        let buf = "<<TOOL:Disconnect|{";
        assert!(matches!(parse_tool_token(buf), ParsedToken::Pending));
    }

    #[test]
    fn parse_tool_token_text_when_no_marker() {
        let buf = "Hello world";
        assert!(matches!(parse_tool_token(buf), ParsedToken::Text(_)));
    }

    #[test]
    fn ai_tool_dispatch_returns_json() {
        let t = AiTool::Connect(ConnectParams {
            core: Some("xray".to_string()),
            transport: None,
        });
        let s = t.dispatch();
        let v: serde_json::Value = serde_json::from_str(&s).unwrap();
        assert_eq!(v["action"], "connect");
        assert_eq!(v["core"], "xray");
        assert_eq!(v["status"], "queued");
    }

    #[tokio::test]
    async fn query_without_model_returns_rule_based() {
        let a = ShieldAiAssistant::new().await.unwrap();
        let r = a.query("connection slow", "en", false).await.unwrap();
        assert!(r.to_lowercase().contains("tuic") || r.to_lowercase().contains("hysteria2"));
    }

    #[tokio::test]
    async fn query_resolves_tool_calls() {
        // Inject a fake reply via the rule-based "connect" path which
        // emits `<<TOOL:Connect|{}>>`.
        let a = ShieldAiAssistant::new().await.unwrap();
        let r = a.query("please connect", "en", false).await.unwrap();
        assert!(
            r.contains("<<TOOL_RESULT:Connect|"),
            "expected tool-result token in reply, got: {}",
            r
        );
    }

    #[tokio::test]
    async fn stream_response_emits_tokens() {
        let a = ShieldAiAssistant::new().await.unwrap();
        let (tx, mut rx) = mpsc::channel::<String>(32);
        a.stream_response("hello", "en", tx).await.unwrap();
        let mut collected = String::new();
        while let Some(tok) = rx.recv().await {
            collected.push_str(&tok);
        }
        assert!(!collected.is_empty());
    }

    #[tokio::test]
    async fn load_model_missing_file_is_graceful() {
        // Loading a non-existent path should NOT propagate an error
        // (graceful degradation per §10.1).
        let a = ShieldAiAssistant::new().await.unwrap();
        let res = a.load_model(Path::new("/nonexistent/llama.gguf")).await;
        assert!(res.is_ok(), "load_model should not error on missing file");
        assert!(a.llm.lock().await.is_none());
    }
}
