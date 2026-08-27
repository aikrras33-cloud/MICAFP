#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# scripts/build-windows-release.sh
# §5.2 Windows cell — x86_64-pc-windows-msvc
# Produces:
#   • unifiedshield-<ver>-enterprise-windows-installer.exe  (Inno Setup, full app)
#   • unifiedshield-<ver>-enterprise-windows-portable.zip  (full app + daemon)
#   • unifiedshield-<ver>-enterprise-windows-daemon.exe    (bare Rust daemon)
#   • optional .msix
# Runs under Git Bash on the windows-2022 runner.
# ══════════════════════════════════════════════════════════════════════════════
set -x; set -e; set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="9.0.0-enterprise"
REL="release/${VERSION}"
mkdir -p "${REL}/windows"

command -v cargo  >/dev/null || { echo "::error::cargo missing"; exit 1; }
command -v rustup >/dev/null || { echo "::error::rustup missing"; exit 1; }

# ── zip helper: prefer zip, fall back to 7-Zip (Git Bash has no zip.exe) ──────
archive_zip() {
  local src_dir="$1" out="$2"
  if command -v zip >/dev/null 2>&1; then
    ( cd "$src_dir" && zip -qry "$out" . )
  elif command -v 7z >/dev/null 2>&1; then
    7z a -tzip "$out" "$src_dir/." >/dev/null
  elif [ -f "/c/Program Files/7-Zip/7z.exe" ]; then
    "/c/Program Files/7-Zip/7z.exe" a -tzip "$(cygpath -w "$out")" "$(cygpath -w "$src_dir")/*" >/dev/null
  else
    echo "::warning::no zip utility available"
    return 1
  fi
}

WIN_TARGET="x86_64-pc-windows-msvc"
rustup target add "$WIN_TARGET" >/dev/null 2>&1 || true

# ── Compile Rust daemon for Windows ───────────────────────────────────────────
CARGO_BIN="${CARGO_BIN:-cargo}"
echo "==[ Building Rust daemon for ${WIN_TARGET} ]=="
( cd daemon && $CARGO_BIN build --release --target "$WIN_TARGET" --features platform-windows ) || \
  echo "::warning::Rust build failed for ${WIN_TARGET} — continuing with Flutter-only artifacts"

# Locate the .exe produced by Cargo
DAEMON_EXE="daemon/target/${WIN_TARGET}/release/shield-daemon.exe"
if [ -f "$DAEMON_EXE" ]; then
  cp -v "$DAEMON_EXE" "${REL}/windows/unifiedshield-${VERSION}-enterprise-windows-daemon.exe"
else
  echo "::warning::${DAEMON_EXE} not found — daemon artifacts will be skipped"
fi

# ── Flutter Windows build (full app: exe + DLLs + data) ──────────────────────
FLUTTER_DIR="flutter_app"; [ -d flutter_app ] || FLUTTER_DIR="flutter"
APP_BUNDLE=""
if [ -d "$FLUTTER_DIR/windows" ]; then
  ( cd "$FLUTTER_DIR" && flutter pub get )
  ( cd "$FLUTTER_DIR" && flutter build windows --release ) || \
    echo "::warning::flutter Windows build failed"
  # Flutter 3.x output layout: build/windows/x64/runner/Release/
  APP_BUNDLE=$(find "$FLUTTER_DIR/build/windows" -type d -name 'Release' 2>/dev/null | head -1)
  if [ -n "$APP_BUNDLE" ] && [ -d "$APP_BUNDLE" ]; then
    # Bundle the Rust daemon alongside the Flutter executable so the app can
    # spawn it as its local tunnel engine on desktop.
    if [ -f "$DAEMON_EXE" ]; then
      cp -v "$DAEMON_EXE" "$APP_BUNDLE/shield-daemon.exe"
    fi
    echo "==[ Flutter app bundle: ${APP_BUNDLE} ]=="
    ls -la "$APP_BUNDLE"
  else
    APP_BUNDLE=""
  fi
fi

# ── Portable zip (the complete runnable folder) ───────────────────────────────
if [ -n "$APP_BUNDLE" ]; then
  archive_zip "$APP_BUNDLE" "${REL}/windows/unifiedshield-${VERSION}-enterprise-windows-portable.zip" \
    || echo "::warning::portable zip failed"
fi

# ── Inno Setup installer (.exe) — primary Windows artifact ────────────────────
ISS_FILE="windows/installer/setup_flutter.iss"
if [ -n "$APP_BUNDLE" ] && [ -f "$ISS_FILE" ]; then
  # ISCC.exe is preinstalled on GitHub windows runners; resolve it robustly.
  ISCC_BIN="$(command -v iscc || true)"
  if [ -z "$ISCC_BIN" ] && [ -f "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" ]; then
    ISCC_BIN="/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
  fi
  if [ -n "$ISCC_BIN" ]; then
    # Copy the bundle to a stable staging path for the .iss script.
    STAGE="windows/installer/staging"
    rm -rf "$STAGE"; mkdir -p "$STAGE"
    cp -R "$APP_BUNDLE"/. "$STAGE/"
    echo "==[ Compiling Inno Setup installer ]=="
    "$ISCC_BIN" "$(cygpath -w "$ISS_FILE" 2>/dev/null || echo "$ISS_FILE")" "/Q" \
      "/DAppVersion=${VERSION}" "/DAppSource=staging" || \
      echo "::warning::Inno Setup compiler failed"
    INSTALLER=$(find windows/installer/Output -name '*.exe' 2>/dev/null | head -1)
    if [ -n "$INSTALLER" ] && [ -f "$INSTALLER" ]; then
      cp -v "$INSTALLER" "${REL}/windows/unifiedshield-${VERSION}-enterprise-windows-installer.exe"
    fi
    rm -rf "$STAGE"
  else
    echo "::notice::Inno Setup (ISCC.exe) not available — skipping installer .exe (portable zip still produced)"
  fi
else
  echo "::notice::Flutter bundle or setup_flutter.iss missing — skipping installer"
fi

# ── Optional MSIX (MakeAppx required) ─────────────────────────────────────────
if command -v MakeAppx >/dev/null 2>&1 && [ -d windows/msix ]; then
  MakeAppx pack /d windows/msix /p "${REL}/windows/unifiedshield-${VERSION}-enterprise-windows.msix" /v || \
    echo "::warning::MakeAppx failed — skipping MSIX"
fi

# ── .sha256 siblings ──────────────────────────────────────────────────────────
( cd "${REL}/windows" && for f in *; do
    [ -f "$f" ] && sha256sum "$f" > "$f.sha256"
done )

echo "==[ Windows release artifacts ]=="
ls -la "${REL}/windows"
