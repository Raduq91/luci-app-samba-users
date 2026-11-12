#!/bin/sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
STAGE="/tmp/luci-samba-stage-$$"

rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"

cp -a "$ROOT/root/." "$STAGE/"
mkdir -p "$STAGE/www"
cp -a "$ROOT/htdocs/." "$STAGE/www/"

chmod 755 "$STAGE/usr/libexec/rpcd/luci.samba_users" 2>/dev/null || true
chmod 755 "$STAGE/etc/uci-defaults/"* 2>/dev/null || true

tar --owner=0 --group=0 -C "$STAGE" -czf "$DIST/luci-app-samba-users-files.tar.gz" .
rm -rf "$STAGE"
echo "Wrote $DIST/luci-app-samba-users-files.tar.gz"
tar tzvf "$DIST/luci-app-samba-users-files.tar.gz" | grep -E 'luci.samba|uci-defaults'
