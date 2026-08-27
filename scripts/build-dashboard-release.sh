#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# scripts/build-dashboard-release.sh
# §5.2 Dashboard cell — Next.js production build + .deb/.rpm
# ══════════════════════════════════════════════════════════════════════════════
set -x; set -e; set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="9.0.0-enterprise"
REL="release/${VERSION}"
mkdir -p "${REL}/dashboard"

command -v node >/dev/null || { echo "::error::node missing"; exit 1; }
command -v npm  >/dev/null || { echo "::error::npm missing"; exit 1; }

# ── Next.js build ────────────────────────────────────────────────────────────
echo "==[ dashboard: npm ci ]=="
( cd dashboard && npm ci )

echo "==[ dashboard: npx prisma generate ]=="
( cd dashboard && npx prisma generate || echo "::warning::prisma generate failed" )

echo "==[ dashboard: npm run build ]=="
( cd dashboard && npm run build )

# ── Package built .next/ + public/ into a portable .tar.gz ────────────────────
PUBLISH_ROOT="${REL}/.dashboard-pkg/usr/share/unifiedshield-dashboard"
mkdir -p "$PUBLISH_ROOT"
cp -Rv dashboard/.next "$PUBLISH_ROOT/" 2>/dev/null || true
cp -Rv dashboard/public "$PUBLISH_ROOT/" 2>/dev/null || true
cp -v  dashboard/package.json "$PUBLISH_ROOT/" 2>/dev/null || true
cat > "$PUBLISH_ROOT/start.sh" <<EOF
#!/usr/bin/env bash
cd /usr/share/unifiedshield-dashboard
NODE_ENV=production npm start
EOF
chmod +x "$PUBLISH_ROOT/start.sh"

( cd "${REL}/.dashboard-pkg" && \
  tar czf "${REL}/dashboard/unifiedshield-${VERSION}-enterprise-dashboard.tar.gz" . )
rm -rf "${REL}/.dashboard-pkg"

# ── .deb packaging ───────────────────────────────────────────────────────────
DEB_ROOT="${REL}/.deb-root/unifiedshield-dashboard_${VERSION}-1_all"
mkdir -p "$DEB_ROOT/DEBIAN" "$DEB_ROOT/usr/share/unifiedshield-dashboard" "$DEB_ROOT/etc/systemd/system"
tar xzf "${REL}/dashboard/unifiedshield-${VERSION}-enterprise-dashboard.tar.gz" \
  -C "$DEB_ROOT/usr/share/unifiedshield-dashboard"
cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: unifiedshield-dashboard
Version: ${VERSION}
Section: net
Priority: optional
Architecture: all
Depends: nodejs (>= 18)
Maintainer: UnifiedShield Team <bot@unifiedshield.local>
Description: UnifiedShield Enterprise — Next.js dashboard
 Production build of the control-plane UI.
EOF
if command -v dpkg-deb >/dev/null 2>&1; then
  ( cd "${REL}/.deb-root" && dpkg-deb --build "unifiedshield-dashboard_${VERSION}-1_all" )
  mv -v "${REL}/.deb-root/unifiedshield-dashboard_${VERSION}-1_all.deb" \
        "${REL}/dashboard/unifiedshield-${VERSION}-enterprise-dashboard.deb"
fi
rm -rf "${REL}/.deb-root"

# ── .rpm packaging ────────────────────────────────────────────────────────────
if command -v rpmbuild >/dev/null 2>&1; then
  SPEC="${REL}/.dashboard.spec"
  cat > "$SPEC" <<EOF
Name: unifiedshield-dashboard
Version: ${VERSION}
Release: 1
Summary: UnifiedShield Enterprise dashboard
License: GPL-3.0
BuildArch: noarch
%description
Production Next.js dashboard for UnifiedShield Enterprise.
%prep
%build
%install
install -d %{buildroot}/usr/share/unifiedshield-dashboard
tar xzf ${ROOT}/${REL}/dashboard/unifiedshield-${VERSION}-enterprise-dashboard.tar.gz \
  -C %{buildroot}/usr/share/unifiedshield-dashboard
%files
/usr/share/unifiedshield-dashboard
EOF
  rpmbuild -bb "$SPEC" \
    --define "_topdir ${REL}/.rpm-top" \
    --target noarch 2>&1 || echo "::warning::rpmbuild failed for dashboard"
  find "${REL}/.rpm-top" -name '*.rpm' \
    -exec cp -v {} "${REL}/dashboard/unifiedshield-${VERSION}-enterprise-dashboard.rpm" \; 2>/dev/null || true
  rm -rf "${REL}/.rpm-top" "$SPEC"
fi

# ── .sha256 siblings ──────────────────────────────────────────────────────────
( cd "${REL}/dashboard" && for f in *; do [ -f "$f" ] && sha256sum "$f" > "$f.sha256"; done )

echo "==[ Dashboard release artifacts ]=="
ls -la "${REL}/dashboard"
