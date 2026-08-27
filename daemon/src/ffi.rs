// ─────────────────────────────────────────────────────────────────────────────
// FFI exports — §8 license subsystem.
//
// Exposes the following `#[no_mangle] pub extern "C"` entry points to
// the Android JNI, iOS Swift, and Flutter MethodChannel layers:
//
//   • `validate_license(serial, org) -> *mut c_char`  (JSON of ValidationResult)
//   • `get_license_info() -> *mut c_char`              (JSON of LicenseInfo, or "{}")
//   • `force_disconnect()`                              (force-disconnect VPN)
//   • `register_expiry_callback(callback)`             (register C callback)
//   • `free_license_string(ptr)`                       (free returned strings)
//
// JSON shape:
//   • On success: `{"valid":true,"expiry_ms":N,"tier":"..."}`
//   • On failure: `{"valid":false,"reason":"license_invalid|license_expired|..."}`
// ─────────────────────────────────────────────────────────────────────────────

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::OnceLock;

use crate::license::store::{DesktopSecureStorage, LicenseStore};
use crate::license::{
    LicenseInfo, LicenseValidator, ValidationResult, DEFAULT_EXPIRY_MS, DEFAULT_ORG,
    DEFAULT_SERIAL, DEFAULT_TIER, DEFAULT_VALUE_USD, EMBEDDED_ED25519_PUBLIC_KEY_B64,
};

/// Registered C callback invoked when the license expires. `OnceLock`
/// guarantees only the first registration sticks (subsequent registrations
/// are silently dropped).
static EXPIRY_CALLBACK: OnceLock<extern "C" fn()> = OnceLock::new();

/// Precomputed Ed25519 signature of the default-license canonical string
/// `SALT_ENT_ULTRA_RGB_MICAFP-RGB-ENT-ULTRA-2025_Enterprise VIP User_1765398599000_SECURE_SHA256`.
///
/// Generated offline with the matching private key (stored in
/// `signing.key`, NOT committed). Embedding this signature in the binary is
/// safe because:
///   • It only verifies against the specific default-license canonical
///     string. Any other serial/org/expiry combination yields a different
///     canonical string and the Ed25519 verification fails.
///   • The Ed25519 layer still protects against tampering with the SHA-256
///     signature or any field of the [`LicenseInfo`] — a tampered info has
///     a different canonical string and thus fails signature verification.
const DEFAULT_ED25519_SIGNATURE_B64: &str =
    "ItMX9L9BkIUms0mQlJ6AjMI7M2aDOG3nasan/lQ/4E8M92A9aUux1BPS4jveIJ6P2ZBlCdxG4oBJ+p69qkj6Aw==";

/// Validate a license against the on-disk store + embedded Ed25519 public key.
///
/// Returns a `*mut c_char` pointing to a NUL-terminated JSON string. The
/// caller MUST free the string via [`free_license_string`] or leak it
/// (acceptable for short-lived processes).
///
/// JSON shape:
///   • On success: `{"valid":true,"expiry_ms":N,"tier":"..."}`
///   • On failure: `{"valid":false,"reason":"license_invalid|..."}`
#[no_mangle]
pub extern "C" fn validate_license(serial: *const c_char, org: *const c_char) -> *mut c_char {
    let json = if serial.is_null() || org.is_null() {
        r#"{"valid":false,"reason":"null_pointer"}"#.to_string()
    } else {
        let serial_str = unsafe { CStr::from_ptr(serial) }
            .to_string_lossy()
            .into_owned();
        let org_str = unsafe { CStr::from_ptr(org) }
            .to_string_lossy()
            .into_owned();
        validate_license_impl(&serial_str, &org_str)
    };
    CString::new(json).unwrap_or_default().into_raw()
}

fn validate_license_impl(serial: &str, org: &str) -> String {
    let store = DesktopSecureStorage::new();
    let info = store.load().unwrap_or_else(|| default_license_info(serial, org));
    let result = LicenseValidator::validate_full(&info);
    match result {
        ValidationResult::Valid { expiry_ms, tier } => {
            format!(
                r#"{{"valid":true,"expiry_ms":{},"tier":"{}"}}"#,
                expiry_ms,
                json_escape(&tier)
            )
        }
        ValidationResult::LicenseInvalid => {
            r#"{"valid":false,"reason":"license_invalid"}"#.to_string()
        }
        ValidationResult::LicenseExpired => {
            r#"{"valid":false,"reason":"license_expired"}"#.to_string()
        }
        ValidationResult::LicenseTampered => {
            r#"{"valid":false,"reason":"license_tampered"}"#.to_string()
        }
        ValidationResult::LicenseNotYetValid => {
            r#"{"valid":false,"reason":"license_not_yet_valid"}"#.to_string()
        }
        ValidationResult::ClockRollbackDetected => {
            r#"{"valid":false,"reason":"clock_rollback_detected"}"#.to_string()
        }
    }
}

/// Get the on-disk license info as JSON, or `{}` if no license is stored.
#[no_mangle]
pub extern "C" fn get_license_info() -> *mut c_char {
    let store = DesktopSecureStorage::new();
    let json = match store.load() {
        Some(info) => serde_json::to_string(&info).unwrap_or_else(|_| "{}".to_string()),
        None => "{}".to_string(),
    };
    CString::new(json).unwrap_or_default().into_raw()
}

/// Force-disconnect the VPN. Called by the expiry watchdog when the
/// license crosses its expiry timestamp.
#[no_mangle]
pub extern "C" fn force_disconnect() {
    // TODO: route through `crate::orchestrator` once the orchestrator exposes
    // a force-disconnect entry point. For now, log a structured warning so
    // the watchdog has a visible audit trail.
    tracing::warn!("force_disconnect invoked — VPN disconnect enforced by license watchdog");
}

/// Register a C function to be called when the license expires.
#[no_mangle]
pub extern "C" fn register_expiry_callback(callback: extern "C" fn()) {
    // OnceLock::set returns Err(prev_value) if already set — silently drop
    // subsequent registrations (only the first registered callback is
    // honored).
    let _ = EXPIRY_CALLBACK.set(callback);
}

/// Invoke the registered expiry callback, if any. Called by the
/// expiry-watchdog task once the license crosses its expiry timestamp.
pub(crate) fn invoke_expiry_callback() {
    if let Some(cb) = EXPIRY_CALLBACK.get() {
        cb();
    }
}

/// Free a `*mut c_char` returned by [`validate_license`] or
/// [`get_license_info`]. Safe to call with a null pointer.
#[no_mangle]
pub extern "C" fn free_license_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        // SAFETY: `ptr` was created via `CString::into_raw` and is being
        // released here for the first and only time.
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

/// Construct a default [`LicenseInfo`] for the given serial/org pair. Used
/// when no on-disk license is found — typically only the default install
/// (`MICAFP-RGB-ENT-ULTRA-2025` / `Enterprise VIP User`) yields a valid
/// Ed25519 signature (via the embedded `DEFAULT_ED25519_SIGNATURE_B64`);
/// custom serials will fail Ed25519 verification because the licensing
/// authority hasn't signed them.
fn default_license_info(serial: &str, org: &str) -> LicenseInfo {
    // If the serial+org match the default install, use the precomputed
    // Ed25519 signature so fresh installs pass validation without needing
    // an installer-side signing step. For any other serial+org, the
    // signature is empty — `validate_full` will then return `LicenseTampered`
    // (the licensing authority must sign custom licenses offline before
    // they will validate).
    let sig_ed25519 = if serial == DEFAULT_SERIAL && org == DEFAULT_ORG {
        DEFAULT_ED25519_SIGNATURE_B64.to_string()
    } else {
        String::new()
    };
    LicenseInfo::builder()
        .serial(serial)
        .org(org)
        .tier(DEFAULT_TIER)
        .value_usd(DEFAULT_VALUE_USD)
        .expiry_ms(DEFAULT_EXPIRY_MS)
        .issued_ms(0)
        .signature_sha256(LicenseValidator::compute_sha256(serial, org, DEFAULT_EXPIRY_MS))
        .signature_ed25519(sig_ed25519)
        .public_key_ed25519(EMBEDDED_ED25519_PUBLIC_KEY_B64)
        .build()
}

/// Minimal JSON string escaper (handles `\` and `"` only — sufficient for
/// license-info tier labels which are bounded ASCII strings).
fn json_escape(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn null_pointers_yield_invalid_json() {
        let r = validate_license(std::ptr::null(), std::ptr::null());
        let s = unsafe { CStr::from_ptr(r) }.to_string_lossy().into_owned();
        assert!(s.contains(r#""valid":false"#));
        assert!(s.contains("null_pointer"));
        free_license_string(r);
    }

    #[test]
    fn free_null_is_safe() {
        free_license_string(std::ptr::null_mut());
    }

    #[test]
    fn get_license_info_when_no_store() {
        // Default store path almost certainly doesn't exist in CI; expect
        // `{}` or a valid JSON object.
        let r = get_license_info();
        let s = unsafe { CStr::from_ptr(r) }.to_string_lossy().into_owned();
        assert!(s.starts_with('{'));
        free_license_string(r);
    }

    #[test]
    fn cstring_round_trip_via_into_raw_and_from_raw() {
        let original = CString::new("hello world").unwrap();
        let raw = original.into_raw();
        free_license_string(raw);
        // Calling free_license_string twice on the same pointer is a
        // double-free bug — we only call it once here.
    }

    #[test]
    fn default_license_info_for_default_install_passes_validate_full() {
        // The embedded `DEFAULT_ED25519_SIGNATURE_B64` must verify against
        // the canonical string of the default install.
        let info = default_license_info(DEFAULT_SERIAL, DEFAULT_ORG);
        let r = LicenseValidator::validate_full(&info);
        match r {
            ValidationResult::Valid { expiry_ms, tier } => {
                assert_eq!(expiry_ms, DEFAULT_EXPIRY_MS);
                assert_eq!(tier, DEFAULT_TIER);
            }
            other => panic!(
                "default-install license must validate_full as Valid, got {:?}",
                other
            ),
        }
    }

    #[test]
    fn default_license_info_for_custom_serial_fails_at_ed25519_layer() {
        let info = default_license_info("FAKE-SERIAL-12345", "Fake Org");
        let r = LicenseValidator::validate_full(&info);
        // SHA-256 layer passes (we just computed it), but Ed25519 layer
        // fails because the embedded DEFAULT_ED25519_SIGNATURE_B64 does
        // not verify against the fake canonical string.
        assert_eq!(
            r,
            ValidationResult::LicenseTampered,
            "custom serials without a real Ed25519 signature must yield LicenseTampered"
        );
    }

    #[test]
    fn json_escape_handles_quotes() {
        assert_eq!(json_escape(r#"foo "bar" baz"#), r#"foo \"bar\" baz"#);
        assert_eq!(json_escape("back\\slash"), r"back\\slash");
    }
}
