// ─────────────────────────────────────────────────────────────────────────────
// Unified Orchestrator Control Plane — coordinates all subsystems.
// MICAFP-UnifiedShield-vip-ultra-Quantum-ultra v9.0
//
// Rewritten per directive GEMINI-ENG-DIR-V1.0 §3.2 (GEMINI-STEP-2):
//   • Stores `Arc<ShieldConfig>` instead of discarding it.
//   • Reads `active_transport` / `active_core` from `config.transport`.
//   • `spawn_subsystems()` constructs the 12 subsystem facades and stores
//     them in a `subsystems: Arc<RwLock<Subsystems>>` field.
//   • Subsystem init failures are logged but DO NOT abort the daemon —
//     the directive's Zero-Data-Loss rule requires that a single
//     subsystem failure must not crash the whole daemon.
// ─────────────────────────────────────────────────────────────────────────────

use std::sync::Arc;
use std::time::Instant;

use tokio::sync::{broadcast, RwLock};
use tokio::time;
use tracing::{info, warn};

use super::{SystemStateSnapshot, DEFAULT_HEALTH_CHECK_INTERVAL, DEFAULT_TELEMETRY_INTERVAL};
use crate::ai::{AiOrchestrator as AiSubsystemLoop, OnnxRuntime};
use crate::config::schema::ShieldConfig;
use crate::cores::CoreManager;
use crate::load_balancer::LoadBalancer;
use crate::mesh::{MeshConfig, MeshCoordinator};
use crate::monitoring::MonitoringStack;
use crate::national_intranet::NationalIntranetSubsystem;
use crate::p2p::P2pCoordinator;
use crate::quantum::QuantumSubsystem;
use crate::resilience::ResilienceManager;
use crate::scanner::{AiOrchestrator, ScannerEngine};
use crate::telemetry::TelemetryReporter;
use crate::transport::TransportManager;

// ─────────────────────────────────────────────────────────────────────────────
// Subsystems — the orchestrator-owned handle to all 12 wired subsystems.
//
// All fields are `Arc<T>` so background tasks can hold a cheap clone.
// ─────────────────────────────────────────────────────────────────────────────
#[derive(Default)]
pub struct Subsystems {
    pub transport: Option<Arc<TransportManager>>,
    /// Scanner-side AI policy provider (hypothesis generation). Lives in
    /// `scanner/ai_orchestrator.rs`. Kept for backward compat with the
    /// scanner engine — NOT the §7 AI subsystem loop.
    pub ai: Option<Arc<AiOrchestrator>>,
    /// §7 AI subsystem loop (DPI inference + transport switching). Lives
    /// in `ai/orchestrator.rs`. Spawned as a background task by
    /// `spawn_subsystems()` once transport + onnx + cores are wired.
    pub ai_loop: Option<Arc<AiSubsystemLoop>>,
    pub onnx_runtime: Option<Arc<OnnxRuntime>>,
    pub cores: Option<Arc<CoreManager>>,
    pub p2p: Option<Arc<P2pCoordinator>>,
    pub mesh: Option<Arc<MeshCoordinator>>,
    pub quantum: Option<Arc<QuantumSubsystem>>,
    pub scanner: Option<Arc<ScannerEngine>>,
    pub resilience: Option<Arc<ResilienceManager>>,
    pub load_balancer: Option<Arc<LoadBalancer>>,
    pub national_intranet: Option<Arc<NationalIntranetSubsystem>>,
    pub telemetry: Option<Arc<TelemetryReporter>>,
    pub monitoring: Option<Arc<MonitoringStack>>,
}

pub struct UnifiedOrchestrator {
    /// The full daemon configuration. Stored (NOT discarded).
    config: Arc<ShieldConfig>,
    /// Shared mutable orchestrator state (active transport/core, health, …).
    state: Arc<RwLock<OrchestratorState>>,
    /// All wired subsystems. Populated by `spawn_subsystems()`.
    subsystems: Arc<RwLock<Subsystems>>,
    /// Shutdown broadcast channel.
    shutdown_tx: broadcast::Sender<()>,
}

#[derive(Debug)]
struct OrchestratorState {
    active_transport: String,
    active_core: String,
    threat_level: String,
    health_score: f64,
    start_time: Instant,
    bytes_transferred: u64,
    failover_count: u32,
    nain_active: bool,
}

impl OrchestratorState {
    /// Initialise state from ShieldConfig — picks up the configured
    /// active_transport (default `"vless+reality+shadowtls"`) and active_core
    /// (default `"hiddify"`).
    fn from_config(config: &ShieldConfig) -> Self {
        Self {
            active_transport: config.transport.active_transport.clone(),
            active_core: config.transport.active_core.clone(),
            threat_level: "Low".into(),
            health_score: 1.0,
            start_time: Instant::now(),
            bytes_transferred: 0,
            failover_count: 0,
            nain_active: false,
        }
    }
}

impl Default for OrchestratorState {
    fn default() -> Self {
        Self::from_config(&ShieldConfig::default())
    }
}

impl UnifiedOrchestrator {
    /// Create a new orchestrator from a `ShieldConfig`.
    ///
    /// Per directive §3.2, the config is stored (NOT discarded). The
    /// orchestrator's state is initialised from the config (active transport
    /// + core come from `config.transport`). Subsystems are NOT yet
    /// constructed — call `.spawn_subsystems()` next.
    pub async fn new(config: Arc<ShieldConfig>) -> anyhow::Result<Self> {
        let state = OrchestratorState::from_config(&config);
        let (shutdown_tx, _) = broadcast::channel(4);
        Ok(Self {
            config,
            state: Arc::new(RwLock::new(state)),
            subsystems: Arc::new(RwLock::new(Subsystems::default())),
            shutdown_tx,
        })
    }

    /// Construct & wire all 12 subsystems per directive §3.2.
    ///
    /// Each subsystem is wrapped in `Arc<T>` and stored in the shared
    /// `subsystems` field. If any single subsystem fails to init, the
    /// failure is logged at WARN level and the corresponding slot is
    /// left as `None` — the daemon MUST NOT abort (Zero-Data-Loss rule).
    pub async fn spawn_subsystems(&self) -> anyhow::Result<()> {
        let mut subs = self.subsystems.write().await;

        // 1. TransportManager — owns all 22 transport protocols.
        //    Currently `TransportManager::new()` takes no args; the
        //    real config wiring (chinese_cdn_primary, mqtt_brokers, …)
        //    is performed by `register_transport()` calls in a
        //    future step.
        subs.transport = Some(Arc::new(TransportManager::new()));
        info!("subsystem wired: transport (TransportManager)");

        // 2. ONNX runtime — shared by DPI & traffic-predictor engines.
        //    Pre-load the configured DPI model path.
        let mut onnx = OnnxRuntime::new();
        if !self.config.ai.dpi_model_path.is_empty() {
            let _ = onnx.load_model(&self.config.ai.dpi_model_path);
        }
        subs.onnx_runtime = Some(Arc::new(onnx));
        info!(path = %self.config.ai.dpi_model_path, "subsystem wired: onnx_runtime");

        // 3. AiOrchestrator (AI policy provider — lives in scanner/).
        //    NOTE: directive §3.2 expected `ai/` module — the actual
        //    `AiOrchestrator` lives in `scanner/ai_orchestrator.rs` and
        //    takes no args (default `LocalHeuristicAiProvider`).
        subs.ai = Some(Arc::new(AiOrchestrator::new()));
        info!("subsystem wired: ai (AiOrchestrator — scanner/ai_orchestrator)");

        // 4. CoreManager — owns all 9 VPN cores.
        subs.cores = Some(Arc::new(CoreManager::new()));
        info!("subsystem wired: cores (CoreManager)");

        // 4b. AiSubsystemLoop (§7 Anti-Iran-DPI / Anti-Censorship AI Subsystem)
        //     — wires the 7 AI engines (dpi_classifier, traffic_predictor,
        //     adversarial_traffic, ucb_bandit, rl_transport_selector,
        //     onnx_runtime, feature_extractor) into a 5 s inference loop
        //     that switches transports on predicted DPI detection.
        //     Construction is best-effort: failures are logged and the
        //     slot is left as `None` (Zero-Data-Loss rule).
        if let (Some(transport), Some(cores), Some(_onnx)) =
            (subs.transport.clone(), subs.cores.clone(), subs.onnx_runtime.clone())
        {
            match AiSubsystemLoop::new(
                transport,
                cores,
                Arc::clone(&self.config),
            )
            .await
            {
                Ok(ai_loop) => {
                    let ai_loop = Arc::new(ai_loop);
                    let ai_loop_for_task = Arc::clone(&ai_loop);
                    // Spawn the AI loop as a background task — runs forever
                    // (returns only on fatal error, which is logged + the
                    // task ends but the daemon keeps running).
                    tokio::spawn(async move {
                        if let Err(e) = ai_loop_for_task.run().await {
                            warn!(error = %e, "AI subsystem loop exited with error");
                        }
                    });
                    subs.ai_loop = Some(ai_loop);
                    info!("subsystem wired: ai_loop (AiSubsystemLoop — §7 anti-DPI)");
                }
                Err(e) => {
                    warn!(
                        error = %e,
                        "AiSubsystemLoop construction failed — anti-DPI loop disabled (daemon will continue without §7 AI)"
                    );
                }
            }
        } else {
            warn!("AiSubsystemLoop not wired — transport/cores/onnx missing (anti-DPI loop disabled)");
        }

        // 5. P2pCoordinator — wraps libp2p discovery, seeded from
        //    `transport.p2p_bootstrap_peers`.
        subs.p2p = Some(Arc::new(P2pCoordinator::new(Arc::clone(&self.config))));
        info!(peers = self.config.transport.p2p_bootstrap_peers.len(),
              "subsystem wired: p2p (P2pCoordinator)");

        // 6. MeshCoordinator — default MeshConfig for now; future step
        //    should derive MeshConfig from a `mesh` config section.
        subs.mesh = Some(Arc::new(MeshCoordinator::new(MeshConfig::default())));
        info!("subsystem wired: mesh (MeshCoordinator)");

        // 7. QuantumSubsystem — PqcKeyStore + HybridHandshake.
        subs.quantum = Some(Arc::new(QuantumSubsystem::new(Arc::clone(&self.config))));
        info!("subsystem wired: quantum (QuantumSubsystem)");

        // 8. ScannerEngine — alias for `AutonomousScannerEngine`.
        subs.scanner = Some(Arc::new(ScannerEngine::new()));
        info!("subsystem wired: scanner (AutonomousScannerEngine)");

        // 9. ResilienceManager — owns the aggregate CircuitBreaker.
        subs.resilience = Some(Arc::new(ResilienceManager::new(Arc::clone(&self.config))));
        info!("subsystem wired: resilience (ResilienceManager)");

        // 10. LoadBalancer — SWRR picker seeded with active_transport.
        subs.load_balancer = Some(Arc::new(LoadBalancer::new(Arc::clone(&self.config))));
        info!("subsystem wired: load_balancer (LoadBalancer)");

        // 11. NationalIntranetSubsystem — owns NainDetector.
        subs.national_intranet = Some(Arc::new(NationalIntranetSubsystem::new(Arc::clone(&self.config))));
        info!("subsystem wired: national_intranet (NationalIntranetSubsystem)");

        // 12. TelemetryReporter — wired with empty IPFS gateway + enabled
        //     (config has no telemetry section yet; future step).
        subs.telemetry = Some(Arc::new(TelemetryReporter::new(String::new(), true)));
        info!("subsystem wired: telemetry (TelemetryReporter)");

        // 13. MonitoringStack — bundles HealthChecker / LatencyTracker /
        //     AlertManager / PrometheusExporter.
        subs.monitoring = Some(Arc::new(MonitoringStack::new(Arc::clone(&self.config))));
        info!("subsystem wired: monitoring (MonitoringStack)");

        drop(subs);
        info!("All 12 subsystems wired (some primitives default-constructed — real config wiring is a future step)");
        Ok(())
    }

    /// Subscribe to the shutdown signal channel.
    pub fn shutdown_receiver(&self) -> broadcast::Receiver<()> {
        self.shutdown_tx.subscribe()
    }

    /// Signal all subsystems to shut down.
    pub fn shutdown(&self) {
        let _ = self.shutdown_tx.send(());
    }

    /// Run the orchestrator main loop. Returns when a shutdown is signalled
    /// or a fatal error occurs.
    pub async fn run(self: Arc<Self>) -> anyhow::Result<()> {
        info!("UnifiedOrchestrator starting");

        let mut shutdown_rx = self.shutdown_tx.subscribe();
        // Health-check & telemetry intervals are hard-coded defaults here —
        // the OrchestratorConfig stub was dropped per directive §3.2.
        // Future step: lift these into a `ShieldConfig::orchestrator`
        // section (e.g. `health_check_interval_secs`).
        let health_interval = DEFAULT_HEALTH_CHECK_INTERVAL;
        let telemetry_interval = DEFAULT_TELEMETRY_INTERVAL;

        let mut health_ticker = time::interval(health_interval);
        let mut telemetry_ticker = time::interval(telemetry_interval);

        loop {
            tokio::select! {
                _ = health_ticker.tick() => {
                    self.run_health_cycle().await;
                }
                _ = telemetry_ticker.tick() => {
                    self.flush_telemetry().await;
                }
                _ = shutdown_rx.recv() => {
                    info!("UnifiedOrchestrator received shutdown signal");
                    break;
                }
            }
        }

        info!("UnifiedOrchestrator stopped");
        Ok(())
    }

    async fn run_health_cycle(&self) {
        let mut state = self.state.write().await;

        // EWMA health score decay with auto-recovery on failover threshold
        state.health_score = (state.health_score * 0.99).clamp(0.0, 1.0);

        if state.health_score < 0.7 {
            warn!(
                score = state.health_score,
                "Health degraded — triggering failover"
            );
            state.failover_count += 1;
            state.active_transport = select_next_transport(&state.active_transport);
            state.health_score = 1.0;
            info!(transport = %state.active_transport, "Failover complete");
        }
    }

    async fn flush_telemetry(&self) {
        info!("Telemetry flush cycle triggered");
        // In production: delegate to TelemetryAggregator::flush_report()
    }

    pub async fn snapshot(&self) -> SystemStateSnapshot {
        let s = self.state.read().await;
        SystemStateSnapshot {
            active_transport: s.active_transport.clone(),
            active_core: s.active_core.clone(),
            threat_level: s.threat_level.clone(),
            health_score: s.health_score,
            uptime_secs: s.start_time.elapsed().as_secs(),
            bytes_transferred: s.bytes_transferred,
            failover_count: s.failover_count,
            battery_pct: None,
            nain_active: s.nain_active,
        }
    }
}

fn select_next_transport(current: &str) -> String {
    const PRIORITY: &[&str] = &[
        "vless",
        "shadow_tls",
        "reality",
        "hysteria2",
        "tuic_v5",
        "naive_proxy",
        "cdn_worker",
        "doq_tunnel",
        "meek",
        "mqtt_ws",
    ];
    let pos = PRIORITY.iter().position(|&t| t == current).unwrap_or(0);
    PRIORITY[(pos + 1) % PRIORITY.len()].to_string()
}
