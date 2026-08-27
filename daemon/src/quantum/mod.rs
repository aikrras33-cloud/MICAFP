pub mod homomorphic_routing;
pub mod hybrid_handshake;
pub mod lattice_onion;
pub mod neural_steganography;
pub mod pqc_key_store;
pub mod qkd_simulation;
pub mod quantum_noise;
pub mod quantum_obfuscator;
pub mod quantum_ratchet;
pub mod quantum_seed_protocol;
pub mod zkp_auth;

pub use hybrid_handshake::HybridHandshake;
pub use lattice_onion::LatticeOnionRouter;
pub use neural_steganography::NeuralSteganographer;
pub use pqc_key_store::PqcKeyStore;
pub use quantum_noise::QuantumNoiseInjector;
pub use quantum_obfuscator::QuantumObfuscator;
pub use quantum_ratchet::QuantumRatchet;
pub use quantum_seed_protocol::QuantumSeedProtocolEngine;
pub type QuantumHybridHandshake = HybridHandshake;
pub type LatticeOnionEncoder = LatticeOnionRouter;
pub type NeuralSteganography = NeuralSteganographer;
pub type QuantumNoiseShaper = QuantumNoiseInjector;

/// Canonical alias for ZkpAuthenticator.
pub type ZkpAuth = zkp_auth::ZkpAuthenticator;

// ─────────────────────────────────────────────────────────────────────────────
// QuantumSubsystem — thin orchestrator-facing facade introduced per
// directive §3.2. It groups the post-quantum / hybrid-handshake / lattice /
// steganography primitives under a single Arc-friendly root so the
// UnifiedOrchestrator can hold them collectively.
//
// The individual primitives (HybridHandshake, QuantumRatchet, etc.) all
// default-construct cleanly; deeper config-driven wiring (e.g. seeding
// PqcKeyStore from disk, choosing the lattice parameter set) is a future
// step.
// ─────────────────────────────────────────────────────────────────────────────
use std::sync::Arc;

use crate::config::schema::ShieldConfig;

pub struct QuantumSubsystem {
    /// Snapshot of the daemon config (read by background tasks).
    pub config: Arc<ShieldConfig>,
    /// Post-quantum key store (currently default-constructed — placeholder).
    pub key_store: PqcKeyStore,
    /// Hybrid classical+PQ handshake engine.
    pub handshake: HybridHandshake,
}

impl QuantumSubsystem {
    pub fn new(config: Arc<ShieldConfig>) -> Self {
        Self {
            config,
            key_store: PqcKeyStore::default(),
            handshake: HybridHandshake::new_initiator(0),
        }
    }
}

impl Default for QuantumSubsystem {
    fn default() -> Self {
        Self::new(Arc::new(ShieldConfig::default()))
    }
}
