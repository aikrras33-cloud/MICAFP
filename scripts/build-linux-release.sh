#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# scripts/build-linux-release.sh
# §5.2 Linux cells — x86_64-unknown-linux-gnu + aarch64-unknown-linux-gnu
# Build AppImage + .deb + .rpm for both arches
# ══════════════════════════════════════════════════════════════════════════════
set -x; set -e; set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="9.0.0-enterprise"
REL="release/${VERSION}"
mkdir -p "${REL}/linux" "${REL}/deb" "${REL}/rpm"

command -v cargo  >/dev/null || { echo "::error::cargo missing"; exit 1; }
command -v rustup >/dev/null || { echo "::error::rustup missing"; exit 1; }

LINUX_TARGETS=(x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu)
for t in "${LINUX_TARGETS[@]}"; do
  rustup target add "$t" >/dev/null 2>&1 || true
done

# Prefer `cross` for aarch64 (avoids needing the cross-compiler on the host)
CROSS_BIN="cross"
if ! command -v "$CROSS_BIN" >/dev/null 2>&1; then
  CROSS_BIN="cargo"
  echo "::notice::cross not found — using cargo (aarch64 may require gcc-aarch64-linux-gnu)"
fi

# ── Cross-compile Rust daemon for each Linux arch ─────────────────────────────
declare -A ARCH_LABELS=( [x86_64-unknown-linux-gnu]="x64" [aarch64-unknown-linux-gnu]="arm64" )
for target in "${LINUX_TARGETS[@]}"; do
  arch="${ARCH_LABELS[$target]}"
  echo "==[ Building Rust for ${target} ]=="
  if ( cd daemon && $CROSS_BIN build --release --target "$target" --features platform-linux ); then
    cp -v "daemon/target/${target}/release/shield-daemon" \
          "${REL}/linux/unifiedshield-${VERSION}-enterprise-linux-${arch}-daemon" 2>/dev/null || true
  else
    echo "::warning::Rust build failed for ${target}"
  fi
done

# ── AppImage (per arch; linuxdeploy + appimagetool required) ──────────────────
for target in "${LINUX_TARGETS[@]}"; do
  arch="${ARCH_LABELS[$target]}"
  DAEMON_BIN="${REL}/linux/unifiedshield-${VERSION}-enterprise-linux-${arch}-daemon"
  [ -f "$DAEMON_BIN" ] || continue
  APPDIR="${REL}/.AppDir-${arch}"
  mkdir -p "$APPDIR/usr/bin"
  cp -v "$DAEMON_BIN" "$APPDIR/usr/bin/unifiedshield"
  chmod +x "$APPDIR/usr/bin/unifiedshield"
  # Minimal AppRun
  cat > "$APPDIR/AppRun" <<'APPRUN'
#!/usr/bin/env bash
SELF="$(dirname "$(readlink -f "$0")")"
exec "$SELF/usr/bin/unifiedshield" "$@"
APPRUN
  chmod +x "$APPDIR/AppRun"
  cat > "$APPDIR/unifiedshield.desktop" <<EOF
[Desktop Entry]
Name=UnifiedShield Enterprise
Exec=unifiedshield
Type=Application
Categories=Network;
Icon=unifiedshield
EOF
  if command -v appimagetool >/dev/null 2>&1; then
    appimagetool "$APPDIR" \
      "${REL}/linux/unifiedshield-${VERSION}-enterprise-linux-${arch}.AppImage" \
      || echo "::warning::appimagetool failed for ${arch}"
  else
    echo "::notice::appimagetool not available — skipping AppImage for ${arch}"
  fi
  rm -rf "$APPDIR"
done

# ── Flutter Linux app AppImage (x64; the full GUI application) ───────────────
# Requires GTK dev headers on the build host (installed by the CI workflow).
# Produces: unifiedshield-<ver>-enterprise-linux-app-x64.AppImage
if command -v flutter >/dev/null 2>&1; then
  FLUTTER_DIR="flutter_app"; [ -d flutter_app ] || FLUTTER_DIR="flutter"
  if [ -d "$FLUTTER_DIR/linux" ]; then
    echo "==[ Flutter Linux app build ]=="
    ( cd "$FLUTTER_DIR" && flutter pub get )
    ( cd "$FLUTTER_DIR" && flutter build linux --release ) || \
      echo "::warning::flutter linux build failed — app AppImage skipped"
    BUNDLE_DIR="$FLUTTER_DIR/build/linux/x64/release/bundle"
    if [ -d "$BUNDLE_DIR" ] && [ -f "$BUNDLE_DIR/unified_shield" ]; then
      APPAPPDIR="${REL}/.AppDir-app-x64"
      rm -rf "$APPAPPDIR"; mkdir -p "$APPAPPDIR/usr/bin"
      cp -R "$BUNDLE_DIR"/. "$APPAPPDIR/usr/bin/"
      # Embed the daemon engine next to the app binary.
      X64_DAEMON="${REL}/linux/unifiedshield-${VERSION}-enterprise-linux-x64-daemon"
      [ -f "$X64_DAEMON" ] && cp -v "$X64_DAEMON" "$APPAPPDIR/usr/bin/shield-daemon"
      chmod +x "$APPAPPDIR/usr/bin/unified_shield"
      cat > "$APPAPPDIR/AppRun" <<'APPRUN'
#!/usr/bin/env bash
SELF="$(dirname "$(readlink -f "$0")")"
exec "$SELF/usr/bin/unified_shield" "$@"
APPRUN
      chmod +x "$APPAPPDIR/AppRun"
      cat > "$APPAPPDIR/unifiedshield-app.desktop" <<EOF
[Desktop Entry]
Name=UnifiedShield Enterprise
Exec=unified_shield
Type=Application
Categories=Network;
Icon=unifiedshield
StartupWMClass=unified_shield
EOF
      # Reuse the daemon .svg/.png icon if present
      [ -f "$APPAPPDIR/unifiedshield.svg" ] || \
        find . -maxdepth 3 -name 'unifiedshield.svg' -exec cp -v {} "$APPAPPDIR/" \; 2>/dev/null || true
      if command -v appimagetool >/dev/null 2>&1; then
        appimagetool "$APPAPPDIR" \
          "${REL}/linux/unifiedshield-${VERSION}-enterprise-linux-app-x64.AppImage" \
          || echo "::warning::appimagetool failed for the Flutter app"
      else
        echo "::notice::appimagetool not available — skipping Flutter app AppImage"
      fi
      rm -rf "$APPAPPDIR"
    else
      echo "::warning::Flutter linux bundle missing at ${BUNDLE_DIR}"
    fi
  fi
else
  echo "::notice::flutter not on PATH — skipping Flutter app AppImage (daemon artifacts still produced)"
fi

# ── .deb (dpkg-deb) for each arch ─────────────────────────────────────────────
for target in "${LINUX_TARGETS[@]}"; do
  arch="${ARCH_LABELS[$target]}"
  DEB_NAME="unifiedshield_${VERSION}-1_${arch}"
  DEB_ROOT="${REL}/.deb-root-${arch}/${DEB_NAME}"
  mkdir -p "$DEB_ROOT/DEBIAN" "$DEB_ROOT/usr/bin" "$DEB_ROOT/etc/systemd/system"
  DAEMON_BIN="${REL}/linux/unifiedshield-${VERSION}-enterprise-linux-${arch}-daemon"
  [ -f "$DAEMON_BIN" ] && cp -v "$DAEMON_BIN" "$DEB_ROOT/usr/bin/unifiedshield" || true
  chmod +x "$DEB_ROOT/usr/bin/unifiedshield" 2>/dev/null || true
  cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: unifiedshield
Version: ${VERSION}
Section: net
Priority: optional
Architecture: ${arch}
Depends: libc6
Maintainer: UnifiedShield Team <bot@unifiedshield.local>
Description: UnifiedShield Enterprise — anti-censorship VPN daemon
 ${VERSION} — cross-compiled for ${arch}
EOF
  cp -v linux/unifiedshield.service "$DEB_ROOT/etc/systemd/system/" 2>/dev/null || true
  if command -v dpkg-deb >/dev/null 2>&1; then
    ( cd "${REL}/.deb-root-${arch}" && dpkg-deb --build "$DEB_NAME" )
    mv -v "${REL}/.deb-root-${arch}/${DEB_NAME}.deb" \
          "${REL}/deb/unifiedshield-${VERSION}-enterprise-linux-${arch}.deb" 2>/dev/null || true
  else
    echo "::notice::dpkg-deb not available — skipping .deb for ${arch}"
  fi
  rm -rf "${REL}/.deb-root-${arch}"
done

# ── .rpm (rpmbuild) for each arch ─────────────────────────────────────────────
for target in "${LINUX_TARGETS[@]}"; do
  arch="${ARCH_LABELS[$target]}"
  SPEC="linux/packaging/unifiedshield.spec"
  if [ -f "$SPEC" ] && command -v rpmbuild >/dev/null 2>&1; then
    rpmbuild -bb "$SPEC" \
      --define "version ${VERSION}" \
      --define "_topdir ${REL}/.rpm-top-${arch}" \
      --target "$arch" || echo "::warning::rpmbuild failed for ${arch}"
    find "${REL}/.rpm-top-${arch}" -name '*.rpm' \
      -exec cp -v {} "${REL}/rpm/unifiedshield-${VERSION}-enterprise-linux-${arch}.rpm" \; 2>/dev/null || true
    rm -rf "${REL}/.rpm-top-${arch}"
  else
    echo "::notice::rpmbuild or spec file not available — skipping .rpm for ${arch}"
  fi
done

# ── .sha256 siblings ──────────────────────────────────────────────────────────
( cd "${REL}/linux" && for f in *; do [ -f "$f" ] && sha256sum "$f" > "$f.sha256"; done )
( cd "${REL}/deb"   && for f in *.deb; do [ -f "$f" ] && sha256sum "$f" > "$f.sha256"; done )
( cd "${REL}/rpm"   && for f in *.rpm; do [ -f "$f" ] && sha256sum "$f" > "$f.sha256"; done )

echo "==[ Linux release artifacts ]=="
ls -la "${REL}/linux" "${REL}/deb" "${REL}/rpm"
