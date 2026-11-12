#!/bin/sh
set -e
URL="https://raw.githubusercontent.com/Raduq91/luci-app-samba-users/main/htdocs/luci-static/resources/view/samba-users/overview.js"
DEST="/www/luci-static/resources/view/samba-users/overview.js"
mkdir -p "$(dirname "$DEST")"
wget -O "$DEST.tmp" "$URL" || exit 1
# strip CR
tr -d '\r' < "$DEST.tmp" > "$DEST"
rm -f "$DEST.tmp"
wc -c "$DEST"
echo "First lines:"
head -5 "$DEST"
echo "----"
grep -n "DEBUG-v3\|RPC list_users" "$DEST" | head -5
echo "Done. Hard-refresh LuCI (Ctrl+F5) or open private window."
