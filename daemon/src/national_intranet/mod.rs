// ─────────────────────────────────────────────────────────────────────────────
// National Intranet / NAIN detection subsystem
// MICAFP-UnifiedShield-vip-ultra-Quantum-ultra v8.0
// ─────────────────────────────────────────────────────────────────────────────

pub mod acoustic_covert;
pub mod ble_mesh;
pub mod fallback_routing;
pub mod intranet_detector;
pub mod iran_ip_ranges;
pub mod local_dns_resolver;
pub mod nain_detector;
pub mod ntp_covert;
pub mod sms_bootstrap;
pub mod wifi_aware;

pub use ble_mesh::BleMeshConfig;
pub use fallback_routing::FallbackRouting;
pub use intranet_detector::IntranetDetector;
pub use iran_ip_ranges::IranIpRanges;
pub use local_dns_resolver::LocalDnsResolver;
pub use nain_detector::NainDetector;
pub use ntp_covert::NtpCovertChannel;
pub use sms_bootstrap::SmsBootstrapChannel;
pub use wifi_aware::WifiAwareMesh;

pub type NainFallbackRouter = FallbackRouting;
pub type BleMeshTransport = BleMeshConfig;
pub type WifiAwareTransport = WifiAwareMesh;
pub type SmsBootstrap = SmsBootstrapChannel;
pub type AcousticCovertChannel = acoustic_covert::AcousticPayload;

// ─────────────────────────────────────────────────────────────────────────────
// NationalIntranetSubsystem — thin orchestrator-facing facade introduced per
// directive §3.2. Owns a `NainDetector` initialised with a fresh
// `NainState` and stores the daemon config so the background detection
// task can read `intranet.check_interval_secs` & `iranian_dns_servers`.
//
// Future step: spawn the actual adaptive-probe background task and expose
// `last_status()` / `coalesce_with_ntp()` to the orchestrator.
// ─────────────────────────────────────────────────────────────────────────────
use std::sync::Arc;

use tokio::sync::RwLock;

use crate::config::schema::ShieldConfig;

pub struct NationalIntranetSubsystem {
    /// Snapshot of the daemon config (read by background tasks).
    pub config: Arc<ShieldConfig>,
    /// Shared mutable NAIN state.
    pub state: Arc<RwLock<NainState>>,
    /// Underlying NAIN detector (probes international/domestic reachability).
    pub detector: Option<nain_detector::NainDetector>,
}

impl NationalIntranetSubsystem {
    pub fn new(config: Arc<ShieldConfig>) -> Self {
        let state = Arc::new(RwLock::new(NainState::default()));
        // NainDetector::new is fallible (returns Result) but never actually
        // fails for the ShieldError path; if it ever does, we degrade
        // gracefully by leaving `detector = None` and logging.
        let detector = match nain_detector::NainDetector::new(Arc::clone(&state)) {
            Ok(d) => Some(d),
            Err(e) => {
                tracing::warn!(error = %e, "NainDetector init failed — subsystem degraded");
                None
            }
        };
        Self {
            config,
            state,
            detector,
        }
    }
}

impl Default for NationalIntranetSubsystem {
    fn default() -> Self {
        Self::new(Arc::new(ShieldConfig::default()))
    }
}

// ── Shared NAIN status types ─────────────────────────────────────────────────

/// Detection status reported by the NAIN module.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum NainStatus {
    /// Full internet access — no national intranet detected.
    FullInternet,
    /// National intranet only — international internet blocked.
    NainOnly,
    /// Complete network blackout — all connectivity lost.
    CompleteBlackout,
    /// Unknown or transitioning state.
    Unknown,
}

/// Internal mutable state for the NAIN detector.
#[derive(Debug, Clone, Default)]
pub struct NainState {
    pub last_status: Option<NainStatus>,
    pub check_count: u64,
    pub nain_active: bool,
    pub confirmation_count: u64,
    pub screen_on: bool,
    pub is_charging: bool,
    pub power_mode: u8,
}
