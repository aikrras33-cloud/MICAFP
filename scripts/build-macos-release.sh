#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# scripts/build-macos-release.sh
# §5.2 macOS cell — universal daemon via lipo + Flutter .app → .dmg + .pkg
# ══════════════════════════════════════════════════════════════════════════════
set -x; set -e; set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="9.0.0-enterprise"
REL="release/${VERSION}"
mkdir -p "${REL}/macos"

command -v cargo  >/dev/null || { echo "::error::cargo missing"; exit 1; }
command -v rustup >/dev/null || { echo "::error::rustup missing"; exit 1; }

MACOS_TARGETS=(aarch64-apple-darwin x86_64-apple-darwin)
for t in "${MACOS_TARGETS[@]}"; do
  rustup target add "$t" >/dev/null 2>&1 || true
done

# ── Compile Rust daemon for both macOS arches ─────────────────────────────────
# NOTE: uses the default feature set (platform-linux → `tun` crate), which
# compiles on macOS via the utun backend. The previous release of this script
# incorrectly passed --features platform-linux explicitly; the default set is
# identical but future-proof.
declare -A BIN_PATHS
for target in "${MACOS_TARGETS[@]}"; do
  echo "==[ Building Rust for ${target} ]=="
  if ( cd daemon && cargo build --release --target "$target" ); then
    BIN_PATHS["$target"]="daemon/target/${target}/release/shield-daemon"
  else
    echo "::warning::Rust build failed for ${target}"
  fi
done

# ── lipo into universal binary ────────────────────────────────────────────────
UNIVERSAL_BIN="${REL}/macos/unifiedshield-${VERSION}-enterprise-macos-universal-daemon"
if [ -n "${BIN_PATHS[aarch64-apple-darwin]:-}" ] && [ -n "${BIN_PATHS[x86_64-apple-darwin]:-}" ]; then
  lipo -create -output "$UNIVERSAL_BIN" \
    "${BIN_PATHS[aarch64-apple-darwin]}" \
    "${BIN_PATHS[x86_64-apple-darwin]}"
  chmod +x "$UNIVERSAL_BIN"
else
  echo "::warning::one or both macOS arch binaries missing — skipping lipo"
fi

# ── Flutter macOS build (.app) ────────────────────────────────────────────────
FLUTTER_DIR="flutter_app"; [ -d flutter_app ] || FLUTTER_DIR="flutter"
APP_PATH=""
if [ -d "$FLUTTER_DIR/macos" ]; then
  ( cd "$FLUTTER_DIR" && flutter pub get )
  ( cd "$FLUTTER_DIR" && flutter build macos --release ) || \
    echo "::warning::flutter macOS build failed"
  APP_PATH=$(find "$FLUTTER_DIR/build/macos" -name '*.app' -maxdepth 4 2>/dev/null | head -1)
fi

# ── Embed the universal daemon inside the .app bundle ─────────────────────────
if [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ] && [ -f "$UNIVERSAL_BIN" ]; then
  echo "==[ Embedding universal daemon into ${APP_PATH} ]=="
  cp -v "$UNIVERSAL_BIN" "$APP_PATH/Contents/MacOS/shield-daemon"
  chmod +x "$APP_PATH/Contents/MacOS/shield-daemon"
fi

# ── .dmg (hdiutil) — prefers the Flutter .app; falls back to daemon-only ─────
if command -v hdiutil >/dev/null 2>&1; then
  DMG_DIR="${REL}/.dmg-root"
  rm -rf "$DMG_DIR"; mkdir -p "$DMG_DIR"
  if [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ]; then
    cp -R "$APP_PATH" "$DMG_DIR/"
    hdiutil create -volname "UnifiedShield ${VERSION}" \
      -srcfolder "$DMG_DIR" -fs HFS+ \
      -ov "${REL}/macos/unifiedshield-${VERSION}-enterprise-macos.dmg" || \
      echo "::warning::hdiutil failed (app dmg)"
  elif [ -f "$UNIVERSAL_BIN" ]; then
    cp "$UNIVERSAL_BIN" "$DMG_DIR/"
    hdiutil create -volname "UnifiedShield ${VERSION}" \
      -srcfolder "$DMG_DIR" -fs HFS+ \
      -ov "${REL}/macos/unifiedshield-${VERSION}-enterprise-macos-daemon.dmg" || \
      echo "::warning::hdiutil failed (daemon dmg)"
  else
    echo "::warning::nothing to package into .dmg"
  fi
  rm -rf "$DMG_DIR"
fi

# ── .pkg (pkgbuild) — installs the .app into /Applications ────────────────────
if command -v pkgbuild >/dev/null 2>&1; then
  if [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ]; then
    PKG_ROOT="${REL}/.pkg-root"
    rm -rf "$PKG_ROOT"; mkdir -p "$PKG_ROOT/Applications"
    cp -R "$APP_PATH" "$PKG_ROOT/Applications/"
    pkgbuild \
      --identifier com.unifiedshield.app \
      --version "$VERSION" \
      --root "$PKG_ROOT" \
      --install-location "/" \
      "${REL}/macos/unifiedshield-${VERSION}-enterprise-macos-app.pkg" || \
      echo "::warning::pkgbuild failed (app pkg)"
    rm -rf "$PKG_ROOT"
  elif [ -f "$UNIVERSAL_BIN" ]; then
    # Fallback: CLI daemon .pkg installing to /usr/local/bin
    PKG_ROOT="${REL}/.pkg-cli-root/usr/local/bin"
    rm -rf "${REL}/.pkg-cli-root"; mkdir -p "$PKG_ROOT"
    cp "$UNIVERSAL_BIN" "$PKG_ROOT/shield-daemon"
    pkgbuild \
      --identifier com.unifiedshield.daemon \
      --version "$VERSION" \
      --root "${REL}/.pkg-cli-root" \
      "${REL}/macos/unifiedshield-${VERSION}-enterprise-macos-daemon.pkg" || \
      echo "::warning::pkgbuild failed (daemon pkg)"
    rm -rf "${REL}/.pkg-cli-root"
  fi
fi

# ── .sha256 siblings ──────────────────────────────────────────────────────────
( cd "${REL}/macos" && for f in *; do
    [ -f "$f" ] && sha256sum "$f" > "$f.sha256"
done )

echo "==[ macOS release artifacts ]=="
ls -la "${REL}/macos"
