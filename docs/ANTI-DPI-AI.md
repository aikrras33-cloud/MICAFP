# UnifiedShield Enterprise v9.0.0-enterprise — AI-Driven DPI Evasion

> **Authoritative reference for the AI subsystem that powers UnifiedShield's
> Iran-DPI evasion.** Covers (1) the reality of Iran's filtering landscape,
> (2) the `feature_extractor → ONNX → bandit → switch` pipeline,
> (3) the 6 committed ONNX model artifacts, (4) ISP detection heuristics,
> (5) the 8-step resilience fallback chain, (6) anti-active-probing defenses,
> (7) anti-traffic-analysis defenses, (8) the steganography layer, and
> (9) the adversarial-traffic GAN.

Source code: `daemon/src/ai/` (`feature_extractor.rs`, `dpi_classifier.rs`, `traffic_predictor.rs`, `ucb_bandit.rs`, `rl_transport_selector.rs`, `onnx_runtime.rs`, `adversarial_traffic.rs`) + `daemon/src/obfuscation/` + `daemon/src/security/ephemeral_identity.rs` + `daemon/src/resilience/fallback_chain.rs`.

See also: `docs/ANTI-DPI-TECHNIQUES.md` for the classical (non-AI) evasion techniques that this document builds on.

---

## 1. Iran Filtering Reality Check (which transports work, which are blocked)

Empirically observed over the 2024–2025 reporting period:

| Transport | Status | Notes |
|-----------|--------|-------|
| **XTLS-Reality** | ✅ Works | Steals a real website's TLS handshake; survives active probing. |
| **VLESS-Reality (community)** | ✅ Works | Same principle, community-hosted. |
| **Hysteria2 (QUIC)** | ✅ Works | QUIC is harder to fingerprint; "Brutal" congestion control defeats throttling. |
| **TUICv5 (QUIC)** | ✅ Works | Same as Hysteria2; better for UDP relay. |
| **Shadowsocks-2022** | ⚠️ Spotty | Sometimes flagged by entropy analysis; padding + size-normalization required. |
| **WireGuard** | ❌ Blocked | UDP port 51820 fingerprinted and throttled at MCI/Mokhaberat. |
| **AmneziaWG** | ✅ Works | WireGuard with junk headers defeats the WG fingerprint. |
| **Trojan** | ⚠️ Spotty | TLS-SNI still visible; needs SNI-fronting. |
| **NaïveProxy** | ✅ Works | Uses Chromium's actual net stack; zero fingerprint difference. |
| **Domain Fronting (via Chinese CDN)** | ✅ Works | Alibaba/Tencent CDNs not blocked. |
| **Domain Fronting (via Cloudflare)** | ❌ Blocked | Cloudflare IP ranges hard-blocked in Iran. |
| **Tor (direct)** | ❌ Blocked | 6/9 directory authorities are IP-blocked; entry guards blocked. |
| **Tor + Snowflake** | ✅ Works | Snowflake's WebRTC-volunteer-bridge model escapes the IP-blocklist. |
| **Psiphon (with meek-fronting)** | ✅ Works | CDN-fronted; survives active probing. |
| **Lantern** | ✅ Works (slow) | Domain-fronted; throttled at MCI. |
| **ProtonVPN** | ❌ Blocked | All Proton exit IPs are on Iran's IP-blocklist. |
| **Windscribe** | ❌ Blocked | Same. |
| **Cloudflare WARP (1.1.1.1)** | ❌ Blocked | WARP endpoints are hard-blocked at ISP level. |
| **MQTT-over-WSS (cloudflare_worker)** | ✅ Works | Masquerades as IoT MQTT-over-WebSocket; survives SNI inspection. |
| **DoH/DoQ (AliDNS/DNSPod)** | ✅ Works | Persian-region DoH/DoQ upstreams. |

The "blocked" set is updated quarterly by `scripts/refresh-free-servers.py` and is encoded into `configs/isp-profiles.json` (per-ISP throttling/blocked-port matrices).

---

## 2. AI Architecture

The pipeline runs at every connection attempt and every 60 seconds during an active session:

```mermaid
flowchart LR
    TRACE[Packet Trace<br/>last 5000 pkts]
    FE[feature_extractor<br/>extract FeatureVec[128]]
    CLS[dpi_classifier<br/>ONNX 6-class]
    PRED[traffic_predictor<br/>ONNX 60s forecast]
    BAND[ucb_bandit<br/>9-arm UCB1]
    RL[rl_transport_selector<br/>PPO]
    SW[switch_core / switch_transport]
    RES[Resilience fallback chain<br/>8 steps]

    TRACE --> FE
    FE --> CLS
    FE --> PRED
    CLS --> BAND
    CLS --> RL
    PRED --> BAND
    PRED --> RL
    BAND --> SW
    RL --> SW
    SW -->|on failure| RES
```

### 2.1 `feature_extractor` — 128-feature vector

Source: `daemon/src/ai/feature_extractor.rs`.

Computes a fixed-length 128-f32 feature vector from the last 5000 packets. The feature layout (per the Python mirror at `ai-models/train/feature_engineering.py`):

| Index range | Feature family |
|-------------|----------------|
| 0–9 | Packet-size percentiles (p10, p20, …, p90, p99) |
| 10–19 | Inter-arrival-time percentiles |
| 20–24 | Flow duration, byte-count, packet-count, mean pkt-size, mean IAT |
| 25–44 | TLS-ClientHello fields (version, cipher-suites histogram 0–14, extensions bitmap, ALPN, SNI length, JA3 fragment) |
| 45–54 | QUIC connection-ID lengths + DCID entropy |
| 55–64 | Direction ratios (in:out byte ratio, in:out pkt ratio, …) |
| 65–84 | Burst statistics (5 burst-count, 5 burst-size percentiles, …) |
| 85–99 | Hour-of-day + day-of-week one-hot |
| 100–127 | Reserved padding (zeros) for forward-compat |

### 2.2 `dpi_classifier` — 6-class ONNX

Source: `daemon/src/ai/dpi_classifier.rs`. Consumes `models/dpi_classifier.onnx` (or the int8-quantized variant for low-end devices).

Output is a 6-class softmax over:
1. `clean` — no DPI signature detected
2. `tls_reset` — DPI is injecting TLS RST after SNI inspection
3. `http_403` — DPI is returning HTTP 403 after Host-header inspection
4. `null_route` — DPI is dropping packets silently (blackholing)
5. `sni_filter` — DPI is matching the SNI against a blocklist
6. `dns_poison` — DPI is poisoning DNS responses

The argmax class determines which **fallback transport** is selected (see §2.5 below).

### 2.3 `traffic_predictor` — 60-second-ahead forecast

Source: `daemon/src/ai/traffic_predictor.rs`. Consumes `models/traffic_predictor.onnx`.

Input: a `(1, 60, 4)` tensor = last 60 seconds of `[rx_bytes, tx_bytes, rtt_ms, loss_ratio]`.
Output: a `(1, 60, 2)` tensor = forecast `[rx_bytes, rtt_ms]` for the next 60 seconds.

The forecast is fed into the `ucb_bandit` reward model (§2.4) so the bandit can down-rank a core that's predicted to be slow in the near future even if it has performed well historically.

### 2.4 `ucb_bandit` — 9-arm UCB1 paid-tier core selector

Source: `daemon/src/ai/ucb_bandit.rs`. The 9 paid-tier cores are enumerated by `CoreArm` (matched 1:1 against `cores::CoreId`):

```
arm 0: hiddify
arm 1: xray
arm 2: singbox
arm 3: amneziavpn
arm 4: defyx
arm 5: moav
arm 6: mahsang
arm 7: psiphon
arm 8: lantern
```

(The 3 free-tier arms — `tor_snowflake`, `hysteria2_community`, `vless_reality_community` — are NOT in the bandit; they are switched-to manually via `free_tier_cores()` and the health monitor's `match core_id.as_str()` skips their reward update.)

The bandit computes `UCB1(arm) = μ(arm) + c × √(ln(N) / n(arm))` with `c = √2 ≈ 1.414`. The reward `μ(arm)` is a weighted blend of:
- 0.40 × inverse-mean-RTT
- 0.30 × throughput (bytes/sec)
- 0.20 × inverse-packet-loss
- 0.10 × traffic_predictor's 60s-ahead RTT forecast (negative correlation)

### 2.5 `rl_transport_selector` — PPO-trained transport picker

Source: `daemon/src/ai/rl_transport_selector.rs`. Consumes `models/transport_selector_ppo.onnx`.

State (32-dim f32): concatenation of (a) `dpi_classifier` argmax one-hot (6) + (b) current-ISP-id one-hot (8) + (c) hour-of-day one-hot (24) — total 38 dims, projected down to 32 by a learned linear layer baked into the ONNX.

Action space: 22 transports (one-hot, 22 dims).

The selector is invoked when the `dpi_classifier` detects a non-clean class — the argmax class is mapped to a transport-swap heuristic:
- `tls_reset` / `sni_filter` → switch to a TLS-less transport (QUIC-based: `hysteria2`, `tuic_v5`, or `mqtt_ws`)
- `http_403` → switch to a non-HTTP fronting transport (`reality` or `shadow_tls`)
- `null_route` → switch transport + rotate server IP via `ephemeral_identity`
- `dns_poison` → activate `local_dns_resolver` + switch to DoH/DoQ upstream

### 2.6 `onnx_runtime` — model registry

Source: `daemon/src/ai/onnx_runtime.rs`. Uses the `ort` crate (ONNX Runtime C-API bindings). The `ModelRegistry::load_all()` loader resolves paths via `daemon/build.rs`:
- `models/dpi_classifier.onnx`
- `models/dpi_classifier_int8.onnx`
- `models/traffic_predictor.onnx`
- `models/traffic_predictor_int8.onnx`
- `models/transport_selector_ppo.onnx`
- `models/adversarial_traffic_gan.onnx`

The int8 variants are auto-selected when the device's `available_memory < 2 GiB` (Android Go / older iPhones).

---

## 3. ONNX Model Artifacts — 6 Files Committed to `models/`

| File | Engine | Input → Output | Notes |
|------|--------|-----------------|-------|
| `dpi_classifier.onnx` | dpi_classifier | `[1,128] f32 → [1,6] f32` | 6-class softmax; F1≈0.92 on the held-out Iran test set. |
| `dpi_classifier_int8.onnx` | dpi_classifier | same shape, int8 weights | 4× smaller, 2× faster on ARM Cortex-A55; F1≈0.89. |
| `traffic_predictor.onnx` | traffic_predictor | `[1,60,4] f32 → [1,60,2] f32` | 2-layer LSTM; MAE 8 ms on RTT. |
| `traffic_predictor_int8.onnx` | traffic_predictor | same shape, int8 weights | For low-RAM devices. |
| `transport_selector_ppo.onnx` | rl_transport_selector | `[1,32] f32 → [1,22] f32` | PPO actor net; trained over 5 M environment steps. |
| `adversarial_traffic_gan.onnx` | adversarial_traffic | `[1,100] f32 (noise) → [1,64,64,1] f32` | GAN generator; produces 4-KiB adversarial traffic micro-bursts. |

All 6 are committed to `models/` (Git-LFS tracked). `scripts/preflight.sh` verifies their SHA-256s against `models/MANIFEST.sha256` before every release.

Training pipelines live in `ai-models/train/`:
- `feature_engineering.py` — produces the 128-dim feature vector
- `dpi_classifier_train.py` — trains the classifier (PyTorch → ONNX export)
- `traffic_predictor_train.py` — trains the LSTM (PyTorch → ONNX export)
- `adversarial_traffic_gan.py` — trains the GAN
- `dataset_collector.py` — collects packet traces from `tests/censorship-simulation/iran_dpi_simulator.py`

Quantization: `ai-models/quantize/quantize_models.py` produces the int8 ONNX variants; `validate_onnx.py` cross-checks parity with the FP32 originals.

---

## 4. ISP Detection

Source: `daemon/src/config/isp_profiles.rs` + `flutter_app/lib/services/isp_detector.dart` + `extensions/shared/isp-database.ts` (browser-extension mirror).

Four orthogonal detection signals are fused into an `IspId` enum (`MCI / Irancell / Rightel / Shatel / ParsOnline / Mokhaberat / AsiaTech / Other`):

### 4.1 ASN lookup
The daemon's `libp2p` peer records carry the upstream ASN. The big-5 Iranian ASNs:
- `AS197207` — MCI (همراه اول)
- `AS44244` — Irancell (ایرانسل)
- `AS49581` — Rightel (رایتل)
- `AS31549` — Shatel (شتل)
- `AS16322` — ParsOnline (پارس‌آنلاین)
- `AS58224` — Mokhaberat (مخابرات)
- `AS43740` — AsiaTech (آسیاتک)

### 4.2 DNS-injection probe
The daemon sends a DNS query for a random non-existent TLD (e.g. `<random>.zzz`). If the response is non-empty, the ISP is injecting; this signal alone is enough to classify MCI vs Irancell (MCI returns NXDOMAIN without injection, while Irancell returns an injected A-record).

### 4.3 NTP-monlist probe
The daemon queries `time.asis-ir.pool.ntp.org` and `time.iranpool.ntp.org`. The response characteristics (filtered vs unfiltered) provide a secondary ISP signal.

### 4.4 Arvan Cloud probe
The daemon hits `https://www.arvancloud.com/` and measures RTT. Arvan is Iranian-hosted, so an RTT < 5 ms is a strong signal that the device is on an Iranian ISP (vs a VPN exit). Used to confirm "intranet mode" eligibility.

The four signals are weighted into a softmax and the argmax is the `IspId`. Per-ISP core-preference matrices (`configs/isp-profiles.json`) then bias the bandit's reward prior:
- MCI prefers `mahsang` + `amneziavpn`
- Irancell prefers `hiddify` + `defyx`
- Shatel prefers `amneziavpn` + `psiphon`
- AsiaTech prefers `mahsang` + `hiddify`
- Rightel prefers `defyx` + `hiddify`
- Mokhaberat prefers `xray` (GFW-knocker fork is the only one that survives the heavy active-probing)
- ParsOnline is "relatively open" — no preference, falls through to UCB1's natural exploration.

---

## 5. Resilience Fallback Chain — 8 Steps

Source: `daemon/src/resilience/fallback_chain.rs`.

When a connection drops, the chain executes the 8 steps in order, each with a budget timeout. A failed step falls through to the next. The total ladder has a 60-second ceiling; failure of all 8 steps engages the kill-switch permanently.

| Step | Action | Budget | Triggered by |
|------|--------|--------|-------------|
| 1 | Re-establish on the same core + transport | 2 s | Brief UDP/QUIC packet loss |
| 2 | Switch to next transport on same core (e.g. `reality` → `shadow_tls`) | 5 s | Transport-layer failure |
| 3 | Switch to next core in the same tier (paid→paid, free→free) | 8 s | Core-layer failure |
| 4 | Drop to free-tier fallback (`tor_snowflake` → `psiphon` → `lantern` → `hysteria2_community` → `vless_reality_community`) | 5 s | All paid cores blocked |
| 5 | Activate NAIN fallback (`fallback_routing`) + national intranet mode | 5 s | Iran-wide outage |
| 6 | Activate P2P relay (`p2p::relay_selection`) + mesh coordinator | 10 s | Direct egress blocked |
| 7 | Activate NTP/SMS covert channel (`ntp_covert` / `sms_bootstrap`) | 10 s | TCP/UDP both blocked |
| 8 | Hard kill-switch stays engaged; surface "walled-garden" UI | ∞ | Total blackout |

`daemon/src/resilience/circuit_breaker.rs` opens after 3 consecutive failed ladders and refuses new attempts for 30 s (exponential back-off up to 10 min).

`daemon/src/resilience/retry_policy.rs` configures the per-step retry count (default 2 retries per step before falling through).

---

## 6. Anti-Active-Probing Defenses

Source: `daemon/src/obfuscation/probe_resistance.rs` + `daemon/src/security/ephemeral_identity.rs` + `daemon/src/transport/reality.rs`.

Iran's DPI periodically performs **active probing** — it connects to a suspected proxy server and inspects the handshake to confirm it's a proxy.

### 6.1 `probe_resistance` — masquerade-and-route
Drops any inbound connection whose TLS ClientHello doesn't match the registered client "password". Non-matching handshakes are transparently reverse-proxied to the real masquerade target (e.g. `www.microsoft.com`), so the prober sees a perfectly valid, perfectly boring website.

### 6.2 `ephemeral_identity` — periodic identity rotation
Rotates the daemon's listening identity (port + keypair + TLS certificate) every 5 minutes, or immediately on probe-detection. The previous identity is wiped from memory with `zeroize()`.

### 6.3 **Reality** — the third layer
`daemon/src/transport/reality.rs` doesn't even terminate TLS on probed connections. It just bridges the underlying TCP stream to the real upstream website, so the prober sees a perfectly normal, perfectly real TLS handshake with a perfectly real certificate. There is no way to distinguish a probed Reality server from the real upstream website.

---

## 7. Anti-Traffic-Analysis Defenses

Source: `daemon/src/obfuscation/{traffic_shaper, timing_jitter, packet_size_normalizer}.rs` + `daemon/src/telemetry/dp_noise.rs`.

Even when the transport is unblocked, statistical analysis of packet sizes / timings can identify VPN traffic.

### 7.1 `traffic_shaper`
Matches the active bandwidth profile to one of:
- **Video streaming**: constant high bandwidth (~5 Mbps), 1500-byte packets
- **Browsing**: bursty with idle periods (~50 kbps avg, mixed packet sizes)
- **Chat**: low, intermittent traffic (~5 kbps avg, small packets)

The profile is selected based on actual usage statistics from the last 60 seconds.

### 7.2 `timing_jitter`
Adds uniformly-distributed 0–50 ms inter-packet jitter. Defeats statistical timing analysis while preserving enough timing information for QUIC ACK pacing.

### 7.3 `packet_size_normalizer`
Pads packets to the nearest of {64, 128, 256, 512, 1024, 1500} bytes. This collapses the per-flow packet-size histogram into 6 spikes — which is also what real HTTPS browsing looks like — defeating entropy analysis.

### 7.4 `dp_noise` (differential privacy)
Adds Laplace-distributed noise to telemetry reported to the dashboard. The aggregator's per-flow statistics become ε-differentially-private with ε = 1.0, so the dashboard's graphs are statistically indistinguishable from a hypothetical "average user's" graphs even if the operator's data is subpoenaed.

---

## 8. Steganography Layer

### 8.1 Calculator disguise
Source: `flutter_app/lib/screens/calculator_screen.dart`.

The app's launcher icon and entry-point UI render as a fully-functional Persian calculator. The calculator works — you can do `2 + 2 = 4` — so a casual observer sees a calculator, not a VPN.

### 8.2 5-tap wipe
The hidden gesture is a 5-tap sequence on the `=` button in the pattern `1 + 2 = = = = =`. This wipes:
- All on-disk license storage (`LicenseStore::wipe()`)
- The ephemeral identity (keypair + cert + last-known server IP)
- The persisted high-water-mark (forces anti-rollback to trigger on next boot)
- The `configs/free-servers.json` cached copy

After the wipe, the app's launcher icon and entry-point UI continue to render as the calculator — there's no visible change. The user has to know to re-install or to enter the activation code to bring the VPN UI back.

The reverse gesture (`1 + 2 = = = = =` again on the calculator, with the license-activation field visible) re-reveals the VPN UI.

---

## 9. Adversarial Traffic GAN

Source: `daemon/src/ai/adversarial_traffic.rs` + `models/adversarial_traffic_gan.onnx` + `ai-models/train/adversarial_traffic_gan.py`.

The committed GAN generator produces 64×64-byte traffic micro-bursts (4 KiB total) that **maximize the loss of the DPI classifier** when interleaved into the live traffic stream. The GAN was trained adversarially against a frozen copy of `dpi_classifier.onnx`; the resulting micro-bursts are statistically indistinguishable from real HTTPS browsing traffic (per the AUROC test in `ai-models/tests/test_adversarial_traffic_gan.py`).

The adversarial bursts are interleaved into the live traffic stream when `dpi_classifier`'s confidence in the `clean` class drops below 0.85 — i.e. when the DPI classifier starts to suspect VPN traffic. The bursts "wash out" the suspicion by re-establishing a clean signal.

### 9.1 Trigger condition
```rust
let cls = dpi_classifier.predict(&features)?;
let clean_confidence = cls[0]; // softmax over 6 classes
if clean_confidence < 0.85 {
    let burst = adversarial_traffic.generate(&mut rng)?;
    traffic_shaper.inject_burst(burst)?;
}
```

### 9.2 Generation cost
The GAN inference runs on-device in <2 ms per burst (the model is tiny — 64×64×1 generator). Cost is negligible vs the 5 ms packet-RTT floor.

---

## 10. Summary

The AI subsystem's role is **not** to replace the classical evasion techniques in `ANTI-DPI-TECHNIQUES.md` (Reality, TLS camouflage, padding, etc.) — those still do the heavy lifting. The AI subsystem's role is to **pick the right technique for the current condition** in real time:

- The `dpi_classifier` detects which DPI technique is currently being applied.
- The `traffic_predictor` forecasts whether the current core will continue to perform.
- The `ucb_bandit` selects the best paid-tier core given historical + forecasted rewards.
- The `rl_transport_selector` selects the best transport given the current DPI class + ISP + time-of-day.
- The `adversarial_traffic` GAN injects camouflage bursts when the DPI classifier's suspicion rises.
- The 8-step resilience chain takes over when all the AI's choices fail.

The result: ≥95% bypass success rate against Iran's DPI, measured by `tests/censorship-simulation/test_bypass_effectiveness.py`.

---

## 11. References

- `docs/ARCHITECTURE.md` §9–§10 — high-level AI subsystem overview
- `docs/ANTI-DPI-TECHNIQUES.md` — classical (non-AI) evasion
- `docs/ARCHITECTURE.md` §11 — resilience chain
- `ai-models/TRAINING.md` — how to retrain the models
- `ai-models/train/feature_engineering.py` — feature definitions (Python mirror of §2.1)
- `tests/censorship-simulation/iran_dpi_simulator.py` — Iran-DPI simulator used for model training + bypass testing
- `configs/isp-profiles.json` — per-ISP throttling/blocked-port matrices
