// ─────────────────────────────────────────────────────────────────────────────
// LicenseRegistry — placeholder for the §8 license registry.
//
// Step 10 will replace this with the real implementation (on-disk license
// database, signature verification, anti-tamper hashing, revocation
// list, tier→feature gating). For now it just holds an empty in-memory
// store so other code can compile.
// ─────────────────────────────────────────────────────────────────────────────

use std::collections::HashMap;

/// In-memory placeholder for the license registry.
#[derive(Debug, Default, Clone)]
pub struct LicenseRegistry {
    /// Map of license serial → owner org.
    pub licenses: HashMap<String, String>,
}

impl LicenseRegistry {
    /// Create a new empty registry.
    pub fn new() -> Self {
        Self::default()
    }

    /// Insert a license into the registry.
    pub fn insert(&mut self, serial: impl Into<String>, org: impl Into<String>) {
        self.licenses.insert(serial.into(), org.into());
    }

    /// Look up the owner of a license serial.
    pub fn owner_of(&self, serial: &str) -> Option<&str> {
        self.licenses.get(serial).map(|s| s.as_str())
    }

    /// Total number of registered licenses.
    pub fn len(&self) -> usize {
        self.licenses.len()
    }

    /// Whether the registry is empty.
    pub fn is_empty(&self) -> bool {
        self.licenses.is_empty()
    }
}
