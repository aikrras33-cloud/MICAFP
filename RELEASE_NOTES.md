# UnifiedShield v9.0.0-enterprise — Quantum RGB Enterprise Edition

> **Short auto-generated release notes — consumed by `.github/workflows/release.yml`'s GitHub Release body.**

Released: **2025-12-10** (Azar 19 1404 IRT — license expiry synchronized with this date).

Tag: `v9.0.0-enterprise`

---

## Highlights

- **🎨 Quantum Enterprise RGB UI** — dark-first, glassmorphism, 9-stop RGB gradient ring on the connect button, 60-FPS animation budget, max-3-simultaneous-animations rule, custom replacements for Material 2 `Switch` / `Checkbox` / `Dialog` / `SnackBar` / `CircularProgressIndicator`. Cross-surface token parity across Flutter, Next.js, browser extensions, Android Compose, iOS SwiftUI.

- **🔐 Enterprise license system (Azar 19 1404 expiry)** — SHA-256 canonical-string anti-tamper + Ed25519 detached signature + monotonic-clock anti-rollback. 4-cell countdown (days/hours/minutes/seconds) with Persian numerals when `Locale("fa")`. Pre-expiry ladder: T−24h toast → T−1h push → T−5m push → T−0 force-disconnect. Three storage backends (Android Keychain, iOS Keychain, Desktop SecureStorage with ChaCha20-Poly1305). Zero phone-home.

- **🤖 Anti-Iran-DPI AI subsystem** — `feature_extractor → dpi_classifier → traffic_predictor → ucb_bandit → rl_transport_selector → switch` pipeline with 6 committed ONNX models. ISP detection via ASN + DNS-injection + NTP + Arvan-Cloud RTT. 8-step resilience fallback chain. Anti-active-probing (probe_resistance + ephemeral_identity + Reality). Anti-traffic-analysis (traffic_shaper + timing_jitter + packet_size_normalizer + dp_noise). Calculator-disguise steganography with 5-tap wipe. Adversarial-traffic GAN.

- **🆓 Free-tier integration (5 platforms)** — Tor+Snowflake, Psiphon, Lantern, Hysteria2 community, VLESS-Reality community. Always-available, no Enterprise license required. Weekly Monday-03:00-UTC auto-discovery via `scripts/refresh-free-servers.py` + `.github/workflows/refresh-free-servers.yml`. Bypass success-rate target ≥95% across the 5 cores × 3 Iranian ISPs (15 cells). PC app exposes the active free-tier core as a SOCKS5 proxy on `127.0.0.1` (ports 9050, 9080, 9081, 9090, 9091).

- **🧠 On-device LLM + cloud Gemini assistant** — `llama-cpp-2` QuantQ3_K_M GGUF model committed to `models/`, streamed token-by-token via `EventChannel("unifiedshield/ai_stream")`. Zero network calls during inference. Cloud Gemini as opt-in fallback only when on-device refuses twice AND the daemon is in a non-Iranian exit country.

---

## Build artifacts — 18 produced by a 12-cell GitHub Actions matrix

`.github/workflows/release.yml` runs 12 parallel cells (5 Android + 2 iOS + 1 macOS + 1 Windows + 2 Linux + 1 OpenWrt) producing 18 artifacts: 3 Android APKs + 1 AAB, 1 iOS IPA, 1 macOS .app + 1 .dmg, 1 Windows .exe + 1 .msi, 2 Linux .deb + 1 .rpm + 1 AppImage + 1 PKGBUILD + 1 systemd unit, 2 OpenWrt .ipk, 2 browser-extension .zip. `fail-fast: false` so every cell completes regardless of sibling failures.

## Auto-fix CI loop

`.github/workflows/auto-fix.yml` triggers on `ci.yml` / `release.yml` failures, classifies into 6 buckets (`missing-dep / missing-file / api-drift / lint / path-mismatch / type-mismatch`), applies regex-driven patches, commits `fix(ci): auto-remediate {bucket} ({n} files)`, opens a GitHub Issue after 3 stalled rounds.

## Zero-data-loss audit

Per the directive's invariant, the merge preserves — across all 13 source projects:
- 27 daemon modules · 22 transports · 9 cores (+ 3 free-tier = 12) · 7 AI engines · 11 quantum/PQC modules · 10 NAIN channels · 6 P2P · 4 mesh · 5 tunnel · 10 scanner · 9 obfuscation + 1 wasm-obfuscator crate · 9 CDN workers · 2 browser extensions · 11 Prisma models · 19 dashboard API routes · 6 ONNX model artifacts.

---

## Full release notes

👉 **See [`docs/RELEASE-9.0.0-ENTERPRISE.md`](docs/RELEASE-9.0.0-ENTERPRISE.md)** for the complete release notes including the full build-artifact matrix, GitHub Actions 12-cell matrix, auto-fix loop, Quantum Enterprise RGB UI, license system with Azar-19-1404 expiry, anti-Iran-DPI AI subsystem, free-tier integration, on-device LLM + cloud Gemini, quantum/PQC cryptography, zero-data-loss audit, compatibility matrix, documentation index, upgrade path, and acknowledgments.

Other docs:
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — comprehensive system architecture
- [`docs/ENTERPRISE-UI-DESIGN.md`](docs/ENTERPRISE-UI-DESIGN.md) — Quantum RGB design language
- [`docs/LICENSE-SYSTEM.md`](docs/LICENSE-SYSTEM.md) — license validation flow
- [`docs/ANTI-DPI-AI.md`](docs/ANTI-DPI-AI.md) — AI-driven DPI evasion
- [`docs/FREE-TIER.md`](docs/FREE-TIER.md) — 5 free-tier platforms
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md) — changelog v6 → v9
- [`MERGE-MANIFEST.md`](MERGE-MANIFEST.md) — 13-source merge audit

---

*UnifiedShield Enterprise v9.0.0-enterprise — Quantum RGB Enterprise Edition.*
*Released: 2025-12-10. License expires: 2025-12-10 23:59:59 IRT.*
