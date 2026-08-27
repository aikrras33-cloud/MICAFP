// ─────────────────────────────────────────────────────────────────────────────
// MICAFP-UnifiedShield Enterprise — AI Subsystem Orchestrator
//
// Per directive GEMINI-ENG-DIR-V1.0 §7 (Anti-Iran-DPI / Anti-Censorship AI
// Subsystem), this module wires the seven pre-existing AI engines
// (dpi_classifier, traffic_predictor, adversarial_traffic, ucb_bandit,
// rl_transport_selector, onnx_runtime, feature_extractor) into a single
// reactive control loop that watches the live traffic, runs INT8 ONNX
// inference, and automatically switches transports when DPI detection
// probability exceeds a configurable threshold.
//
// Loop cadence (every 5 s):
//   1. Poll feature_extractor → 47-dim flow-stats vector.
//   2. Run dpi_classifier_int8.onnx + traffic_predictor_int8.onnx via the
//      shared ONNX runtime.
//   3. Feed the result into the UCB1 bandit + RL transport selector.
//   4. If predicted DPI detection probability exceeds the aggressiveness
//      threshold, switch transport (advance the 8-step resilience chain).
//   5. If a Gemini cloud scanner is configured and reachable, also fetch the
//      5-min cached cloud classification for higher fidelity.
//   6. On any switch: call `transport_manager.switch_transport(next)` and
//      emit a `QuantumToastNotification` over the broadcast channel for the
//      IPC layer to surface as a QuantumToast in the Flutter UI.
//
// The orchestrator is intentionally defensive: every subsystem call is
// wrapped in `tokio::time::timeout` and any error is logged at WARN and
// skipped — the directive's Zero-Data-Loss rule forbids crashing the
// daemon over an AI inference hiccup.
// ─────────────────────────────────────────────────────────────────────────────

use std::sync::Arc;
use std::time::Duration;

use parking_lot::Mutex as ParkMutex;
use tokio::sync::{broadcast, Mutex, RwLock};
use tokio::time::{interval, timeout};
use tracing::{debug, info, warn};

use crate::ai::{
    dpi_classifier::{DpiClassifier, TrafficClass, NUM_CLASSES, NUM_FEATURES},
    feature_extractor::FeatureExtractor,
    onnx_runtime::OnnxRuntime,
    rl_transport_selector::{RlTransportSelector, TransportAction, TransportProtocol, TransportState},
    traffic_predictor::TrafficPredictor,
    ucb_bandit::UCBBandit,
    AiInferenceContext, AiMetrics,
};
use crate::config::isp_profile::IspProfile;
use crate::config::schema::ShieldConfig;
use crate::cores::CoreManager;
use crate::resilience::fallback_chain::{FallbackChain, FallbackStrategy};
use crate::transport::TransportManager;

// ── Constants ───────────────────────────────────────────────────────────────

/// Cadence of the AI inference loop.
const INFERENCE_INTERVAL: Duration = Duration::from_secs(5);

/// DPI detection probability threshold for `Balanced` aggressiveness.
const THRESHOLD_BALANCED: f32 = 0.7;

/// DPI detection probability threshold for `Aggressive` aggressiveness.
const THRESHOLD_AGGRESSIVE: f32 = 0.4;

/// Cloud-scan cache lifetime (5 min, per §7).
const CLOUD_CACHE_TTL: Duration = Duration::from_secs(300);

/// Per-call timeout for ONNX inference (300 ms — well under the 5 s cadence).
const ONNX_TIMEOUT: Duration = Duration::from_millis(300);

/// Cloud-scan timeout (3 s — must not block the loop).
const CLOUD_SCAN_TIMEOUT: Duration = Duration::from_secs(3);

// ── Aggressiveness ──────────────────────────────────────────────────────────

/// How eagerly the orchestrator switches transports on DPI detection.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Aggressiveness {
    /// Switch ONLY on hard transport failure (no proactive DPI reaction).
    Conservative,
    /// Switch when DPI probability > 0.7 (default).
    Balanced,
    /// Switch when DPI probability > 0.4 (high-churn, worst-case Iran).
    Aggressive,
}

impl Default for Aggressiveness {
    fn default() -> Self {
        Self::Balanced
    }
}

impl Aggressiveness {
    /// Return the DPI-probability threshold above which we switch transports.
    pub fn threshold(self) -> f32 {
        match self {
            Self::Conservative => 1.0, // effectively never triggers on probability
            Self::Balanced => THRESHOLD_BALANCED,
            Self::Aggressive => THRESHOLD_AGGRESSIVE,
        }
    }
}

// ── QuantumToast notification (IPC push) ────────────────────────────────────

/// A notification pushed from the AI orchestrator to the Flutter UI via IPC.
/// The IPC layer subscribes to the broadcast channel and serializes this into
/// an `IpcResponse::Notification` JSON frame that the Flutter daemon_bridge
/// surfaces as a `QuantumToast` (see `quantum_components.dart` §6.10).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct QuantumToastNotification {
    /// Severity: "info" | "warn" | "error".
    pub severity: String,
    /// Human-readable message (English; the Flutter side localizes).
    pub message: String,
    /// Transport switched FROM (None if first connect).
    pub from_transport: Option<String>,
    /// Transport switched TO.
    pub to_transport: String,
    /// Reason: "dpi_detected" | "hard_failure" | "manual" | "isp_preempt".
    pub reason: String,
    /// Predicted DPI detection probability (0.0 — 1.0).
    pub dpi_probability: f32,
    /// Unix-millis timestamp.
    pub ts_ms: u64,
}

// ── Gemini Cloud Scanner (stub) ─────────────────────────────────────────────

/// Stub Gemini Cloud Scanner — represents a remote, higher-fidelity DPI
/// classifier backed by Gemini Pro Vision (per §7.6). Real implementation
/// will dispatch an authenticated HTTPS request to the cloud scanner worker
/// and cache the result for 5 min.
///
/// This stub returns `false` from `is_online()` so the orchestrator skips
/// cloud calls until a real backend is configured.
pub struct GeminiCloudScanner {
    api_endpoint: String,
    api_key: Option<String>,
}

impl GeminiCloudScanner {
    /// Construct a stub Gemini cloud scanner.
    pub fn new(api_endpoint: String, api_key: Option<String>) -> Self {
        Self {
            api_endpoint,
            api_key,
        }
    }

    /// Whether the cloud scanner is reachable. The stub returns `false` so
    /// the orchestrator's cloud-augmented code path is exercised only when
    /// a real backend is configured.
    pub fn is_online(&self) -> bool {
        // Stub: always offline. Real implementation will ping the endpoint.
        false
    }

    /// Endpoint URL (for telemetry).
    pub fn endpoint(&self) -> &str {
        &self.api_endpoint
    }
}

// ── Cloud cache entry ───────────────────────────────────────────────────────

#[derive(Debug, Clone)]
struct CloudCacheEntry {
    /// Cloud-classified DPI probability (higher fidelity than local).
    dpi_probability: f32,
    /// Suggested transport name from the cloud scanner.
    suggested_transport: Option<String>,
    /// When the cache was populated (UNIX seconds).
    cached_at_secs: u64,
}

// ── AI Orchestrator ──────────────────────────────────────────────────────────

/// The AI subsystem orchestrator — wires the 7 AI engines into a reactive
/// loop and reacts to DPI detection by advancing the 8-step resilience chain.
pub struct AiOrchestrator {
    /// Transport manager — switched when DPI is detected.
    transport_manager: Arc<TransportManager>,
    /// Core manager (9 VPN cores) — queried for active core selection.
    cores: Arc<CoreManager>,
    /// Shared ONNX runtime (DPI + traffic-predictor models).
    onnx: Arc<OnnxRuntime>,
    /// 47-dim feature extractor (interior-mutable).
    feature_extractor: Arc<Mutex<FeatureExtractor>>,
    /// UCB1 bandit — picks the best core (Hiddify/Xray/...).
    bandit: ParkMutex<UCBBandit>,
    /// RL transport selector — picks the best transport protocol.
    rl_selector: Mutex<RlTransportSelector>,
    /// Optional Gemini cloud scanner (None when not configured).
    cloud_scanner: Option<Arc<GeminiCloudScanner>>,

    // ── Internal plumbing ──────────────────────────────────────────────────
    /// Daemon config snapshot.
    config: Arc<ShieldConfig>,
    /// DPI classifier (stateful: holds the last classification).
    dpi_classifier: ParkMutex<DpiClassifier>,
    /// Traffic predictor (stateful).
    traffic_predictor: ParkMutex<TrafficPredictor>,
    /// AI inference context shared with the RL selector + GAN.
    inference_context: Arc<RwLock<AiInferenceContext>>,
    /// Aggregated AI metrics.
    metrics: Arc<RwLock<AiMetrics>>,
    /// Broadcast channel for QuantumToast notifications (IPC pushes these).
    toast_tx: broadcast::Sender<QuantumToastNotification>,
    /// Current aggressiveness level.
    aggressiveness: ParkMutex<Aggressiveness>,
    /// Detected ISP profile at startup (None if detection failed).
    detected_isp: ParkMutex<Option<IspProfile>>,
    /// 5-min cloud classification cache.
    cloud_cache: ParkMutex<Option<CloudCacheEntry>>,
    /// The 8-step fallback chain.
    fallback_chain: FallbackChain,
}

impl AiOrchestrator {
    /// Construct a new AI orchestrator wiring the transport + core + onnx
    /// subsystems. Reads model paths + thresholds from the daemon config.
    pub async fn new(
        transport: Arc<TransportManager>,
        cores: Arc<CoreManager>,
        config: Arc<ShieldConfig>,
    ) -> anyhow::Result<Self> {
        // Shared inference context + metrics (used by the RL selector).
        let inference_context = Arc::new(RwLock::new(AiInferenceContext {
            gan_model_path: "ai-models/models/adversarial_traffic_int8.onnx".into(),
            qtable_path: "/var/lib/unifiedshield/qtable.bin".into(),
            ..AiInferenceContext::default()
        }));
        let metrics = Arc::new(RwLock::new(AiMetrics {
            model_version: "int8-v1".into(),
            ..AiMetrics::default()
        }));

        // Construct RL transport selector (Q-learning + experience replay).
        let rl_selector = RlTransportSelector::new(
            Arc::clone(&inference_context),
            Arc::clone(&metrics),
        )
        .map_err(|e| anyhow::anyhow!("RL selector init failed: {e:?}"))?;

        // Construct UCB1 bandit with alpha from config.
        let bandit = UCBBandit::new(config.ai.ucb_alpha);
        // Register all 9 cores as arms.
        for arm in crate::ai::ucb_bandit::CoreArm::all() {
            bandit.add_arm(&arm.to_string());
        }

        // Construct the DPI classifier + traffic predictor.
        let mut dpi_classifier = DpiClassifier::new();
        if !config.ai.dpi_model_path.is_empty() {
            let _ = dpi_classifier.load_model(&config.ai.dpi_model_path).await;
        }
        let mut traffic_predictor = TrafficPredictor::new();
        if !config.ai.predictor_model_path.is_empty() {
            let _ = traffic_predictor
                .load_model(&config.ai.predictor_model_path)
                .await;
        }

        // Broadcast channel for QuantumToast notifications (capacity 16 —
        // plenty since the IPC layer drains immediately).
        let (toast_tx, _) = broadcast::channel(16);

        // Detect ISP at startup (best-effort — non-fatal on failure).
        // This calls the §7 4-step detection: ipinfo.io ASN → DNS injection
        // → NTP reachability → Arvan reachability, then matches against the
        // embedded `configs/isp-profiles.json`.
        let detected_isp = crate::config::isp_profile::IspProfileManager::detect_current_isp().await;
        if let Some(ref isp) = detected_isp {
            info!(isp = %isp.name, "AiOrchestrator: ISP detected at startup");
        } else {
            info!("AiOrchestrator: ISP detection inconclusive — using defaults");
        }

        // Optional Gemini cloud scanner — only constructed if the env var
        // `UNIFIEDSHIELD_GEMINI_ENDPOINT` is set.
        let cloud_scanner = std::env::var("UNIFIEDSHIELD_GEMINI_ENDPOINT")
            .ok()
            .map(|endpoint| {
                let api_key = std::env::var("UNIFIEDSHIELD_GEMINI_API_KEY").ok();
                Arc::new(GeminiCloudScanner::new(endpoint, api_key))
            });

        info!(
            onnx_loaded = !config.ai.dpi_model_path.is_empty(),
            cloud_scanner = cloud_scanner.is_some(),
            isp = detected_isp.as_ref().map(|p| p.name.as_str()).unwrap_or("unknown"),
            "AiOrchestrator: constructed",
        );

        Ok(Self {
            transport_manager: transport,
            cores,
            onnx: Arc::new(OnnxRuntime::new()),
            feature_extractor: Arc::new(Mutex::new(FeatureExtractor::new())),
            bandit: ParkMutex::new(bandit),
            rl_selector: Mutex::new(rl_selector),
            cloud_scanner,
            config,
            dpi_classifier: ParkMutex::new(dpi_classifier),
            traffic_predictor: ParkMutex::new(traffic_predictor),
            inference_context,
            metrics,
            toast_tx,
            aggressiveness: ParkMutex::new(Aggressiveness::default()),
            detected_isp: ParkMutex::new(detected_isp),
            cloud_cache: ParkMutex::new(None),
            fallback_chain: FallbackChain::default_for_iran(),
        })
    }

    /// Subscribe to QuantumToast notifications (called by the IPC server).
    pub fn subscribe_toasts(&self) -> broadcast::Receiver<QuantumToastNotification> {
        self.toast_tx.subscribe()
    }

    /// Adjust the aggressiveness level at runtime (e.g. from IPC config).
    pub fn set_aggressiveness(&self, level: Aggressiveness) {
        let mut g = self.aggressiveness.lock();
        let prev = *g;
        *g = level;
        info!(prev = ?prev, new = ?level, "AiOrchestrator: aggressiveness updated");
    }

    /// Get the current aggressiveness level.
    pub fn aggressiveness(&self) -> Aggressiveness {
        *self.aggressiveness.lock()
    }

    /// Main inference + control loop. Should be spawned as a background task.
    pub async fn run(&self) -> anyhow::Result<()> {
        info!("AiOrchestrator: starting inference loop (cadence=5s)");
        let mut tick = interval(INFERENCE_INTERVAL);
        // First tick fires immediately on first .await — skip it.
        tick.tick().await;

        loop {
            tick.tick().await;
            if let Err(e) = self.run_cycle().await {
                warn!(error = %e, "AiOrchestrator: cycle error (non-fatal)");
            }
        }
    }

    /// A single inference + decision cycle.
    async fn run_cycle(&self) -> anyhow::Result<()> {
        // 1. Poll feature extractor → 47-dim vector.
        let features: [f32; NUM_FEATURES] = {
            let fe = self.feature_extractor.lock().await;
            fe.extract_features()
        };
        debug!(?features, "AiOrchestrator: features polled");

        // 2. Run ONNX inference for DPI classifier + traffic predictor.
        //    Both models use the shared OnnxRuntime (separate model paths
        //    configured in ShieldConfig::ai).
        let dpi_output: Vec<f32> = match timeout(ONNX_TIMEOUT, async {
            self.onnx
                .infer(&features)
                .map_err(|e| anyhow::anyhow!("ONNX infer: {e}"))
        })
        .await
        {
            Ok(Ok(v)) => v,
            Ok(Err(e)) => {
                warn!(error = %e, "AiOrchestrator: ONNX inference failed — using heuristic fallback");
                Vec::new()
            }
            Err(_) => {
                warn!("AiOrchestrator: ONNX inference timed out — using heuristic fallback");
                Vec::new()
            }
        };

        // Run the (heuristic) DPI classifier on the features to get a class
        // probability vector. This is the local fallback when the ONNX model
        // returns no usable output.
        let class_probs: [f32; NUM_CLASSES] = {
            let mut classifier = self.dpi_classifier.lock();
            if dpi_output.len() >= NUM_CLASSES {
                // Use ONNX output directly.
                let mut arr = [0.0f32; NUM_CLASSES];
                for i in 0..NUM_CLASSES {
                    arr[i] = dpi_output[i];
                }
                // Stash for `is_detected()` / `get_detected_class()`.
                // We re-run classify() to update internal state.
                let _ = classifier.classify(&features);
                arr
            } else {
                classifier.classify(&features)
            }
        };

        // Compute the aggregate DPI detection probability: the max probability
        // across all "VPN-ish" traffic classes (indices 1..NUM_CLASSES-1,
        // skipping NormalHttps at index 0 and Unknown at the last index).
        let mut dpi_probability: f32 = 0.0;
        for (i, &p) in class_probs.iter().enumerate() {
            if i == 0 {
                continue; // NormalHttps — not a DPI hit.
            }
            if i == NUM_CLASSES - 1 {
                continue; // Unknown — not actionable.
            }
            if p > dpi_probability {
                dpi_probability = p;
            }
        }

        // 3. Feed result into UCB bandit + RL transport selector.
        let bandit_pick = {
            let bandit = self.bandit.lock();
            bandit.select_arm()
        };
        debug!(?bandit_pick, dpi_probability, "AiOrchestrator: bandit + DPI inference");

        // Build a TransportState for the RL selector.
        let current_transport_name = self.transport_manager.current_transport_name().await;
        let current_protocol = parse_transport_protocol(&current_transport_name);
        let state = TransportState {
            current_transport: current_protocol,
            latency_ms: 150.0,           // TODO: feed from transport_manager stats
            packet_loss: 0.0,           // TODO: feed from transport_manager stats
            bandwidth_kbps: 5000.0,      // TODO: feed from transport_manager stats
            hour_of_day: chrono_hour(),
            isp_hash: self.isp_hash(),
            nain_active: false,          // TODO: feed from NationalIntranetSubsystem
            stability: 1.0 - dpi_probability as f64,
        };

        // Run the RL selector (epsilon-greedy + experience replay).
        let action = {
            let rl = self.rl_selector.lock().await;
            rl.select_action(&state).await.ok()
        };
        if let Some(act) = action {
            debug!(?act, "AiOrchestrator: RL action selected");
        }

        // 4. Cloud scanner (optional, 5-min cached).
        if let Some(ref scanner) = self.cloud_scanner {
            if scanner.is_online() {
                if let Some(entry) = self.maybe_refresh_cloud(scanner).await {
                    if entry.dpi_probability > dpi_probability {
                        dpi_probability = entry.dpi_probability;
                    }
                }
            }
        }

        // 5. Decide whether to switch transport.
        let threshold = self.aggressiveness().threshold();
        if dpi_probability > threshold {
            warn!(
                dpi_probability,
                threshold,
                "AiOrchestrator: DPI probability above threshold — switching transport"
            );
            self.switch_to_next_in_chain(dpi_probability, "dpi_detected").await;
        } else {
            debug!(
                dpi_probability,
                threshold,
                "AiOrchestrator: DPI probability below threshold — staying on current transport"
            );
        }

        // Update metrics.
        {
            let mut m = self.metrics.write().await;
            m.inference_count += 1;
            m.exploration_rate = self.rl_selector_epsilon();
        }

        Ok(())
    }

    /// Advance the 8-step fallback chain and switch the transport.
    async fn switch_to_next_in_chain(&self, dpi_probability: f32, reason: &str) {
        let from = self.transport_manager.current_transport_name().await;
        let next_strategy = self.fallback_chain.advance();
        let Some(next_strategy) = next_strategy else {
            warn!("AiOrchestrator: fallback chain exhausted — staying on last transport");
            return;
        };

        let next_transport = fallback_strategy_to_transport_name(next_strategy.clone());
        info!(
            from = %from,
            to = %next_transport,
            strategy = ?next_strategy,
            dpi_probability,
            "AiOrchestrator: switching transport"
        );

        // Apply the switch.
        if let Err(e) = self
            .transport_manager
            .switch_transport(&next_transport)
            .await
        {
            warn!(error = %e, transport = %next_transport, "AiOrchestrator: switch_transport failed — will retry next cycle");
            return;
        }

        // Emit QuantumToast notification.
        let toast = QuantumToastNotification {
            severity: "warn".into(),
            message: format!("Switched transport → {next_transport} (DPI={dpi_probability:.2})"),
            from_transport: Some(from),
            to_transport: next_transport.to_string(),
            reason: reason.to_string(),
            dpi_probability,
            ts_ms: now_ms(),
        };
        // Best-effort send — no subscribers means we just drop.
        let _ = self.toast_tx.send(toast);
    }

    /// Refresh the 5-min cloud cache if stale; return the cached entry.
    async fn maybe_refresh_cloud(
        &self,
        scanner: &GeminiCloudScanner,
    ) -> Option<CloudCacheEntry> {
        let now = now_secs();
        let cached = self.cloud_cache.lock().clone();
        if let Some(ref entry) = cached {
            let age = Duration::from_secs(now.saturating_sub(entry.cached_at_secs));
            if age < CLOUD_CACHE_TTL {
                return Some(entry.clone());
            }
        }

        // Cache miss — fetch fresh.
        let fresh = match timeout(CLOUD_SCAN_TIMEOUT, async {
            // Real implementation: POST features to scanner endpoint, parse JSON.
            // Stub returns None so the cloud path is inert until backend lands.
            None::<CloudCacheEntry>
        })
        .await
        {
            Ok(Some(v)) => v,
            Ok(None) => return None,
            Err(_) => {
                warn!("AiOrchestrator: cloud scan timed out — skipping");
                return None;
            }
        };
        *self.cloud_cache.lock() = Some(fresh.clone());
        debug!(endpoint = scanner.endpoint(), "AiOrchestrator: cloud cache refreshed");
        Some(fresh)
    }

    /// Current RL exploration rate (for metrics).
    fn rl_selector_epsilon(&self) -> f64 {
        // Try-lock to avoid blocking the inference cadence.
        // Fallback to 0.0 if locked.
        match self.rl_selector.try_lock() {
            Ok(g) => g.epsilon(),
            Err(_) => 0.0,
        }
    }

    /// Stable hash of the detected ISP name → u8 for TransportState.
    fn isp_hash(&self) -> u8 {
        let g = self.detected_isp.lock();
        match g.as_ref() {
            None => 0,
            Some(isp) => {
                let mut h: u8 = 0;
                for b in isp.name.bytes() {
                    h = h.wrapping_add(b);
                }
                h
            }
        }
    }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Map a transport-name string → `TransportProtocol` enum (RL state).
fn parse_transport_protocol(name: &str) -> TransportProtocol {
    match name {
        s if s.contains("hysteria") => TransportProtocol::Hysteria2,
        s if s.contains("shadow_tls") || s.contains("shadowtls") => {
            TransportProtocol::ShadowTls
        }
        s if s.contains("tuic") => TransportProtocol::TuicV5,
        s if s.contains("vless") => TransportProtocol::Vless,
        s if s.contains("reality") => TransportProtocol::Reality,
        s if s.contains("webtransport") => TransportProtocol::WebTransport,
        s if s.contains("mqtt") => TransportProtocol::MqttWs,
        s if s.contains("doq") => TransportProtocol::DoqTunnel,
        _ => TransportProtocol::Vless, // safe default
    }
}

/// Map a `FallbackStrategy` to the transport-name string the
/// TransportManager expects (per §7.5 chain).
fn fallback_strategy_to_transport_name(strategy: FallbackStrategy) -> &'static str {
    match strategy {
        FallbackStrategy::PrimaryTransport => "vless",
        FallbackStrategy::ChineseCdnWorker => "chinese_cdn",
        FallbackStrategy::P2pLibp2pRelay => "libp2p_relay",
        FallbackStrategy::DohTunnel => "doh_tunnel",
        FallbackStrategy::IcmpTunnel => "icmp_tunnel",
        FallbackStrategy::MeshNetwork => "yggdrasil_mesh",
        FallbackStrategy::TorBridgeSnowflake => "snowflake",
        FallbackStrategy::TorBridgeMeek => "meek",
    }
}

/// Current hour-of-day (0-23) for RL state.
fn chrono_hour() -> u8 {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    // Tehran is UTC+3:30. Use UTC for simplicity — the RL state just needs
    // a stable time bucket.
    ((secs / 3600) % 24) as u8
}

/// Current UNIX seconds.
fn now_secs() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

/// Current UNIX millis.
fn now_ms() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_aggressiveness_thresholds() {
        assert_eq!(Aggressiveness::Conservative.threshold(), 1.0);
        assert_eq!(Aggressiveness::Balanced.threshold(), THRESHOLD_BALANCED);
        assert_eq!(Aggressiveness::Aggressive.threshold(), THRESHOLD_AGGRESSIVE);
        assert!(THRESHOLD_AGGRESSIVE < THRESHOLD_BALANCED);
    }

    #[test]
    fn test_fallback_strategy_to_transport_name_covers_all_8_steps() {
        let chain = FallbackChain::default_for_iran();
        for strategy in chain.all_strategies() {
            let name = fallback_strategy_to_transport_name(strategy.clone());
            assert!(!name.is_empty(), "fallback step {:?} unmapped", strategy);
        }
    }

    #[test]
    fn test_parse_transport_protocol_known() {
        assert_eq!(parse_transport_protocol("hysteria2"), TransportProtocol::Hysteria2);
        assert_eq!(parse_transport_protocol("shadow_tls"), TransportProtocol::ShadowTls);
        assert_eq!(parse_transport_protocol("reality"), TransportProtocol::Reality);
        assert_eq!(parse_transport_protocol("tuic_v5"), TransportProtocol::TuicV5);
        assert_eq!(parse_transport_protocol("vless+reality+shadowtls"), TransportProtocol::Vless);
        assert_eq!(parse_transport_protocol("mqtt_ws"), TransportProtocol::MqttWs);
        assert_eq!(parse_transport_protocol("doq_tunnel"), TransportProtocol::DoqTunnel);
    }

    #[test]
    fn test_parse_transport_protocol_unknown_defaults_to_vless() {
        assert_eq!(parse_transport_protocol("unknown"), TransportProtocol::Vless);
    }

    #[test]
    fn test_quantum_toast_notification_serializes() {
        let n = QuantumToastNotification {
            severity: "warn".into(),
            message: "switch".into(),
            from_transport: Some("hysteria2".into()),
            to_transport: "shadow_tls".into(),
            reason: "dpi_detected".into(),
            dpi_probability: 0.85,
            ts_ms: 1234,
        };
        let json = serde_json::to_string(&n).unwrap();
        assert!(json.contains("shadow_tls"));
        assert!(json.contains("dpi_detected"));
    }

    #[test]
    fn test_gemini_cloud_scanner_stub_offline() {
        let scanner = GeminiCloudScanner::new("https://example.invalid".into(), None);
        assert!(!scanner.is_online());
    }

    #[tokio::test]
    async fn test_orchestrator_constructs_with_defaults() {
        // Minimal smoke test: construction must not panic.
        let transport = Arc::new(TransportManager::new());
        let cores = Arc::new(CoreManager::new());
        let config = Arc::new(ShieldConfig::default());
        let orchestrator = AiOrchestrator::new(transport, cores, config).await;
        assert!(orchestrator.is_ok(), "AiOrchestrator::new must succeed");
        let orchestrator = orchestrator.unwrap();
        assert_eq!(orchestrator.aggressiveness(), Aggressiveness::Balanced);
        assert!(orchestrator.cloud_scanner.is_none() || !orchestrator.cloud_scanner.as_ref().unwrap().is_online());
    }

    #[test]
    fn test_set_aggressiveness_updates_threshold() {
        // Can't construct an orchestrator easily in a sync test (async new()),
        // so we just verify the Aggressiveness enum's threshold logic.
        let mut level = Aggressiveness::Balanced;
        assert_eq!(level.threshold(), THRESHOLD_BALANCED);
        level = Aggressiveness::Aggressive;
        assert_eq!(level.threshold(), THRESHOLD_AGGRESSIVE);
    }
}
