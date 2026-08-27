#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# MICAFP-UnifiedShield Enterprise v9.0.0-enterprise — CDN Endpoint Health Checker
# Automatically validates all CDN endpoints across every provider in the config.
#
# The configs/cdn-endpoints.json file has a NESTED shape:
#   {
#     "metadata": {...},
#     "alibaba_cdn": { ... relay_function_urls: { ... } ... },
#     "tencent_cdn": { ... relay_function_urls: { ... } ... },
#     ...
#     "endpoints": [ { provider, sni_domain, front_domains[], ... } ]
#   }
#
# This script iterates TOP-LEVEL KEYS (provider names) and for each
# provider object collects every URL it can find (from `relay_function_urls`
# values and `front_domains[]`). It then also iterates the top-level
# `endpoints[]` array and probes each entry's `front_domains[]` and
# `sni_domain`. This makes the script robust against both shapes.
# ══════════════════════════════════════════════════════════════

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/configs/cdn-endpoints.json"
RESULTS_FILE="${PROJECT_ROOT}/configs/endpoint-health.json"

log_info()  { echo -e "${GREEN}[CHECK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check if jq is available
if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required. Install: apt install jq / brew install jq"
    exit 1
fi

if [ ! -f "${CONFIG_FILE}" ]; then
    log_error "Config file not found: ${CONFIG_FILE}"
    exit 1
fi

log_info "Checking CDN endpoint health from ${CONFIG_FILE}..."

# ── Collect URLs from every provider in the nested JSON shape ─────────────
# Step 1: iterate top-level object keys (provider names) and pull all URL-like
#         strings from each provider's `relay_function_urls` values and
#         `front_domains[]` array (if present).
# Step 2: iterate the top-level `endpoints[]` array entries and pull each
#         entry's `sni_domain` and `front_domains[]`.

declare -a URLS=()
declare -A URL_SEEN=()

add_url() {
    local url="$1"
    # Skip empty / null / obvious non-URLs
    [ -z "${url}" ] && return
    [ "${url}" = "null" ] && return
    [[ "${url}" != http* ]] && [[ "${url}" != *.* ]] && return
    # Skip pure IP CIDRs like 47.246.0.0/16
    [[ "${url}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]] && return
    if [ -z "${URL_SEEN[${url}]:-}" ]; then
        URL_SEEN[${url}]=1
        URLS+=("${url}")
    fi
}

log_step "Iterating per-provider objects (top-level keys)..."
# Get all top-level keys; skip 'metadata', 'version', 'endpoints' (handled separately)
TOP_KEYS=$(jq -r 'keys[]' "${CONFIG_FILE}")
for key in ${TOP_KEYS}; do
    case "${key}" in
        metadata|version|endpoints) continue ;;
    esac

    # relay_function_urls is an object whose values are URL strings
    RELAY_URLS=$(jq -r --arg k "${key}" '.[$k].relay_function_urls // {} | to_entries[] | .value // empty' "${CONFIG_FILE}" 2>/dev/null || true)
    for url in ${RELAY_URLS}; do
        add_url "${url}"
    done

    # front_domains is an array of domain strings
    FRONT_DOMAINS=$(jq -r --arg k "${key}" '.[$k].front_domains // [] | .[]' "${CONFIG_FILE}" 2>/dev/null || true)
    for url in ${FRONT_DOMAINS}; do
        add_url "${url}"
    done

    # Per-provider `endpoints[]` array (defensive: handles directive's expected shape)
    PER_PROVIDER_ENDPOINTS=$(jq -r --arg k "${key}" '.[$k].endpoints // [] | .[].url // empty' "${CONFIG_FILE}" 2>/dev/null || true)
    for url in ${PER_PROVIDER_ENDPOINTS}; do
        add_url "${url}"
    done
done

log_step "Iterating top-level endpoints[] array..."
# Top-level endpoints[] entries use sni_domain + front_domains[]
TOP_ENDPOINTS_SNI=$(jq -r '.endpoints // [] | .[].sni_domain // empty' "${CONFIG_FILE}" 2>/dev/null || true)
for url in ${TOP_ENDPOINTS_SNI}; do
    add_url "${url}"
done

TOP_ENDPOINTS_FRONT=$(jq -r '.endpoints // [] | .[].front_domains // [] | .[]' "${CONFIG_FILE}" 2>/dev/null || true)
for url in ${TOP_ENDPOINTS_FRONT}; do
    add_url "${url}"
done

# Also handle the legacy top-level shape `.endpoints[].url` defensively
TOP_ENDPOINTS_URLS=$(jq -r '.endpoints // [] | .[].url // empty' "${CONFIG_FILE}" 2>/dev/null || true)
for url in ${TOP_ENDPOINTS_URLS}; do
    add_url "${url}"
done

if [ ${#URLS[@]} -eq 0 ]; then
    log_error "No URLs found in ${CONFIG_FILE}. Aborting."
    exit 1
fi

log_info "Discovered ${#URLS[@]} unique endpoint URLs across all providers."

# ── Probe each URL ─────────────────────────────────────────────────────────
HEALTHY=()
UNHEALTHY=()
TOTAL=0
HEALTHY_COUNT=0

probe_url() {
    local target="$1"
    # Normalize: protocol-relative or bare domain → https://
    local url="${target}"
    [[ "${url}" != http* ]] && [[ "${url}" == *.* ]] && url="https://${url}"

    TOTAL=$((TOTAL + 1))

    local START HTTP_CODE END LATENCY
    START=$(date +%s%N)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 5 \
        --max-time 10 \
        "${url}/health" 2>/dev/null || echo "000")
    END=$(date +%s%N)
    LATENCY=$(( (END - START) / 1000000 ))

    if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "204" ]; then
        HEALTHY+=("${url}")
        HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
        log_info "✅ ${url} — ${LATENCY}ms (HTTP ${HTTP_CODE})"
    else
        UNHEALTHY+=("${url}")
        log_error "❌ ${url} — ${LATENCY}ms (HTTP ${HTTP_CODE})"
    fi
}

for target in "${URLS[@]}"; do
    probe_url "${target}"
done

# ── Generate health report ─────────────────────────────────────────────────
log_info "═════════════════════════════════════════════════════════"
log_info "Health check complete: ${HEALTHY_COUNT}/${TOTAL} endpoints healthy"

# Build JSON arrays for healthy + unhealthy (properly escaped via jq for safety)
HEALTHY_JSON=$(printf '%s\n' "${HEALTHY[@]}"   | jq -R . | jq -s . 2>/dev/null || echo "[]")
UNHEALTHY_JSON=$(printf '%s\n' "${UNHEALTHY[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")

if [ "${TOTAL}" -gt 0 ]; then
    HEALTH_PCT=$(awk -v h="${HEALTHY_COUNT}" -v t="${TOTAL}" 'BEGIN { printf "%.1f", (h * 100.0) / t }')
else
    HEALTH_PCT="0.0"
fi

cat > "${RESULTS_FILE}" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "config_file": "${CONFIG_FILE}",
  "total_endpoints": ${TOTAL},
  "healthy_endpoints": ${HEALTHY_COUNT},
  "unhealthy_endpoints": $((TOTAL - HEALTHY_COUNT)),
  "health_percentage": ${HEALTH_PCT},
  "healthy": ${HEALTHY_JSON},
  "unhealthy": ${UNHEALTHY_JSON}
}
EOF

log_info "Results saved to ${RESULTS_FILE}"

# Exit with error if less than 50% healthy
if [ "${HEALTHY_COUNT}" -lt "$((TOTAL / 2))" ]; then
    log_error "Less than 50% of endpoints are healthy!"
    exit 1
fi
