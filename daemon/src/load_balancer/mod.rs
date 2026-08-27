// ─────────────────────────────────────────────────────────────────────────────
// Load Balancer — Smooth Weighted Round Robin + Session Affinity
// MICAFP-UnifiedShield-vip-ultra-Quantum-ultra v8.0
// ─────────────────────────────────────────────────────────────────────────────

pub mod session_affinity;
pub mod swrr;

pub use session_affinity::SessionAffinityTable;
pub use swrr::SmoothedWeightedRoundRobin;

/// Canonical exported name used throughout the codebase.
pub type SmoothWeightedRoundRobin = SmoothedWeightedRoundRobin;
/// Canonical exported name for session affinity table.
pub type SessionAffinity = SessionAffinityTable;

// ─────────────────────────────────────────────────────────────────────────────
// LoadBalancer — thin orchestrator-facing facade introduced per directive
// §3.2. It owns a `SmoothedWeightedRoundRobin` (SWRR) instance seeded with
// the transport identifiers declared in `ShieldConfig::transport`.
//
// Future step: read a richer per-transport weight table from ShieldConfig
// (e.g. via a `transport.weights` map) and feed it into the SWRR at
// construction time.
// ─────────────────────────────────────────────────────────────────────────────
use std::sync::Arc;

use crate::config::schema::ShieldConfig;

pub struct LoadBalancer {
    /// Snapshot of the daemon config (read by background tasks).
    pub config: Arc<ShieldConfig>,
    /// Underlying SWRR picker.
    pub swrr: Arc<SmoothedWeightedRoundRobin>,
}

impl LoadBalancer {
    pub fn new(config: Arc<ShieldConfig>) -> Self {
        // Seed the SWRR with the active-transport identifier — keeps the
        // picker functional even when no explicit weight table is provided.
        let transports = vec![config.transport.active_transport.clone()];
        Self {
            config,
            swrr: Arc::new(SmoothedWeightedRoundRobin::new(transports)),
        }
    }
}

impl Default for LoadBalancer {
    fn default() -> Self {
        Self::new(Arc::new(ShieldConfig::default()))
    }
}

// ── Shared load balancer types ────────────────────────────────────────────────

/// A named item with a static weight and running current_weight for SWRR.
pub use crate::transport::TransportWeight;
