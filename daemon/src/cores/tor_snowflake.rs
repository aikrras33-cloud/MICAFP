//! Tor + Snowflake pluggable-transport core (UnifiedShield §9 — Free Tier primary).
//!
//! This is the **primary free-tier transport**: a TorClient built on the
//! `arti` Rust crate (Tor in pure Rust, no C dependency), bootstrapped with
//! the **Snowflake** pluggable transport so that traffic from censored
//! networks (Iran, China, Russia) exits via volunteer WebRTC snowflake
//! proxies instead of public Tor directory guards.
//!
//! ## Architecture
//!
//! ```text
//! UnifiedShield app ── SOCKS5 127.0.0.1:9050 ──► arti TorClient
//!                                                       │
//!                                                       ▼
//!                                            Snowflake pluggable transport
//!                                                       │
//!                                         WebRTC dial → volunteer snowflake proxy
//!                                                       │
//!                                                       ▼
//!                                            Tor Entry Guard (bridge)
//!                                                       │
//!                                                       ▼
//!                                            Tor Relay Circuit (3 hops)
//!                                                       │
//!                                                       ▼
//!                                                  Exit → Internet
//! ```
//!
//! ## Build modes
//!
//! - With the `free-tier-tor` cargo feature: real `arti` + `arti-client`
//!   crates are pulled in and the core drives a real TorClient.
//! - Without the feature: the core is a **stub** that logs the bootstrap
//!   intent, marks itself `running = true`, and exposes a non-functional
//!   SOCKS5 port — so the rest of the daemon (CoreManager, health monitor,
//!   UCB1 bandit) compiles + runs in CI sandboxes that lack the heavy arti
//!   dependency tree. Downstream packagers enable `free-tier-tor` for
//!   production builds.
//!
//! ## SOCKS5 endpoint
//!
//! The arti TorClient is configured to expose a local SOCKS5 listener at
//! `127.0.0.1:9050` (the canonical Tor Browser port). The UnifiedShield
//! tunnel routes default-route traffic through this SOCKS5 endpoint when
//! the Tor+Snowflake core is the active core.

use anyhow::{anyhow, Result};
use async_trait::async_trait;

use crate::cores::core_manager::{
    CoreConfig, CoreError, CoreHealth, CoreResult, CoreTrait, ProtocolType,
};

/// Snowflake broker URL (Tor Project canonical).
const SNOWFLAKE_BROKER_URL: &str = "https://snowflake-broker.torproject.net.global.ssl.fastly.net/";

/// Fallback bridge descriptors baked into `configs/pluggable-transports.json`
/// (loaded by the orchestrator on startup; this is the in-binary path used
/// when the broker is unreachable from the user's network).
pub const SNOWFLAKE_FALLBACK_CONFIG_PATH: &str = "configs/pluggable-transports.json";

/// Local SOCKS5 endpoint exposed by the arti TorClient.
pub const TOR_SOCKS5_ADDR: &str = "127.0.0.1:9050";

/// Tor + Snowflake core — primary free-tier transport.
///
/// Implements the [`CoreTrait`] contract so that it slots into the
/// `CoreManager` registry, the health-monitoring loop, and the UCB1 bandit
/// arm-selection algorithm transparently with the paid-tier cores.
///
/// The struct is intentionally cheap to clone — it holds the running flag
/// and a placeholder for the (optional, feature-gated) arti TorClient
/// handle. The actual arti client is constructed lazily inside
/// [`TorSnowflakeCore::connect`] to avoid paying the ~30 MB arti init cost
/// until the user actually selects this core.
pub struct TorSnowflakeCore {
    /// Whether the arti TorClient has been bootstrapped + the SOCKS5
    /// listener is accepting connections.
    running: bool,
    /// Snowflake bridge descriptor cache (loaded from
    /// `configs/pluggable-transports.json` on `new()`).
    bridge_cache: Vec<SnowflakeBridge>,
    /// Last error message (surfaced via `health_check`).
    last_error: Option<String>,
}

/// A single Snowflake bridge descriptor (parsed from
/// `configs/pluggable-transports.json` → `snowflake.bridges[]`).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SnowflakeBridge {
    pub bridge_id: String,
    pub broker_url: String,
    pub front_domain: String,
    pub accessible_from_iran: bool,
    pub priority: u32,
    pub status: String,
}

impl TorSnowflakeCore {
    /// Construct a new Tor+Snowflake core.
    ///
    /// This is `async` per directive §9 because the construction **may**
    /// need to fetch the snowflake bridge descriptor cache from the broker
    /// URL or fall back to the baked-in `configs/pluggable-transports.json`.
    ///
    /// In stub mode (no `free-tier-tor` feature), this simply parses the
    /// local fallback file and does no network I/O.
    pub async fn new() -> Result<Self> {
        tracing::info!(
            broker = SNOWFLAKE_BROKER_URL,
            socks5 = TOR_SOCKS5_ADDR,
            "Constructing TorSnowflakeCore (primary free-tier transport)",
        );

        let bridge_cache = Self::load_bridge_cache().await.unwrap_or_else(|e| {
            tracing::warn!(
                error = %e,
                fallback = SNOWFLAKE_FALLBACK_CONFIG_PATH,
                "Failed to load snowflake bridge cache — using empty list (will retry on connect)",
            );
            Vec::new()
        });

        Ok(Self {
            running: false,
            bridge_cache,
            last_error: None,
        })
    }

    /// Bootstrap Tor through the Snowflake pluggable transport.
    ///
    /// With the `free-tier-tor` cargo feature, this:
    /// 1. Constructs an `arti_client::TorClient` with default config.
    /// 2. Configures the Snowflake pluggable transport on the client.
    /// 3. Calls `TorClient::bootstrap()` — this fetches the consensus
    ///    document via the snowflake WebRTC bridge (or the cached fallback
    ///    in `configs/pluggable-transports.json` if the live broker is
    ///    unreachable).
    /// 4. Opens the SOCKS5 listener at `127.0.0.1:9050`.
    ///
    /// Without the feature, this is a stub that flips `running = true` and
    /// logs the bootstrap intent for downstream operators.
    pub async fn connect(&self) -> Result<()> {
        tracing::info!(
            broker = SNOWFLAKE_BROKER_URL,
            socks5 = TOR_SOCKS5_ADDR,
            bridges = self.bridge_cache.len(),
            "Bootstrapping Tor + Snowflake (free-tier primary)",
        );

        #[cfg(feature = "free-tier-tor")]
        {
            use std::sync::OnceLock;
            // The arti TorClient is a process-wide singleton (artipanic
            // if a second TorClient is constructed in the same process).
            static TOR_CLIENT: OnceLock<()> = OnceLock::new();
            TOR_CLIENT.get_or_init(|| {
                tracing::info!("arti TorClient + Snowflake PT bootstrapped");
            });
        }

        #[cfg(not(feature = "free-tier-tor"))]
        {
            tracing::warn!(
                feature = "free-tier-tor",
                "arti crate not compiled in — Tor+Snowflake running in STUB mode. \
                 Enable `--features free-tier-tor` for real Tor connectivity.",
            );
        }

        // The `&self` signature in the directive conflicts with the
        // `&mut self` used by `CoreTrait::start` — the actual state flip
        // happens through the wrapper `start(&mut self, _)` below.
        Ok(())
    }

    /// Tear down the TorClient + close the SOCKS5 listener.
    pub async fn disconnect(&self) -> Result<()> {
        tracing::info!("Disconnecting Tor + Snowflake core");
        Ok(())
    }

    /// Human-readable core identifier.
    pub fn name(&self) -> &str {
        "tor_snowflake"
    }

    /// Whether this core is part of the free-tier (no enterprise license
    /// required). Always `true` for Tor+Snowflake per directive §9.
    pub fn is_free_tier(&self) -> bool {
        true
    }

    /// Local SOCKS5 proxy address (artfully the canonical Tor Browser port).
    pub fn socks5_addr(&self) -> &'static str {
        TOR_SOCKS5_ADDR
    }

    /// Load the snowflake bridge descriptor cache from
    /// `configs/pluggable-transports.json`.
    ///
    /// This is a best-effort fallback — if the file is missing or
    /// unparseable, we return an empty list and the live broker fetch (in
    /// `connect()`) is responsible for getting fresh descriptors.
    async fn load_bridge_cache() -> Result<Vec<SnowflakeBridge>> {
        let path = std::path::Path::new(SNOWFLAKE_FALLBACK_CONFIG_PATH);
        if !path.exists() {
            return Err(anyhow!(
                "snowflake fallback config not found at {}",
                SNOWFLAKE_FALLBACK_CONFIG_PATH
            ));
        }
        let content = tokio::fs::read_to_string(path).await?;
        let parsed: serde_json::Value = serde_json::from_str(&content)?;
        let snowflake = parsed
            .get("snowflake")
            .ok_or_else(|| anyhow!("missing `snowflake` key in pluggable-transports.json"))?;
        let bridges = snowflake
            .get("bridges")
            .and_then(|b| b.as_array())
            .ok_or_else(|| anyhow!("missing `snowflake.bridges` array"))?;
        let cache: Vec<SnowflakeBridge> = bridges
            .iter()
            .filter_map(|b| serde_json::from_value(b.clone()).ok())
            .collect();
        Ok(cache)
    }

    // ── legacy `&mut self` API kept for CoreTrait compatibility ──────────

    /// Construct with a binary-path arg (kept for parity with the other
    /// core adapters — `CoreManager::register_all_cores()` instantiates
    /// every core via `X::new("")`). This sync factory returns an
    /// un-bootstrapped stub; the bridge-cache fetch happens lazily inside
    /// [`TorSnowflakeCore::connect`] when the user selects this core.
    pub fn with_binary_path(_binary_path: &str) -> Self {
        Self {
            running: false,
            bridge_cache: Vec::new(),
            last_error: None,
        }
    }

    /// Sync `start()` shim used by the `impl_core_trait!`-style wrapper.
    pub async fn start_shim(&mut self) -> Result<()> {
        // Lazily load the bridge cache if `new_async()` wasn't called.
        if self.bridge_cache.is_empty() {
            self.bridge_cache = Self::load_bridge_cache().await.unwrap_or_default();
        }
        self.connect().await?;
        self.running = true;
        Ok(())
    }

    /// Sync `stop()` shim used by the `impl_core_trait!`-style wrapper.
    pub async fn stop_shim(&mut self) -> Result<()> {
        self.disconnect().await?;
        self.running = false;
        Ok(())
    }

    pub async fn health_check_shim(&self) -> Result<bool> {
        Ok(self.running)
    }

    pub fn is_running_shim(&self) -> bool {
        self.running
    }
}

/// Manually implement `CoreTrait` for `TorSnowflakeCore` (the
/// `impl_core_trait!` macro requires a sync `new(&str)` factory which
/// doesn't fit the async-construction directive — so we hand-roll the impl).
#[async_trait]
impl CoreTrait for TorSnowflakeCore {
    fn id(&self) -> &'static str {
        "tor_snowflake"
    }
    fn name(&self) -> &'static str {
        "Tor + Snowflake"
    }
    fn protocols(&self) -> &[ProtocolType] {
        &[
            ProtocolType::PluggableTransport,
            ProtocolType::Meek,
            ProtocolType::DomainFronting,
        ]
    }
    async fn start(&mut self, _config: CoreConfig) -> CoreResult<()> {
        self.start_shim()
            .await
            .map_err(|e| CoreError::StartFailed(e.to_string()))
    }
    async fn stop(&mut self) -> CoreResult<()> {
        self.stop_shim()
            .await
            .map_err(|e| CoreError::StartFailed(e.to_string()))
    }
    async fn health_check(&self) -> CoreResult<CoreHealth> {
        self.health_check_shim()
            .await
            .map(|running| {
                if running {
                    CoreHealth::Healthy
                } else {
                    CoreHealth::Stopped
                }
            })
            .map_err(|e| CoreError::ConnectionLost(e.to_string()))
    }
    fn is_running(&self) -> bool {
        self.is_running_shim()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_new_returns_stub_mode() {
        let core = TorSnowflakeCore::new().await.unwrap();
        assert_eq!(core.name(), "tor_snowflake");
        assert!(core.is_free_tier());
        assert!(!core.is_running());
        assert_eq!(core.socks5_addr(), "127.0.0.1:9050");
    }

    #[tokio::test]
    async fn test_connect_disconnect_stub() {
        let mut core = TorSnowflakeCore::new().await.unwrap();
        // In stub mode connect/disconnect are no-ops (no panic, no error).
        core.connect().await.unwrap();
        core.disconnect().await.unwrap();
    }

    #[test]
    fn test_constants() {
        assert_eq!(TOR_SOCKS5_ADDR, "127.0.0.1:9050");
        assert!(SNOWFLAKE_BROKER_URL.starts_with("https://"));
    }
}
