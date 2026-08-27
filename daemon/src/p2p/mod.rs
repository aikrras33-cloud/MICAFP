pub mod i2p_overlay;
pub mod libp2p_discovery;
pub mod nat_traversal;
pub mod peer_exchange;
pub mod relay_selection;
pub mod yggdrasil_overlay;

pub use i2p_overlay::I2pOverlay;
pub use libp2p_discovery::Libp2pDiscovery;
pub use nat_traversal::NatTraversal;
pub use relay_selection::RelaySelection;
pub use yggdrasil_overlay::YggdrasilOverlay;

/// Canonical alias used throughout the codebase.
pub type RelaySelector = RelaySelection;

// ─────────────────────────────────────────────────────────────────────────────
// P2pCoordinator — thin orchestrator-facing facade introduced per directive
// §3.2. It owns a `Libp2pDiscovery` instance seeded from
// `ShieldConfig::transport::p2p_bootstrap_peers` (the embedded JSON resource
// at `daemon/resources/p2p-bootstrap-peers.json` is the ultimate fallback).
//
// Real per-channel wiring (NAT traversal, I2P / Yggdrasil overlays, relay
// selection) is a future step — this struct exists so the UnifiedOrchestrator
// can construct & hold the P2P subsystem as an `Arc<P2pCoordinator>`.
// ─────────────────────────────────────────────────────────────────────────────
use std::sync::Arc;

use crate::config::schema::ShieldConfig;

pub struct P2pCoordinator {
    /// Snapshot of the daemon config (read by background tasks).
    pub config: Arc<ShieldConfig>,
    /// libp2p DHT discovery primitive (no-op until `bootstrap()` is called).
    pub discovery: Libp2pDiscovery,
}

impl P2pCoordinator {
    /// Construct a P2P coordinator from the daemon config.
    ///
    /// Uses the configured bootstrap peers if any are present, else falls
    /// back to the empty list (real production deployments should populate
    /// `transport.p2p_bootstrap_peers` in `ShieldConfig.toml`).
    pub fn new(config: Arc<ShieldConfig>) -> Self {
        let peers: Vec<String> = config.transport.p2p_bootstrap_peers.clone();
        Self {
            config,
            discovery: Libp2pDiscovery::new(&peers),
        }
    }
}

impl Default for P2pCoordinator {
    fn default() -> Self {
        Self::new(Arc::new(ShieldConfig::default()))
    }
}
