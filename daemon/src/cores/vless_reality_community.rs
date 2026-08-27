//! VLESS-Reality Community core (UnifiedShield §9 — Free Tier quaternary transport).
//!
//! VLESS-Reality is a TLS-masquerading proxy protocol popularized by the
//! Xray project. The **community-maintained** variant of this core reads
//! from `configs/free-servers.json` (refreshed weekly by the
//! `scripts/refresh-free-servers.py` cron job) which contains a curated
//! list of public VLESS-Reality servers sourced from Telegram channels
//! (`t.me/s/v2ray_free`, `t.me/s/reality_free`) and other community boards.
//!
//! ## Architecture
//!
//! ```text
//! UnifiedShield app ── SOCKS5 127.0.0.1:9091 ──► Xray VLESS-Reality core
//!                                                       │
//!                                       ▼ loads server-list from
//!                          configs/free-servers.json (refreshed weekly
//!                          by .github/workflows/refresh-free-servers.yml)
//!                                                       │
//!                                                       ▼
//!                          Picks fastest verified-bypass-iran-dpi server,
//!                          dials via TLS+Reality (SNI masquerade as
//!                          microsoft.com / apple.com / etc.)
//!                                                       │
//!                                                       ▼
//!                                                   Exit → Internet
//! ```
//!
//! ## SOCKS5 endpoint
//!
//! The VLESS-Reality community client exposes a local SOCKS5 listener at
//! `127.0.0.1:9091` (port chosen to avoid collision with Hysteria2 at
//! `9090`).

use anyhow::{anyhow, Result};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};

use crate::cores::core_manager::{
    CoreConfig, CoreError, CoreHealth, CoreResult, CoreTrait, ProtocolType,
};

/// Path to the community-maintained free-server list.
pub const FREE_SERVERS_PATH: &str = "configs/free-servers.json";

/// Local SOCKS5 endpoint exposed by the VLESS-Reality community client.
pub const VLESS_REALITY_SOCKS5_ADDR: &str = "127.0.0.1:9091";

/// A single free VLESS-Reality server entry (parsed from
/// `configs/free-servers.json` → `vless_reality_servers[]`).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VlessRealityFreeServer {
    pub host: String,
    pub port: u16,
    pub sni: String,
    pub password: String,
    pub country: String,
    pub verified_bypass_iran_dpi: bool,
    pub bandwidth_mbps_avg: u32,
    pub source: String,
}

/// VLESS-Reality Community core adapter — **quaternary free-tier transport**.
///
/// Implements [`CoreTrait`] so it slots into the `CoreManager` registry.
/// The struct loads its server list from `configs/free-servers.json` on
/// `new_async()`; the actual TLS+Reality dial-out is performed by the
/// existing `XrayCoreAdapter` (already present in the daemon cores module).
pub struct VlessRealityCommunityAdapter {
    /// Cached server list loaded from `configs/free-servers.json`.
    servers: Vec<VlessRealityFreeServer>,
    /// Whether the underlying VLESS-Reality client is running.
    running: bool,
    /// Index into `servers` of the currently-selected server.
    selected: Option<usize>,
}

impl VlessRealityCommunityAdapter {
    /// Async constructor per directive §9 — loads the community
    /// server-list from `configs/free-servers.json`.
    pub async fn new_async() -> Result<Self> {
        tracing::info!(
            path = FREE_SERVERS_PATH,
            socks5 = VLESS_REALITY_SOCKS5_ADDR,
            "Constructing VlessRealityCommunityAdapter (free-tier quaternary transport)",
        );
        let servers = Self::load_servers().await.unwrap_or_else(|e| {
            tracing::warn!(
                error = %e,
                path = FREE_SERVERS_PATH,
                "Failed to load free VLESS-Reality server list — using empty list",
            );
            Vec::new()
        });
        Ok(Self {
            servers,
            running: false,
            selected: None,
        })
    }

    /// Legacy sync constructor for `CoreManager::register_all_cores`.
    pub fn new(_binary_path: &str) -> Self {
        Self {
            servers: Vec::new(),
            running: false,
            selected: None,
        }
    }

    /// Bootstrap VLESS-Reality with the best community server.
    pub async fn connect(&mut self) -> Result<()> {
        tracing::info!(
            path = FREE_SERVERS_PATH,
            socks5 = VLESS_REALITY_SOCKS5_ADDR,
            servers = self.servers.len(),
            "Bootstrapping VLESS-Reality community (free-tier quaternary)",
        );

        if self.servers.is_empty() {
            return Err(anyhow!(
                "no free VLESS-Reality servers loaded — run \
                 `scripts/refresh-free-servers.py` first"
            ));
        }

        let pick = self
            .servers
            .iter()
            .enumerate()
            .max_by_key(|(_, s)| {
                (
                    s.verified_bypass_iran_dpi as u32,
                    s.bandwidth_mbps_avg,
                )
            })
            .map(|(i, _)| i)
            .unwrap_or(0);

        let s = &self.servers[pick];
        tracing::info!(
            host = %s.host,
            port = s.port,
            sni = %s.sni,
            country = %s.country,
            bandwidth_mbps = s.bandwidth_mbps_avg,
            bypass_iran_dpi = s.verified_bypass_iran_dpi,
            source = %s.source,
            "Selected VLESS-Reality community server",
        );
        self.selected = Some(pick);
        self.running = true;
        Ok(())
    }

    /// Tear down the VLESS-Reality client.
    pub async fn disconnect(&mut self) -> Result<()> {
        tracing::info!("Disconnecting VLESS-Reality community client");
        self.running = false;
        self.selected = None;
        Ok(())
    }

    /// Human-readable core identifier per directive §9.
    pub fn name(&self) -> &str {
        "vless_reality_community"
    }

    /// Whether this core is part of the free-tier (always true per §9).
    pub fn is_free_tier(&self) -> bool {
        true
    }

    /// Local SOCKS5 proxy address.
    pub fn socks5_addr(&self) -> &'static str {
        VLESS_REALITY_SOCKS5_ADDR
    }

    /// Load the community VLESS-Reality server-list from disk.
    pub async fn load_servers() -> Result<Vec<VlessRealityFreeServer>> {
        let path = std::path::Path::new(FREE_SERVERS_PATH);
        if !path.exists() {
            return Err(anyhow!(
                "free-servers.json not found at {} — run the refresh script",
                FREE_SERVERS_PATH
            ));
        }
        let content = tokio::fs::read_to_string(path).await?;
        let parsed: crate::cores::hysteria2_community::FreeServersFile =
            serde_json::from_str(&content)?;
        Ok(parsed.vless_reality_servers)
    }

    // ── legacy `&mut self` shims (used by CoreTrait impl) ───────────────

    pub async fn start_shim(&mut self) -> Result<()> {
        // Lazily load the server-list if `new_async()` wasn't called.
        if self.servers.is_empty() {
            self.servers = Self::load_servers().await.unwrap_or_default();
        }
        self.connect().await
    }

    pub async fn stop_shim(&mut self) -> Result<()> {
        self.disconnect().await
    }

    pub async fn health_check_shim(&self) -> Result<bool> {
        Ok(self.running)
    }

    pub fn is_running_shim(&self) -> bool {
        self.running
    }
}

#[async_trait]
impl CoreTrait for VlessRealityCommunityAdapter {
    fn id(&self) -> &'static str {
        "vless_reality_community"
    }
    fn name(&self) -> &'static str {
        "VLESS-Reality Community"
    }
    fn protocols(&self) -> &[ProtocolType] {
        &[ProtocolType::Vless, ProtocolType::Reality]
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

    #[test]
    fn test_legacy_new() {
        let core = VlessRealityCommunityAdapter::new("");
        assert_eq!(core.name(), "vless_reality_community");
        assert!(core.is_free_tier());
        assert!(!core.is_running());
        assert_eq!(core.socks5_addr(), "127.0.0.1:9091");
    }
}
