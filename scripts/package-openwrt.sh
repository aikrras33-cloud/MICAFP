#!/bin/bash
# ══════════════════════════════════════════════════════════════
# MICAFP-UnifiedShield Enterprise v9.0.0-enterprise — OpenWrt Packaging
#
# Standardized Rust targets (no mips-unknown-linux-musl — that target
# is broken for musl libc + Rust; OpenWrt routers are MIPS-EL endian):
#   - mipsel-unknown-linux-musl   (most common MIPS routers)
#   - aarch64-unknown-linux-musl  (ARM routers: NanoPi, etc.)
#   - x86_64-unknown-linux-musl   (x86 routers + VMs)
# ══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DAEMON_DIR="${PROJECT_ROOT}/daemon"
RELEASE_DIR="${PROJECT_ROOT}/release/9.0.0-enterprise"

mkdir -p "${RELEASE_DIR}"

# Standardized OpenWrt Rust targets (see header comment for rationale)
RUST_TARGETS=(
    "mipsel-unknown-linux-musl"
    "aarch64-unknown-linux-musl"
    "x86_64-unknown-linux-musl"
)

echo "=== Package for OpenWrt (Enterprise v9.0.0-enterprise) ==="
for target in "${RUST_TARGETS[@]}"; do
    echo "Building daemon for ${target}..."
    if ! rustup target list --installed 2>/dev/null | grep -q "${target}"; then
        echo "  [WARN] Rust target ${target} not installed. Run: rustup target add ${target}"
        echo "  [WARN] Skipping ${target}."
        continue
    fi

    (
        cd "${DAEMON_DIR}"
        if command -v cross &>/dev/null; then
            cross build --release --target "${target}" --features platform-openwrt
        else
            cargo build --release --target "${target}" --features platform-openwrt
        fi
    )

    BINARY_PATH="${DAEMON_DIR}/target/${target}/release/shield-daemon"
    if [ -f "${BINARY_PATH}" ]; then
        cp "${BINARY_PATH}" "${RELEASE_DIR}/unifiedshield-daemon-${target}"
        chmod +x "${RELEASE_DIR}/unifiedshield-daemon-${target}"
        echo "  [OK] Packaged: unifiedshield-daemon-${target}"
    else
        echo "  [WARN] Build succeeded but binary not found at ${BINARY_PATH}"
    fi
done

echo "=== OpenWrt packaging complete ==="
echo "Artifacts in: ${RELEASE_DIR}/"
ls -lah "${RELEASE_DIR}/"
