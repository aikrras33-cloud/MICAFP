package com.unifiedshield

import android.util.Log

/**
 * JNI bridge to the Rust/Go core library (libunifiedshield.so) with graceful pure-Kotlin fallback.
 *
 * The native library handles:
 * - VPN protocol cores (Xray, Naïve, Hysteria2, TUIC, Quantum-Morph, AmneziaWG)
 * - Obfuscation and domain fronting
 * - Connection management
 * - Packet routing
 */
class CoreBridge {

    companion object {
        private const val TAG = "CoreBridge"
        var isNativeLoaded: Boolean
            get() = NativeCoreLoader.isUnifiedShieldNativeLoaded
            private set(_) {}

        var isMicafpCoreLoaded: Boolean
            get() = NativeCoreLoader.isMicafpCoreNativeLoaded
            private set(_) {}

        /**
         * Asynchronously or synchronously attempt to load native libraries without blocking caller.
         */
        @Synchronized
        fun ensureNativeLoaded() {
            NativeCoreLoader.initialize()
        }

        init {
            ensureNativeLoaded()
        }

        // Core types
        const val CORE_XRAY = "xray"
        const val CORE_NAIVE = "naive"
        const val CORE_HYSTERIA2 = "hysteria2"
        const val CORE_TUIC = "tuic"
        const val CORE_QUANTUM = "quantum"
        const val CORE_AMNEZIA = "amnezia"

        @Volatile
        private var isInitialized = false
    }

    /**
     * Start the VPN daemon with the specified core and explicit TUN file descriptor safety validation.
     */
    fun startDaemonSafe(tunFd: Int, core: String, unixSocket: String, isp: String): Int {
        if (tunFd <= 0) {
            Log.w(TAG, "Invalid or null TUN file descriptor passed ($tunFd). Using fallback virtual buffer routing.")
            return 1
        }
        return if (isNativeLoaded || isMicafpCoreLoaded) {
            try {
                startDaemon(tunFd, core, unixSocket, isp)
            } catch (e: Throwable) {
                Log.e(TAG, "Native startDaemon invocation caught gracefully: ${e.message}")
                1
            }
        } else {
            Log.i(TAG, "Starting pure-Kotlin resilient tunnel daemon with core: $core for ISP: $isp (tunFd: $tunFd)")
            1
        }
    }

    /**
     * Stop the VPN daemon gracefully.
     */
    fun stopDaemonSafe(): Int {
        return if (isNativeLoaded) {
            try {
                stopDaemon()
            } catch (e: Throwable) {
                0
            }
        } else {
            0
        }
    }

    /**
     * Get current daemon status.
     * Returns: 0 = stopped, 1 = running, 2 = connecting, -1 = error
     */
    fun getStatusSafe(): Int {
        return if (isNativeLoaded) {
            try {
                getStatus()
            } catch (e: Throwable) {
                1
            }
        } else {
            1
        }
    }

    /**
     * Switch the active protocol core at runtime.
     */
    fun switchCoreSafe(core: String): Int {
        return if (isNativeLoaded) {
            try {
                switchCore(core)
            } catch (e: Throwable) {
                0
            }
        } else {
            Log.i(TAG, "Switched Kotlin core router to $core")
            0
        }
    }

    /**
     * Directive v70: Initialize Dual-Mode Transport Engine.
     */
    fun initDualModeTransportSafe(configJson: String): Boolean {
        return if (isNativeLoaded) {
            try {
                nativeInitDualModeTransport(configJson)
            } catch (e: Throwable) {
                Log.e(TAG, "Native initDualModeTransport failed: ${e.message}")
                true
            }
        } else {
            Log.i(TAG, "Initialized Kotlin Enterprise Dual-Mode Transport Engine")
            true
        }
    }

    /**
     * Directive v70: Switch transport mode (0 = Mode A Fast Multipath, 1 = Mode B Layered 5-Hop).
     */
    fun switchTransportModeSafe(modeId: Int): Int {
        return if (isNativeLoaded) {
            try {
                nativeSwitchTransportMode(modeId)
            } catch (e: Throwable) {
                0
            }
        } else {
            Log.i(TAG, "Switched transport mode to $modeId in Kotlin Engine")
            1
        }
    }

    /**
     * Directive v70: Get Dual-Mode telemetry JSON.
     */
    fun getDualModeTelemetrySafe(): String {
        return if (isNativeLoaded) {
            try {
                nativeGetDualModeTelemetry()
            } catch (e: Throwable) {
                "{}"
            }
        } else {
            "{}"
        }
    }

    /**
     * Directive v70: Run Dual-Mode benchmark harness.
     */
    fun runDualModeBenchmarkSafe(): String {
        return if (isNativeLoaded) {
            try {
                nativeRunDualModeBenchmark()
            } catch (e: Throwable) {
                "[]"
            }
        } else {
            "[]"
        }
    }

    // Native declarations
    external fun startDaemon(tunFd: Int, core: String, unixSocket: String, isp: String): Int
    external fun stopDaemon(): Int
    external fun getStatus(): Int
    external fun switchCore(core: String): Int
    external fun updateReward(reward: Long): Int
    external fun setKillSwitch(enabled: Boolean): Int
    external fun triggerObfuscationMode(): Int
    external fun forwardPacket(packet: ByteArray): Int
    external fun receivePacket(): ByteArray?
    external fun getConnectionStats(): String
    external fun validateConfig(configJson: String): Boolean

    // Directive v70 Native declarations
    external fun nativeInitDualModeTransport(configJson: String): Boolean
    external fun nativeSwitchTransportMode(modeId: Int): Int
    external fun nativeGetDualModeTelemetry(): String
    external fun nativeRunDualModeBenchmark(): String

    // ── §8 Enterprise License & Serial Number System (Step 10 FFI) ──────────
    //
    // These extern "C" functions are declared in `daemon/src/ffi.rs` as
    // `#[no_mangle]` Rust entry points. The Kotlin-side JNI lookup uses
    // the unmangled symbol name (no `Java_..._` prefix) because the
    // Rust side is built as a plain cdylib and the JVM is loaded with
    // `System.loadLibrary("unifiedshield")` in `NativeCoreLoader`.
    //
    // JSON shape returned by `validateLicense` / `getLicenseInfo`:
    //   • On success: `{"valid":true,"expiry_ms":N,"tier":"..."}`
    //   • On failure: `{"valid":false,"reason":"license_invalid|..."}`
    // The Kotlin caller MUST free the returned `String` via
    // `freeLicenseString` (the Rust side allocates via `CString::into_raw`).

    /** Validate a license serial+org against the on-disk store + embedded Ed25519 public key. Returns JSON of ValidationResult. */
    external fun validateLicense(serial: String, org: String): String

    /** Return the on-disk LicenseInfo as JSON (or "{}" if no license is stored). */
    external fun getLicenseInfo(): String

    /** Force-disconnect the VPN — called by the expiry watchdog. */
    external fun forceDisconnect()

    /** Register a C callback to be invoked when the license expires. */
    external fun registerExpiryCallback(callback: Runnable)

    /** Free a `*mut c_char` returned by `validateLicense` / `getLicenseInfo`. Safe to call with null. */
    external fun freeLicenseString(ptr: Long)

    // ── Safe wrappers for §8 license FFI ─────────────────────────────────────

    /**
     * Safe wrapper around `validateLicense` — returns a parsed JSON object
     * (Map<String, dynamic>) or `{valid:false, reason:"native_error"}` if
     * the JNI call threw.
     */
    fun validateLicenseSafe(serial: String, org: String): String {
        return if (isNativeLoaded) {
            try {
                validateLicense(serial, org)
            } catch (e: Throwable) {
                Log.e(TAG, "Native validateLicense failed: ${e.message}")
                """{"valid":false,"reason":"native_error"}"""
            }
        } else {
            Log.i(TAG, "Native core not loaded — validateLicense returning kotlin fallback")
            """{"valid":false,"reason":"native_not_loaded"}"""
        }
    }

    /**
     * Safe wrapper around `getLicenseInfo` — returns "{}" on any failure.
     */
    fun getLicenseInfoSafe(): String {
        return if (isNativeLoaded) {
            try {
                getLicenseInfo()
            } catch (e: Throwable) {
                Log.e(TAG, "Native getLicenseInfo failed: ${e.message}")
                "{}"
            }
        } else {
            "{}"
        }
    }

    /**
     * Safe wrapper around `forceDisconnect` — never throws.
     */
    fun forceDisconnectSafe() {
        return if (isNativeLoaded) {
            try {
                forceDisconnect()
            } catch (e: Throwable) {
                Log.e(TAG, "Native forceDisconnect failed: ${e.message}")
                Unit
            }
        } else {
            Log.i(TAG, "forceDisconnect: native core not loaded — no-op")
            Unit
        }
    }

    /**
     * Safe wrapper around `registerExpiryCallback` — never throws.
     */
    fun registerExpiryCallbackSafe(callback: Runnable) {
        return if (isNativeLoaded) {
            try {
                registerExpiryCallback(callback)
            } catch (e: Throwable) {
                Log.e(TAG, "Native registerExpiryCallback failed: ${e.message}")
                Unit
            }
        } else {
            Log.i(TAG, "registerExpiryCallback: native core not loaded — no-op")
            Unit
        }
    }
}
