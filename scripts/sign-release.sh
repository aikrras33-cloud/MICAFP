#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# scripts/sign-release.sh
# §5.4 — Generate SHA256SUMS, sign with minisign, emit VERSION.txt
# ══════════════════════════════════════════════════════════════════════════════
set -x; set -e; set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="9.0.0-enterprise"
REL="release/${VERSION}"

if [ ! -d "$REL" ]; then
  echo "::error::release directory ${REL} does not exist — run make release-all first"
  exit 1
fi

# Required tooling
command -v sha256sum >/dev/null || { echo "::error::sha256sum missing"; exit 1; }
command -v minisign  >/dev/null 2>&1 || echo "::warning::minisign missing — release will be unsigned"

# Minisign private key (provided by CI as env var; local users can export it)
: "${MINISIGN_PRIVATE_KEY:=}"
: "${MINISIGN_PASSWORD:=}"

# Materialize the private key to a temp file if available
KEY_FILE=""
if [ -n "$MINISIGN_PRIVATE_KEY" ]; then
  KEY_FILE="$(mktemp -t unifiedshield-minisign-key.XXXXXX)"
  printf '%s\n' "$MINISIGN_PRIVATE_KEY" > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
fi

# ── Collect artifacts (exclude SHA256SUMS itself + signature files) ──────────
ARTIFACT_LIST="$(find "$REL" -type f \
  ! -name 'SHA256SUMS' ! -name 'SHA256SUMS.minisig' \
  ! -name 'VERSION.txt' ! -name '*.sha256' \
  -print | sort)"

if [ -z "$ARTIFACT_LIST" ]; then
  echo "::error::no artifacts found in ${REL}"
  [ -n "$KEY_FILE" ] && rm -f "$KEY_FILE"
  exit 1
fi

# ── Generate SHA256SUMS (relative paths for portability) ──────────────────────
echo "==[ Generating SHA256SUMS ]=="
# Recompute every artifact's sha256 → write SHA256SUMS at release root
( cd "$REL" && find . -type f \
    ! -name 'SHA256SUMS' ! -name 'SHA256SUMS.minisig' \
    ! -name 'VERSION.txt' ! -name '*.sha256' \
    -print0 | xargs -0 sha256sum -- | sort -k2 > SHA256SUMS )
cat "$REL/SHA256SUMS"

# ── Generate per-file .sha256 siblings (idempotent, for IDE/tooling UX) ────
echo "==[ Refreshing per-file .sha256 siblings ]=="
find "$REL" -type f \
  ! -name 'SHA256SUMS' ! -name 'SHA256SUMS.minisig' \
  ! -name 'VERSION.txt' ! -name '*.sha256' \
  -print0 | while IFS= read -r -d '' f; do
    ( cd "$(dirname "$f")" && sha256sum "$(basename "$f")" > "$(basename "$f").sha256" )
done

# ── Sign SHA256SUMS with minisign ───────────────────────────────────────────
echo "==[ Signing SHA256SUMS with minisign ]=="
if [ -n "$KEY_FILE" ] && command -v minisign >/dev/null 2>&1; then
  if [ -n "$MINISIGN_PASSWORD" ]; then
    printf '%s\n' "$MINISIGN_PASSWORD" | minisign -S -s "$KEY_FILE" \
      -m "$REL/SHA256SUMS" -x "$REL/SHA256SUMS.minisig"
  else
    minisign -S -s "$KEY_FILE" -m "$REL/SHA256SUMS" -x "$REL/SHA256SUMS.minisig"
  fi
  echo "::notice::SHA256SUMS signed → ${REL}/SHA256SUMS.minisig"
else
  echo "::warning::minisign signing skipped — set MINISIGN_PRIVATE_KEY to enable"
fi
[ -n "$KEY_FILE" ] && rm -f "$KEY_FILE"

# ── Generate VERSION.txt ──────────────────────────────────────────────────────
echo "==[ Generating VERSION.txt ]=="
{
  echo "UnifiedShield Enterprise ${VERSION}"
  echo "Build commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "Build date:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  echo "=== Artifacts ==="
  find "$REL" -type f \
    ! -name 'SHA256SUMS' ! -name 'SHA256SUMS.minisig' \
    ! -name 'VERSION.txt' ! -name '*.sha256' \
    -print | sort | while IFS= read -r f; do
      rel="${f#${REL}/}"
      sha="$(sha256sum "$f" | awk '{print $1}')"
      sig=""
      [ -f "${f}.minisig" ] && sig="(minisign signed)"
      [ -f "${REL}/SHA256SUMS.minisig" ] && sig="(covered by SHA256SUMS.minisig)"
      printf '  %-50s %s %s\n' "$rel" "$sha" "$sig"
    done
  echo ""
  echo "=== Verification ==="
  echo "  cd release/${VERSION}"
  echo "  sha256sum -c SHA256SUMS"
  if [ -f "$REL/SHA256SUMS.minisig" ]; then
    echo "  minisign -V -m SHA256SUMS -x SHA256SUMS.minisig -p <public-key>"
  else
    echo "  (minisign signature not present — release is unsigned)"
  fi
} > "$REL/VERSION.txt"
cat "$REL/VERSION.txt"

echo "==[ sign-release.sh complete ]=="
