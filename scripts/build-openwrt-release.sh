#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# scripts/build-openwrt-release.sh
# §5.2 OpenWrt cell — mipsel + aarch64 + x86_64 (all musl) packaged as .ipk
# ══════════════════════════════════════════════════════════════════════════════
set -x; set -e; set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="9.0.0-enterprise"
REL="release/${VERSION}"
mkdir -p "${REL}/ipk"

command -v cargo  >/dev/null || { echo "::error::cargo missing"; exit 1; }
command -v rustup >/dev/null || { echo "::error::rustup missing"; exit 1; }

OPENWRT_TARGETS=(mipsel-unknown-linux-musl aarch64-unknown-linux-musl x86_64-unknown-linux-musl)
declare -A ARCH_LABELS=(
  [mipsel-unknown-linux-musl]="mipsel"
  [aarch64-unknown-linux-musl]="aarch64"
  [x86_64-unknown-linux-musl]="x86_64"
)

for t in "${OPENWRT_TARGETS[@]}"; do
  rustup target add "$t" >/dev/null 2>&1 || true
done

# Prefer `cross` for musl builds to avoid host musl-gcc requirements
CROSS_BIN="cross"
if ! command -v "$CROSS_BIN" >/dev/null 2>&1; then
  CROSS_BIN="cargo"
  echo "::notice::cross not found — using cargo (musl cross-compiler required on host)"
fi

for target in "${OPENWRT_TARGETS[@]}"; do
  arch="${ARCH_LABELS[$target]}"
  echo "==[ Building Rust daemon for ${target} ]=="
  if ( cd daemon && $CROSS_BIN build --release --target "$target" --features platform-openwrt ); then
    BIN_PATH="daemon/target/${target}/release/shield-daemon"
    if [ -f "$BIN_PATH" ]; then
      cp -v "$BIN_PATH" "${REL}/ipk/unifiedshield-${VERSION}-enterprise-openwrt-${arch}-daemon"
    fi
  else
    echo "::warning::Rust build failed for ${target}"
  fi
done

# ── Package each arch's daemon as a minimal .ipk ──────────────────────────────
# .ipk is just an ar archive containing control.tar.gz + data.tar.gz + debian-binary
for target in "${OPENWRT_TARGETS[@]}"; do
  arch="${ARCH_LABELS[$target]}"
  DAEMON="${REL}/ipk/unifiedshield-${VERSION}-enterprise-openwrt-${arch}-daemon"
  [ -f "$DAEMON" ] || continue
  IPK_TMP="${REL}/.ipk-${arch}"
  rm -rf "$IPK_TMP"; mkdir -p "$IPK_TMP/data/usr/bin" "$IPK_TMP/control"
  cp -v "$DAEMON" "$IPK_TMP/data/usr/bin/unifiedshield"
  chmod +x "$IPK_TMP/data/usr/bin/unifiedshield"
  cat > "$IPK_TMP/control/control" <<EOF
Package: unifiedshield
Version: ${VERSION}
Architecture: ${arch}
Maintainer: UnifiedShield Team
Section: net
Priority: optional
Description: UnifiedShield Enterprise daemon for OpenWrt (${arch})
EOF
  ( cd "$IPK_TMP/control" && tar czf control.tar.gz . )
  ( cd "$IPK_TMP/data"    && tar czf data.tar.gz . )
  printf '2.0\n' > "$IPK_TMP/debian-binary"
  ( cd "$IPK_TMP" && ar r \
      "${REL}/ipk/unifiedshield-${VERSION}-enterprise-openwrt-${arch}.ipk" \
      debian-binary control.tar.gz data.tar.gz 2>/dev/null ) || \
    echo "::warning::ar packaging failed for ${arch} (requires binutils)"
  rm -rf "$IPK_TMP"
done

# ── .sha256 siblings ──────────────────────────────────────────────────────────
( cd "${REL}/ipk" && for f in *.ipk; do [ -f "$f" ] && sha256sum "$f" > "$f.sha256"; done )

echo "==[ OpenWrt release artifacts ]=="
ls -la "${REL}/ipk"
