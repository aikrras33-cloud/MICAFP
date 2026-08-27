pub mod alert_manager;
pub mod health_checker;
pub mod latency_tracker;
pub mod prometheus_exporter;
pub use alert_manager::AlertManager;
pub use health_checker::HealthChecker;
pub use latency_tracker::LatencyTracker;
pub use prometheus_exporter::PrometheusExporter;

// ─────────────────────────────────────────────────────────────────────────────
// MonitoringStack — thin orchestrator-facing facade introduced per directive
// §3.2. It bundles the four monitoring primitives (health checker, latency
// tracker, alert manager, Prometheus exporter) under a single Arc-friendly
// root, so the UnifiedOrchestrator can hold them collectively.
//
// Each underlying primitive currently default-constructs (no args). Future
// step: read per-subsystem config (probe intervals, alert thresholds,
// Prometheus port) from ShieldConfig.
// ─────────────────────────────────────────────────────────────────────────────
use std::sync::Arc;

use crate::config::schema::ShieldConfig;

pub struct MonitoringStack {
    /// Snapshot of the daemon config (read by background tasks).
    pub config: Arc<ShieldConfig>,
    /// Periodic self-diagnostics.
    pub health: Arc<HealthChecker>,
    /// Per-endpoint latency histogram.
    pub latency: Arc<LatencyTracker>,
    /// Alert dispatcher (log / push / webhook).
    pub alerts: Arc<AlertManager>,
    /// Prometheus exporter (metrics endpoint).
    pub prometheus: Arc<PrometheusExporter>,
}

impl MonitoringStack {
    pub fn new(config: Arc<ShieldConfig>) -> Self {
        Self {
            config,
            health: Arc::new(HealthChecker::new()),
            latency: Arc::new(LatencyTracker::new()),
            alerts: Arc::new(AlertManager::new()),
            prometheus: Arc::new(PrometheusExporter::new()),
        }
    }
}

impl Default for MonitoringStack {
    fn default() -> Self {
        Self::new(Arc::new(ShieldConfig::default()))
    }
}
