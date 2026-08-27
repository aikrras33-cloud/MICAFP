// ─────────────────────────────────────────────────────────────────────────────
// LicenseInfo — canonical license record stored on disk.
//
// Per directive §8 — Enterprise License & Serial Number System.
//
// Fields:
//   • `serial`             — e.g. `"MICAFP-RGB-ENT-ULTRA-2025"` (default per §8)
//   • `organization`        — e.g. `"Enterprise VIP User"` (default per §8)
//   • `tier`                — e.g. `"Enterprise RGB Supreme"` (default per §8)
//   • `value_usd`           — license monetary value in USD; default = $999,999,999,999
//   • `expiry_ms`           — Unix-epoch ms of expiry (Azar 19 1404 = 2025-12-10T23:59:59+03:30 IRT)
//   • `issued_ms`          — Unix-epoch ms of issuance
//   • `signature_sha256`    — hex SHA-256 of canonical string (first anti-tamper layer)
//   • `signature_ed25519`  — base64 Ed25519 signature of canonical string (second anti-tamper layer)
//   • `public_key_ed25519` — base64 Ed25519 public key (32 bytes)
//
// Builder: `LicenseInfo::builder().serial(...).org(...).build()`
// ─────────────────────────────────────────────────────────────────────────────

use serde::{Deserialize, Serialize};

/// On-disk license record.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LicenseInfo {
    /// License serial number (e.g. `MICAFP-RGB-ENT-ULTRA-2025`).
    pub serial: String,
    /// Owning organization (e.g. `Enterprise VIP User`).
    pub organization: String,
    /// Tier label (e.g. `Enterprise RGB Supreme`).
    pub tier: String,
    /// License monetary value in USD.
    pub value_usd: u64,
    /// Expiry Unix-epoch milliseconds.
    pub expiry_ms: i64,
    /// Issuance Unix-epoch milliseconds.
    pub issued_ms: i64,
    /// Hex SHA-256 of the canonical string (first anti-tamper layer).
    pub signature_sha256: String,
    /// Base64 Ed25519 signature of the canonical string (second anti-tamper layer).
    pub signature_ed25519: String,
    /// Base64 Ed25519 public key (32 bytes after base64 decode).
    pub public_key_ed25519: String,
}

impl LicenseInfo {
    /// Construct a new [`LicenseInfoBuilder`].
    pub fn builder() -> LicenseInfoBuilder {
        LicenseInfoBuilder::default()
    }

    /// Canonical string used for SHA-256 hashing AND Ed25519 signing:
    /// `SALT_ENT_ULTRA_RGB_{serial}_{org}_{expiryMs}_SECURE_SHA256`
    pub fn canonical(&self) -> String {
        format!(
            "SALT_ENT_ULTRA_RGB_{}_{}_{}_SECURE_SHA256",
            self.serial, self.organization, self.expiry_ms
        )
    }

    /// Serialize to JSON.
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }

    /// Pretty-printed JSON for on-disk debugging.
    pub fn to_json_pretty(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(self)
    }

    /// Deserialize from JSON.
    pub fn from_json(s: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(s)
    }
}

impl std::fmt::Display for LicenseInfo {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let sha_short: &str = if self.signature_sha256.len() >= 8 {
            &self.signature_sha256[..8]
        } else {
            &self.signature_sha256
        };
        write!(
            f,
            "LicenseInfo{{ serial={}, org={}, tier={}, value_usd=${}, expiry_ms={}, sha256={}... }}",
            self.serial,
            self.organization,
            self.tier,
            self.value_usd,
            self.expiry_ms,
            sha_short
        )
    }
}

/// Builder for [`LicenseInfo`]. Public fields are exposed for diagnostic
/// purposes — prefer the fluent setters when constructing new instances.
#[derive(Debug, Default, Clone)]
pub struct LicenseInfoBuilder {
    /// License serial.
    pub serial: String,
    /// Owning organization.
    pub organization: String,
    /// Tier label.
    pub tier: String,
    /// Monetary value in USD.
    pub value_usd: u64,
    /// Expiry Unix-epoch ms.
    pub expiry_ms: i64,
    /// Issuance Unix-epoch ms.
    pub issued_ms: i64,
    /// Hex SHA-256 signature.
    pub signature_sha256: String,
    /// Base64 Ed25519 signature.
    pub signature_ed25519: String,
    /// Base64 Ed25519 public key.
    pub public_key_ed25519: String,
}

impl LicenseInfoBuilder {
    /// Set the serial.
    pub fn serial(mut self, s: impl Into<String>) -> Self {
        self.serial = s.into();
        self
    }
    /// Set the organization.
    pub fn org(mut self, s: impl Into<String>) -> Self {
        self.organization = s.into();
        self
    }
    /// Set the tier.
    pub fn tier(mut self, s: impl Into<String>) -> Self {
        self.tier = s.into();
        self
    }
    /// Set the value_usd.
    pub fn value_usd(mut self, v: u64) -> Self {
        self.value_usd = v;
        self
    }
    /// Set the expiry_ms.
    pub fn expiry_ms(mut self, v: i64) -> Self {
        self.expiry_ms = v;
        self
    }
    /// Set the issued_ms.
    pub fn issued_ms(mut self, v: i64) -> Self {
        self.issued_ms = v;
        self
    }
    /// Set the SHA-256 signature.
    pub fn signature_sha256(mut self, s: impl Into<String>) -> Self {
        self.signature_sha256 = s.into();
        self
    }
    /// Set the Ed25519 signature.
    pub fn signature_ed25519(mut self, s: impl Into<String>) -> Self {
        self.signature_ed25519 = s.into();
        self
    }
    /// Set the Ed25519 public key.
    pub fn public_key_ed25519(mut self, s: impl Into<String>) -> Self {
        self.public_key_ed25519 = s.into();
        self
    }
    /// Materialize the [`LicenseInfo`].
    pub fn build(self) -> LicenseInfo {
        LicenseInfo {
            serial: self.serial,
            organization: self.organization,
            tier: self.tier,
            value_usd: self.value_usd,
            expiry_ms: self.expiry_ms,
            issued_ms: self.issued_ms,
            signature_sha256: self.signature_sha256,
            signature_ed25519: self.signature_ed25519,
            public_key_ed25519: self.public_key_ed25519,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builder_round_trip_json() {
        let info = LicenseInfo::builder()
            .serial("MICAFP-RGB-ENT-ULTRA-2025")
            .org("Enterprise VIP User")
            .tier("Enterprise RGB Supreme")
            .value_usd(999_999_999_999)
            .expiry_ms(1_765_398_599_000)
            .issued_ms(0)
            .signature_sha256("deadbeef")
            .signature_ed25519("sig")
            .public_key_ed25519("pk")
            .build();
        let json = info.to_json().unwrap();
        let back = LicenseInfo::from_json(&json).unwrap();
        assert_eq!(back.serial, info.serial);
        assert_eq!(back.organization, info.organization);
        assert_eq!(back.value_usd, info.value_usd);
        assert_eq!(back.expiry_ms, info.expiry_ms);
        assert_eq!(back.signature_sha256, info.signature_sha256);
    }

    #[test]
    fn canonical_string_format() {
        let info = LicenseInfo::builder()
            .serial("S")
            .org("O")
            .expiry_ms(42)
            .build();
        assert_eq!(info.canonical(), "SALT_ENT_ULTRA_RGB_S_O_42_SECURE_SHA256");
    }
}
