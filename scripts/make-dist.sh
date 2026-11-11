#!/bin/sh
# Build dist/luci-app-samba-users-files.tar.gz for GitHub Releases
# Run from the package root (parent of scripts/).

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
STAGE="$DIST/stage"

rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"

cp -a "$ROOT/root/." "$STAGE/"
mkdir -p "$STAGE/www"
cp -a "$ROOT/htdocs/." "$STAGE/www/"

# sensible perms
find "$STAGE" -type d -exec chmod 755 {} \;
find "$STAGE" -type f -exec chmod 644 {} \;
chmod 755 "$STAGE/etc/uci-defaults/"* 2>/dev/null || true
chmod 755 "$STAGE/usr/share/rpcd/ucode/samba_users.uc" 2>/dev/null || true

tar --owner=0 --group=0 -C "$STAGE" -czf "$DIST/luci-app-samba-users-files.tar.gz" .
rm -rf "$STAGE"

echo "Wrote $DIST/luci-app-samba-users-files.tar.gz"
ls -la "$DIST/luci-app-samba-users-files.tar.gz"
