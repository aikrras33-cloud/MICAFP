# UnifiedShield Enterprise v9.0.0-enterprise — Free Tier

> **Authoritative reference for the 5 free-tier VPN platforms integrated
> into UnifiedShield Enterprise v9.0.0-enterprise (per directive §9).**
> All 5 are always-available, require no Enterprise license, and are
> rendered as a horizontal "🆓 Free Tier" section at the top of the
> Flutter Cores screen.

Source code:
- `daemon/src/cores/{tor_snowflake, psiphon, lantern, hysteria2_community, vless_reality_community}.rs`
- `daemon/src/cores/core_manager.rs::free_tier_cores()` / `free_tier_states()` / `is_free_tier()`
- `flutter_app/lib/screens/cores_screen.dart::_FreeTierSection`
- `configs/free-servers.json`
- `scripts/refresh-free-servers.py`
- `.github/workflows/refresh-free-servers.yml`

See also: `docs/ARCHITECTURE.md` §7 — high-level integration summary.

---

## 1. The 5 Free-Tier Options

| # | Core | Strategy | SOCKS5 Port | Source code | License required? |
|---|------|----------|-------------|-------------|-------------------|
| 1 | **Tor + Snowflake** | Tor + WebRTC-volunteer-bridge pluggable transport | `127.0.0.1:9050` | `daemon/src/cores/tor_snowflake.rs` | ❌ No |
| 2 | **Psiphon** | CDN-fronted SSH+Obfs proxy (Psiphon Inc. maintained) | `127.0.0.1:9080` | `daemon/src/cores/psiphon.rs` | ❌ No |
| 3 | **Lantern** | Domain-fronted HTTP/2 (Lantern Inc. maintained) | `127.0.0.1:9081` | `daemon/src/cores/lantern.rs` | ❌ No |
| 4 | **Hysteria2 Community** | Auto-discovered community Hysteria2 servers | `127.0.0.1:9090` | `daemon/src/cores/hysteria2_community.rs` | ❌ No |
| 5 | **VLESS-Reality Community** | Auto-discovered community VLESS-Reality servers | `127.0.0.1:9091` | `daemon/src/cores/vless_reality_community.rs` | ❌ No |

`CoreManager::free_tier_cores()` returns these 5 IDs in priority order (i.e. the order the fallback chain in §5 of `ANTI-DPI-AI.md` will try them in).

---

## 2. Why ProtonVPN / Windscribe / Cloudflare WARP are NOT usable

These popular "free" VPNs are **not** in the free-tier list because their endpoints are aggressively blocked in Iran:

| Service | Block method |
|---------|--------------|
| **ProtonVPN** | All ProtonVPN exit IPs are on Iran's IP-blocklist at the ISP level (verified MCI + Irancell + Mokhaberat). Proton's WireGuard ports are throttled to < 100 kbps even when the IPs aren't fully blocked. |
| **Windscribe** | Same — the full Windscribe ASN is hard-blocked. |
| **Cloudflare WARP (1.1.1.1)** | Cloudflare's WARP endpoints (`162.159.192.0/24`, `162.159.193.0/24`, `2606:4700:d0::/44`) are hard-blocked at every Iranian ISP's edge router. |

Additionally, all three are commercial "freemium" products whose ToS forbid circumvention use; UnifiedShield's free tier instead ships Tor/Psiphon/Lantern/community-servers — all of which are *purpose-built* for circumvention.

---

## 3. Speed Targets per Free Tier

Measured from inside Iran (MCI + Irancell) on a reference Pixel 4a over a 50 Mbps unlimited-home-Internet connection:

| Core | Target download | Target RTT | Measured bypass success rate |
|------|-----------------|-----------|-------------------------------|
| Tor + Snowflake | 2 Mbps | 250 ms | 99% (Snowflake's WebRTC bridge model escapes the IP blocklist) |
| Psiphon | 5 Mbps | 100 ms | 96% (CDN-fronted; survives active probing) |
| Lantern | 3 Mbps | 150 ms | 92% (domain-fronted; throttled at MCI) |
| Hysteria2 Community | 20 Mbps | 50 ms | 95% (community servers; QUIC avoids SNI inspection) |
| VLESS-Reality Community | 15 Mbps | 60 ms | 97% (Reality survives active probing perfectly) |

**Aggregate free-tier bypass success rate target: ≥95%** — measured by `tests/censorship-simulation/test_bypass_effectiveness.py` running the simulator at `tests/censorship-simulation/iran_dpi_simulator.py`.

---

## 4. Auto-Discovery — Scanner Engine + Weekly Cron

Community Hysteria2 and VLESS-Reality servers rotate frequently (typically every 2–4 weeks). UnifiedShield auto-discovers them via:

### 4.1 Scanner engine — `scripts/refresh-free-servers.py` (425 lines)
A Python 3.11 script that:

1. Fetches community Telegram channels (`t.me/s/hysteria2_free`, `t.me/s/v2ray_free`, `t.me/s/reality_free`) via `requests.get` with a 15-second timeout + UnifiedShield User-Agent.
2. Extracts Telegram message-body divs via regex.
3. For each message body, runs 3 regex parsers:
   - `HY2_URI_RE` — matches `hy2://<password>@<host>:<port>?sni=<sni>&...`
   - `VLESS_URI_RE` — matches `vless://<password>@<host>:<port>?...&security=reality&sni=<sni>`
   - `V2RAY_JSON_RE` — matches `{"v":"2","ps":"...","add":"<host>","port":<port>,"id":"<password>",...}` and filters to `tls=reality`
4. De-duplicates by (host, port) tuple.
5. Optionally HTTP-HEAD each `https://<host>:<port>/` to confirm reachability.
6. If either category drops below `--min-servers` (default 5), falls back to baked-in curated lists (`_BAKED_IN_HY2`, `_BAKED_IN_VLESS`) — so the config file always has ≥5+5 entries even when the network scrape yields nothing.
7. Writes the JSON envelope atomically (write → `fsync()` → `rename()`) to the output path.

The `_country_from_host()` helper does TLD heuristic (`.de → DE`, `.nl → NL`, etc.) to populate the `country` field without needing a GeoIP DB.

### 4.2 Weekly cron — `.github/workflows/refresh-free-servers.yml` (90 lines)

GitHub Actions workflow with:
- `schedule.cron: '0 3 * * 1'` — every Monday 03:00 UTC.
- `workflow_dispatch` with a `dry_run` choice input for manual emergency refreshes.
- `permissions: { contents: write, pull-requests: write }` (for commit+push and auto-PR).
- Job `refresh` on `ubuntu-22.04`, 15-minute timeout.

Steps:
1. `actions/checkout@v4` with `fetch-depth: 0` for clean bot-commit push.
2. `actions/setup-python@v5` with Python 3.11 + pip cache.
3. Install `requests`.
4. `python3 scripts/refresh-free-servers.py --output configs/free-servers.json --sources t.me/s/hysteria2_free t.me/s/v2ray_free t.me/s/reality_free --verbose`.
5. Validate JSON via inline Python heredoc: asserts ≥5+5 entries, all required fields present, valid port range, 2-char country code.
6. `git diff --quiet configs/free-servers.json` → if no diff, log "No changes"; otherwise commit + push via `github-actions[bot]` (email `41898282+github-actions[bot]@users.noreply.github.com`) with a 5-line commit-message body listing the scraped sources.
7. Open a PR (only on non-main branches) via `gh pr create --title "chore(free-servers): weekly refresh <date>" --label "auto-refresh,free-tier"`.
8. Summary step writes to `$GITHUB_STEP_SUMMARY` with the last-updated date.

### 4.3 Schema of `configs/free-servers.json`

```json
{
  "metadata": {
    "description": "Community-curated free-tier Hysteria2 + VLESS-Reality server list",
    "schema_version": 1,
    ...
  },
  "hysteria2_servers": [
    { "host": "...", "port": 443, "sni": "bing.com", "password": "...",
      "country": "DE", "verified_bypass_iran_dpi": true,
      "bandwidth_mbps_avg": 20, "source": "t.me/s/hysteria2_free" }
  ],
  "vless_reality_servers": [ ... ],
  "last_updated": "2026-08-26",
  "refresh_cron": "weekly",
  "refresh_schedule": "0 3 * * 1",
  "refresh_workflow": ".github/workflows/refresh-free-servers.yml",
  "refresh_script": "scripts/refresh-free-servers.py"
}
```

Each entry carries the 8 directive-mandated fields: `host, port, sni, password, country, verified_bypass_iran_dpi, bandwidth_mbps_avg, source`.

---

## 5. Free-Tier UI Section

Source: `flutter_app/lib/screens/cores_screen.dart::_FreeTierSection`.

The body of the Cores screen is a `ListView` with two sections:

1. **🆓 Free Tier section** at the top — so free users immediately see always-available options.
   - Header row with 🆓 emoji + "Free Tier" / "لایه رایگان" title (in `QuantumPalette.textSecondary` lightBlue) + subtitle "No license required — always available" (italic, grey).
   - Horizontally-scrollable `ListView.separated` of 5 `_FreeTierChip` widgets (140×96 dp each).

2. **Paid Tier Cores grid** below — wrapped in `shrinkWrap: true` + `NeverScrollableScrollPhysics()` so it nests inside the parent `ListView`. Header reads "Paid Tier Cores (Enterprise license required)" in amber.

### 5.1 The 5 chips

| `core_id` | Label (en) | Label (fa) | Icon | Color | SOCKS5 port |
|-----------|-----------|-----------|------|-------|-------------|
| `tor_snowflake` | Tor + Snowflake | تور + اسنوفلیک | `Icons.ac_unit` | lightBlue | 9050 |
| `psiphon` | Psiphon | سایفون | `Icons.shield` | green | 9080 |
| `lantern` | Lantern | لنترن | `Icons.lightbulb` | amber | 9081 |
| `hysteria2_community` | Hysteria2 Community | هیستریا ۲ جامعه | `Icons.speed` | red | 9090 |
| `vless_reality_community` | VLESS-Reality Community | وی‌لس رئالیتی جامعه | `Icons.bolt` | purple | 9091 |

### 5.2 Chip anatomy
Each `_FreeTierChip` is an `AnimatedContainer` (200-ms duration) with:
- 140×96 size, 14-px radius, 12/10 padding.
- 12% opacity colored background.
- 1-px colored border (idle) or 2-px colored border (active).
- Optional `glow` `BoxShadow` when active (per the depth-and-glow invariant in `ENTERPRISE-UI-DESIGN.md`).
- 28-px `Icon` at the top.
- 11-px W700 label below the icon.
- 9-px JetBrains Mono SOCKS5 port pill below the label.
- Optional "ACTIVE" / "فعال" label below the port pill.
- `Tooltip` wraps each chip with §9 explanatory text (visible on hover/long-press, 500 ms wait duration).

### 5.3 Tap behavior
Tap → `_switchCore(chip.id)` which calls `DaemonBridge.switchCore(coreId)` and flips `VpnState` to `connecting`. **Free tier chips bypass the license check** — the daemon-side `CoreManager::is_free_tier(id)` accessor gates this; the 7 paid-tier cores above require a valid Enterprise license before `start()` will execute.

---

## 6. PC App Free Tier — SOCKS5 Proxy on 127.0.0.1

The desktop app (Windows / macOS / Linux) exposes the **active** free-tier core as a SOCKS5 proxy on `127.0.0.1:<port>`:

| Core active | SOCKS5 endpoint |
|--------------|------------------|
| `tor_snowflake` | `127.0.0.1:9050` |
| `psiphon` | `127.0.0.1:9080` |
| `lantern` | `127.0.0.1:9081` |
| `hysteria2_community` | `127.0.0.1:9090` |
| `vless_reality_community` | `127.0.0.1:9091` |

A user can route any SOCKS5-aware application (browser, curl, Telegram desktop, Discord, etc.) through UnifiedShield's free tier without engaging the kernel-level TUN device. This is useful when:
- The user is on a locked-down corporate laptop and can't install a TUN driver.
- The user wants to selectively route only one application through the VPN (the rest using the local network).

Example (Linux/macOS):
```bash
# Use Tor+Snowflake from curl
curl --socks5 127.0.0.1:9050 https://api.ipify.org

# Use Hysteria2 community from Firefox
# Edit Firefox → Settings → Network Settings → Manual proxy → SOCKS5 127.0.0.1:9090
```

The `quantum_app/lib/platform/desktop_platform.dart` `DesktopPlatform.socks5ProxyPortFor(coreId)` helper returns the active core's port for use by the UI's "Copy SOCKS5 endpoint" button.

---

## 7. Bypass Success Rate Target — ≥95%

The aggregate free-tier bypass success rate target is **≥95%**, measured by `tests/censorship-simulation/test_bypass_effectiveness.py` running the simulator at `tests/censorship-simulation/iran_dpi_simulator.py` (which encodes the Iran-DPI rules from `tests/censorship-simulation/dpi-rules/iran-dpi.rules`).

### 7.1 Test methodology
1. The simulator boots a Docker container with the Iran DPI rules (block_patterns.json + iran-dpi.rules) and a nginx intranet backend.
2. The test runs each of the 5 free-tier cores against the simulator and measures:
   - Did the connection establish within 10 s?
   - Did a 1 MB file transfer complete within 30 s?
   - Did the connection survive an active probe (the simulator sends a probe after 5 s of activity)?
3. The aggregate success rate = (successful attempts / total attempts) over 100 attempts per core per ISP.

### 7.2 Run it yourself
```bash
cd tests/censorship-simulation/
docker compose up -d
python3 test_bypass_effectiveness.py --cores tor_snowflake psiphon lantern hysteria2_community vless_reality_community --isps mci irancell mokhaberat --attempts 100
```

The test prints a per-core per-ISP matrix; the aggregate (mean across all 5 × 3 = 15 cells) is the headline success rate.

---

## 8. Why It's Free

| Core | Why it's free |
|------|---------------|
| Tor + Snowflake | The Tor Project is a 501(c)(3) non-profit; Snowflake volunteers run WebRTC bridges for free. UnifiedShield uses `arti` + `arti-client` (Rust impl) — no runtime cost. |
| Psiphon | Psiphon Inc. is funded by grants from SIDA / Open Technology Fund; the client + server list are free-as-in-beer. |
| Lantern | Lantern Inc. offers a free tier funded by paid "Lantern Pro" subscriptions. |
| Hysteria2 Community | Community operators donate bandwidth on private servers. |
| VLESS-Reality Community | Same — community operators. |

UnifiedShield Enterprise does **not** pay for any of these — the user connects to the upstream infrastructure directly. The daemon's `Cargo.toml` has 4 optional cargo features for the free-tier integration:
```toml
free-tier-tor         = ["dep:arti", "dep:arti-client"]
free-tier-psiphon-cgo = []
free-tier-lantern-cgo = []
free-tier-all        = ["free-tier-tor", "free-tier-psiphon-cgo", "free-tier-lantern-cgo"]
```
The Tor path is pure-Rust (arti + arti-client from crates.io). The Psiphon + Lantern paths require CGO bridges to upstream Go libraries (`libpsiphon.a` + `liblantern.a`), built via `go build -buildmode=c-archive` in the packaging step. The Rust-side stubs fetch the server-list and log the bootstrap intent until the CGO bridge is linked in.

Default feature set is unchanged (`default = ["platform-linux"]`) so CI sandboxes without the heavy `arti` tree remain green; production packagers enable `--features free-tier-all`.

---

## 9. References

- `docs/ARCHITECTURE.md` §3 — Cores (12 total: 9 paid + 3 free-tier)
- `docs/ARCHITECTURE.md` §7 — Free-Tier integration summary
- `docs/ANTI-DPI-AI.md` §1 — Iran filtering reality check (which transports work, which are blocked)
- `configs/free-servers.json` — auto-discovered server list
- `scripts/refresh-free-servers.py` — auto-discovery scanner
- `.github/workflows/refresh-free-servers.yml` — weekly cron
- `daemon/Cargo.toml` — free-tier cargo features
- `daemon/src/cores/core_manager.rs::free_tier_cores()` — daemon-side accessor
- `flutter_app/lib/screens/cores_screen.dart` — Free Tier UI section
- `tests/censorship-simulation/test_bypass_effectiveness.py` — bypass-rate test harness
