// ─────────────────────────────────────────────────────────────────────────────
// Orchestrator — Central control plane
// MICAFP-UnifiedShield-vip-ultra-Quantum-ultra v9.0
//
// Per directive GEMINI-ENG-DIR-V1.0 §3.2 (GEMINI-STEP-2), the
// `OrchestratorConfig` stub has been DROPPED — `UnifiedOrchestrator` now
// stores an `Arc<ShieldConfig>` directly and reads active_transport /
// active_core / health-check intervals from there.
// ─────────────────────────────────────────────────────────────────────────────

use std::time::Duration;

pub mod control_plane;
pub mod failover;
pub mod health_monitor;

pub use control_plane::{Subsystems, UnifiedOrchestrator};
pub use failover::FailoverEngine;
pub use health_monitor::HealthMonitor;

/// Alias for the orchestrator health monitor.
pub type OrchestratorHealthMonitor = HealthMonitor;
/// Alias for the failover engine.
pub type FailoverController = FailoverEngine;

/// Hard-coded default health-check interval.
///
/// Future step: lift this into a `ShieldConfig::orchestrator` section
/// (e.g. `health_check_interval_secs`) and read at orchestrator init.
pub const DEFAULT_HEALTH_CHECK_INTERVAL: Duration = Duration::from_secs(30);

/// Hard-coded default telemetry-flush interval.
pub const DEFAULT_TELEMETRY_INTERVAL: Duration = Duration::from_secs(300);

/// A point-in-time snapshot of the orchestrator's system state.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SystemStateSnapshot {
    pub active_transport: String,
    pub active_core: String,
    pub threat_level: String,
    pub health_score: f64,
    pub uptime_secs: u64,
    pub bytes_transferred: u64,
    pub failover_count: u32,
    pub battery_pct: Option<u8>,
    pub nain_active: bool,
}
