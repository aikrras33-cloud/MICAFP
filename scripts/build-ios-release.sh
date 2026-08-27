#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# scripts/build-ios-release.sh
# §5.2 iOS cell — cross-compile Rust for aarch64-apple-ios + sim, build .ipa
# ══════════════════════════════════════════════════════════════════════════════
set -x; set -e; set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="9.0.0-enterprise"
REL="release/${VERSION}"
mkdir -p "${REL}/ipa"

command -v cargo  >/dev/null || { echo "::error::cargo missing"; exit 1; }
command -v rustup >/dev/null || { echo "::error::rustup missing"; exit 1; }

IOS_TARGETS=(aarch64-apple-ios aarch64-apple-ios-sim)
for t in "${IOS_TARGETS[@]}"; do
  rustup target add "$t" >/dev/null 2>&1 || true
done

# ── Cross-compile Rust daemon for iOS ─────────────────────────────────────────
for target in "${IOS_TARGETS[@]}"; do
  echo "==[ Building Rust for ${target} ]=="
  ( cd daemon && cargo build --release --target "$target" --features platform-ios ) || \
    echo "::warning::Rust build failed for ${target} (Xcode required on macOS host)"
done

# ── Flutter iOS build (.ipa, no codesign for CI) ──────────────────────────────
FLUTTER_DIR="flutter_app"; [ -d flutter_app ] || FLUTTER_DIR="flutter"
echo "==[ flutter pub get ]=="
( cd "$FLUTTER_DIR" && flutter pub get )

echo "==[ flutter build ios --release --no-codesign ]=="
( cd "$FLUTTER_DIR" && flutter build ios --release --no-codesign )

# Locate the .app product and assemble a device .ipa
APP_PATH=$(find "$FLUTTER_DIR/build/ios" -name 'Runner.app' -path '*Release-iphoneos*' 2>/dev/null | head -1)
if [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ]; then
  PAYLOAD="${REL}/.ios-payload/Payload"
  mkdir -p "$PAYLOAD"
  cp -R "$APP_PATH" "$PAYLOAD/"
  ( cd "${REL}/.ios-payload" && zip -qr "${REL}/ipa/unifiedshield-${VERSION}-enterprise-ios-device.ipa" Payload )
  rm -rf "${REL}/.ios-payload"
else
  echo "::warning::Runner.app not found — skipping .ipa creation"
fi

# Simulator .ipa (built from sim target)
SIM_APP=$(find "$FLUTTER_DIR/build/ios" -name 'Runner.app' -path '*Release-iphonesimulator*' 2>/dev/null | head -1)
if [ -n "$SIM_APP" ] && [ -d "$SIM_APP" ]; then
  PAYLOAD="${REL}/.ios-sim-payload/Payload"
  mkdir -p "$PAYLOAD"
  cp -R "$SIM_APP" "$PAYLOAD/"
  ( cd "${REL}/.ios-sim-payload" && zip -qr "${REL}/ipa/unifiedshield-${VERSION}-enterprise-ios-simulator.ipa" Payload )
  rm -rf "${REL}/.ios-sim-payload"
fi

# ── .sha256 siblings ──────────────────────────────────────────────────────────
( cd "${REL}/ipa" && for f in *.ipa; do [ -f "$f" ] && sha256sum "$f" > "$f.sha256"; done )

echo "==[ iOS release artifacts ]=="
ls -la "${REL}/ipa"
