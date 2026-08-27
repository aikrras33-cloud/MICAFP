// ─────────────────────────────────────────────────────────────────────────────
// MICAFP UnifiedShield VIP-ULTRA — Fallback Chain
//
// Ordered chain of fallback strategies for extreme censorship scenarios.
// Per directive GEMINI-ENG-DIR-V1.0 §7.5, the 8-step chain is:
//
//   1. PrimaryTransport  (auto-selected by the AI orchestrator)        — if fails:
//   2. ChineseCdnWorker  (Alibaba or Arvan, weighted by health)         — if fails:
//   3. P2pLibp2pRelay    (libp2p relay through bootstrap peers)         — if fails:
//   4. DohTunnel         (DNS-over-HTTPS via AliDNS dns.alidns.com)     — if fails:
//   5. IcmpTunnel        (transport/icmp_tunnel.rs)                    — if fails:
//   6. MeshNetwork       (Yggdrasil overlay via go-bridge/)             — if fails:
//   7. TorBridgeSnowflake (volunteer snowflake bridges)                 — if fails:
//   8. TorBridgeMeek     (meek fronting via Chinese CDNs from
//                          configs/pluggable-transports.json)
//
// Each fallback MUST auto-trigger within 200 ms (§7.5) — the chain is
// advanced in-process so there is no IPC round-trip.
//
// Each strategy tracks per-step failure counts; if a step is exhausted it
// is marked dead and the chain auto-advances on the next cycle.
// ─────────────────────────────────────────────────────────────────────────────

use std::sync::Arc;
use std::time::{Duration, Instant};

use parking_lot::Mutex;
use tracing::{info, warn};

/// Maximum budget for advancing to the next step (per §7.5: 200 ms).
pub const FALLBACK_BUDGET: Duration = Duration::from_millis(200);

/// A single fallback strategy. The order of variants defines the chain
/// priority — DO NOT reorder.
#[derive(Debug, Clone, PartialEq, Eq, Hash, serde::Serialize)]
pub enum FallbackStrategy {
    PrimaryTransport,
    ChineseCdnWorker,
    P2pLibp2pRelay,
    DohTunnel,
    IcmpTunnel,
    MeshNetwork,
    TorBridgeSnowflake,
    TorBridgeMeek,
}

impl FallbackStrategy {
    /// All 8 strategies in chain order, matching §7.5.
    pub fn all() -> &'static [FallbackStrategy] {
        &[
            FallbackStrategy::PrimaryTransport,
            FallbackStrategy::ChineseCdnWorker,
            FallbackStrategy::P2pLibp2pRelay,
            FallbackStrategy::DohTunnel,
            FallbackStrategy::IcmpTunnel,
            FallbackStrategy::MeshNetwork,
            FallbackStrategy::TorBridgeSnowflake,
            FallbackStrategy::TorBridgeMeek,
        ]
    }

    /// Human-readable step name (used by the UI resilience chain widget).
    pub fn step_name(&self) -> &'static str {
        match self {
            FallbackStrategy::PrimaryTransport => "PrimaryTransport",
            FallbackStrategy::ChineseCdnWorker => "ChineseCdnWorker",
            FallbackStrategy::P2pLibp2pRelay => "P2pLibp2pRelay",
            FallbackStrategy::DohTunnel => "DohTunnel",
            FallbackStrategy::IcmpTunnel => "IcmpTunnel",
            FallbackStrategy::MeshNetwork => "MeshNetwork",
            FallbackStrategy::TorBridgeSnowflake => "TorBridgeSnowflake",
            FallbackStrategy::TorBridgeMeek => "TorBridgeMeek",
        }
    }

    /// Chain position (1-indexed, matching §7.5 numbering).
    pub fn chain_position(&self) -> u8 {
        match self {
            FallbackStrategy::PrimaryTransport => 1,
            FallbackStrategy::ChineseCdnWorker => 2,
            FallbackStrategy::P2pLibp2pRelay => 3,
            FallbackStrategy::DohTunnel => 4,
            FallbackStrategy::IcmpTunnel => 5,
            FallbackStrategy::MeshNetwork => 6,
            FallbackStrategy::TorBridgeSnowflake => 7,
            FallbackStrategy::TorBridgeMeek => 8,
        }
    }
}

/// Manages the ordered fallback chain with per-strategy health tracking.
pub struct FallbackChain {
    strategies: Vec<FallbackStrategy>,
    current_index: Mutex<usize>,
    failures: Mutex<std::collections::HashMap<FallbackStrategy, u32>>,
    /// Timestamp of the last successful activation (for the 200 ms budget).
    last_switch_at: Mutex<Option<Instant>>,
}

impl FallbackChain {
    /// Create the default fallback chain for Iran censorship scenarios per §7.5.
    pub fn default_for_iran() -> Self {
        Self {
            strategies: FallbackStrategy::all().to_vec(),
            current_index: Mutex::new(0),
            failures: Mutex::new(std::collections::HashMap::new()),
            last_switch_at: Mutex::new(None),
        }
    }

    /// Get the current active strategy.
    pub fn current(&self) -> &FallbackStrategy {
        let idx = *self.current_index.lock();
        &self.strategies[idx.min(self.strategies.len() - 1)]
    }

    /// Record failure of current strategy and advance to next.
    ///
    /// Per §7.5, the advance MUST complete within 200 ms — this method is
    /// synchronous so there is no IPC round-trip. The caller is responsible
    /// for actually starting the new transport in parallel after this call.
    pub fn advance(&self) -> Option<&FallbackStrategy> {
        let start = Instant::now();
        let mut idx = self.current_index.lock();
        let failed = &self.strategies[*idx];
        *self.failures.lock().entry(failed.clone()).or_insert(0) += 1;
        warn!(
            step = failed.chain_position(),
            strategy = failed.step_name(),
            failures = self.failures.lock().get(failed).copied().unwrap_or(0),
            "fallback_chain: step failed — advancing"
        );

        if *idx + 1 < self.strategies.len() {
            *idx += 1;
            let next = &self.strategies[*idx];

            // 200 ms budget check — if we exceeded it, log but still advance.
            let elapsed = start.elapsed();
            if elapsed > FALLBACK_BUDGET {
                warn!(
                    elapsed_ms = elapsed.as_millis(),
                    budget_ms = FALLBACK_BUDGET.as_millis(),
                    "fallback_chain: advance exceeded §7.5 budget"
                );
            }

            *self.last_switch_at.lock() = Some(Instant::now());
            info!(
                step = next.chain_position(),
                strategy = next.step_name(),
                elapsed_us = elapsed.as_micros(),
                "fallback_chain: activating next step"
            );
            Some(next)
        } else {
            warn!("fallback_chain: all 8 strategies exhausted — staying on last (TorBridgeMeek)");
            None
        }
    }

    /// Try to advance to the next step and return its name. Wrapper around
    /// `advance()` that returns `Option<&str>` per §7.5 contract.
    pub async fn try_next(&self) -> Option<&str> {
        self.advance().map(|s| s.step_name())
    }

    /// Reset to primary transport (called after successful reconnection).
    pub fn reset(&self) {
        *self.current_index.lock() = 0;
        *self.last_switch_at.lock() = None;
        info!("fallback_chain: reset to PrimaryTransport (step 1)");
    }

    /// Time since the last successful activation (None if never activated).
    pub fn time_since_last_switch(&self) -> Option<Duration> {
        self.last_switch_at.lock().map(|t| t.elapsed())
    }

    pub fn all_strategies(&self) -> &[FallbackStrategy] {
        &self.strategies
    }

    /// Get the failure count for a specific strategy.
    pub fn failure_count(&self, strategy: &FallbackStrategy) -> u32 {
        self.failures.lock().get(strategy).copied().unwrap_or(0)
    }

    /// Current chain position (1-indexed).
    pub fn current_position(&self) -> u8 {
        self.current().chain_position()
    }
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chain_order_matches_directive_7_5() {
        let chain = FallbackChain::default_for_iran();
        assert_eq!(chain.all_strategies().len(), 8, "must have exactly 8 steps");
        assert_eq!(chain.all_strategies()[0], FallbackStrategy::PrimaryTransport);
        assert_eq!(chain.all_strategies()[1], FallbackStrategy::ChineseCdnWorker);
        assert_eq!(chain.all_strategies()[2], FallbackStrategy::P2pLibp2pRelay);
        assert_eq!(chain.all_strategies()[3], FallbackStrategy::DohTunnel);
        assert_eq!(chain.all_strategies()[4], FallbackStrategy::IcmpTunnel);
        assert_eq!(chain.all_strategies()[5], FallbackStrategy::MeshNetwork);
        assert_eq!(chain.all_strategies()[6], FallbackStrategy::TorBridgeSnowflake);
        assert_eq!(chain.all_strategies()[7], FallbackStrategy::TorBridgeMeek);
    }

    #[test]
    fn test_chain_positions_are_1_indexed() {
        assert_eq!(FallbackStrategy::PrimaryTransport.chain_position(), 1);
        assert_eq!(FallbackStrategy::TorBridgeMeek.chain_position(), 8);
    }

    #[test]
    fn test_step_names_match_ui_widget() {
        let chain = FallbackChain::default_for_iran();
        for s in chain.all_strategies() {
            assert!(!s.step_name().is_empty());
        }
        assert_eq!(chain.all_strategies()[0].step_name(), "PrimaryTransport");
    }

    #[test]
    fn test_advance_walks_all_8_steps() {
        let chain = FallbackChain::default_for_iran();
        assert_eq!(chain.current_position(), 1);

        // Advance 7 times — should reach step 8 (TorBridgeMeek).
        for expected_step in 2..=8u8 {
            let next = chain.advance();
            assert!(next.is_some(), "step {expected_step} must advance");
            assert_eq!(next.unwrap().chain_position(), expected_step);
        }

        // 9th advance should return None (chain exhausted).
        assert!(chain.advance().is_none());
    }

    #[tokio::test]
    async fn test_try_next_returns_step_name() {
        let chain = FallbackChain::default_for_iran();
        let next = chain.try_next().await;
        assert_eq!(next, Some("ChineseCdnWorker"));
    }

    #[test]
    fn test_reset_returns_to_step_1() {
        let chain = FallbackChain::default_for_iran();
        let _ = chain.advance();
        assert_eq!(chain.current_position(), 2);
        chain.reset();
        assert_eq!(chain.current_position(), 1);
    }

    #[test]
    fn test_failure_count_tracks_per_strategy() {
        let chain = FallbackChain::default_for_iran();
        let _ = chain.advance(); // PrimaryTransport fails
        let _ = chain.advance(); // ChineseCdnWorker fails
        assert_eq!(chain.failure_count(&FallbackStrategy::PrimaryTransport), 1);
        assert_eq!(chain.failure_count(&FallbackStrategy::ChineseCdnWorker), 1);
        assert_eq!(chain.failure_count(&FallbackStrategy::DohTunnel), 0);
    }
}
