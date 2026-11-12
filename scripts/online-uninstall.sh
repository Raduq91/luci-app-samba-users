#!/bin/sh
# Remove luci-app-samba-users
set -e
log() { printf '%s\n' "$*"; }
log "Removing luci-app-samba-users ..."
rm -f /usr/libexec/rpcd/luci.samba_users
rm -f /usr/share/rpcd/ucode/samba_users.uc
rm -f /usr/share/rpcd/acl.d/luci-app-samba-users.json
rm -f /usr/share/luci/menu.d/luci-app-samba-users.json
rm -f /etc/uci-defaults/80_luci-samba-users
rm -rf /www/luci-static/resources/view/samba-users
[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart
log "Uninstalled. Log out of LuCI and log back in."
log "Samba/ksmbd users and system accounts were NOT deleted."
