// ─────────────────────────────────────────────────────────────────────────────
// LicenseValidator — §8 anti-tamper + Ed25519 + anti-rollback.
//
// Three-layer license integrity verification:
//   1. SHA-256 of canonical string
//      `SALT_ENT_ULTRA_RGB_{serial}_{org}_{expiryMs}_SECURE_SHA256`
//   2. Ed25519 signature of the same canonical string (verified against the
//      embedded public key — matching private key lives in `signing.key`,
//      which is NOT committed to the repo).
//   3. Monotonic-clock anti-rollback: the system clock must never go
//      backwards past the persisted high-water-mark.
//
// Default enterprise license (per §8):
//   • serial       = `MICAFP-RGB-ENT-ULTRA-2025`
//   • organization = `Enterprise VIP User`
//   • tier         = `Enterprise RGB Supreme`
//   • value_usd    = $999,999,999,999
//   • expiry       = Azar 19 1404 (Persian) = 2025-12-10T23:59:59+03:30 IRT
//                    = Unix ms 1_765_398_599_000
// ─────────────────────────────────────────────────────────────────────────────

use super::info::LicenseInfo;
use base64::Engine;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use sha2::{Digest, Sha256};

// ─── SALT marker ─────────────────────────────────────────────────────────────
/// Reference salt marker. The full canonical string format is:
/// `SALT_ENT_ULTRA_RGB_{serial}_{org}_{expiryMs}_SECURE_SHA256`
/// (this constant itself is the prefix+suffix — `${serial}_${org}_${expiryMs}`
/// is interpolated at runtime).
pub const SALT: &str = "SALT_ENT_ULTRA_RGB_..._SECURE_SHA256";

// ─── Default license constants (per §8) ──────────────────────────────────────
/// Default serial number: `MICAFP-RGB-ENT-ULTRA-2025`.
pub const DEFAULT_SERIAL: &str = "MICAFP-RGB-ENT-ULTRA-2025";
/// Default organization name.
pub const DEFAULT_ORG: &str = "Enterprise VIP User";
/// Default tier label.
pub const DEFAULT_TIER: &str = "Enterprise RGB Supreme";
/// Default license monetary value in USD: $999,999,999,999.
pub const DEFAULT_VALUE_USD: u64 = 999_999_999_999;
/// Default expiry: Azar 19 1404 (Persian) = 2025-12-10T23:59:59+03:30 IRT.
/// In Unix-epoch milliseconds: 1_765_398_599_000.
pub const DEFAULT_EXPIRY_MS: i64 = 1_765_398_599_000;

// ─── Embedded Ed25519 public key ─────────────────────────────────────────────
/// Embedded Ed25519 public key (32 bytes, base64). This is the second-layer
/// signature verification key. The matching private key lives in
/// `signing.key` (NOT committed to the repo — only used by the licensing
/// authority to sign new licenses offline).
///
/// Placeholder keypair generated for the §8 reference implementation. To
/// rotate the keypair:
///   1. Generate a new Ed25519 keypair.
///   2. Commit only the public key here.
///   3. Store the private key in `signing.key` (gitignored).
///   4. Re-sign every existing license with the new private key.
pub const EMBEDDED_ED25519_PUBLIC_KEY_B64: &str =
    "PmyPEdSc1PdRBLKRwCqKQR/Nr/gfI0/eil/MWoIL4X4=";

// ─── Expiry warning thresholds ─────────────────────────────────────────────
/// 24 hours in milliseconds.
pub const WARNING_24H_MS: i64 = 24 * 60 * 60 * 1000;
/// 1 hour in milliseconds.
pub const WARNING_1H_MS: i64 = 60 * 60 * 1000;
/// 5 minutes in milliseconds.
pub const WARNING_5M_MS: i64 = 5 * 60 * 1000;

// ─── Result enums ────────────────────────────────────────────────────────────
/// Outcome of a full license validation attempt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ValidationResult {
    /// License is cryptographically valid and not expired.
    Valid {
        /// Expiry timestamp (ms) echoed back to the caller.
        expiry_ms: i64,
        /// Tier label (e.g. `Enterprise RGB Supreme`).
        tier: String,
    },
    /// License fields are structurally invalid (empty serial, malformed
    /// organization, bad base64 in the public key, etc.).
    LicenseInvalid,
    /// License has expired (`expiry_ms < now`).
    LicenseExpired,
    /// SHA-256 mismatch OR Ed25519 signature mismatch — the license has
    /// been tampered with.
    LicenseTampered,
    /// License `issued_ms` is in the future (not yet activated).
    LicenseNotYetValid,
    /// System clock rolled backwards past the persisted high-water-mark.
    ClockRollbackDetected,
}

/// Expiry state classification (returned by [`LicenseValidator::check_expiry`]).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExpiryState {
    /// More than 24h remaining.
    Valid,
    /// ≤ 24h remaining.
    Warning24h,
    /// ≤ 1h remaining.
    Warning1h,
    /// ≤ 5 min remaining.
    Warning5m,
    /// Past the expiry timestamp.
    Expired,
}

/// Anti-rollback check outcome (returned by
/// [`LicenseValidator::check_anti_rollback`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AntiRollbackResult {
    /// Clock is at-or-ahead of the high-water-mark. Caller should persist
    /// the new high-water-mark = `high_water_mark_ms`.
    Ok {
        /// Updated high-water-mark (= the observed `now_ms`).
        high_water_mark_ms: i64,
    },
    /// Clock is behind the persisted high-water-mark — rollback detected.
    ClockRollbackDetected {
        /// Observed clock value.
        observed_ms: i64,
        /// Persisted high-water-mark that was violated.
        high_water_mark_ms: i64,
    },
}

// ─── Validator ───────────────────────────────────────────────────────────────
/// Stateless license validator. All methods are associated functions so
/// callers don't need to instantiate it; the `new()` ctor exists for
/// API-stability with prior scaffolds.
#[derive(Debug, Default, Clone)]
pub struct LicenseValidator;

impl LicenseValidator {
    /// Construct a new (stateless) validator.
    pub fn new() -> Self {
        Self
    }

    /// Recompute the SHA-256 of the canonical string
    /// `SALT_ENT_ULTRA_RGB_{serial}_{org}_{expiryMs}_SECURE_SHA256` and
    /// compare to the provided `signature_sha256` (hex).
    ///
    /// Returns:
    ///   • `Valid { expiry_ms, tier }` on match
    ///   • `LicenseInvalid` if `serial` or `org` is empty
    ///   • `LicenseTampered` on SHA-256 mismatch
    pub fn validate(
        serial: &str,
        org: &str,
        expiry_ms: i64,
        signature_sha256: &str,
    ) -> ValidationResult {
        if serial.is_empty() || org.is_empty() {
            return ValidationResult::LicenseInvalid;
        }
        let computed = Self::compute_sha256(serial, org, expiry_ms);
        if !ct_eq(computed.as_bytes(), signature_sha256.as_bytes()) {
            return ValidationResult::LicenseTampered;
        }
        ValidationResult::Valid {
            expiry_ms,
            tier: DEFAULT_TIER.to_string(),
        }
    }

    /// Full validation: SHA-256 + Ed25519 signature check + not-yet-valid
    /// check against the system clock.
    ///
    /// On success returns `Valid { expiry_ms, tier }`. Otherwise one of:
    /// `LicenseInvalid`, `LicenseTampered`, `LicenseNotYetValid`.
    pub fn validate_full(license: &LicenseInfo) -> ValidationResult {
        // Layer 1: SHA-256
        match Self::validate(
            &license.serial,
            &license.organization,
            license.expiry_ms,
            &license.signature_sha256,
        ) {
            ValidationResult::Valid { .. } => {}
            other => return other,
        }

        // Layer 2: Ed25519
        if license.signature_ed25519.is_empty() {
            // No second-layer signature on record — treat as tampered.
            return ValidationResult::LicenseTampered;
        }
        let pubkey_b64 = if license.public_key_ed25519.is_empty() {
            EMBEDDED_ED25519_PUBLIC_KEY_B64
        } else {
            &license.public_key_ed25519
        };
        let pubkey_bytes = match base64::engine::general_purpose::STANDARD.decode(pubkey_b64) {
            Ok(b) => b,
            Err(_) => return ValidationResult::LicenseInvalid,
        };
        if pubkey_bytes.len() != 32 {
            return ValidationResult::LicenseInvalid;
        }
        let mut pk_arr = [0u8; 32];
        pk_arr.copy_from_slice(&pubkey_bytes);
        let vk = match VerifyingKey::from_bytes(&pk_arr) {
            Ok(k) => k,
            Err(_) => return ValidationResult::LicenseInvalid,
        };
        let sig_bytes = match base64::engine::general_purpose::STANDARD
            .decode(&license.signature_ed25519)
        {
            Ok(b) => b,
            Err(_) => return ValidationResult::LicenseTampered,
        };
        if sig_bytes.len() != 64 {
            return ValidationResult::LicenseTampered;
        }
        let mut sig_arr = [0u8; 64];
        sig_arr.copy_from_slice(&sig_bytes);
        let sig = Signature::from_bytes(&sig_arr);
        let canonical = license.canonical();
        if vk.verify(canonical.as_bytes(), &sig).is_err() {
            return ValidationResult::LicenseTampered;
        }

        // Layer 3: not-yet-valid check (issued_ms in the future)
        let now_ms = chrono::Utc::now().timestamp_millis();
        if license.issued_ms > now_ms {
            return ValidationResult::LicenseNotYetValid;
        }

        ValidationResult::Valid {
            expiry_ms: license.expiry_ms,
            tier: license.tier.clone(),
        }
    }

    /// Classify the expiry state given the expiry timestamp and the current
    /// time. Pure function — does not consult the system clock.
    pub fn check_expiry(expiry_ms: i64, now_ms: i64) -> ExpiryState {
        if now_ms >= expiry_ms {
            return ExpiryState::Expired;
        }
        let remaining = expiry_ms - now_ms;
        if remaining <= WARNING_5M_MS {
            ExpiryState::Warning5m
        } else if remaining <= WARNING_1H_MS {
            ExpiryState::Warning1h
        } else if remaining <= WARNING_24H_MS {
            ExpiryState::Warning24h
        } else {
            ExpiryState::Valid
        }
    }

    /// Compare the system clock `now_ms` against the persisted
    /// `high_water_mark_ms`. If `now_ms < high_water_mark_ms`, the clock
    /// has been rolled back and the caller should refuse to honor the
    /// license. Otherwise the caller should update the high-water-mark to
    /// `now_ms`.
    pub fn check_anti_rollback(now_ms: i64, high_water_mark_ms: i64) -> AntiRollbackResult {
        if now_ms < high_water_mark_ms {
            AntiRollbackResult::ClockRollbackDetected {
                observed_ms: now_ms,
                high_water_mark_ms,
            }
        } else {
            AntiRollbackResult::Ok {
                high_water_mark_ms: now_ms,
            }
        }
    }

    /// Compute the SHA-256 hex digest of the canonical string
    /// `SALT_ENT_ULTRA_RGB_{serial}_{org}_{expiryMs}_SECURE_SHA256`.
    pub fn compute_sha256(serial: &str, org: &str, expiry_ms: i64) -> String {
        let canonical = format!(
            "SALT_ENT_ULTRA_RGB_{}_{}_{}_SECURE_SHA256",
            serial, org, expiry_ms
        );
        let mut h = Sha256::new();
        h.update(canonical.as_bytes());
        let digest = h.finalize();
        hex::encode(digest)
    }
}

/// Constant-time byte equality (mitigates timing side-channels on signature
/// comparison).
fn ct_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut acc: u8 = 0;
    for (x, y) in a.iter().zip(b.iter()) {
        acc |= x ^ y;
    }
    acc == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_of_default_license_matches_precomputed() {
        let h = LicenseValidator::compute_sha256(DEFAULT_SERIAL, DEFAULT_ORG, DEFAULT_EXPIRY_MS);
        assert_eq!(
            h,
            "8936d67817378f1a308cf147b41a1354894c8bd1c1b14d345965085daae2fa3c"
        );
        assert_eq!(h.len(), 64);
    }

    #[test]
    fn validate_rejects_empty_serial() {
        let r = LicenseValidator::validate("", DEFAULT_ORG, DEFAULT_EXPIRY_MS, "x");
        assert_eq!(r, ValidationResult::LicenseInvalid);
    }

    #[test]
    fn validate_detects_tampered_signature() {
        let real = LicenseValidator::compute_sha256(DEFAULT_SERIAL, DEFAULT_ORG, DEFAULT_EXPIRY_MS);
        let mut tampered: Vec<char> = real.chars().collect();
        tampered[0] = if tampered[0] == 'a' { 'b' } else { 'a' };
        let tampered_str: String = tampered.iter().collect();
        let r = LicenseValidator::validate(DEFAULT_SERIAL, DEFAULT_ORG, DEFAULT_EXPIRY_MS, &tampered_str);
        assert_eq!(r, ValidationResult::LicenseTampered);
    }

    #[test]
    fn check_expiry_thresholds() {
        // expired
        assert_eq!(LicenseValidator::check_expiry(0, 1), ExpiryState::Expired);
        // 5 min remaining → warning5m
        assert_eq!(
            LicenseValidator::check_expiry(WARNING_5M_MS, 0),
            ExpiryState::Warning5m
        );
        // 1h remaining → warning1h
        assert_eq!(
            LicenseValidator::check_expiry(WARNING_1H_MS, 0),
            ExpiryState::Warning1h
        );
        // 24h remaining → warning24h
        assert_eq!(
            LicenseValidator::check_expiry(WARNING_24H_MS, 0),
            ExpiryState::Warning24h
        );
        // > 24h remaining → valid
        assert_eq!(
            LicenseValidator::check_expiry(WARNING_24H_MS + 1, 0),
            ExpiryState::Valid
        );
    }

    #[test]
    fn check_anti_rollback_thresholds() {
        // Equal: ok
        assert!(matches!(
            LicenseValidator::check_anti_rollback(1000, 1000),
            AntiRollbackResult::Ok { high_water_mark_ms: 1000 }
        ));
        // Ahead: ok, new high-water-mark = now
        assert!(matches!(
            LicenseValidator::check_anti_rollback(2000, 1000),
            AntiRollbackResult::Ok { high_water_mark_ms: 2000 }
        ));
        // Behind: rollback detected
        assert!(matches!(
            LicenseValidator::check_anti_rollback(500, 1000),
            AntiRollbackResult::ClockRollbackDetected {
                observed_ms: 500,
                high_water_mark_ms: 1000
            }
        ));
    }
}
