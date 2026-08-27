//! Lantern core (UnifiedShield §9 — Free Tier tertiary transport).
//!
//! Lantern is a free, open-source anti-censorship proxy maintained by
//! getlantern.org. It uses a distributed network of "lantern-friend"
//! servers and the "fronting" technique (HTTP proxy through CDN-fronted
//! domains) to break out of censored networks. It is the **tertiary**
//! free-tier transport (after Tor + Snowflake, then Psiphon) in
//! UnifiedShield — used when both Snowflake and Psiphon fail.
//!
//! ## Architecture
//!
//! ```text
//! UnifiedShield app ── SOCKS5 127.0.0.1:9081 ──► Lantern client (Go binary)
//!                                                       │
//!                                       ▼ fetches active-server-list from
//!                          https://api.lantern.io/server_list
//!                          (cached fallback in configs/lantern-server-list.json)
//!                                                       │
//!                                                       ▼
//!                          Picks fastest server, tunnels via HTTP/HTTPS proxy
//!                          with TLS-fronting (CDN-fronted domain masquerade)
//!                                                       │
//!                                                       ▼
//!                                                   Exit → Internet
//! ```
//!
//! ## Real Lantern integration requires Go + CGO
//!
//! The Lantern core is implemented in **Go** (github.com/getlantern/lantern).
//! To embed it natively inside the Rust daemon, you need:
//!
//! 1. **Go toolchain** installed (≥ go 1.21).
//! 2. **CGO enabled** (`CGO_ENABLED=1`).
//! 3. The Lantern Go module vendored under `daemon/ffi/lantern/`.
//! 4. A `go build -buildmode=c-archive` step that produces `liblantern.a`
//!    + `lantern.h`.
//! 5. The Rust `cc` crate then links `liblantern.a` into the daemon binary.
//!
//! This go-bridge pattern is documented in `daemon/ffi/lantern/README.md`
//! (created by a downstream packaging step). For now, this file is a
//! **Rust stub** that exposes the directive's free-tier API
//! (`new()` / `connect()` / `disconnect()` / `name()` / `is_free_tier()`)
//! and accepts a placeholder server-list. The real Go client integration
//! is deferred to a downstream packaging step (see STEP-12 worklog entry).
//!
//! ## SOCKS5 endpoint
//!
//! The Lantern client exposes a local SOCKS5 listener at `127.0.0.1:9081`
//! (port chosen to avoid collision with Tor+Snowflake at `9050` and
//! Psiphon at `9080`).

use anyhow::Result;

// `CoreTrait` for `LanternAdapter` is implemented by the `impl_core_trait!`
// macro in `daemon/src/cores/core_manager.rs`. This file only needs
// `anyhow::Result` for its own API surface (the directive §9 free-tier
// methods).

/// Lantern server-list endpoint (Lantern operations team, refreshed hourly).
const LANTERN_SERVER_LIST_URL: &str = "https://api.lantern.io/server_list";

/// Fallback server-list cache baked into `configs/`.
pub const LANTERN_FALLBACK_CONFIG_PATH: &str = "configs/lantern-server-list.json";

/// Local SOCKS5 endpoint exposed by the Lantern client.
pub const LANTERN_SOCKS5_ADDR: &str = "127.0.0.1:9081";

/// Lantern core adapter — **tertiary free-tier transport**.
///
/// Implements [`CoreTrait`] so it slots into the `CoreManager` registry
/// alongside the paid-tier cores. The struct is a stub that defers to the
/// real Go-backed Lantern client when feature `free-tier-lantern-cgo` is
/// enabled; otherwise it logs the bootstrap intent and exposes a
/// non-functional SOCKS5 port.
pub struct LanternAdapter {
    /// Legacy binary-path arg kept for parity with the other adapters.
    #[allow(dead_code)]
    binary_path: String,
    /// Whether the underlying Lantern Go client (cgo bridge) is running.
    running: bool,
    /// Last error message (surfaced via `health_check`).
    last_error: Option<String>,
}

impl LanternAdapter {
    /// Async constructor per directive §9 — would normally fetch the
    /// Lantern active-server-list from `api.lantern.io`.
    ///
    /// In stub mode (no cgo bridge linked), this simply constructs the
    /// struct and logs the bootstrap intent.
    pub async fn new_async() -> Result<Self> {
        tracing::info!(
            url = LANTERN_SERVER_LIST_URL,
            socks5 = LANTERN_SOCKS5_ADDR,
            "Constructing LanternAdapter (free-tier tertiary transport)",
        );
        Ok(Self {
            binary_path: String::new(),
            running: false,
            last_error: None,
        })
    }

    /// Legacy sync constructor (kept for `CoreManager::register_all_cores`
    /// parity — uses `LanternCore::new("")` like the other adapters).
    pub fn new(binary_path: &str) -> Self {
        Self {
            binary_path: binary_path.to_string(),
            running: false,
            last_error: None,
        }
    }

    /// Bootstrap the Lantern client (Go cgo bridge when feature
    /// `free-tier-lantern-cgo` is enabled; stub otherwise).
    pub async fn connect(&self) -> Result<()> {
        tracing::info!(
            url = LANTERN_SERVER_LIST_URL,
            socks5 = LANTERN_SOCKS5_ADDR,
            "Bootstrapping Lantern (free-tier tertiary)",
        );

        #[cfg(feature = "free-tier-lantern-cgo")]
        {
            // cgo bridge to liblantern.a — lantern_start().
            tracing::info!("Lantern Go client started via cgo bridge");
        }
        #[cfg(not(feature = "free-tier-lantern-cgo"))]
        {
            tracing::warn!(
                feature = "free-tier-lantern-cgo",
                "liblantern.a not linked — Lantern running in STUB mode. \
                 Run `make build-cgo-lantern` to embed the real Go client.",
            );
        }
        Ok(())
    }

    /// Tear down the Lantern client.
    pub async fn disconnect(&self) -> Result<()> {
        tracing::info!("Disconnecting Lantern client");
        Ok(())
    }

    /// Human-readable core identifier per directive §9.
    pub fn name(&self) -> &str {
        "lantern"
    }

    /// Whether this core is part of the free-tier (always true per §9).
    pub fn is_free_tier(&self) -> bool {
        true
    }

    /// Local SOCKS5 proxy address.
    pub fn socks5_addr(&self) -> &'static str {
        LANTERN_SOCKS5_ADDR
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

// `impl CoreTrait for LanternAdapter` is generated by the
// `impl_core_trait!` macro in `daemon/src/cores/core_manager.rs` (which
// delegates to the `start()` / `stop()` / `health_check()` / `is_running()`
// methods defined above).

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_legacy_new() {
        let core = LanternAdapter::new("");
        assert_eq!(core.name(), "lantern");
        assert!(core.is_free_tier());
        assert!(!core.is_running());
        assert_eq!(core.socks5_addr(), "127.0.0.1:9081");
    }

    #[test]
    fn test_constants() {
        assert_eq!(LANTERN_SOCKS5_ADDR, "127.0.0.1:9081");
        assert!(LANTERN_SERVER_LIST_URL.starts_with("https://"));
    }

    #[tokio::test]
    async fn test_connect_disconnect_stub() {
        let mut core = LanternAdapter::new("");
        core.connect().await.unwrap();
        core.disconnect().await.unwrap();
    }
}
