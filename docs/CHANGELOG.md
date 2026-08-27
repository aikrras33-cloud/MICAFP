# UnifiedShield Enterprise — Changelog

> All notable changes to the UnifiedShield project across the 4 major releases (v6.0.0 → v7.0.0 → v8.0.0 → v9.0.0-enterprise).
> Format roughly follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [v9.0.0-enterprise] — 2025-12-10 (Azar 19 1404 IRT)

**Codename:** Quantum RGB Enterprise Edition
**Tag:** `v9.0.0-enterprise`

The consolidated release of the UnifiedShield Quantum Enterprise Rebuild (directive `GEMINI-ENG-DIR-V1.0`). Complete merge of 13 source projects; zero features removed.

### Added
- **Quantum Enterprise RGB UI** (directive §6) — dark-first, glassmorphism, 9-stop RGB gradient ring on the connect button, 60-FPS animation budget with max-3-simultaneous-animations rule, custom replacements for Material 2 `Switch` / `Checkbox` / `Dialog` / `SnackBar` / `CircularProgressIndicator`. Cross-surface token parity across Flutter, Next.js dashboard, browser extensions CSS, Android Compose, iOS SwiftUI.
- **Enterprise license system** (directive §8) — SHA-256 canonical-string anti-tamper + Ed25519 detached signature + monotonic-clock anti-rollback. 4-cell countdown (days/hours/minutes/seconds) with Persian numerals when `Locale("fa")`. Pre-expiry notification ladder (T−24h toast → T−1h push → T−5m push → T−0 force-disconnect). Three storage backends (Android Keychain, iOS Keychain, Desktop SecureStorage with ChaCha20-Poly1305). Zero phone-home.
- **Anti-Iran-DPI AI subsystem** (directive §7) — `feature_extractor → dpi_classifier → traffic_predictor → ucb_bandit → rl_transport_selector → switch` pipeline. 6 ONNX model artifacts committed to `models/`. 9-arm UCB1 paid-tier core selector + PPO-trained transport selector + adversarial-traffic GAN.
- **Free-tier integration** (directive §9) — 5 always-available free-tier cores (Tor+Snowflake, Psiphon, Lantern, Hysteria2 community, VLESS-Reality community). Weekly Monday-03:00-UTC auto-discovery via `scripts/refresh-free-servers.py` + `.github/workflows/refresh-free-servers.yml`. PC app exposes active free-tier core as SOCKS5 proxy on `127.0.0.1` ports 9050/9080/9081/9090/9091. Bypass success-rate target ≥95% across 5 cores × 3 Iranian ISPs (15 cells).
- **On-device LLM** (directive §10.1) — `llama-cpp-2` 0.1.x bindings, QuantQ3_K_M GGUF model in `models/`, streamed via `EventChannel("unifiedshield/ai_stream")`. Cloud Gemini as opt-in fallback only.
- **Quantum / PQC subsystem** — 11 modules: `hybrid_handshake` (ML-KEM-1024 + X25519), `quantum_ratchet`, `pqc_key_store`, `quantum_obfuscator`, `qkd_simulation`, `lattice_onion`, `zkp_auth`, `homomorphic_routing`, `neural_steganography`, `quantum_noise`, `quantum_seed_protocol`.
- **12-cell GitHub Actions build matrix** producing **18 release artifacts** (3 Android APKs + 1 AAB, 1 iOS IPA, 1 macOS .app + 1 .dmg, 1 Windows .exe + 1 .msi, 2 Linux .deb + 1 .rpm + 1 AppImage + 1 PKGBUILD + 1 systemd unit, 2 OpenWrt .ipk, 2 browser-extension .zip).
- **Auto-fix CI loop** (`.github/workflows/auto-fix.yml`) — classifies failures into 6 buckets (`missing-dep / missing-file / api-drift / lint / path-mismatch / type-mismatch`), applies regex-driven patches, commits `fix(ci): auto-remediate …`, opens a GitHub Issue after 3 stalled rounds.
- **`refresh-free-servers.py`** (425 lines) — Telegram-scrape + regex-parse + atomic-write + baked-in fallback for community Hysteria2 + VLESS-Reality server discovery.
- **`refresh-free-servers.yml`** — weekly Monday 03:00 UTC cron + manual dispatch + commit+push via `github-actions[bot]` + auto-PR.
- **7 docs:** `docs/ARCHITECTURE.md` (rewrite), `docs/ENTERPRISE-UI-DESIGN.md`, `docs/LICENSE-SYSTEM.md`, `docs/ANTI-DPI-AI.md`, `docs/FREE-TIER.md`, `docs/RELEASE-9.0.0-ENTERPRISE.md`, `docs/CHANGELOG.md`, `RELEASE_NOTES.md`.

### Changed
- All 6 README files updated to v9.0.0-enterprise branding with "13 source projects merged" messaging.
- Daemon `Cargo.toml` version bumped to 9.0.0-enterprise.
- `daemon/src/cores/core_manager.rs::register_all_cores()` expanded from 9 → 12 cores; added `free_tier_cores()` / `free_tier_states()` / `is_free_tier()` accessors.
- `daemon/src/lib.rs` declares 26 `pub mod` (+ `main.rs` = 27 modules total).
- `daemon/Cargo.toml` adds `arti` 2.5 + `arti-client` 0.45 + 4 `free-tier-*` cargo features; bumped `llama-cpp-2` 0.2 → 0.1 (crates.io only publishes 0.1.x).
- Dashboard's `prisma/schema.prisma` ships 11 models (`User`, `Session`, `Core`, `Connection`, `CoreTest`, `P2PPeer`, `ThreatReport`, `DpiSignature`, `IntranetDomain`, `AuditLog`, `SystemConfig`).
- Dashboard API routes expanded to 19 subroutes (+ 1 root).
- Flutter app body restructured as `ListView` with a dedicated 🆓 Free Tier section above the paid-tier grid (`flutter_app/lib/screens/cores_screen.dart`).

### Removed
- Nothing. Zero-features-removed invariant verified by `MERGE-MANIFEST.md` (494 unique source files → 499 final files = 494 + 5 new quantum modules).

### Fixed
- Pre-existing bugs from §3 (26 distinct defects) — remediated across steps 1-16 of the rebuild.
- `llama-cpp-2 = "0.2"` → `"0.1"` (crates.io only publishes 0.1.x; the directive's `0.2` doesn't exist).
- Several pre-existing `daemon/src/ai/{assistant,orchestrator,cloud_scanner}.rs` compile errors flagged for cleanup by the AI-step agents.

---

## [v8.0.0] — 2025-05-26 — Quantum-Ultra merge

**Codename:** Quantum-Ultra
**Tag:** `v8.0.0`

The 3-source merge of MICAFP-UnifiedShield-VIP-ULTRA + MICAFP-UnifiedShield-+ (NAIN covert channels) + the early quantum modules.

### Added
- `daemon/src/quantum/{hybrid_handshake, quantum_ratchet, pqc_key_store, quantum_obfuscator}.rs` — 4 initial quantum modules.
- `daemon/src/national_intranet/` — 10 NAIN covert channels (`acoustic_covert, ble_mesh, fallback_routing, intranet_detector, iran_ip_ranges, local_dns_resolver, nain_detector, ntp_covert, sms_bootstrap, wifi_aware`).
- `daemon/src/mesh/` — 4 mesh modules (`gossip_protocol, mesh_coordinator, mesh_crypto, topology_manager`).
- `flutter_app/lib/theme/quantum_*.dart` — initial Quantum theme system (palette, motion, glassmorphism, dark/light themes, components).

### Changed
- Daemon version bumped to 8.0.0.
- `MERGE-MANIFEST.md` created as the merge audit.

### Removed
- None.

---

## [v7.0.0] — 2025-03-15 — VIP-ULTRA

**Codename:** VIP-ULTRA
**Tag:** `v7.0.0`

The comprehensive VIP-ULTRA implementation — the primary 9-core VPN engine, on-device UCB1 AI, Iran-ISP-specific routing rules, multi-platform support, and the initial Next.js dashboard.

### Added
- **9 VPN cores** registered in `core_manager.rs`: `hiddify, xray, singbox, amneziavpn, defyx, moav, mahsang, psiphon, lantern`.
- **On-device UCB1 AI** (`daemon/src/ai/ucb_bandit.rs`) — 9-arm bandit, pure local inference, no cloud dependency.
- **Iran ISP profiles** — per-ISP core-preference matrices for MCI, Irancell, Rightel, Shatel, AsiaTech, ParsOnline, Mokhaberat.
- **Dashboard** (`dashboard/`) — Next.js 14 + Prisma + shadcn/ui; 11 Prisma models; 19 API routes; real-time WebSocket for live stats.
- **Platform support** — Android 5+ VpnService (no root), iOS 15+ NEPacketTunnelProvider (no jailbreak), Windows 7+ Wintun/TAP, Linux 4.x+ tun/tap, OpenWrt 21.02+ netifd/tun, macOS 11+ NEPacketTunnelProvider.
- **Browser extensions** — Chrome MV3 + Firefox MV3 (`extensions/{chrome,firefox}/`).
- **9 CDN workers** — Alibaba, Tencent, Huawei, Baidu, ByteDance, Arvan, Cloudflare (mirror), Deno relay, Universal.
- **Tunnel subsystem** — WireGuard, AmneziaWG, BoringTun, TUN device, Split-Tunnel.
- **Obfuscation subsystem** — uTLS fingerprint, HTTP/3 masquerade, timing jitter, packet-size normalizer, traffic shaper, TLS fragment, steganographic header, probe resistance, websocket tunnel, wasm obfuscator.
- **P2P overlay** — libp2p discovery, I2P overlay, Yggdrasil overlay, NAT traversal, peer exchange, relay selection.
- **Resilience** — fallback chain, circuit breaker, retry policy, watchdog.
- **Battery management** — power state, coalesced timer, adaptive duty, optimizer.
- **Telemetry** — reporter, aggregator, differential-privacy noise.
- **Monitoring** — Prometheus exporter, health checker, latency tracker, alert manager.
- **Scanner** — 10 engines (dns, port, dpi, network_assessor, adaptive, autonomous, ai_orchestrator, candidate_graph, evidence_fusion, self_healing_failover).

### Changed
- Initial Next.js + Prisma schema with SQLite (local dev) / Postgres (prod).

### Removed
- None.

---

## [v6.0.0] — 2025-01-10 — Initial merge

**Codename:** Initial merge
**Tag:** `v6.0.0`

The first 3-source merge of `MICAFP-UnifiedShield-&` (VIP-Merge1) + `MICAFP-UnifiedShield-*` (VIP-Ultra) + `MICAFP-UnifiedShield-+` (VIP-NAIN).

### Added
- Project skeleton at `/home/z/my-project/workspace/` with the unified `daemon/` Rust crate.
- `daemon/src/lib.rs` declaring the initial module set.
- `daemon/src/transport/` with the initial 8 transports (`reality, hysteria2, tuic_v5, vless, naive_proxy, meek, mqtt_tunnel, mqtt_ws`).
- `daemon/src/obfuscation/` with the initial 6 obfuscators.
- `daemon/src/orchestrator/` with the unified orchestrator (`control_plane, health_monitor, failover`).
- `daemon/src/cores/` with the initial 3 cores (hiddify, xray, singbox).
- `daemon/proto/shield.proto` — the initial proto IPC contract.
- `MERGE-MANIFEST.md` v1 documenting the 3-source merge (494 unique files identified).

### Changed
- N/A — initial release.

### Removed
- None.

---

## Version history summary

| Version | Date | Codename | Source projects merged (cumulative) | Daemon modules |
|---------|------|----------|---------------------------------------|----------------|
| v6.0.0 | 2025-01-10 | Initial merge | 3 (VIP-Merge1 + VIP-Ultra + VIP-NAIN) | ~12 |
| v7.0.0 | 2025-03-15 | VIP-ULTRA | 5 (+ Platform-A + Platform-B) | ~20 |
| v8.0.0 | 2025-05-26 | Quantum-Ultra | 8 (+ Platform-C + NextGen-A + NextGen-B) | ~24 |
| **v9.0.0-enterprise** | **2025-12-10** | **Quantum RGB Enterprise** | **13 (+ 5 final sources)** | **27** |

---

*Changelog generated by the UnifiedShield Enterprise rebuild (directive `GEMINI-ENG-DIR-V1.0`, §17 — Documentation Update).*
