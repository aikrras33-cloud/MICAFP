use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

// ─────────────────────────────────────────────────────────────────────────────
// ShieldConfig — the canonical top-level configuration for the UnifiedShield
// daemon. Renamed from `AppConfig` per GEMINI-ENG-DIR-V1.0 §3.3.
//
// Search order for `load_or_default()` (§3.3):
//   1. `./config.toml`                 (cwd-local override, useful for tests)
//   2. `/etc/unifiedshield/config.toml` (system-wide deployment)
//   3. `$XDG_CONFIG_HOME/unifiedshield/config.toml`
//         (falls back to `~/.config/unifiedshield/config.toml` if
//         `XDG_CONFIG_HOME` is unset, via the `dirs` crate).
// If none of these files are present, `ShieldConfig::default()` is returned.
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShieldConfig {
    #[serde(default)]
    pub tunnel: TunnelConfig,
    #[serde(default)]
    pub transport: TransportConfig,
    #[serde(default)]
    pub ai: AiConfig,
    #[serde(default)]
    pub intranet: IntranetConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TunnelConfig {
    #[serde(default = "default_mtu")]
    pub mtu: u16,
    #[serde(default = "default_addr")]
    pub address: String,
    #[serde(default = "default_iran_path")]
    pub iran_ip_ranges_path: String,
    #[serde(default = "default_true")]
    pub split_tunnel_enabled: bool,
    #[serde(default = "default_true")]
    pub kill_switch_enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransportConfig {
    #[serde(default = "default_true")]
    pub chinese_cdn_primary: bool,
    /// Default transport combo per directive §3.2 — `"vless+reality+shadowtls"`.
    #[serde(default = "default_active_transport")]
    pub active_transport: String,
    /// Default core per directive §3.2 — `"hiddify"` is a reasonable default
    /// (chosen over Xray because Hiddify's config surface is simpler).
    #[serde(default = "default_active_core")]
    pub active_core: String,
    #[serde(default)]
    pub cloudflare_worker_urls: Vec<String>,
    #[serde(default)]
    pub mqtt_brokers: Vec<String>,
    #[serde(default)]
    pub p2p_bootstrap_peers: Vec<String>,
    #[serde(default)]
    pub meek_bridges: Vec<String>,
    #[serde(default)]
    pub snowflake_broker: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiConfig {
    #[serde(default = "default_dpi_model")]
    pub dpi_model_path: String,
    #[serde(default = "default_pred_model")]
    pub predictor_model_path: String,
    #[serde(default = "default_threshold")]
    pub confidence_threshold: f32,
    #[serde(default = "default_alpha")]
    pub ucb_alpha: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntranetConfig {
    #[serde(default = "default_true")]
    pub auto_detect: bool,
    #[serde(default)]
    pub iranian_dns_servers: Vec<String>,
    #[serde(default = "default_check_interval")]
    pub check_interval_secs: u64,
}

impl Default for ShieldConfig {
    fn default() -> Self {
        Self {
            tunnel: TunnelConfig::default(),
            transport: TransportConfig::default(),
            ai: AiConfig::default(),
            intranet: IntranetConfig::default(),
        }
    }
}

impl Default for TunnelConfig {
    fn default() -> Self {
        Self {
            mtu: 1380,
            address: "172.19.0.1".into(),
            iran_ip_ranges_path: "/etc/unifiedshield/iran-ip-ranges.json".into(),
            split_tunnel_enabled: true,
            kill_switch_enabled: true,
        }
    }
}

impl Default for TransportConfig {
    fn default() -> Self {
        Self {
            chinese_cdn_primary: true,
            active_transport: default_active_transport(),
            active_core: default_active_core(),
            cloudflare_worker_urls: vec![],
            mqtt_brokers: vec!["broker.hivemq.com:1883".into()],
            p2p_bootstrap_peers: vec![],
            meek_bridges: vec!["azure".into()],
            snowflake_broker: "https://snowflake-broker.torproject.net/".into(),
        }
    }
}

impl Default for IntranetConfig {
    fn default() -> Self {
        Self {
            auto_detect: true,
            iranian_dns_servers: vec!["10.202.10.10".into(), "78.157.42.100".into()],
            check_interval_secs: 30,
        }
    }
}

impl Default for AiConfig {
    fn default() -> Self {
        Self {
            dpi_model_path: "ai-models/models/dpi_classifier.onnx".into(),
            predictor_model_path: "ai-models/models/traffic_predictor.onnx".into(),
            confidence_threshold: 0.72,
            ucb_alpha: 1.414,
        }
    }
}

impl ShieldConfig {
    /// Parse a TOML string into a `ShieldConfig`.
    ///
    /// Accepts an empty / `{}` body and returns `default()` in that case
    /// (preserves the previous JSON-style behaviour for legacy callers).
    pub fn from_toml(toml_str: &str) -> Result<Self> {
        let trimmed = toml_str.trim();
        if trimmed.is_empty() || trimmed == "{}" {
            return Ok(Self::default());
        }
        toml::from_str(trimmed).context("Failed to parse ShieldConfig TOML")
    }

    /// Parse a JSON string into a `ShieldConfig` (legacy compatibility shim —
    /// some callers still hand us JSON blobs).
    pub fn from_json(json: &str) -> Result<Self> {
        let trimmed = json.trim();
        if trimmed.is_empty() || trimmed == "{}" {
            return Ok(Self::default());
        }
        serde_json::from_str(trimmed).context("Failed to parse ShieldConfig JSON")
    }

    /// Return the ordered list of candidate config-file paths to probe.
    ///
    /// Per directive §3.3 the search order is:
    ///   1. `./config.toml`                      (cwd-local override)
    ///   2. `/etc/unifiedshield/config.toml`     (system deployment)
    ///   3. `$XDG_CONFIG_HOME/unifiedshield/config.toml`
    ///        (or `~/.config/unifiedshield/config.toml` if XDG is unset).
    pub fn config_search_paths() -> Vec<PathBuf> {
        let mut paths = Vec::with_capacity(3);
        paths.push(PathBuf::from("./config.toml"));
        paths.push(PathBuf::from("/etc/unifiedshield/config.toml"));
        if let Some(xdg) = std::env::var_os("XDG_CONFIG_HOME") {
            if !xdg.is_empty() {
                paths.push(PathBuf::from(xdg).join("unifiedshield").join("config.toml"));
            }
        } else if let Some(cfg) = dirs::config_dir() {
            paths.push(cfg.join("unifiedshield").join("config.toml"));
        }
        paths
    }

    /// Load configuration from the first existing standard path, or return
    /// defaults if no config file is present.
    ///
    /// Per directive §3.3, this is the canonical entry point used by the
    /// daemon's `main()`.
    pub fn load_or_default() -> Result<Self> {
        for candidate in Self::config_search_paths() {
            if candidate.exists() {
                tracing::debug!(path = %candidate.display(), "Loading ShieldConfig");
                let body = std::fs::read_to_string(&candidate)
                    .with_context(|| format!("read config {}", candidate.display()))?;
                return Self::from_toml(&body);
            }
        }
        tracing::debug!("No ShieldConfig.toml found — using defaults");
        Ok(Self::default())
    }
}

// ── Default value helpers (referenced by `#[serde(default = "...")]` above).
// These MUST keep their current signatures — renaming or removing them will
// break the `#[serde(default = "...")]` attributes on the config fields.
// ─────────────────────────────────────────────────────────────────────────────

fn default_mtu() -> u16 {
    1380
}
fn default_addr() -> String {
    "172.19.0.1".into()
}
fn default_iran_path() -> String {
    "/etc/unifiedshield/iran-ip-ranges.json".into()
}
fn default_true() -> bool {
    true
}
fn default_dpi_model() -> String {
    "ai-models/models/dpi_classifier.onnx".into()
}
fn default_pred_model() -> String {
    "ai-models/models/traffic_predictor.onnx".into()
}
fn default_threshold() -> f32 {
    0.72
}
fn default_alpha() -> f64 {
    1.414
}
fn default_check_interval() -> u64 {
    30
}
fn default_active_transport() -> String {
    "vless+reality+shadowtls".into()
}
fn default_active_core() -> String {
    "hiddify".into()
}
