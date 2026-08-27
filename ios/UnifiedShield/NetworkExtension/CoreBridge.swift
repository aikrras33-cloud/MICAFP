import Foundation

/**
 * Bridge to the Rust core library via FFI.
 *
 * The Rust core (libunifiedshield.a) handles:
 * - VPN protocol cores (Xray, Naïve, Hysteria2, TUIC)
 * - Obfuscation and domain fronting
 * - Connection management and packet routing
 * - CDN preference (Alibaba/Tencent primary, Cloudflare blocked in Iran)
 */
class CoreBridge {

    private var isInitialized = false

    // MARK: - Rust FFI Declarations

    // These correspond to the Rust FFI functions in libunifiedshield
    // The actual symbols are linked at compile time via the static library

    /**
     * Start the VPN daemon with specified core.
     */
    func startDaemon(
        core: String,
        tunAddress: String,
        dnsServers: [String],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Call Rust FFI: unifiedshield_start_daemon
            let coreCStr = core.withCString { $0 }
            let tunCStr = tunAddress.withCString { $0 }
            let dnsJson = (dnsServers as NSArray).componentsJoined(by: ",")

            let result = dnsJson.withCString { dnsCStr in
                // FFI call - returns 0 on success
                return self.ffiStartDaemon(coreCStr, tunCStr, dnsCStr)
            }

            DispatchQueue.main.async {
                if result == 0 {
                    self.isInitialized = true
                    completion(.success(()))
                } else {
                    completion(.failure(CoreError.startFailed(code: result)))
                }
            }
        }
    }

    /**
     * Stop the daemon.
     */
    func stopDaemon() {
        guard isInitialized else { return }
        ffiStopDaemon()
        isInitialized = false
    }

    /**
     * Get daemon status.
     * Returns: 0=stopped, 1=running, 2=connecting, -1=error
     */
    func getStatus() -> Int {
        return Int(ffiGetStatus())
    }

    /**
     * Switch protocol core at runtime.
     */
    func switchCore(to core: String) {
        core.withCString { coreCStr in
            ffiSwitchCore(coreCStr)
        }
    }

    /**
     * Trigger obfuscation mode.
     */
    func triggerObfuscationMode() {
        ffiTriggerObfuscationMode()
    }

    /**
     * Reconnect the daemon.
     */
    func reconnect() {
        guard isInitialized else { return }
        ffiStopDaemon()
        // Allow brief cool-down before reconnecting
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.ffiReconnect()
        }
    }

    /**
     * Process a packet from the TUN interface.
     */
    func processPacket(_ packet: Data, protocolFamily: NSNumber) {
        guard isInitialized else { return }

        packet.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            ffiProcessPacket(
                baseAddress.assumingMemoryBound(to: UInt8.self),
                UInt32(packet.count),
                protocolFamily.int32Value
            )
        }
    }

    /**
     * Set CDN preference for domain fronting.
     * Chinese CDNs are primary (Cloudflare blocked in Iran).
     */
    func setCdnPreference(_ cdn: String) {
        cdn.withCString { cdnCStr in
            ffiSetCdnPreference(cdnCStr)
        }
    }

    /**
     * Update reward/credit balance.
     */
    func updateReward(_ reward: Int64) {
        ffiUpdateReward(reward)
    }

    // MARK: - FFI Function Pointers

    // These will be resolved from the Rust static library at link time.
    // In the Xcode project, libunifiedshield.a is linked to the Network Extension target.

    @discardableResult
    private func ffiStartDaemon(_ core: UnsafePointer<CChar>, _ tunAddr: UnsafePointer<CChar>, _ dns: UnsafePointer<CChar>) -> Int32 {
        // Rust FFI: int32_t unifiedshield_start_daemon(const char* core, const char* tun_addr, const char* dns)
        // Linked from libunifiedshield.a
        typealias StartDaemonFn = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32

        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "unifiedshield_start_daemon") else {
            return -1
        }

        let fn = unsafeBitCast(symbol, to: StartDaemonFn.self)
        return fn(core, tunAddr, dns)
    }

    private func ffiStopDaemon() {
        typealias StopDaemonFn = @convention(c) () -> Void
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "unifiedshield_stop_daemon") else { return }
        let fn = unsafeBitCast(symbol, to: StopDaemonFn.self)
        fn()
    }

    private func ffiGetStatus() -> Int32 {
        typealias GetStatusFn = @convention(c) () -> Int32
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "unifiedshield_get_status") else { return -1 }
        let fn = unsafeBitCast(symbol, to: GetStatusFn.self)
        return fn()
    }

    private func ffiSwitchCore(_ core: UnsafePointer<CChar>) {
        typealias SwitchCoreFn = @convention(c) (UnsafePointer<CChar>) -> Void
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "unifiedshield_switch_core") else { return }
        let fn = unsafeBitCast(symbol, to: SwitchCoreFn.self)
        fn(core)
    }

    private func ffiTriggerObfuscationMode() {
        typealias TriggerFn = @convention(c) () -> Void
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "unifiedshield_trigger_obfuscation") else { return }
        let fn = unsafeBitCast(symbol, to: TriggerFn.self)
        fn()
    }

    private func ffiReconnect() {
        typealias ReconnectFn = @convention(c) () -> Void
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "unifiedshield_reconnect") else { return }
        let fn = unsafeBitCast(symbol, to: ReconnectFn.self)
        fn()
    }

    private func ffiProcessPacket(_ data: UnsafePointer<UInt8>, _ len: UInt32, _ proto: Int32) {
        typealias ProcessPacketFn = @convention(c) (UnsafePointer<UInt8>, UInt32, Int32) -> Void
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "unifiedshield_process_packet") else { return }
        let fn = unsafeBitCast(symbol, to: ProcessPacketFn.self)
        fn(data, len, proto)
    }

    private func ffiSetCdnPreference(_ cdn: UnsafePointer<CChar>) {
        typealias SetCdnFn = @convention(c) (UnsafePointer<CChar>) -> Void
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "unifiedshield_set_cdn_preference") else { return }
        let fn = unsafeBitCast(symbol, to: SetCdnFn.self)
        fn(cdn)
    }

    private func ffiUpdateReward(_ reward: Int64) {
        typealias UpdateRewardFn = @convention(c) (Int64) -> Void
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "unifiedshield_update_reward") else { return }
        let fn = unsafeBitCast(symbol, to: UpdateRewardFn.self)
        fn(reward)
    }

    // MARK: - §8 Enterprise License & Serial Number System (Step 10 FFI)
    //
    // These extern "C" functions are declared in `daemon/src/ffi.rs` as
    // `#[no_mangle]` Rust entry points. The Swift side resolves them via
    // `dlopen(nil, RTLD_NOW)` + `dlsym(handle, "validate_license")` and
    // casts via `unsafeBitCast` to a `@convention(c)` function pointer.
    //
    // JSON shape returned by `validateLicense` / `getLicenseInfo`:
    //   • On success: `{"valid":true,"expiry_ms":N,"tier":"..."}`
    //   • On failure: `{"valid":false,"reason":"license_invalid|..."}`
    // The Swift caller MUST free the returned `*mut c_char` via
    // `free_license_string` (the Rust side allocates via
    // `CString::into_raw`).

    /**
     * Validate a license serial+org against the on-disk store + embedded
     * Ed25519 public key. Returns a JSON string of ValidationResult.
     */
    func validateLicense(serial: String, org: String) -> String {
        return serial.withCString { serialCStr in
            org.withCString { orgCStr in
                guard let raw = ffiValidateLicense(serialCStr, orgCStr) else {
                    return "{\"valid\":false,\"reason\":\"ffi_null\"}"
                }
                let result = String(cString: raw)
                ffiFreeLicenseString(raw)
                return result
            }
        }
    }

    /**
     * Get the on-disk LicenseInfo as JSON, or "{}" if no license is stored.
     */
    func getLicenseInfo() -> String {
        guard let raw = ffiGetLicenseInfo() else {
            return "{}"
        }
        let result = String(cString: raw)
        ffiFreeLicenseString(raw)
        return result
    }

    /**
     * Force-disconnect the VPN — called by the expiry watchdog.
     */
    func forceDisconnect() {
        ffiForceDisconnect()
    }

    /**
     * Register a C callback to be invoked when the license expires.
     * The `callback` parameter must be a `@convention(c) () -> Void`
     * function pointer (a plain C function). C function pointers in Swift
     * are non-capturing and can be safely stored for later invocation by
     * the Rust side.
     */
    func registerExpiryCallback(_ callback: @convention(c) () -> Void) {
        ffiRegisterExpiryCallback(callback)
    }

    // MARK: - §8 FFI Function Pointers

    @discardableResult
    private func ffiValidateLicense(_ serial: UnsafePointer<CChar>, _ org: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
        // Rust FFI: char* validate_license(const char* serial, const char* org)
        // Linked from libunifiedshield.a (or libunifiedshield.so on Android).
        typealias ValidateLicenseFn = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "validate_license") else {
            return nil
        }
        let fn = unsafeBitCast(symbol, to: ValidateLicenseFn.self)
        return fn(serial, org)
    }

    private func ffiGetLicenseInfo() -> UnsafeMutablePointer<CChar>? {
        // Rust FFI: char* get_license_info()
        typealias GetLicenseInfoFn = @convention(c) () -> UnsafeMutablePointer<CChar>?

        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "get_license_info") else {
            return nil
        }
        let fn = unsafeBitCast(symbol, to: GetLicenseInfoFn.self)
        return fn()
    }

    private func ffiForceDisconnect() {
        // Rust FFI: void force_disconnect()
        typealias ForceDisconnectFn = @convention(c) () -> Void

        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "force_disconnect") else { return }
        let fn = unsafeBitCast(symbol, to: ForceDisconnectFn.self)
        fn()
    }

    private func ffiRegisterExpiryCallback(_ callback: @convention(c) () -> Void) {
        // Rust FFI: void register_expiry_callback(void (*callback)(void))
        typealias RegisterExpiryCallbackFn = @convention(c) (@convention(c) () -> Void) -> Void

        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "register_expiry_callback") else { return }
        let fn = unsafeBitCast(symbol, to: RegisterExpiryCallbackFn.self)
        fn(callback)
    }

    private func ffiFreeLicenseString(_ ptr: UnsafeMutablePointer<CChar>?) {
        // Rust FFI: void free_license_string(char* ptr)
        // Safe to call with nil.
        typealias FreeLicenseStringFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "free_license_string") else { return }
        let fn = unsafeBitCast(symbol, to: FreeLicenseStringFn.self)
        fn(ptr)
    }
}

enum CoreError: Error {
    case startFailed(code: Int32)
    case notInitialized
    case switchFailed
}
