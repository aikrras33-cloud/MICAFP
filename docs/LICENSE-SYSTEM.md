# UnifiedShield Enterprise v9.0.0-enterprise — License System

> **Authoritative reference for the UnifiedShield Enterprise license validation flow.**
> Implements directive §8 in full: SHA-256 anti-tamper, Ed25519 second-layer
> signature, monotonic-clock anti-rollback, 4-cell countdown with Persian
> numerals, pre-expiry notifications, three platform-secure-storage backends,
> FFI exports, and offline (no-phone-home) operation.

Source code: `daemon/src/license/` (`validator.rs`, `info.rs`, `store.rs`, `countdown.rs`, `anti_rollback.rs`, `registry.rs`, `validation_tests.rs`) + `daemon/src/ffi.rs`.

---

## 1. License Specification

The default Enterprise license (per §8) is hard-coded into the daemon so the binary can boot without any external storage:

| Field | Value |
|-------|-------|
| `serial` | `MICAFP-RGB-ENT-ULTRA-2025` |
| `organization` | `Enterprise VIP User` |
| `tier` | `Enterprise RGB Supreme` |
| `value_usd` | `$999,999,999,999` (i.e. 9.999 × 10¹¹ USD) |
| `expiry_ms` (Unix epoch, ms) | `1_765_398_599_000` |
| `expiry` (Gregorian) | **2025-12-10 23:59:59 +03:30 IRT** |
| `expiry` (Persian) | **Azar 19 1404 23:59:59 IRT** |
| `issued_ms` | Set when the on-disk `LicenseInfo` is first persisted (defaults to "now" if the license was never stored) |

These constants live in `daemon/src/license/validator.rs`:

```rust
pub const DEFAULT_SERIAL:     &str = "MICAFP-RGB-ENT-ULTRA-2025";
pub const DEFAULT_ORG:        &str = "Enterprise VIP User";
pub const DEFAULT_TIER:       &str = "Enterprise RGB Supreme";
pub const DEFAULT_VALUE_USD:  u64  = 999_999_999_999;
pub const DEFAULT_EXPIRY_MS:  i64  = 1_765_398_599_000;
```

The Azar-19-1404 Persian date maps 1:1 to 2025-12-10 Gregorian, and 23:59:59 Iran Standard Time (UTC+03:30) maps to Unix ms 1_765_398_599_000.

---

## 2. Anti-Tamper Validation — Two-Layer Defense

### 2.1 Layer 1 — SHA-256 over the canonical string

The canonical string format is:
```
SALT_ENT_ULTRA_RGB_{serial}_{org}_{expiryMs}_SECURE_SHA256
```
with a fixed key order, no whitespace, no JSON. The SHA-256 hex digest of this string is the `signature_sha256` field on `LicenseInfo`.

`LicenseValidator::compute_sha256(serial, org, expiry_ms)` recomputes the digest; `LicenseValidator::validate(...)` compares it to the on-disk `signature_sha256` using a **constant-time** byte equality (`ct_eq` in `validator.rs:290`) to mitigate timing side-channels.

Precomputed reference for the default license:
```
sha256("SALT_ENT_ULTRA_RGB_MICAFP-RGB-ENT-ULTRA-2025_Enterprise VIP User_1765398599000_SECURE_SHA256")
= 8936d67817378f1a308cf147b41a1354894c8bd1c1b14d345965085daae2fa3c
```

### 2.2 Layer 2 — Ed25519 detached signature

The **same** canonical string is signed with Ed25519; the resulting 64-byte detached signature is base64-encoded into the `signature_ed25519` field on `LicenseInfo`.

The **public key** is embedded into the daemon binary as a `const` byte array (`EMBEDDED_ED25519_PUBLIC_KEY_B64` at `validator.rs:59`):
```
PmyPEdSc1PdRBLKRwCqKQR/Nr/gfI0/eil/MWoIL4X4=
```
The matching private key lives in `signing.key` (gitignored, held by the licensing authority offline). `LicenseValidator::validate_full(license)` decodes the base64 public key, decodes the base64 signature, and calls `ed25519_dalek::VerifyingKey::verify(canonical, sig)`.

### 2.3 Outcome matrix
The full validator (`validate_full`) returns one of 6 outcomes:

| Result | Triggered by |
|--------|--------------|
| `Valid { expiry_ms, tier }` | Both layers pass + `issued_ms ≤ now` |
| `LicenseInvalid` | Empty serial / empty org / malformed base64 in pubkey / pubkey ≠ 32 bytes |
| `LicenseTampered` | SHA-256 mismatch OR Ed25519 signature mismatch OR signature ≠ 64 bytes |
| `LicenseExpired` | `expiry_ms < now_ms` (checked downstream in the orchestrator) |
| `LicenseNotYetValid` | `issued_ms > now_ms` (clock-skew / future-dated license) |
| `ClockRollbackDetected` | Monotonic-clock check (see §3) |

---

## 3. Anti-Rollback — Monotonic Clock + High-Water-Mark

`LicenseValidator::check_anti_rollback(now_ms, high_water_mark_ms)` compares the system clock against a persisted **high-water-mark** — the latest valid timestamp the daemon has ever observed.

Behavior:
- `now_ms ≥ high_water_mark_ms` → `AntiRollbackResult::Ok { high_water_mark_ms: now_ms }` (caller persists the new HWM).
- `now_ms < high_water_mark_ms` → `AntiRollbackResult::ClockRollbackDetected { observed_ms, high_water_mark_ms }` (caller refuses to honor the license).

The high-water-mark is persisted to the **same** platform-secure-storage backend as the license (§6). It is updated on every daemon tick (every 30 s when the screen is on, every 2 min screen-off-light, every 10 min screen-off-deep — matching `NAIN_PROBE_INTERVAL_*` constants in `lib.rs`).

A clock rollback invalidates the license even if its SHA-256 + Ed25519 layers both pass — preventing the "freeze the clock before expiry" attack.

---

## 4. Countdown Display

`daemon/src/license/countdown.rs` implements `CountdownTimer::tick(expiry_ms, now_ms) -> CountdownSnapshot` returning the 4-cell snapshot:

```rust
pub struct CountdownSnapshot {
    pub days: i64,
    pub hours: i64,
    pub minutes: i64,
    pub seconds: i64,
    pub is_expired: bool,
    pub border_animation_speed_multiplier: i64,
}
```

### 4.1 Persian numerals when `Locale("fa")`

`CountdownSnapshot::to_persian_string()` renders the 4 cells with Persian digits (`۰۱۲۳۴۵۶۷۸۹`):
```
۲۳:۰۸:۴۲:۱۷
```
where the Latin `to_latin_string()` is the same value with `0-9` digits.

The Flutter UI in `QuantumEnterpriseLicensePanel` (`flutter_app/lib/theme/quantum_components.dart`) reads `Localizations.localeOf(context).languageCode` and picks `to_persian_string()` when `languageCode == "fa"`, otherwise `to_latin_string()`.

### 4.2 Faster animation as expiry approaches

The `border_animation_speed_multiplier` field maps to the RGB ring sweep rate on the panel's border:
- **1× when > 24 h remaining** (idle pulsing).
- **4× at T−24 h** (slow warning pulse).
- **8× at T−1 h** (urgent pulse).
- **16× at T−5 min and at T−0** (maximum-urgency pulse).

Combined with the per-cell `QuantumCountdownTimer` widget (see `ENTERPRISE-UI-DESIGN.md` §5.9), which itself accelerates the seconds-tick down to a 60-ms minimum as expiry approaches, the countdown gets **visibly more urgent** the closer the license gets to expiry.

### 4.3 4-cell layout

The panel renders 4 cells side-by-side:

| Cell | Label (fa) | Label (en) |
|------|-----------|------------|
| Days | روز | D |
| Hours | ساعت | H |
| Minutes | دقیقه | M |
| Seconds | ثانیه | S |

Separator dots between cells pulse at the period of the cell they precede — the seconds-dot pulses every 1 s, the minutes-dot every 1 min, etc.

---

## 5. Pre-Expiry Notifications

`LicenseValidator::check_expiry(expiry_ms, now_ms) -> ExpiryState` returns one of:

| State | Triggered |
|-------|-----------|
| `Valid` | more than 24 h remaining |
| `Warning24h` | ≤ 24 h remaining |
| `Warning1h` | ≤ 1 h remaining |
| `Warning5m` | ≤ 5 min remaining |
| `Expired` | `now_ms ≥ expiry_ms` |

The orchestrator's watchdog polls `check_expiry` every 1 s. The notification ladder is:

| Threshold | Channel | Action |
|-----------|---------|--------|
| T−24 h (`Warning24h`) | In-app toast (`QuantumToast`) | "اعتبار لایسنس کمتر از ۲۴ ساعت است" / "License expires in < 24 h" |
| T−1 h (`Warning1h`) | OS push notification (Android `NotificationManager` / iOS `UNUserNotificationCenter`) | "۱ ساعت تا انقضای لایسنس" / "1 h until license expiry" |
| T−5 min (`Warning5m`) | OS push notification (high priority) | "۵ دقیقه تا انقضای لایسنس — اتصال به‌زودی قطع می‌شود" / "5 min until license expiry — connection will be cut off" |
| T−0 (`Expired`) | Force-disconnect | `force_disconnect("license_expired")` FFI call; the VPN tunnel is torn down and the kill-switch stays engaged. |

All thresholds are exported as constants in `validator.rs:64-68` (`WARNING_24H_MS`, `WARNING_1H_MS`, `WARNING_5M_MS`) so they can be tuned without touching the watchdog.

---

## 6. Storage Backends

`daemon/src/license/store.rs` defines the `LicenseStore` trait with three implementations:

### 6.1 Android Keychain (`AndroidKeychainStore`)
- JNI bridge to `KeyStore.getInstance("AndroidKeyStore")` + `Cipher` initialized with a `KeyGenParameterSpec` backed by the StrongBox HWM if available.
- Backed up by the user's screen lock — wiping the device's keystore on factory reset, never exportable.
- Stub in the current build (returns `None` on load, no-op on save/wipe); production builds enable `--features android-jni` for the real impl.

### 6.2 iOS Keychain (`IosKeychainStore`)
- `Security.framework` `SecItemAdd` with `kSecClassKey` + `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (so the key never enters an iCloud backup).
- Same stub-vs-real split as Android (real impl gated by `--features ios-security`).

### 6.3 Desktop SecureStorage (`DesktopSecureStorage`)
- Encrypted JSON file at `$XDG_CONFIG_HOME/unifiedshield/license.json` (Linux), `~/Library/Application Support/unifiedshield/license.json` (macOS), `%APPDATA%\unifiedshield\license.json` (Windows).
- Encryption: ChaCha20-Poly1305 with a 32-byte key derived from the device secret (`daemon/src/security/device_secret.rs`), which itself is derived from a per-device hardware fingerprint (UUID + CPU serial + boot-volume serial on macOS/Windows; root partition UUID on Linux).
- Random 24-byte nonce per write; nonce is prepended to the ciphertext.
- Wipe uses 3-pass secure-delete (zero / 0xFF / random) before unlinking the file.

The trait is `Send + Sync` so the orchestrator holds one `Box<dyn LicenseStore>` selected at boot via `#[cfg(target_os = ...)]`.

---

## 7. FFI Exports

`daemon/src/ffi.rs` exports the following C-ABI functions for consumption by Flutter's `MethodChannel("unifiedshield/license")` (and by iOS/Android native bridges):

| Export | Signature | Returns / Side-effect |
|--------|-----------|------------------------|
| `validate_license` | `extern "C" fn validate_license(serial: *const c_char, org: *const c_char) -> *mut c_char` | JSON `{"valid":bool,"reason":"..."}`. Caller must free with `free_license_string`. |
| `get_license_info` | `extern "C" fn get_license_info() -> *mut c_char` | JSON of `LicenseInfo` or `{}` if none stored. |
| `force_disconnect` | `extern "C" fn force_disconnect(reason: *const c_char)` | Tears down the VPN tunnel and engages the kill switch. |
| `register_expiry_callback` | `extern "C" fn register_expiry_callback(cb: extern "C" fn(*const c_char))` | Registers a C callback invoked once at T−0 with the reason string. The `OnceLock<extern "C" fn>` is the global registration slot. |
| `free_license_string` | `extern "C" fn free_license_string(ptr: *mut c_char)` | RAII pair for the two `*mut c_char`-returning exports above. |

The Flutter side (`flutter_app/lib/services/daemon_bridge.dart`) wraps each of these into a typed Dart function, e.g.:

```dart
Future<Map<String, dynamic>> validateLicense(String serial, String org) async {
  final json = await _methodChannel.invokeMethod<String>('validate_license', {
    'serial': serial, 'org': org,
  });
  return jsonDecode(json ?? '{}') as Map<String, dynamic>;
}
```

The Android `MainActivity.kt` and iOS `Runner/AppDelegate.swift` register these on the MethodChannel — see `docs/ARCHITECTURE.md` §4 for the full IPC contract.

---

## 8. Offline Operation

The license system makes **zero network calls**:

1. The public key is embedded in the binary (`EMBEDDED_ED25519_PUBLIC_KEY_B64`).
2. The license itself is stored locally (§6) and re-validated on every boot.
3. The high-water-mark is local.
4. The default license is compiled in as constants (`DEFAULT_SERIAL`, `DEFAULT_ORG`, `DEFAULT_EXPIRY_MS`, …).

There is no license-server HTTP endpoint, no telemetry phone-home, no revocation-list fetch. A license once issued remains valid until its `expiry_ms` (or until the SHA-256 + Ed25519 layers fail to verify, or the high-water-mark is violated).

**Why offline?** An Iranian DPI operator cannot block what doesn't exist; a phone-home call would be a free signal that "this user is checking a VPN license". The offline design eliminates that signal entirely.

---

## 9. Unit Tests — 7 Cases

`daemon/src/license/validation_tests.rs` ships the 7-case Rust-side mirror of the Dart tests in `flutter_app/test/license_validation_test.dart`. The suite builds a properly Ed25519-signed test license using a test-only private key (matching `EMBEDDED_ED25519_PUBLIC_KEY_B64`, **not** compiled into release builds) and runs:

| # | Test name | Asserts |
|---|-----------|---------|
| 1 | `test_valid_license_passes` | `validate_full` returns `Valid { expiry_ms: DEFAULT_EXPIRY_MS, tier: "Enterprise RGB Supreme" }` for the default license. |
| 2 | `test_expired_license_fails` | When `expiry_ms` is set to `now_ms - 1`, the watchdog's `check_expiry` returns `Expired` and `force_disconnect` is invoked. |
| 3 | `test_tampered_signature_fails` | Flipping one byte in `signature_sha256` → `LicenseTampered`. |
| 4 | `test_future_dated_license_fails` | Setting `issued_ms` to `now_ms + 10⁶` → `LicenseNotYetValid`. |
| 5 | `test_empty_serial_fails` | Empty `serial` → `LicenseInvalid`. |
| 6 | `test_recompute_sha256_consistency` | Re-compute the SHA-256 10 000 times in a tight loop; every iteration must yield the same 64-hex-char digest (regression against hash-state corruption). |
| 7 | `test_countdown_math_at_T_minus_24h_1h_5min_0` | `CountdownTimer::tick(expiry_ms, now_ms)` returns the correct `(days, hours, minutes, seconds)` and the correct `border_animation_speed_multiplier` (1×, 4×, 8×, 16×) at T−24h, T−1h, T−5min, and T−0. |

The test binary is built only under `cargo test --features test-ed25519-key`; the release binary never contains `TEST_ED25519_PRIVATE_KEY_B64`.

The Flutter side has a parallel `flutter_app/test/license_validation_test.dart` running the same 7 logical cases against the FFI exports (invoked via the `MethodChannel` shim).

---

## 10. References

- `daemon/src/license/validator.rs` — the two-layer validator + anti-rollback check
- `daemon/src/license/info.rs` — `LicenseInfo` struct + `canonical()` method
- `daemon/src/license/store.rs` — three storage backends
- `daemon/src/license/countdown.rs` — 4-cell countdown + animation multiplier
- `daemon/src/license/anti_rollback.rs` — HWM persistence helpers
- `daemon/src/license/registry.rs` — per-device license registry
- `daemon/src/license/validation_tests.rs` — 7-case test suite
- `daemon/src/ffi.rs` — C-ABI exports (§7 above)
- `flutter_app/test/license_validation_test.dart` — Flutter mirror of the 7 cases
- `flutter_app/lib/screens/license_activation_screen.dart` — UI entry-point
- `flutter_app/lib/theme/quantum_components.dart` §5.4 — `QuantumEnterpriseLicensePanel`
- `docs/ARCHITECTURE.md` §8 — high-level summary
- `docs/ENTERPRISE-UI-DESIGN.md` §5.4 + §5.9 — UI spec
