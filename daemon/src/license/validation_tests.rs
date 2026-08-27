// ─────────────────────────────────────────────────────────────────────────────
// 7-case validation test suite for the §8 license subsystem.
//
// Default license baseline (per §8):
//   • serial = `MICAFP-RGB-ENT-ULTRA-2025`
//   • org    = `Enterprise VIP User`
//   • expiry = 2025-12-10T23:59:59+03:30 IRT = 1_765_398_599_000 ms
//
// Test cases:
//   1. test_valid_license_passes
//   2. test_expired_license_fails
//   3. test_tampered_signature_fails
//   4. test_future_dated_license_fails
//   5. test_empty_serial_fails
//   6. test_recompute_sha256_consistency (10 000 iterations)
//   7. test_countdown_math_at_T_minus_24h_1h_5min_0
//
// The 100% Rust-side mirror of the Dart tests at
// `flutter_app/test/license_validation_test.dart`.
// ─────────────────────────────────────────────────────────────────────────────

#![cfg(test)]

use super::countdown::{CountdownTimer, MS_PER_HOUR, MS_PER_MIN, MS_PER_SEC};
use super::info::LicenseInfo;
use super::validator::{
    ExpiryState, LicenseValidator, ValidationResult, DEFAULT_EXPIRY_MS, DEFAULT_ORG,
    DEFAULT_SERIAL, DEFAULT_TIER, DEFAULT_VALUE_USD, EMBEDDED_ED25519_PUBLIC_KEY_B64,
};
use base64::Engine;
use ed25519_dalek::{Signer, SigningKey};

// Test-only private key matching `EMBEDDED_ED25519_PUBLIC_KEY_B64`. NOT
// compiled into release builds — present only during `cargo test`. The
// production matching private key lives in `signing.key` (not committed).
const TEST_ED25519_PRIVATE_KEY_B64: &str = "n8qwHUt6IuniMp20HEmyRbe4pfWCs0lee9t5xA+FhPw=";

/// Build a properly-signed test license with the given fields.
fn make_test_license(serial: &str, org: &str, expiry_ms: i64, issued_ms: i64) -> LicenseInfo {
    let sig_sha = LicenseValidator::compute_sha256(serial, org, expiry_ms);

    // Sign the canonical string with the test private key.
    let priv_bytes = base64::engine::general_purpose::STANDARD
        .decode(TEST_ED25519_PRIVATE_KEY_B64)
        .expect("test private key base64 decodes");
    assert_eq!(
        priv_bytes.len(),
        32,
        "test private key must be 32 bytes after base64 decode"
    );
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&priv_bytes);
    let sk = SigningKey::from_bytes(&arr);
    let canonical = format!(
        "SALT_ENT_ULTRA_RGB_{}_{}_{}_SECURE_SHA256",
        serial, org, expiry_ms
    );
    let sig = sk.sign(canonical.as_bytes());
    let sig_b64 = base64::engine::general_purpose::STANDARD.encode(sig.to_bytes());

    LicenseInfo::builder()
        .serial(serial)
        .org(org)
        .tier(DEFAULT_TIER)
        .value_usd(DEFAULT_VALUE_USD)
        .expiry_ms(expiry_ms)
        .issued_ms(issued_ms)
        .signature_sha256(sig_sha)
        .signature_ed25519(sig_b64)
        .public_key_ed25519(EMBEDDED_ED25519_PUBLIC_KEY_B64)
        .build()
}

// ─── Test 1 ─────────────────────────────────────────────────────────────────
#[test]
fn test_valid_license_passes() {
    let info = make_test_license(DEFAULT_SERIAL, DEFAULT_ORG, DEFAULT_EXPIRY_MS, 0);
    let r = LicenseValidator::validate_full(&info);
    match r {
        ValidationResult::Valid { expiry_ms, tier } => {
            assert_eq!(expiry_ms, DEFAULT_EXPIRY_MS);
            assert_eq!(tier, DEFAULT_TIER);
        }
        other => panic!("expected Valid, got {:?}", other),
    }
}

// ─── Test 2 ─────────────────────────────────────────────────────────────────
#[test]
fn test_expired_license_fails() {
    // License whose expiry is in the past (1970-01-01).
    let past_expiry = 0_i64;
    let info = make_test_license(DEFAULT_SERIAL, DEFAULT_ORG, past_expiry, 0);

    // The crypto is still valid; validate_full returns Valid.
    let r = LicenseValidator::validate_full(&info);
    assert!(
        matches!(r, ValidationResult::Valid { .. }),
        "validate_full should still pass crypto check for an expired-but-properly-signed license"
    );

    // The expiry classifier correctly flags it as Expired.
    let now_ms = chrono::Utc::now().timestamp_millis();
    let state = LicenseValidator::check_expiry(past_expiry, now_ms);
    assert_eq!(state, ExpiryState::Expired);
}

// ─── Test 3 ─────────────────────────────────────────────────────────────────
#[test]
fn test_tampered_signature_fails() {
    let mut info = make_test_license(DEFAULT_SERIAL, DEFAULT_ORG, DEFAULT_EXPIRY_MS, 0);
    // Flip one hex character of the SHA-256 signature.
    let orig = info.signature_sha256.clone();
    let mut tampered: Vec<char> = orig.chars().collect();
    let first = tampered[0];
    tampered[0] = if first == 'a' { 'b' } else { 'a' };
    info.signature_sha256 = tampered.iter().collect();

    let r = LicenseValidator::validate_full(&info);
    assert_eq!(
        r,
        ValidationResult::LicenseTampered,
        "tampered SHA-256 signature must yield LicenseTampered"
    );

    // Also test Ed25519 tampering: flip a char of the b64 ed25519 signature.
    let mut info2 = make_test_license(DEFAULT_SERIAL, DEFAULT_ORG, DEFAULT_EXPIRY_MS, 0);
    let orig2 = info2.signature_ed25519.clone();
    let mut tampered2: Vec<char> = orig2.chars().collect();
    if !tampered2.is_empty() {
        let first2 = tampered2[0];
        tampered2[0] = if first2 == 'A' { 'B' } else { 'A' };
    }
    info2.signature_ed25519 = tampered2.iter().collect();
    let r2 = LicenseValidator::validate_full(&info2);
    assert_eq!(
        r2,
        ValidationResult::LicenseTampered,
        "tampered Ed25519 signature must yield LicenseTampered"
    );
}

// ─── Test 4 ─────────────────────────────────────────────────────────────────
#[test]
fn test_future_dated_license_fails() {
    // issued_ms far in the future (year ~2286). validate_full consults the
    // system clock and rejects.
    let far_future_issued = 9_999_999_999_999_i64;
    let info = make_test_license(
        DEFAULT_SERIAL,
        DEFAULT_ORG,
        DEFAULT_EXPIRY_MS,
        far_future_issued,
    );
    let r = LicenseValidator::validate_full(&info);
    assert_eq!(
        r,
        ValidationResult::LicenseNotYetValid,
        "future-dated license must yield LicenseNotYetValid"
    );
}

// ─── Test 5 ─────────────────────────────────────────────────────────────────
#[test]
fn test_empty_serial_fails() {
    // Empty serial → LicenseInvalid
    let r = LicenseValidator::validate("", DEFAULT_ORG, DEFAULT_EXPIRY_MS, "anything");
    assert_eq!(
        r,
        ValidationResult::LicenseInvalid,
        "empty serial must yield LicenseInvalid"
    );

    // Same when invoked via validate_full on a LicenseInfo with empty serial.
    let info = LicenseInfo::builder()
        .serial("")
        .org(DEFAULT_ORG)
        .tier(DEFAULT_TIER)
        .value_usd(DEFAULT_VALUE_USD)
        .expiry_ms(DEFAULT_EXPIRY_MS)
        .issued_ms(0)
        .signature_sha256("deadbeef")
        .signature_ed25519("sig")
        .public_key_ed25519(EMBEDDED_ED25519_PUBLIC_KEY_B64)
        .build();
    let r = LicenseValidator::validate_full(&info);
    assert_eq!(
        r,
        ValidationResult::LicenseInvalid,
        "empty serial via validate_full must yield LicenseInvalid"
    );

    // Also: empty org fails too.
    let r2 = LicenseValidator::validate(DEFAULT_SERIAL, "", DEFAULT_EXPIRY_MS, "anything");
    assert_eq!(r2, ValidationResult::LicenseInvalid);
}

// ─── Test 6 ─────────────────────────────────────────────────────────────────
#[test]
fn test_recompute_sha256_consistency() {
    let expected = LicenseValidator::compute_sha256(DEFAULT_SERIAL, DEFAULT_ORG, DEFAULT_EXPIRY_MS);
    // 10 000 iterations — same input must always yield the same hash.
    for i in 0..10_000 {
        let h = LicenseValidator::compute_sha256(DEFAULT_SERIAL, DEFAULT_ORG, DEFAULT_EXPIRY_MS);
        if h != expected {
            panic!("SHA-256 not deterministic at iteration {}: got {} expected {}", i, h, expected);
        }
    }
    // Sanity: 64 hex chars.
    assert_eq!(expected.len(), 64);
    // The expected hash is the canonical string hash.
    assert_eq!(
        expected,
        "8936d67817378f1a308cf147b41a1354894c8bd1c1b14d345965085daae2fa3c",
        "default-license SHA-256 must match the precomputed reference hash"
    );
}

// ─── Test 7 ─────────────────────────────────────────────────────────────────
#[test]
fn test_countdown_math_at_T_minus_24h_1h_5min_0() {
    let expiry = 10_000_000_000_i64;

    // T-24h: 1 day, 0h, 0m, 0s, border 4×.
    let mut t = CountdownTimer::new(expiry);
    let snap = t.tick(expiry - 24 * MS_PER_HOUR);
    assert_eq!((snap.days, snap.hours, snap.minutes, snap.seconds), (1, 0, 0, 0));
    assert!(!snap.is_expired);
    assert_eq!(snap.border_animation_speed_multiplier, 4);

    // T-1h: 0 days, 1h, 0m, 0s, border 8×.
    let snap = t.tick(expiry - MS_PER_HOUR);
    assert_eq!((snap.days, snap.hours, snap.minutes, snap.seconds), (0, 1, 0, 0));
    assert_eq!(snap.border_animation_speed_multiplier, 8);

    // T-5min: 0d, 0h, 5m, 0s, border 16×.
    let snap = t.tick(expiry - 5 * MS_PER_MIN);
    assert_eq!((snap.days, snap.hours, snap.minutes, snap.seconds), (0, 0, 5, 0));
    assert_eq!(snap.border_animation_speed_multiplier, 16);

    // T-0: expired, border 16×.
    let snap = t.tick(expiry);
    assert_eq!((snap.days, snap.hours, snap.minutes, snap.seconds), (0, 0, 0, 0));
    assert!(snap.is_expired);
    assert_eq!(snap.border_animation_speed_multiplier, 16);

    // Just past expiry (T+60s): still expired, still 16×.
    let snap = t.tick(expiry + 60 * MS_PER_SEC);
    assert!(snap.is_expired);
    assert_eq!(snap.border_animation_speed_multiplier, 16);
}
