#!/bin/sh
# Quick install script for development / testing on a live OpenWrt device.
# Usage: ./install.sh [router-ip]
# Default IP: 192.168.1.1

set -e

TARGET="${1:-192.168.1.1}"
ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "Installing luci-app-samba-users to $TARGET ..."

scp -r "$ROOT/root/"* "root@${TARGET}:/"
scp -r "$ROOT/htdocs/"* "root@${TARGET}:/www/"

ssh "root@${TARGET}" <<'EOF'
	chmod 755 /usr/share/rpcd/ucode/samba_users.uc 2>/dev/null || true
	/etc/init.d/rpcd restart
	echo "rpcd restarted. Log out of LuCI and log back in to see Services → Samba Users."
EOF

echo "Done."
