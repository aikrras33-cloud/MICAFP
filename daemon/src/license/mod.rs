// ─────────────────────────────────────────────────────────────────────────────
// License subsystem — directive §8 Enterprise License & Serial Number System.
//
// Three-layer license integrity verification:
//   1. SHA-256 anti-tamper hash of the canonical string
//      `SALT_ENT_ULTRA_RGB_{serial}_{org}_{expiryMs}_SECURE_SHA256`
//   2. Ed25519 second-layer signature against the embedded public key
//      (matching private key lives in `signing.key`, NOT committed).
//   3. Monotonic-clock anti-rollback via a persisted high-water-mark.
//
// Default enterprise license (per §8):
//   • serial       = `MICAFP-RGB-ENT-ULTRA-2025`
//   • organization = `Enterprise VIP User`
//   • tier         = `Enterprise RGB Supreme`
//   • value_usd    = $999,999,999,999
//   • expiry       = Azar 19 1404 (Persian) = 2025-12-10T23:59:59+03:30 IRT
//                    = Unix ms 1_765_398_599_000
//
// Submodules:
//   • [`info`]          — [`LicenseInfo`] struct + builder + serde
//   • [`validator`]     — [`LicenseValidator`] (SHA-256 + Ed25519 + expiry + anti-rollback)
//   • [`store`]         — [`LicenseStore`] trait + Android/iOS/Desktop backends
//   • [`countdown`]     — [`CountdownTimer`] + Persian numeral support
//   • [`anti_rollback`] — [`AntiRollbackMonitor`] persisted high-water-mark monitor
//   • `validation_tests` — `#[cfg(test)]` 7-case validation suite (not a
//                          public module; collected by `cargo test`)
//
// Back-compat: the legacy `registry` submodule from Step 2's placeholder
// is preserved so any prior `license::LicenseRegistry` references still
// resolve.
// ─────────────────────────────────────────────────────────────────────────────

pub mod anti_rollback;
pub mod countdown;
pub mod info;
pub mod store;
pub mod validator;

#[cfg(test)]
mod validation_tests;

pub use anti_rollback::AntiRollbackMonitor;
pub use countdown::{to_persian_digits, CountdownSnapshot, CountdownTimer,
    BORDER_ANIM_1X, BORDER_ANIM_4X, BORDER_ANIM_8X, BORDER_ANIM_16X,
    MS_PER_DAY, MS_PER_HOUR, MS_PER_MIN, MS_PER_SEC};
pub use info::{LicenseInfo, LicenseInfoBuilder};
pub use store::{
    AndroidKeychainStore, DesktopSecureStorage, IosKeychainStore, LicenseStore,
};
pub use validator::{
    AntiRollbackResult, ExpiryState, LicenseValidator, ValidationResult,
    DEFAULT_EXPIRY_MS, DEFAULT_ORG, DEFAULT_SERIAL, DEFAULT_TIER, DEFAULT_VALUE_USD,
    EMBEDDED_ED25519_PUBLIC_KEY_B64, SALT, WARNING_24H_MS, WARNING_1H_MS, WARNING_5M_MS,
};

// ─── Legacy registry (preserved from Step 2 placeholder) ─────────────────────
pub mod registry;
pub use registry::LicenseRegistry;
