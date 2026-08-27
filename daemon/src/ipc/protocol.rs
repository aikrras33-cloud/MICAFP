// ─────────────────────────────────────────────────────────────────────────────
// IPC Protocol — request/response message types
// MICAFP-UnifiedShield-vip-ultra-Quantum-ultra v8.0
// ─────────────────────────────────────────────────────────────────────────────

use super::{BatteryState, NainStatus};
use crate::error::IpcErrorResponse;
use serde::{Deserialize, Serialize};

/// Commands sent from the Flutter UI to the daemon.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum IpcRequest {
    /// Connect to the anti-censorship network.
    Connect {
        transport: Option<String>,
        endpoint: Option<String>,
    },
    /// Disconnect from the network.
    Disconnect,
    /// Query current daemon status.
    StatusQuery,
    /// Update runtime configuration.
    ConfigUpdate { patch: serde_json::Value },
    /// Trigger emergency wipe (anti-forensics).
    WipeTrigger { auth_token: String },
}

/// A daemon-pushed notification (e.g. QuantumToast message surfacing a
/// transport switch from the AI orchestrator). The Flutter side listens
/// for these and calls `QuantumToast.show()` (`flutter_app/lib/theme/
/// quantum_components.dart` §6.10).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpcNotification {
    /// Severity: "info" | "warn" | "error".
    pub severity: String,
    /// Human-readable message (English; the Flutter side localizes).
    pub message: String,
    /// Notification category: "transport_switch" | "isp_detected" |
    /// "aggressiveness_changed" | "dpi_alert".
    pub category: String,
    /// Optional structured payload (e.g. { from, to, dpi_probability }).
    pub data: Option<serde_json::Value>,
    /// Unix-millis timestamp.
    pub ts_ms: u64,
}

/// Responses sent from the daemon to the Flutter UI.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum IpcResponse {
    /// Acknowledgement of a command (success).
    Ack { for_type: String },
    /// Current status response.
    StatusResponse {
        connected: bool,
        transport: Option<String>,
        battery_state: BatteryState,
        nain_status: NainStatus,
        bytes_sent: u64,
        bytes_recv: u64,
        uptime_secs: u64,
        peer_count: u32,
    },
    /// A daemon-pushed notification (e.g. QuantumToast).
    Notification(IpcNotification),
    /// Structured error response.
    Error(IpcErrorResponse),
}

/// Union of request and response for serialisation.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum IpcMessage {
    Request(IpcRequest),
    Response(IpcResponse),
}
