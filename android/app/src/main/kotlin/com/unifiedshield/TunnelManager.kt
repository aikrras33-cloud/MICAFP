package com.unifiedshield

import android.content.Context
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class TunnelStats(
    val connected: Boolean = false,
    val currentCore: String = "xray", // Default vless+reality
    val shadowCore: String = "hysteria2", // Hot-swap shadow core
    val uploadSpeedKbps: Long = 0,
    val downloadSpeedKbps: Long = 0,
    val totalBytesUploaded: Long = 0,
    val totalBytesDownloaded: Long = 0,
    val dpiScore: Double = 0.0,
    val packetLossRate: Double = 0.0,
    val activeIsp: String = "MCI",
    val isIranian: Boolean = true,
    val isHotSwapActive: Boolean = false,
    val connectedDurationSeconds: Long = 0
)

class TunnelManager private constructor(private val context: Context) {

    private val TAG = "TunnelManager"

    private val _stats = MutableStateFlow(TunnelStats())
    val stats: StateFlow<TunnelStats> = _stats

    // Prioritized core list for Iranian Blackout Evasion:
    // 1. VLESS + REALITY
    // 2. Hysteria 2 Brutal
    // 3. TUIC v5
    // 4. VLESS + Vision / NaïveProxy
    private val priorityCores = listOf("xray", "hysteria2", "tuic", "naive")
    private var currentCoreIndex = 0

    fun selectOptimalBlackoutCore(isInternationalNetDown: Boolean): String {
        return if (isInternationalNetDown) {
            Log.i(TAG, "Blackout condition detected: Prioritizing VLESS+REALITY & Hysteria2")
            "xray" // vless+reality core
        } else {
            priorityCores[currentCoreIndex]
        }
    }

    /**
     * Instant Hot-Swapping between active core and shadow core without dropping TUN connection.
     */
    fun performHotSwap(reason: String): String {
        currentCoreIndex = (currentCoreIndex + 1) % priorityCores.size
        val newCore = priorityCores[currentCoreIndex]
        val shadowCore = priorityCores[(currentCoreIndex + 1) % priorityCores.size]

        _stats.value = _stats.value.copy(
            currentCore = newCore,
            shadowCore = shadowCore,
            isHotSwapActive = true
        )
        Log.w(TAG, "HOT-SWAP TRIGGERED ($reason): Switched to $newCore (Shadow: $shadowCore)")
        return newCore
    }

    fun updateConnectionState(
        connected: Boolean,
        core: String = _stats.value.currentCore,
        isp: String = _stats.value.activeIsp
    ) {
        _stats.value = _stats.value.copy(
            connected = connected,
            currentCore = core,
            activeIsp = isp
        )
    }

    fun updateMetrics(
        uploadKbps: Long,
        downloadKbps: Long,
        dpiScore: Double
    ) {
        _stats.value = _stats.value.copy(
            uploadSpeedKbps = uploadKbps,
            downloadSpeedKbps = downloadKbps,
            dpiScore = dpiScore
        )
    }

    companion object {
        @Volatile
        private var instance: TunnelManager? = null

        fun getInstance(context: Context): TunnelManager {
            return instance ?: synchronized(this) {
                instance ?: TunnelManager(context.applicationContext).also { instance = it }
            }
        }
    }
}
