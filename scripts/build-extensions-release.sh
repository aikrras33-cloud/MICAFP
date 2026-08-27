#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# scripts/build-extensions-release.sh
# §5.2 Extensions cell — Chrome .zip + Firefox .xpi (via web-ext) + WASM .wasm
# ══════════════════════════════════════════════════════════════════════════════
set -x; set -e; set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="9.0.0-enterprise"
REL="release/${VERSION}"
mkdir -p "${REL}/chrome" "${REL}/xpi" "${REL}/wasm"

command -v cargo >/dev/null || { echo "::error::cargo missing"; exit 1; }
command -v node  >/dev/null || { echo "::error::node missing"; exit 1; }
command -v npm   >/dev/null || { echo "::error::npm missing"; exit 1; }

# ── WASM (build first, since both extensions consume it) ────────────────────
echo "==[ Building WASM obfuscator ]=="
if command -v wasm-pack >/dev/null 2>&1; then
  ( cd wasm-obfuscator && wasm-pack build --release --target web --out-dir ../extensions/chrome/wasm ) || \
    echo "::warning::wasm-pack failed"
  # Mirror to firefox
  mkdir -p extensions/firefox/wasm
  cp -rv extensions/chrome/wasm/* extensions/firefox/wasm/ 2>/dev/null || true
  cp -v extensions/chrome/wasm/*.wasm "${REL}/wasm/unifiedshield-${VERSION}-enterprise.wasm" 2>/dev/null || true
else
  echo "::notice::wasm-pack not installed — skipping WASM build"
fi

# ── Chrome extension (npm ci + npm run build → .zip) ───────────────────────────
echo "==[ Building Chrome extension ]=="
( cd extensions/chrome && npm ci && npm run build ) || echo "::warning::chrome build failed"
CHROME_DIST="extensions/chrome/dist"
[ -d "$CHROME_DIST" ] || CHROME_DIST="extensions/chrome/build"
if [ -d "$CHROME_DIST" ]; then
  ( cd "$CHROME_DIST" && \
    zip -qry "${REL}/chrome/unifiedshield-${VERSION}-enterprise-chrome.zip" . )
fi

# ── Firefox extension (npm ci + npm run build → web-ext build → .xpi) ──────────
echo "==[ Building Firefox extension ]=="
( cd extensions/firefox && npm ci && npm run build ) || echo "::warning::firefox build failed"
FIREFOX_DIST="extensions/firefox/dist"
[ -d "$FIREFOX_DIST" ] || FIREFOX_DIST="extensions/firefox/build"
if [ -d "$FIREFOX_DIST" ]; then
  if command -v web-ext >/dev/null 2>&1; then
    ( cd "$FIREFOX_DIST" && \
      web-ext build --overwrite-dest \
        --artifacts-dir "${REL}/xpi" \
        --filename "unifiedshield-${VERSION}-enterprise-firefox.xpi" ) || \
      echo "::warning::web-ext build failed"
  else
    # Fall back to plain zip
    ( cd "$FIREFOX_DIST" && \
      zip -qry "${REL}/xpi/unifiedshield-${VERSION}-enterprise-firefox.xpi" . )
  fi
fi

# ── .sha256 siblings ──────────────────────────────────────────────────────────
( cd "${REL}/chrome" && for f in *.zip;  do [ -f "$f" ] && sha256sum "$f" > "$f.sha256"; done )
( cd "${REL}/xpi"    && for f in *.xpi;  do [ -f "$f" ] && sha256sum "$f" > "$f.sha256"; done )
( cd "${REL}/wasm"   && for f in *.wasm; do [ -f "$f" ] && sha256sum "$f" > "$f.sha256"; done )

echo "==[ Extensions release artifacts ]=="
ls -la "${REL}/chrome" "${REL}/xpi" "${REL}/wasm"
