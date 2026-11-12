#!/bin/sh
# Remove luci-app-samba-users files from the router.
# Usage:
#   sh -c "$(wget -qO- https://raw.githubusercontent.com/Raduq91/luci-app-samba-users/main/scripts/online-uninstall.sh | tr -d '\r')"

set -e

log() { printf '%s\n' "$*"; }

log "Removing luci-app-samba-users ..."

rm -f /usr/share/rpcd/ucode/samba_users.uc
rm -f /usr/share/rpcd/acl.d/luci-app-samba-users.json
rm -f /usr/share/luci/menu.d/luci-app-samba-users.json
rm -f /etc/uci-defaults/80_luci-samba-users
rm -rf /www/luci-static/resources/view/samba-users

if [ -x /etc/init.d/rpcd ]; then
	log "Restarting rpcd ..."
	/etc/init.d/rpcd restart
fi

log "Uninstalled. Log out of LuCI and log back in."
log "Note: Samba/ksmbd users and system accounts were NOT deleted."
