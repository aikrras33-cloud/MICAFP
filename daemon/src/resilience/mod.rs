// ─────────────────────────────────────────────────────────────────────────────
// Resilience subsystem — circuit breaker, retry, fallback chain, watchdog
// MICAFP-UnifiedShield-vip-ultra-Quantum-ultra v8.0
// ─────────────────────────────────────────────────────────────────────────────

pub mod circuit_breaker;
pub mod fallback_chain;
pub mod retry_policy;
pub mod watchdog;

pub use circuit_breaker::CircuitBreaker;
pub use fallback_chain::FallbackChain;
pub use retry_policy::RetryPolicy;
pub use watchdog::Watchdog;

/// Alias: SubsystemWatchdog is the same as the general Watchdog struct.
pub type SubsystemWatchdog = watchdog::Watchdog;

// ─────────────────────────────────────────────────────────────────────────────
// ResilienceManager — thin orchestrator-facing facade introduced per
// directive §3.2. It owns a default-configured `CircuitBreaker` (with a
// placeholder name "transport" — the real per-transport breakers are owned
// by the TransportManager) and exposes nothing yet.
//
// Future step: read failure_threshold / recovery_timeout from ShieldConfig
// (e.g. via a new `resilience` config section) and own the per-transport
// breaker registry here.
// ─────────────────────────────────────────────────────────────────────────────
use std::sync::Arc;
use std::time::Duration;

use crate::config::schema::ShieldConfig;

pub struct ResilienceManager {
    /// Snapshot of the daemon config (read by background tasks).
    pub config: Arc<ShieldConfig>,
    /// Aggregate circuit breaker for the daemon's transport plane.
    pub breaker: Arc<CircuitBreaker>,
}

impl ResilienceManager {
    pub fn new(config: Arc<ShieldConfig>) -> Self {
        Self {
            config,
            breaker: Arc::new(CircuitBreaker::new(
                "transport",
                5,
                Duration::from_secs(30),
            )),
        }
    }
}

impl Default for ResilienceManager {
    fn default() -> Self {
        Self::new(Arc::new(ShieldConfig::default()))
    }
}
