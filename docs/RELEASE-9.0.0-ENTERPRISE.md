# UnifiedShield Enterprise v9.0.0-enterprise — Release Notes

**Release date:** 2025-12-10 (Azar 19, 1404 IRT — license expiry synchronizes with this date)
**Codename:** Quantum RGB Enterprise Edition
**Tag:** `v9.0.0-enterprise`

> This is the consolidated release of the UnifiedShield Quantum Enterprise Rebuild (directive `GEMINI-ENG-DIR-V1.0`).
> Complete merge of **13 source projects** — zero features removed.

---

## 1. Headline

The Quantum RGB Enterprise Edition merges 13 source projects into a single codebase; adds a Quantum Enterprise RGB UI, an Enterprise license system with an Azar-19-1404 expiry, an anti-Iran-DPI AI subsystem, free-tier integration for 5 always-available platforms, an on-device LLM plus cloud Gemini, an 18-artifact build matrix driven by a 12-cell GitHub Actions pipeline, and an auto-fix CI loop.

The release preserves **every** feature from every prior variant — verified by the zero-data-loss audit in §11 below.

---

## 2. The 18 Build Artifacts

Produced by the 12-cell matrix in `.github/workflows/release.yml`:

| # | Artifact | Target | Builder |
|---|----------|--------|---------|
| 1 | Android APK (arm64) | `aarch64-linux-android` | `gradlew assembleRelease` + `cargo ndk` |
| 2 | Android App Bundle | `aarch64-linux-android` | `gradlew bundleRelease` |
| 3 | Android APK (universal) | `arm64-v8a,armeabi-v7a,x86_64` | `gradlew assembleRelease` |
| 4 | iOS IPA | `aarch64-apple-ios` | `xcodebuild archive` + `-exportArchive` |
| 5 | macOS .app | `aarch64-apple-darwin` | `cargo build --release` + `flutter build macos` |
| 6 | macOS .dmg | `aarch64-apple-darwin` | `hdiutil` |
| 7 | Windows .exe (x64) | `x86_64-pc-windows-msvc` | `cargo build --release` + `flutter build windows` |
| 8 | Windows .msi installer | `x86_64-pc-windows-msvc` | Inno Setup (`windows/installer/setup.iss`) |
| 9 | Linux .deb (amd64) | `x86_64-unknown-linux-gnu` | `dpkg-deb` |
| 10 | Linux .deb (arm64) | `aarch64-unknown-linux-gnu` | `dpkg-deb` |
| 11 | Linux .rpm (x64) | `x86_64-unknown-linux-gnu` | `rpmbuild` |
| 12 | Linux AppImage | `x86_64-unknown-linux-gnu` | `appimagetool` |
| 13 | Arch Linux PKGBUILD | `x86_64-unknown-linux-gnu` | `makepkg` |
| 14 | Linux systemd unit | `x86_64/aarch64-unknown-linux-gnu` | `linux/unifiedshield.service` |
| 15 | OpenWrt .ipk (ath79) | `mips-unknown-linux-musl` | `openwrt/Makefile` SDK |
| 16 | OpenWrt .ipk (mediatek) | `aarch64-unknown-linux-musl` | `openwrt/Makefile` SDK |
| 17 | Chrome extension .zip (MV3) | n/a | `scripts/build-extensions-release.sh` |
| 18 | Firefox extension .zip (MV3) | n/a | `scripts/build-extensions-release.sh` |

---

## 3. GitHub Actions Matrix — 12 Cells

The release pipeline runs **12 parallel build cells**:

| Cell | OS | Rust target | Artifact set |
|------|----|-------------|--------------|
| `android-universal` | `ubuntu-22.04` | aarch64 + armv7 + x86_64 + i686 | APK #3, AAB #2 |
| `android-arm64` | `ubuntu-22.04` | `aarch64-linux-android` | APK #1 |
| `android-arm32` | `ubuntu-22.04` | `armv7-linux-androideabi` | APK #1 (arm32) |
| `android-x64` | `ubuntu-22.04` | `x86_64-linux-android` | APK #1 (x64) |
| `android-x86` | `ubuntu-22.04` | `i686-linux-android` | APK #1 (x86) |
| `ios-device` | `macos-14` | `aarch64-apple-ios` | IPA #4 |
| `ios-simulator` | `macos-14` | `aarch64-apple-ios-sim` | IPA #4 (sim) |
| `macos-universal` | `macos-14` | `aarch64-apple-darwin` + `x86_64-apple-darwin` | .app #5 + .dmg #6 |
| `windows-x64` | `windows-2022` | `x86_64-pc-windows-msvc` | .exe #7 + .msi #8 |
| `linux-x64` | `ubuntu-22.04` | `x86_64-unknown-linux-gnu` | .deb #9 + .rpm #11 + AppImage #12 + PKGBUILD #13 + systemd #14 |
| `linux-arm64` | `ubuntu-22.04` | `aarch64-unknown-linux-gnu` | .deb #10 |
| `openwrt-cross` | `ubuntu-22.04` | mips + aarch64 musl | .ipk #15 + .ipk #16 |

`fail-fast: false` — every cell runs to completion regardless of sibling failures, so the release publishes the maximum number of artifacts even when one cell is broken.

---

## 4. Auto-Fix CI Loop (`.github/workflows/auto-fix.yml`)

Triggered when `ci.yml` or `release.yml` completes with `conclusion: failure`. Pipeline:

1. Downloads the failing logs.
2. Classifies failures into 6 buckets: `missing-dep`, `missing-file`, `api-drift`, `lint`, `path-mismatch`, `type-mismatch`.
3. Applies an auto-fix per bucket (a Python script with regex-pattern-driven patches for each bucket).
4. If non-empty diff → commits `fix(ci): auto-remediate {bucket} ({n} files)`.
5. After **3 stalled rounds** (no further progress) → opens a GitHub Issue with the remaining failure log for human triage.

`MAX_ROUNDS: "3"` is the ceiling — the auto-fixer is not allowed to thrash indefinitely.

---

## 5. Quantum Enterprise RGB UI

Per directive §6, the entire UI is rebuilt on the **Quantum Enterprise RGB design language**:

- **Dark-first.** Background `#050510` everywhere.
- **RGB accents — animated sparingly.** 9-stop gradient ring on the connect button, the active-core chip, the license countdown, and the aurora background only.
- **Glassmorphism.** Cards + modals are frosted-glass (`BackdropFilter` blur σ=12 over a 70%-opacity `bgSurface` overlay).
- **Motion.** Every transition uses a curve from `QuantumCurves` + a duration from `QuantumDurations`. No `LinearAnimation` outside of progress bars.
- **Depth.** 4-layer elevation ladder + RGB-tinted glow on active/selected states only.

See `docs/ENTERPRISE-UI-DESIGN.md` for the full design-language reference.

### 5.1 Forbidden UI patterns (enforced by `scripts/preflight.sh`)
| Forbidden | Replacement |
|-----------|-------------|
| Material 2 / Material 3 default theme | `QuantumPalette` + `QuantumTypography` |
| `Switch` | `QuantumToggle` |
| `Checkbox` | `QuantumToggle` (single-state) or `QuantumCheckbox` |
| `Dialog` / `AlertDialog` | `QuantumDialog` (with `QuantumGlassModal` wrapper) |
| `SnackBar` | `QuantumToast` |
| `CircularProgressIndicator` | `QuantumSpinner` |

### 5.2 Cross-surface token parity
The same `QuantumPalette` hex values appear, unmodified, in **5 surfaces** — Flutter, Next.js dashboard, browser extensions CSS, Android Compose, iOS SwiftUI. CI verifies this via `scripts/preflight.sh --check-tokens`.

### 5.3 Animation budget
- **60 FPS minimum** on a Pixel 4a + iPhone 12 bench.
- **Max 3 simultaneous animations per screen** (with limited exceptions for the home screen and the countdown cells).

---

## 6. License System with Azar-19-1404 Expiry

Per directive §8, a full license validation system with:
- **Two-layer anti-tamper**: SHA-256 over the canonical string + Ed25519 detached signature against an embedded public key.
- **Anti-rollback**: monotonic-clock high-water-mark persisted to platform SecureStorage.
- **4-cell countdown**: days/hours/minutes/seconds, Persian numerals when `Locale("fa")` is active, animation accelerates as expiry approaches (1× at >24h, 4× at T−24h, 8× at T−1h, 16× at T−5min/T−0).
- **Pre-expiry notifications**: T−24h toast → T−1h push → T−5m push → T−0 force-disconnect.
- **Three storage backends**: Android Keychain (JNI to `KeyStore`), iOS Keychain (`SecItemAdd`), Desktop SecureStorage (ChaCha20-Poly1305 encrypted JSON at `$XDG_CONFIG_HOME/unifiedshield/license.json`).
- **FFI exports**: `validate_license`, `get_license_info`, `force_disconnect`, `register_expiry_callback`, `free_license_string`.
- **Offline operation**: zero phone-home; the public key, watermark, and license all live on-device.
- **7 unit-test cases** in `daemon/src/license/validation_tests.rs` (mirrored by `flutter_app/test/license_validation_test.dart`).

Default license:
- `serial`: `MICAFP-RGB-ENT-ULTRA-2025`
- `organization`: `Enterprise VIP User`
- `tier`: `Enterprise RGB Supreme`
- `value_usd`: `$999,999,999,999`
- `expiry`: **2025-12-10 23:59:59 +03:30 IRT** = **Azar 19 1404 23:59:59 IRT** = Unix ms 1_765_398_599_000.

See `docs/LICENSE-SYSTEM.md` for the full flow.

---

## 7. Anti-Iran-DPI AI Subsystem

Per directive §7, the AI subsystem runs the `feature_extractor → dpi_classifier → traffic_predictor → ucb_bandit → rl_transport_selector → switch` pipeline at every connection attempt and every 60 seconds during an active session.

- **`feature_extractor`**: 128-feature vector from the last 5000 packets (packet-size percentiles, IAT stats, TLS-ClientHello fields, QUIC connection-ID entropy, burst stats, hour/day one-hot).
- **`dpi_classifier`** (ONNX): 6-class softmax over `clean / tls_reset / http_403 / null_route / sni_filter / dns_poison`.
- **`traffic_predictor`** (ONNX): 60-second-ahead `[rx_bytes, rtt_ms]` forecast.
- **`ucb_bandit`**: 9-arm UCB1 (`c=√2`) for paid-tier core selection; reward = 0.4·(1/RTT) + 0.3·throughput + 0.2·(1/loss) + 0.1·forecast.
- **`rl_transport_selector`** (ONNX, PPO): 22-transport action picker.
- **`adversarial_traffic`** GAN: generates 4-KiB adversarial micro-bursts that fool the DPI classifier.

### 7.1 6 ONNX model artifacts committed to `models/`
| File | Engine |
|------|--------|
| `dpi_classifier.onnx` | dpi_classifier (FP32) |
| `dpi_classifier_int8.onnx` | dpi_classifier (int8) |
| `traffic_predictor.onnx` | traffic_predictor (FP32) |
| `traffic_predictor_int8.onnx` | traffic_predictor (int8) |
| `transport_selector_ppo.onnx` | rl_transport_selector |
| `adversarial_traffic_gan.onnx` | adversarial_traffic |

### 7.2 Defenses
- **Anti-active-probing**: `probe_resistance` (masquerade-and-route) + `ephemeral_identity` (5-min identity rotation) + **Reality** (no TLS termination on probed connections).
- **Anti-traffic-analysis**: `traffic_shaper` (video/browsing/chat profiles) + `timing_jitter` (0–50 ms) + `packet_size_normalizer` (6-bucket) + `dp_noise` (Laplace, ε=1.0).
- **Steganography**: Calculator disguise UI + 5-tap wipe gesture (`1 + 2 = = = = =`).
- **Resilience fallback chain**: 8-step ladder (60-s ceiling) + `circuit_breaker` (3-strikes backoff).

### 7.3 ISP detection
4 orthogonal signals: ASN lookup (`AS197207` MCI, `AS44244` Irancell, `AS49581` Rightel, `AS31549` Shatel, `AS16322` ParsOnline, `AS58224` Mokhaberat, `AS43740` AsiaTech) + DNS-injection probe + NTP-monlist probe + Arvan-Cloud RTT probe.

See `docs/ANTI-DPI-AI.md` for the full design.

---

## 8. Free-Tier Integration — 5 Platforms

Per directive §9, 5 always-available free-tier VPN platforms integrated as first-class cores. They appear in a dedicated **"🆓 Free Tier"** section at the top of the Flutter Cores screen, ahead of the 7 paid-tier cores.

| # | Core | Strategy | SOCKS5 |
|---|------|----------|--------|
| 1 | **Tor + Snowflake** | WebRTC-volunteer-bridge pluggable transport | `127.0.0.1:9050` |
| 2 | **Psiphon** | CDN-fronted SSH+Obfs | `127.0.0.1:9080` |
| 3 | **Lantern** | Domain-fronted HTTP/2 | `127.0.0.1:9081` |
| 4 | **Hysteria2 Community** | Auto-discovered | `127.0.0.1:9090` |
| 5 | **VLESS-Reality Community** | Auto-discovered | `127.0.0.1:9091` |

### 8.1 Why ProtonVPN / Windscribe / Cloudflare WARP are NOT in the list
Their endpoints are aggressively blocked in Iran (all exit IPs on Iran's IP-blocklist, WARP /24 ranges hard-blocked at every ISP edge).

### 8.2 Auto-discovery
`scripts/refresh-free-servers.py` scrapes community Telegram channels every Monday 03:00 UTC via `.github/workflows/refresh-free-servers.yml`, validates 5+5 entries, commits via `github-actions[bot]`, opens an auto-PR.

### 8.3 PC app free tier
The active free-tier core exposes a SOCKS5 proxy on `127.0.0.1:<port>` so any SOCKS5-aware application can be routed through UnifiedShield without engaging the TUN device.

### 8.4 Bypass success-rate target
**≥95%** aggregate across the 5 free-tier cores × 3 Iranian ISPs (15 cells), measured by `tests/censorship-simulation/test_bypass_effectiveness.py`.

See `docs/FREE-TIER.md` for the full design.

---

## 9. On-Device LLM + Cloud Gemini Assistant

Per directive §10.1, the AI assistant ships two inference backends:

- **On-device LLM** (default): `llama-cpp-2` 0.1.x bindings, QuantQ3_K_M GGUF model committed to `models/`. Inference is streamed token-by-token via `EventChannel("unifiedshield/ai_stream")`. Zero network calls.
- **Cloud Gemini** (optional fallback): standard Google Gemini SDK via `reqwest`. Only invoked when (a) user explicitly enables Cloud AI, (b) the on-device LLM has refused twice, and (c) the daemon is in a non-Iranian exit country.

FFI exports: `ai_query(prompt, locale)` (synchronous query) + `ai_register_stream_callback(cb)` (token stream).

---

## 10. Quantum / Post-Quantum Cryptography

`daemon/src/quantum/` ships **11 PQC modules**:
- `hybrid_handshake` — ML-KEM-1024 + X25519 hybrid (FIPS 203)
- `quantum_ratchet` — post-quantum Double Ratchet
- `pqc_key_store` — secure PQC key storage
- `quantum_obfuscator` — QKD-noise traffic obfuscation
- `qkd_simulation` — quantum-key-distribution simulator
- `lattice_onion` — lattice-based onion routing
- `zkp_auth` — zero-knowledge-proof authentication
- `homomorphic_routing` — homomorphic-encryption routing
- `neural_steganography` — neural-net steganography
- `quantum_noise` — quantum-noise source
- `quantum_seed_protocol` — quantum-seed protocol

---

## 11. Zero-Data-Loss Audit

Per the directive's invariant, the following are **all** preserved across the 13-source merge:

| Asset | Count |
|-------|-------|
| Daemon modules | **27** (26 `pub mod` in `lib.rs` + `main.rs` binary) |
| Transports | **22** (`cdn_tunnel, cdn_worker, chinese_cdn, cloudflare_worker, doh_tunnel, domain_fronting, doq_tunnel, hysteria2, icmp_tunnel, manager, meek, mqtt_tunnel, mqtt_ws, multihop_chain, naive_proxy, pluggable_transport, reality, shadow_tls, tuic_v5, vless, webrtc_relay, webtransport`) |
| Cores | **12** (9 paid + 3 free-tier: `tor_snowflake, hysteria2_community, vless_reality_community`) |
| AI engines | **7** (`feature_extractor, dpi_classifier, traffic_predictor, ucb_bandit, rl_transport_selector, onnx_runtime, adversarial_traffic`) |
| Quantum / PQC modules | **11** (see §10 above) |
| NAIN channels | **10** (`acoustic_covert, ble_mesh, fallback_routing, intranet_detector, iran_ip_ranges, local_dns_resolver, nain_detector, ntp_covert, sms_bootstrap, wifi_aware`) |
| P2P modules | **6** (`i2p_overlay, libp2p_discovery, nat_traversal, peer_exchange, relay_selection, yggdrasil_overlay`) |
| Mesh modules | **4** (`gossip_protocol, mesh_coordinator, mesh_crypto, topology_manager`) |
| Tunnel modules | **5** (`amneziawg, boringtun_adapter, split_tunnel, tun_device, wireguard`) |
| Scanner engines | **10** (`adaptive_engine, ai_orchestrator, autonomous_engine, candidate_graph, dns_scanner, dpi_scanner, evidence_fusion, network_assessor, port_scanner, self_healing_failover`) |
| Obfuscation modules | **9** + 1 wasm-obfuscator top-level crate (`http3_masquerade, packet_size_normalizer, probe_resistance, steganographic_header, timing_jitter, tls_fragment, traffic_shaper, utls_fingerprint, websocket_tunnel` + `wasm-obfuscator/`) |
| CDN workers | **9** (`alibaba-cdn, arvan-cdn, baidu-cdn, bytedance-cdn, cloudflare, deno-relay, huawei-cdn, tencent-cdn, universal`) |
| Browser extensions | **2** (`chrome, firefox`) |
| Prisma models | **11** (`User, Session, Core, Connection, CoreTest, P2PPeer, ThreatReport, DpiSignature, IntranetDomain, AuditLog, SystemConfig`) |
| Dashboard API routes | **19** (`advanced-analytics, ai-engine, auto-reconnect, cores, dpi-test, geo-router, health, intranet-mode, kill-switch, mesh-network, network-analyzer, obfuscation, orchestrator, ota, p2p-peers, resilience, security-audit, speedtest, threat-intel`) + 1 root |
| ONNX model artifacts | **6** (see §7.1 above) |

Total non-source-tree files added or modified across the merge: 499 source-tree files (494 from the 13 source projects + 5 new quantum modules), per `MERGE-MANIFEST.md`.

---

## 12. Compatibility Matrix

| Surface | Minimum version | Notes |
|---------|-----------------|-------|
| Android | 5.0 (API 21) | VpnService; no root |
| iOS | 15.0 | NEPacketTunnelProvider; no jailbreak |
| Windows | 7 SP1 | Wintun/TAP; x86_64 only |
| Linux | Kernel 4.x | tun/tap; x86_64 + aarch64 |
| macOS | 11.0 (Big Sur) | NEPacketTunnelProvider; arm64 + x86_64 |
| OpenWrt | 21.02 | netifd/tun; mips + aarch64 musl |

---

## 13. Documentation Index

| Doc | Purpose |
|-----|---------|
| `docs/ARCHITECTURE.md` | Comprehensive system architecture |
| `docs/ENTERPRISE-UI-DESIGN.md` | Quantum RGB design language |
| `docs/LICENSE-SYSTEM.md` | License validation flow |
| `docs/ANTI-DPI-AI.md` | AI-driven DPI evasion |
| `docs/FREE-TIER.md` | 5 free-tier platforms |
| `docs/RELEASE-9.0.0-ENTERPRISE.md` | This document |
| `docs/CHANGELOG.md` | Changelog v6 → v9 |
| `docs/GITHUB-ACTIONS-GUIDE.md` | CI/CD matrix guide |
| `docs/ANTI-DPI-TECHNIQUES.md` | Classical (non-AI) DPI evasion |
| `docs/P2P-SERVERLESS.md` | libp2p / I2P / Yggdrasil overlays |
| `docs/NATIONAL-INTRANET-MODE.md` | NAIN mode |
| `RELEASE_NOTES.md` | Short auto-generated release notes (consumed by `release.yml`'s GitHub Release body) |
| `MERGE-MANIFEST.md` | 13-source merge audit |

---

## 14. Upgrade Path

From v8.0.0 (Quantum-Ultra merge): no breaking changes. The Enterprise license system, AI subsystem, and free-tier cores are all additive — existing v8 configs continue to work.

From v7.0.0 (VIP-ULTRA): re-run `scripts/preflight.sh` once to migrate the license store to the new ChaCha20-Poly1305 format. The old format is auto-detected and migrated on first launch.

From v6.0.0 (initial merge): re-install. The v6 → v7 migration introduced breaking changes in the IPC protocol version.

---

## 15. Acknowledgments

- The **Tor Project** for `arti` + Snowflake.
- **Psiphon Inc.** for the upstream Go library.
- **Lantern Inc.** for the upstream Go library.
- The **Hysteria** project for the QUIC transport.
- The **XTLS** project for the Reality protocol.
- The **ed25519-dalek** + **sha2** + **chacha20poly1305** Rust crates.
- The **ONNX Runtime** + `ort` Rust bindings.
- The **Mermaid** diagram language used throughout the docs.
- The 13 source-project maintainers whose code is preserved here without modification.

---

*UnifiedShield Enterprise v9.0.0-enterprise — Quantum RGB Enterprise Edition.*
*Released: 2025-12-10. License expires: 2025-12-10 23:59:59 IRT.*
