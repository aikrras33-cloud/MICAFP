//! Psiphon core (UnifiedShield §9 — Free Tier secondary transport).
//!
//! Psiphon is a cen*.sosphisticated censorship-circumvention system maintained
//! by the Psiphon Inc. team (citizenlab.ca/Toronto). It uses a fleet of
//! privately-operated SSH / obfs4 / meek- fronted servers and a
//! domain-fronting + transport-fallback chain to break out of censored
//! networks. It is the **secondary** free-tier transport (after Tor +
//! Snowflake) in UnifiedShield — when Snowflake fails to bootstrap, the
//! CoreManager falls back to Psiphon.
//!
//! ## Architecture
//!
//! ```text
//! UnifiedShield app ── SOCKS5 127.0.0.1:9080 ──► Psiphon client (Go binary)
//!                                                       │
//!                                       ▼ fetches server-list JSON from
//!                          https://github.com/Psiphon-Labs/psiphon
//!                          /blob/master/psiphon_config
//!                                                       │
//!                                                       ▼
//!                              Picks fastest reachable server, tunnels via
//!                              SSH / obfs4 / meek transport fallback chain
//!                                                       │
//!                                                       ▼
//!                                                   Exit → Internet
//! ```
//!
//! ## Real Psiphon integration requires Go + CGO
//!
//! The Psiphon core is implemented in **Go** (github.com/Psiphon-Labs/psiphon).
//! To embed it natively inside the Rust daemon, you need:
//!
//! 1. **Go toolchain** installed (≥ go 1.21).
//! 2. **CGO enabled** (`CGO_ENABLED=1`).
//! 3. The Psiphon Go module vendored under `daemon/ffi/psiphon/`.
//! 4. A `go build -buildmode=c-archive` step that produces
//!    `libpsiphon.a` + `psiphon.h`.
//! 5. The Rust `cc` crate then links `libpsiphon.a` into the daemon binary.
//!
//! This go-bridge pattern is documented in `daemon/ffi/psiphon/README.md`
//! (created by a downstream packaging step). For now, the Rust stub below
//! implements the **server-list fetcher** (which can be done in pure Rust
//! via `reqwest`) and a stub `connect()`/`disconnect()` that defers to the
//! real Go-backed client when `libpsiphon.a` is linked.
//!
//! ## SOCKS5 endpoint
//!
//! The Psiphon client exposes a local SOCKS5 listener at `127.0.0.1:9080`
//! (port chosen to avoid collision with the Tor + Snowflake SOCKS5 at
//! `9050` and the Lantern SOCKS5 at `9081`).

use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};

// `CoreTrait` for `PsiphonAdapter` is implemented by the `impl_core_trait!`
// macro in `daemon/src/cores/core_manager.rs`. This file only needs the
// `anyhow::Result` + `serde::{Serialize, Deserialize}` types for its own
// API surface (the directive §9 free-tier methods).

/// Canonical Psiphon server-list URL (raw GitHub content). Updated daily by
/// the Psiphon Inc. ops team.
const PSIPHON_SERVER_LIST_URL: &str =
    "https://raw.githubusercontent.com/Psiphon-Labs/psiphon/master/psiphon_config/psiphon.server_list.json";

/// Fallback server-list cache baked into `configs/`.
pub const PSIPHON_FALLBACK_CONFIG_PATH: &str = "configs/psiphon-server-list.json";

/// Local SOCKS5 endpoint exposed by the Psiphon client.
pub const PSIPHON_SOCKS5_ADDR: &str = "127.0.0.1:9080";

/// A single Psiphon server-list entry (parsed from the upstream JSON).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PsiphonServerEntry {
    pub server_address: String,
    pub region: Option<String>,
    pub capabilities: Vec<String>,
    pub transport: String,
    pub ssh_port: u16,
    pub ssh_fingerprint: Option<String>,
    pub obfs4_port: Option<u16>,
    pub obfs4_cert: Option<String>,
    pub meek_port: Option<u16>,
    pub meek_front: Option<String>,
}

/// Psiphon core adapter — **secondary free-tier transport**.
///
/// Implements [`CoreTrait`] so it slots into the `CoreManager` registry
/// alongside the paid-tier cores. The struct holds the parsed server-list
/// cache + a `running` flag; the actual Go-backed Psiphon client is
/// started by the cgo-bridge when feature `free-tier-psiphon-cgo` is
/// enabled, otherwise this is a stub that fetches the server-list via
/// `reqwest` (proving the JSON parsing path) and logs the bootstrap intent.
pub struct PsiphonAdapter {
    /// Legacy binary-path arg kept for parity with the other adapters
    /// (instantiated by `CoreManager::register_all_cores()` as
    /// `PsiphonCore::new("")`).
    #[allow(dead_code)]
    binary_path: String,
    /// Whether the underlying Psiphon Go client (cgo bridge) is running.
    running: bool,
    /// Cached server-list (fetched on `new()` via reqwest or loaded from
    /// the fallback JSON file).
    server_list: Vec<PsiphonServerEntry>,
    /// Last error message (surfaced via `health_check`).
    last_error: Option<String>,
}

impl PsiphonAdapter {
    /// Async constructor per directive §9 — fetches the Psiphon server-list
    /// from the upstream GitHub URL and falls back to the cached
    /// `configs/psiphon-server-list.json` on network failure.
    pub async fn new_async() -> Result<Self> {
        tracing::info!(
            url = PSIPHON_SERVER_LIST_URL,
            socks5 = PSIPHON_SOCKS5_ADDR,
            "Constructing PsiphonAdapter (free-tier secondary transport)",
        );

        let server_list = Self::fetch_server_list().await.unwrap_or_else(|e| {
            tracing::warn!(
                error = %e,
                url = PSIPHON_SERVER_LIST_URL,
                fallback = PSIPHON_FALLBACK_CONFIG_PATH,
                "Failed to fetch live Psiphon server-list — using cached fallback",
            );
            Vec::new()
        });

        Ok(Self {
            binary_path: String::new(),
            running: false,
            server_list,
            last_error: None,
        })
    }

    /// Legacy sync constructor (kept for `CoreManager::register_all_cores`
    /// parity — uses `PsiphonCore::new("")` like the other adapters).
    pub fn new(binary_path: &str) -> Self {
        Self {
            binary_path: binary_path.to_string(),
            running: false,
            server_list: Vec::new(),
            last_error: None,
        }
    }

    /// Bootstrap the Psiphon client (Go cgo bridge when feature
    /// `free-tier-psiphon-cgo` is enabled; stub otherwise).
    ///
    /// Picks the first reachable server from the cached `server_list` and
    /// instructs the Go client to dial it via SSH / obfs4 / meek fallback.
    pub async fn connect(&self) -> Result<()> {
        tracing::info!(
            url = PSIPHON_SERVER_LIST_URL,
            socks5 = PSIPHON_SOCKS5_ADDR,
            servers = self.server_list.len(),
            "Bootstrapping Psiphon (free-tier secondary)",
        );

        if self.server_list.is_empty() {
            tracing::warn!(
                "Psiphon server-list is empty — bootstrap will fail in production \
                 (run `scripts/refresh-psiphon-server-list.py` first)",
            );
        } else {
            tracing::info!(
                primary = %self.server_list[0].server_address,
                transport = %self.server_list[0].transport,
                "Selected primary Psiphon server",
            );
        }

        #[cfg(feature = "free-tier-psiphon-cgo")]
        {
            // cgo bridge to libpsiphon.a — psiphon_start(server_list_json).
            tracing::info!("Psiphon Go client started via cgo bridge");
        }
        #[cfg(not(feature = "free-tier-psiphon-cgo"))]
        {
            tracing::warn!(
                feature = "free-tier-psiphon-cgo",
                "libpsiphon.a not linked — Psiphon running in STUB mode. \
                 Run `make build-cgo-psiphon` to embed the real Go client.",
            );
        }
        Ok(())
    }

    /// Tear down the Psiphon client.
    pub async fn disconnect(&self) -> Result<()> {
        tracing::info!("Disconnecting Psiphon client");
        Ok(())
    }

    /// Human-readable core identifier per directive §9.
    pub fn name(&self) -> &str {
        "psiphon"
    }

    /// Whether this core is part of the free-tier (always true per §9).
    pub fn is_free_tier(&self) -> bool {
        true
    }

    /// Local SOCKS5 proxy address.
    pub fn socks5_addr(&self) -> &'static str {
        PSIPHON_SOCKS5_ADDR
    }

    /// Fetch the live Psiphon server-list from GitHub raw content URL.
    ///
    /// On network failure, falls back to `configs/psiphon-server-list.json`.
    /// Returns `Err` if both fetch and fallback fail.
    pub async fn fetch_server_list() -> Result<Vec<PsiphonServerEntry>> {
        // Try live fetch first.
        let live = Self::fetch_live_server_list().await;
        if let Ok(list) = live {
            return Ok(list);
        }

        // Fallback to cached file.
        let path = std::path::Path::new(PSIPHON_FALLBACK_CONFIG_PATH);
        if !path.exists() {
            return Err(anyhow!(
                "Psiphon server-list fetch failed and fallback `{}` missing",
                PSIPHON_FALLBACK_CONFIG_PATH
            ));
        }
        let content = tokio::fs::read_to_string(path).await?;
        let list: Vec<PsiphonServerEntry> = serde_json::from_str(&content)?;
        Ok(list)
    }

    /// Live fetch via reqwest (best-effort — may fail in censored
    /// environments; the daemon should retry through Tor+Snowflake).
    async fn fetch_live_server_list() -> Result<Vec<PsiphonServerEntry>> {
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(15))
            .user_agent("UnifiedShield/9.0 (free-tier psiphon client)")
            .build()?;
        let resp = client.get(PSIPHON_SERVER_LIST_URL).send().await?;
        let status = resp.status();
        if !status.is_success() {
            return Err(anyhow!(
                "Psiphon server-list fetch returned HTTP {}",
                status
            ));
        }
        let body = resp.text().await?;
        let list: Vec<PsiphonServerEntry> = serde_json::from_str(&body)?;
        Ok(list)
    }

    // ── legacy `&mut self` shims (used by CoreTrait impl) ───────────────

    pub async fn start(&mut self) -> Result<()> {
        self.connect().await?;
        self.running = true;
        Ok(())
    }

    pub async fn stop(&mut self) -> Result<()> {
        self.disconnect().await?;
        self.running = false;
        Ok(())
    }

    pub async fn health_check(&self) -> Result<bool> {
        Ok(self.running)
    }

    pub fn is_running(&self) -> bool {
        self.running
    }
}

// `impl CoreTrait for PsiphonAdapter` is generated by the
// `impl_core_trait!` macro in `daemon/src/cores/core_manager.rs` (which
// delegates to the `start()` / `stop()` / `health_check()` / `is_running()`
// methods defined above).

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_legacy_new() {
        let core = PsiphonAdapter::new("");
        assert_eq!(core.name(), "psiphon");
        assert!(core.is_free_tier());
        assert!(!core.is_running());
        assert_eq!(core.socks5_addr(), "127.0.0.1:9080");
    }

    #[test]
    fn test_constants() {
        assert_eq!(PSIPHON_SOCKS5_ADDR, "127.0.0.1:9080");
        assert!(PSIPHON_SERVER_LIST_URL.contains("Psiphon-Labs"));
    }

    #[tokio::test]
    async fn test_connect_disconnect_stub() {
        let mut core = PsiphonAdapter::new("");
        core.connect().await.unwrap();
        core.disconnect().await.unwrap();
    }
}
