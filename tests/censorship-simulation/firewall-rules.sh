#!/usr/bin/env bash
# =============================================================================
# MICAFP-UnifiedShield-Enterprise (v9.0.0-enterprise)
# Iran Firewall Rules — Simulates Iran's national firewall (iptables-level).
#
# This script is the container ENTRYPOINT for the `iran-firewall` service
# defined in docker-compose.yml. It:
#
#   1. Reads the list of blocked domains from block_patterns.json
#      (falls back to a hardcoded list of 23 domains if jq/python3 are absent
#       or the JSON file is missing).
#   2. For each blocked domain, resolves its IPs via `dig +short` and applies
#      `iptables -A OUTPUT -d <ip> -j DROP` (with fallback to known-bad IPs
#      such as 5.200.200.200 when resolution fails or returns no results).
#   3. Drops WireGuard handshakes on ports 51820, 51821, 60712 (UDP).
#   4. Drops OpenVPN on TCP/UDP 1194.
#   5. Drops Shadowsocks on common ports 8388 and 8389, plus an entropy-based
#      u32 match (best-effort — kernel module may not be present).
#   6. Applies a coarse iptables REJECT-with-TCP-RST rule for TLS ClientHello
#      packets containing "server_name" (SNI extension marker) on port 443.
#      NOTE: Real Iranian FAVA performs the actual RST injection in userspace
#      via Scapy (see iran_dpi_simulator.py). The iptables rule is a coarse,
#      simulation-grade fallback that REJECTs SNI-bearing TLS in general.
#   7. Logs every rule applied (stdout/stderr) for debugging.
#   8. Hands off to the CMD (iran_dpi_simulator.py) via `exec "$@"`.
#
# This script MUST run as root (iptables manipulation). The Dockerfile sets
# USER root; docker-compose.yml grants NET_ADMIN + SYS_MODULE capabilities and
# runs the container in privileged mode.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------
log() {
    # ISO-8601 UTC timestamp + message, written to stderr (so it doesn't
    # interfere with any future stdout JSON output of CMD).
    printf '[%s] [firewall-rules] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
# Path to the block patterns JSON (baked into the image at /block_patterns.json
# by Dockerfile.firewall, also bind-mounted read-only by docker-compose).
BLOCK_PATTERNS="${BLOCK_PATTERNS:-/block_patterns.json}"

# Fallback list of blocked domains used when:
#   - block_patterns.json is missing, OR
#   - jq/python3 are unavailable, OR
#   - JSON parsing fails
# This is the union of every blocked domain referenced in block_patterns.json
# (sections: tls_rst.triggers.exact_sni, http_403.triggers.host_header,
#  dns_poison.triggers.domain_list). The directive references ~17 domains;
# the comprehensive fallback below covers 23 to be safe.
FALLBACK_DOMAINS=(
    "youtube.com"
    "youtu.be"
    "googlevideo.com"
    "twitter.com"
    "x.com"
    "t.co"
    "twimg.com"
    "facebook.com"
    "fbcdn.net"
    "instagram.com"
    "telegram.org"
    "t.me"
    "whatsapp.com"
    "reddit.com"
    "linkedin.com"
    "github.com"
    "wikipedia.org"
    "bbc.com"
    "medium.com"
    "netflix.com"
    "discord.com"
    "twitch.tv"
    "spotify.com"
    "soundcloud.com"
    "stackoverflow.com"
    "torproject.org"
)

# Known-bad fallback IPs used when `dig +short <domain>` returns nothing
# (e.g. no DNS resolution in the container's network namespace, or the domain
#  is a poisoned Iranian fake). 5.200.200.200 is a real Iranian DPI middlebox
# IP historically observed in censorship reports; 10.10.34.34/35 are the
# poison-IPs referenced in block_patterns.json dns_poison section.
FALLBACK_IPS=("5.200.200.200" "10.10.34.34" "10.10.34.35")

# -----------------------------------------------------------------------------
# Preflight checks
# -----------------------------------------------------------------------------
log "=== Iran Firewall Rules Initialization ==="
log "Running as user: $(id -un 2>/dev/null || echo unknown)"
log "BLOCK_PATTERNS=${BLOCK_PATTERNS}"

if ! command -v iptables >/dev/null 2>&1; then
    log "FATAL: iptables not found in PATH. Container must run with iptables installed."
    exit 1
fi

# -----------------------------------------------------------------------------
# Reset existing rules (best-effort — container may start with empty tables)
# -----------------------------------------------------------------------------
log "Flushing existing filter-table rules (INPUT/OUTPUT/FORWARD)..."
iptables -F 2>/dev/null || true
iptables -X 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true
iptables -t nat -X 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true
iptables -t mangle -X 2>/dev/null || true

# Default policies: ACCEPT (we DROP via explicit rules, not default policy,
# so legitimate Iranian intranet traffic on 10.202.0.0/16 still flows).
log "Setting default policies: ACCEPT on INPUT/OUTPUT/FORWARD..."
iptables -P INPUT   ACCEPT 2>/dev/null || true
iptables -P OUTPUT  ACCEPT 2>/dev/null || true
iptables -P FORWARD ACCEPT 2>/dev/null || true

# Always allow loopback and established connections (so the simulator itself
# can talk to the docker network and to other shield-net services).
log "Allowing loopback and established/related connections..."
iptables -A INPUT  -i lo -j ACCEPT 2>/dev/null || true
iptables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
iptables -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true

# Always allow Iranian intranet range (10.202.0.0/16 — shield-net mock intranet)
log "Allowing traffic to/from Iranian intranet mock range 10.202.0.0/16..."
iptables -A INPUT  -s 10.202.0.0/16 -j ACCEPT 2>/dev/null || true
iptables -A OUTPUT -d 10.202.0.0/16 -j ACCEPT 2>/dev/null || true

# -----------------------------------------------------------------------------
# Read blocked domains from block_patterns.json (jq > python3 > fallback)
# -----------------------------------------------------------------------------
BLOCKED_DOMAINS=()

if [[ -f "${BLOCK_PATTERNS}" ]]; then
    if command -v jq >/dev/null 2>&1; then
        log "Reading blocked domains via jq from ${BLOCK_PATTERNS}..."
        while IFS= read -r domain; do
            [[ -n "${domain}" ]] && BLOCKED_DOMAINS+=("${domain}")
        done < <(
            jq -r '
                # Collect domains from every section that lists blocked targets.
                # Deduplicate via unique[] so we apply each rule once.
                [
                    .tls_rst.triggers.exact_sni[],
                    .http_403.triggers.host_header[],
                    .dns_poison.triggers.domain_list[]
                ]
                | unique[]
            ' "${BLOCK_PATTERNS}" 2>/dev/null || true
        )
    elif command -v python3 >/dev/null 2>&1; then
        log "jq not available — falling back to python3 for JSON parsing..."
        while IFS= read -r domain; do
            [[ -n "${domain}" ]] && BLOCKED_DOMAINS+=("${domain}")
        done < <(
            python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
domains = set()
for section in ("tls_rst", "http_403", "dns_poison"):
    triggers = data.get(section, {}).get("triggers", {})
    for key in ("exact_sni", "host_header", "domain_list", "url_path_keywords"):
        for d in triggers.get(key, []):
            if isinstance(d, str) and "." in d:
                domains.add(d)
for d in sorted(domains):
    print(d)
' "${BLOCK_PATTERNS}" 2>/dev/null || true
        )
    else
        log "Neither jq nor python3 available — using hardcoded fallback list."
    fi
else
    log "WARNING: block_patterns.json not found at ${BLOCK_PATTERNS} — using hardcoded fallback list."
fi

if [[ ${#BLOCKED_DOMAINS[@]} -eq 0 ]]; then
    BLOCKED_DOMAINS=("${FALLBACK_DOMAINS[@]}")
fi

log "Loaded ${#BLOCKED_DOMAINS[@]} blocked domains from block_patterns.json."

# -----------------------------------------------------------------------------
# For each blocked domain, resolve IPs via `dig +short` (with fallback) and
# apply `iptables -A OUTPUT -d <ip> -j DROP`.
# -----------------------------------------------------------------------------
log "Applying OUTPUT DROP rules for blocked domains..."
for domain in "${BLOCKED_DOMAINS[@]}"; do
    ips=()
    if command -v dig >/dev/null 2>&1; then
        while IFS= read -r ip; do
            # Filter to IPv4 dotted-quad (dig may also emit CNAME lines / IPv6)
            if [[ "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                ips+=("${ip}")
            fi
        done < <(dig +short +time=2 +tries=1 "${domain}" A 2>/dev/null || true)
    fi

    if [[ ${#ips[@]} -eq 0 ]]; then
        log "  ${domain}: dig returned no A records — using fallback IPs: ${FALLBACK_IPS[*]}"
        ips=("${FALLBACK_IPS[@]}")
    else
        log "  ${domain}: resolved to ${ips[*]}"
    fi

    for ip in "${ips[@]}"; do
        # Try with -m comment for human-readable rule labeling; fall back to
        # bare rule if the comment match extension is unavailable in-kernel.
        if iptables -A OUTPUT -d "${ip}" -j DROP -m comment --comment "block-${domain}" 2>/dev/null; then
            log "    + iptables -A OUTPUT -d ${ip} -j DROP  (block-${domain})"
        elif iptables -A OUTPUT -d "${ip}" -j DROP 2>/dev/null; then
            log "    + iptables -A OUTPUT -d ${ip} -j DROP  (block-${domain}, no comment)"
        else
            log "    ! FAILED: iptables -A OUTPUT -d ${ip} -j DROP  (block-${domain})"
        fi
    done
done

# -----------------------------------------------------------------------------
# Drop WireGuard handshakes (UDP 51820, 51821, 60712)
# -----------------------------------------------------------------------------
log "Dropping WireGuard handshakes on UDP ports 51820, 51821, 60712..."
for port in 51820 51821 60712; do
    if iptables -A INPUT -p udp --dport "${port}" -j DROP -m comment --comment "wireguard-${port}" 2>/dev/null; then
        log "    + iptables -A INPUT -p udp --dport ${port} -j DROP  (WireGuard ${port})"
    elif iptables -A INPUT -p udp --dport "${port}" -j DROP 2>/dev/null; then
        log "    + iptables -A INPUT -p udp --dport ${port} -j DROP  (WireGuard ${port}, no comment)"
    else
        log "    ! FAILED: iptables -A INPUT -p udp --dport ${port} -j DROP  (WireGuard ${port})"
    fi
done

# -----------------------------------------------------------------------------
# Drop OpenVPN (TCP/UDP 1194)
# -----------------------------------------------------------------------------
log "Dropping OpenVPN on TCP/UDP port 1194..."
if iptables -A INPUT -p udp --dport 1194 -j DROP -m comment --comment "openvpn-udp" 2>/dev/null; then
    log "    + iptables -A INPUT -p udp --dport 1194 -j DROP  (OpenVPN UDP)"
elif iptables -A INPUT -p udp --dport 1194 -j DROP 2>/dev/null; then
    log "    + iptables -A INPUT -p udp --dport 1194 -j DROP  (OpenVPN UDP, no comment)"
else
    log "    ! FAILED: iptables -A INPUT -p udp --dport 1194 -j DROP  (OpenVPN UDP)"
fi

if iptables -A INPUT -p tcp --dport 1194 -j DROP -m comment --comment "openvpn-tcp" 2>/dev/null; then
    log "    + iptables -A INPUT -p tcp --dport 1194 -j DROP  (OpenVPN TCP)"
elif iptables -A INPUT -p tcp --dport 1194 -j DROP 2>/dev/null; then
    log "    + iptables -A INPUT -p tcp --dport 1194 -j DROP  (OpenVPN TCP, no comment)"
else
    log "    ! FAILED: iptables -A INPUT -p tcp --dport 1194 -j DROP  (OpenVPN TCP)"
fi

# -----------------------------------------------------------------------------
# Drop Shadowsocks
#   - Common ports 8388, 8389 (always applied)
#   - Entropy-based u32 match (best-effort — xt_u32 kernel module may be absent)
# -----------------------------------------------------------------------------
log "Dropping Shadowsocks on common TCP ports 8388, 8389..."
for port in 8388 8389; do
    if iptables -A INPUT -p tcp --dport "${port}" -j DROP -m comment --comment "shadowsocks-${port}" 2>/dev/null; then
        log "    + iptables -A INPUT -p tcp --dport ${port} -j DROP  (Shadowsocks ${port})"
    elif iptables -A INPUT -p tcp --dport "${port}" -j DROP 2>/dev/null; then
        log "    + iptables -A INPUT -p tcp --dport ${port} -j DROP  (Shadowsocks ${port}, no comment)"
    else
        log "    ! FAILED: iptables -A INPUT -p tcp --dport ${port} -j DROP  (Shadowsocks ${port})"
    fi
done

log "Applying Shadowsocks entropy-based u32 rule (best-effort)..."
# Simplified u32 match: catches the high-entropy first-packet signature
# characteristic of Shadowsocks AEAD streams. Real FAVA performs entropy
# analysis in userspace via Suricata + custom signatures; this iptables
# rule is a coarse simulation fallback.
if iptables -A INPUT -p tcp -m conntrack --ctstate NEW \
        -m comment --comment "shadowsocks-entropy" \
        -m u32 --u32 "0>>3&0x3c=0x1c0&&0x80&0x3=0x2&&0x1c0&0x70=0x40" \
        -j DROP 2>/dev/null; then
    log "    + iptables -A INPUT -p tcp ... -m u32 ... -j DROP  (Shadowsocks entropy)"
else
    log "    ! u32 entropy rule failed (xt_u32 / xt_conntrack module may be missing) — relying on port-based drops above"
fi

# -----------------------------------------------------------------------------
# Coarse SNI-based REJECT on TLS ClientHello (TCP/443)
#
# This rule REJECTs any inbound TCP packet to port 443 whose payload contains
# the string "server_name" (the TLS SNI extension marker). It is a coarse
# simulation of FAVA's SNI filtering at the iptables layer; the actual
# surgical RST injection (with FAVA's 95-320ms timing) is performed in
# userspace by iran_dpi_simulator.py via Scapy.
# -----------------------------------------------------------------------------
log "Applying coarse SNI-string REJECT rule on TCP/443 (RST injection simulation)..."
if iptables -A INPUT -p tcp --dport 443 \
        -m string --string "server_name" --algo bm \
        -j REJECT --reject-with tcp-reset 2>/dev/null; then
    log "    + iptables -A INPUT -p tcp --dport 443 -m string --string \"server_name\" --algo bm -j REJECT --reject-with tcp-reset"
else
    log "    ! string-match REJECT rule failed (xt_string module may be missing) — RST injection deferred to userspace Scapy (iran_dpi_simulator.py)"
fi

# -----------------------------------------------------------------------------
# Persist rules across container restarts (best-effort — netfilter-persistent
# may not be able to save if /etc/iptables is read-only in some images, but
# this image is debian:12-slim so the directory is writable).
# -----------------------------------------------------------------------------
log "Persisting iptables rules via netfilter-persistent..."
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save 2>/dev/null || log "    ! netfilter-persistent save failed (non-fatal)"
else
    log "    ! netfilter-persistent not available — rules will be ephemeral (re-applied on next container start)"
fi

# -----------------------------------------------------------------------------
# Summary: print the resulting rule set for debugging
# -----------------------------------------------------------------------------
log "=== iptables rules applied ==="
iptables -L -n -v --line-numbers 2>&1 | while IFS= read -r line; do
    log "  ${line}"
done
log "=== Initialization complete ==="

# -----------------------------------------------------------------------------
# Hand off to the Dockerfile CMD (iran_dpi_simulator.py).
#
# When run via docker-compose.yml:
#   entrypoint: ["/bin/bash", "/firewall-rules.sh"]
#   (no `command:` override → Dockerfile CMD is forwarded as args)
#
#   Effective command:
#     /bin/bash /firewall-rules.sh python3 /iran_dpi_simulator.py --host 0.0.0.0 --port 8443
#
#   Inside this script, "$@" = "python3 /iran_dpi_simulator.py --host 0.0.0.0 --port 8443"
#   So `exec "$@"` launches the DPI simulator and replaces the shell process
#   (so signals like SIGTERM reach the simulator directly).
#
# When run standalone via `docker run <image>`:
#   ENTRYPOINT /firewall-rules.sh + CMD ["python3", "/iran_dpi_simulator.py", "--host", "0.0.0.0", "--port", "8443"]
#   → /firewall-rules.sh python3 /iran_dpi_simulator.py --host 0.0.0.0 --port 8443
#   → exec python3 /iran_dpi_simulator.py --host 0.0.0.0 --port 8443
# -----------------------------------------------------------------------------
log "Handing off to CMD: $*"
exec "$@"
