// ─────────────────────────────────────────────────────────────────────────────
// AntiRollbackMonitor — persisted high-water-mark timestamp.
//
// Per §8 anti-rollback: the system clock must NEVER go backwards past the
// persisted high-water-mark. On every `validate` cycle:
//   1. Read the persisted high-water-mark `H` from disk.
//   2. Observe the current clock `N`.
//   3. If `N < H`, return [`AntiRollbackResult::ClockRollbackDetected`] and
//      do NOT update the persisted high-water-mark.
//   4. Else, write `N` to disk as the new high-water-mark and return `Ok`.
//
// The high-water-mark file lives alongside the [`super::store::DesktopSecureStorage`]
// license file at `$XDG_CONFIG_HOME/unifiedshield/anti_rollback.json`.
// ─────────────────────────────────────────────────────────────────────────────

use super::validator::{AntiRollbackResult, LicenseValidator};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Default, Serialize, Deserialize)]
struct HighWaterMark {
    /// Latest observed system clock value (Unix-epoch ms).
    ms: i64,
}

/// Anti-rollback monitor. Persists the high-water-mark timestamp in
/// the same directory as the [`super::store::DesktopSecureStorage`] license
/// file (file name: `anti_rollback.json`).
#[derive(Debug)]
pub struct AntiRollbackMonitor {
    path: PathBuf,
    state: Mutex<HighWaterMark>,
}

impl AntiRollbackMonitor {
    /// Construct a monitor at the default path
    /// (`$XDG_CONFIG_HOME/unifiedshield/anti_rollback.json`).
    pub fn new() -> Self {
        let path = Self::default_path();
        let state = Self::load_or_default(&path);
        Self {
            path,
            state: Mutex::new(state),
        }
    }

    /// Construct with an explicit path (used by tests).
    pub fn with_path(path: impl Into<PathBuf>) -> Self {
        let path = path.into();
        let state = Self::load_or_default(&path);
        Self {
            path,
            state: Mutex::new(state),
        }
    }

    /// Default path: same directory as the license store, separate file.
    pub fn default_path() -> PathBuf {
        let base = dirs::config_dir().unwrap_or_else(|| PathBuf::from("/tmp"));
        base.join("unifiedshield").join("anti_rollback.json")
    }

    /// Check `now_ms` against the persisted high-water-mark.
    pub fn check(&self, now_ms: i64) -> AntiRollbackResult {
        let mut s = self.state.lock();
        let result = LicenseValidator::check_anti_rollback(now_ms, s.ms);
        if let AntiRollbackResult::Ok { high_water_mark_ms } = result {
            s.ms = high_water_mark_ms;
            let _ = Self::persist(&self.path, &s);
        }
        // On rollback, do NOT update the persisted high-water-mark —
        // leave the watermark intact so subsequent clock-tampering attempts
        // are still detectable.
        result
    }

    /// Current high-water-mark (latest observed `now_ms`).
    pub fn high_water_mark(&self) -> i64 {
        self.state.lock().ms
    }

    fn load_or_default(path: &Path) -> HighWaterMark {
        match fs::read_to_string(path) {
            Ok(s) => serde_json::from_str(&s).unwrap_or_default(),
            Err(_) => HighWaterMark::default(),
        }
    }

    fn persist(path: &Path, state: &HighWaterMark) -> std::io::Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let json = serde_json::to_string(state)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
        fs::write(path, json)
    }

    /// Wipe the persisted high-water-mark (used on full license wipe).
    pub fn wipe(&self) {
        let mut s = self.state.lock();
        *s = HighWaterMark::default();
        let _ = fs::remove_file(&self.path);
    }
}

impl Default for AntiRollbackMonitor {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rollback_detected() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let mon = AntiRollbackMonitor::with_path(tmp.path());
        // First check: bootstrap at t=1000
        assert!(matches!(mon.check(1000), AntiRollbackResult::Ok { .. }));
        assert_eq!(mon.high_water_mark(), 1000);
        // Clock rolls back to 500
        let r = mon.check(500);
        assert!(matches!(r, AntiRollbackResult::ClockRollbackDetected { .. }));
        // High-water-mark is NOT updated on rollback
        assert_eq!(mon.high_water_mark(), 1000);
    }

    #[test]
    fn high_water_mark_advances() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let mon = AntiRollbackMonitor::with_path(tmp.path());
        mon.check(1000);
        mon.check(2000);
        mon.check(1500); // rollback — not honored
        assert_eq!(mon.high_water_mark(), 2000);
    }

    #[test]
    fn persistence_round_trip() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let path = tmp.path().to_path_buf();
        {
            let mon = AntiRollbackMonitor::with_path(&path);
            mon.check(42_000);
        }
        // Re-open — high-water-mark should be 42_000.
        let mon = AntiRollbackMonitor::with_path(&path);
        assert_eq!(mon.high_water_mark(), 42_000);
    }

    #[test]
    fn wipe_clears_state() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let mon = AntiRollbackMonitor::with_path(tmp.path());
        mon.check(9_999);
        assert_eq!(mon.high_water_mark(), 9_999);
        mon.wipe();
        assert_eq!(mon.high_water_mark(), 0);
        assert!(std::fs::metadata(tmp.path()).is_err());
    }
}
