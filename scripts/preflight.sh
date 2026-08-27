#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# scripts/preflight.sh — UnifiedShield Release Preflight (§5.1, GEMINI-STEP-8)
# Verifies all required directories and tools exist before starting a release.
# ══════════════════════════════════════════════════════════════════════════════
set -x; set -e; set -u

# Resolve project root (parent of scripts/)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="9.0.0-enterprise"

echo "==[ Preflight: UnifiedShield Enterprise v${VERSION} ]=="

# ── Required directories ──────────────────────────────────────────────────────
REQUIRED_DIRS=(
  daemon
  flutter_app
  dashboard
  extensions/chrome
  extensions/firefox
  workers
  ai-models
  openwrt
  zig-openwrt
  go-bridge
  wasm-obfuscator
  core/micafp-transport-core
  configs
  tests
  docs
  .github/workflows
)

MISSING_DIRS=()
for d in "${REQUIRED_DIRS[@]}"; do
  if [ ! -d "$d" ]; then
    echo "::error::missing directory: $d" >&2
    MISSING_DIRS+=("$d")
  fi
done

if [ ${#MISSING_DIRS[@]} -gt 0 ]; then
  echo "FATAL: ${#MISSING_DIRS[@]} required directories missing: ${MISSING_DIRS[*]}" >&2
  exit 1
fi

# ── Required tools ────────────────────────────────────────────────────────────
REQUIRED_TOOLS=(
  cargo
  flutter
  node
  npm
  python3
  jq
  curl
)

MISSING_TOOLS=()
for t in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "::error::missing tool: $t" >&2
    MISSING_TOOLS+=("$t")
  fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
  echo "FATAL: ${#MISSING_TOOLS[@]} required tools missing: ${MISSING_TOOLS[*]}" >&2
  exit 1
fi

# ── Cargo workspace validity ──────────────────────────────────────────────────
echo "==[ Verifying Cargo workspace ]=="
cargo metadata --no-deps --format-version 1 >/dev/null

# ── Display tool versions ─────────────────────────────────────────────────────
echo "==[ Tool versions ]=="
cargo    --version
flutter  --version 2>/dev/null | head -1
node     --version
npm      --version
python3  --version
jq       --version
curl     --version | head -1

# ── Prepare release output root ───────────────────────────────────────────────
mkdir -p "release/${VERSION}"

echo "==[ preflight OK ]=="
