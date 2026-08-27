// ─────────────────────────────────────────────────────────────────────────────
// MICAFP-UnifiedShield Enterprise v9.0.0-enterprise — Daemon Entry Point
// Complete merge of all 13 source projects. Zero features removed.
// ─────────────────────────────────────────────────────────────────────────────

use anyhow::Result;
use unifiedshield::config::schema::ShieldConfig;
use unifiedshield::orchestrator::UnifiedOrchestrator;
use unifiedshield::watchdog::SystemWatchdog;
use std::sync::Arc;
use tokio::signal;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> Result<()> {
    // ── Telemetry / tracing ──────────────────────────────────────────────────
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .with_target(true)
        .with_thread_ids(true)
        .json()
        .init();

    tracing::info!(
        version = "9.0.0-enterprise",
        project = "MICAFP-UnifiedShield-Enterprise",
        "Daemon starting — complete merge of all 13 source projects"
    );

    // ── Configuration ────────────────────────────────────────────────────────
    let config = ShieldConfig::load_or_default()?;
    let config = Arc::new(config);

    // ── Watchdog ─────────────────────────────────────────────────────────────
    let watchdog = Arc::new(SystemWatchdog::new(30));
    let watchdog_handle = {
        let w = Arc::clone(&watchdog);
        tokio::spawn(async move { w.run().await })
    };

    // ── Orchestrator ─────────────────────────────────────────────────────────
    let orchestrator = UnifiedOrchestrator::new(Arc::clone(&config)).await?;
    let orchestrator = Arc::new(orchestrator);

    // ── Wire subsystems via the orchestrator (§3.2) ─────────────────────────
    // The orchestrator constructs all 12 subsystem facades (transport, ai,
    // cores, p2p, mesh, quantum, scanner, resilience, load_balancer,
    // national_intranet, telemetry, monitoring) and stores them in its
    // shared `subsystems` field. Subsystem init failures are logged but
    // DO NOT abort the daemon (Zero-Data-Loss rule).
    orchestrator.spawn_subsystems().await?;

    // ── Run until signal ─────────────────────────────────────────────────────
    // `run()` takes `Arc<Self>` (consumes one Arc), so we pass a clone
    // and keep the original for the post-loop `shutdown()` call.
    let orchestrator_for_run = Arc::clone(&orchestrator);
    tokio::select! {
        result = orchestrator_for_run.run() => {
            if let Err(e) = result {
                tracing::error!(error = %e, "Orchestrator exited with error");
            }
        }
        _ = signal::ctrl_c() => {
            tracing::info!("SIGINT received — shutting down gracefully");
        }
    }

    orchestrator.shutdown();
    watchdog_handle.abort();
    tracing::info!("Daemon stopped cleanly");
    Ok(())
}
