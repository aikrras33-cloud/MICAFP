// ─────────────────────────────────────────────────────────────────────────────
// LicenseStore — on-disk persistence for [`LicenseInfo`].
//
// Three backends:
//   • [`AndroidKeychainStore`] — Android Keystore via JNI (stub for now)
//   • [`IosKeychainStore`]    — iOS Keychain via Security.framework (stub for now)
//   • [`DesktopSecureStorage`] — encrypted JSON file at
//     `$XDG_CONFIG_HOME/unifiedshield/license.json` (Linux/macOS/Windows),
//     encrypted via ChaCha20-Poly1305 with a device-derived key.
// ─────────────────────────────────────────────────────────────────────────────

use super::info::LicenseInfo;
use chacha20poly1305::{
    aead::{Aead, KeyInit},
    ChaCha20Poly1305, Key, Nonce,
};
use rand::Rng;
use sha2::{Digest, Sha256};

/// Abstract persistence backend for [`LicenseInfo`].
pub trait LicenseStore: Send + Sync {
    /// Load the stored license, or `None` if no license is stored.
    fn load(&self) -> Option<LicenseInfo>;
    /// Persist the given license.
    fn save(&self, info: &LicenseInfo);
    /// Wipe any stored license.
    fn wipe(&self);
}

// ─── Android Keychain (stub) ────────────────────────────────────────────────
/// Android Keystore-backed license store. Real implementation will use JNI
/// to call into `KeyStore.getInstance("AndroidKeyStore")` + `Cipher` with
/// `KeyGenParameterSpec`. For now this is a stub that returns `None` on
/// load and is a no-op on save/wipe — production builds must implement
/// this against `daemon`'s `android-jni` feature flag.
#[derive(Debug, Default, Clone)]
pub struct AndroidKeychainStore;

impl AndroidKeychainStore {
    /// Construct a new (stub) Android keychain store.
    pub fn new() -> Self {
        Self
    }
}

impl LicenseStore for AndroidKeychainStore {
    fn load(&self) -> Option<LicenseInfo> {
        None
    }
    fn save(&self, _info: &LicenseInfo) {}
    fn wipe(&self) {}
}

// ─── iOS Keychain (stub) ────────────────────────────────────────────────────
/// iOS Keychain-backed license store. Real implementation will use
/// `Security.framework`'s `SecItemAdd` / `SecItemCopyMatching` via the
/// `keyring` crate or raw `objc` FFI. For now this is a stub.
#[derive(Debug, Default, Clone)]
pub struct IosKeychainStore;

impl IosKeychainStore {
    /// Construct a new (stub) iOS keychain store.
    pub fn new() -> Self {
        Self
    }
}

impl LicenseStore for IosKeychainStore {
    fn load(&self) -> Option<LicenseInfo> {
        None
    }
    fn save(&self, _info: &LicenseInfo) {}
    fn wipe(&self) {}
}

// ─── Desktop Secure Storage ─────────────────────────────────────────────────
/// Desktop encrypted JSON file store. Persists [`LicenseInfo`] as a JSON
/// blob encrypted with ChaCha20-Poly1305 using a device-derived 256-bit key.
///
/// File layout: `[12-byte nonce || ciphertext || 16-byte Poly1305 tag]`.
#[derive(Debug, Clone)]
pub struct DesktopSecureStorage {
    path: std::path::PathBuf,
    key: [u8; 32],
}

impl DesktopSecureStorage {
    /// Construct with the default path (`$XDG_CONFIG_HOME/unifiedshield/license.json`)
    /// and a device-derived key.
    pub fn new() -> Self {
        let path = Self::default_path();
        let key = Self::derive_device_key();
        Self { path, key }
    }

    /// Construct with an explicit path (used by tests).
    pub fn with_path(path: impl Into<std::path::PathBuf>) -> Self {
        Self {
            path: path.into(),
            key: Self::derive_device_key(),
        }
    }

    /// Default on-disk path: `$XDG_CONFIG_HOME/unifiedshield/license.json`
    /// (or `~/.config/unifiedshield/license.json` on Linux/macOS,
    /// `%APPDATA%\unifiedshield\license.json` on Windows — the `dirs`
    /// crate resolves the platform-appropriate config root).
    pub fn default_path() -> std::path::PathBuf {
        let base = dirs::config_dir().unwrap_or_else(|| std::path::PathBuf::from("/tmp"));
        base.join("unifiedshield").join("license.json")
    }

    /// Derive a 256-bit device key from `hostname + username` via SHA-256.
    /// This is a basic obfuscation layer — for production-grade security
    /// the key should come from a TPM / Secure Enclave / Android KeyStore
    /// hardware-backed key.
    pub fn derive_device_key() -> [u8; 32] {
        let host = hostname_string();
        let user = username_string();
        let mut h = Sha256::new();
        h.update(b"UnifiedShield::LicenseStore::DeviceKey::v1::");
        h.update(host.as_bytes());
        h.update(b"::");
        h.update(user.as_bytes());
        let digest = h.finalize();
        let mut out = [0u8; 32];
        out.copy_from_slice(&digest);
        out
    }

    /// Path accessor (used by the anti-rollback monitor to co-locate
    /// its state file in the same directory).
    pub fn path(&self) -> &std::path::Path {
        &self.path
    }

    fn cipher(&self) -> ChaCha20Poly1305 {
        ChaCha20Poly1305::new(Key::from_slice(&self.key))
    }
}

impl Default for DesktopSecureStorage {
    fn default() -> Self {
        Self::new()
    }
}

impl LicenseStore for DesktopSecureStorage {
    fn load(&self) -> Option<LicenseInfo> {
        let bytes = std::fs::read(&self.path).ok()?;
        if bytes.len() < 12 + 16 {
            return None;
        }
        let (nonce_bytes, ciphertext) = bytes.split_at(12);
        let cipher = self.cipher();
        let plaintext = cipher
            .decrypt(Nonce::from_slice(nonce_bytes), ciphertext)
            .ok()?;
        let json = String::from_utf8(plaintext).ok()?;
        LicenseInfo::from_json(&json).ok()
    }

    fn save(&self, info: &LicenseInfo) {
        let json = match info.to_json() {
            Ok(s) => s,
            Err(_) => return,
        };
        let cipher = self.cipher();
        // Random 12-byte nonce via the `rand` crate (already a dep).
        let nonce_bytes: [u8; 12] = rand::thread_rng().gen();
        let ciphertext = match cipher.encrypt(Nonce::from_slice(&nonce_bytes), json.as_bytes()) {
            Ok(c) => c,
            Err(_) => return,
        };
        let mut out = Vec::with_capacity(12 + ciphertext.len());
        out.extend_from_slice(&nonce_bytes);
        out.extend_from_slice(&ciphertext);
        if let Some(parent) = self.path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let _ = std::fs::write(&self.path, out);
    }

    fn wipe(&self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

fn hostname_string() -> String {
    std::env::var("HOSTNAME")
        .or_else(|_| std::env::var("COMPUTERNAME"))
        .unwrap_or_else(|_| "unknown-host".to_string())
}

fn username_string() -> String {
    std::env::var("USER")
        .or_else(|_| std::env::var("USERNAME"))
        .unwrap_or_else(|_| "unknown-user".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn desktop_store_round_trip() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let store = DesktopSecureStorage::with_path(tmp.path());
        let info = LicenseInfo::builder()
            .serial("TEST-SERIAL")
            .org("TEST-ORG")
            .tier("Enterprise RGB Supreme")
            .value_usd(1)
            .expiry_ms(1_765_398_599_000)
            .issued_ms(0)
            .signature_sha256("deadbeef")
            .signature_ed25519("sig")
            .public_key_ed25519("pk")
            .build();
        store.save(&info);
        let loaded = store.load().expect("license should round-trip");
        assert_eq!(loaded.serial, "TEST-SERIAL");
        assert_eq!(loaded.organization, "TEST-ORG");
        assert_eq!(loaded.expiry_ms, 1_765_398_599_000);
        store.wipe();
        assert!(store.load().is_none());
    }

    #[test]
    fn desktop_store_corrupt_file_returns_none() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        std::fs::write(tmp.path(), b"not valid ciphertext").unwrap();
        let store = DesktopSecureStorage::with_path(tmp.path());
        assert!(store.load().is_none());
    }
}
