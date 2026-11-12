#!/bin/sh
# luci-app-samba-users - one-command online install (OpenWrt 25.12)
#
# On the router:
#   sh -c "$(wget -qO- https://raw.githubusercontent.com/Raduq91/luci-app-samba-users/main/scripts/online-install.sh | tr -d '\r')"

set -e

REPO="${REPO:-Raduq91/luci-app-samba-users}"
BRANCH="${BRANCH:-main}"
VERSION="${VERSION:-latest}"
TMP="${TMPDIR:-/tmp}/luci-samba-users-$$"
ASSET="luci-app-samba-users-files.tar.gz"

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v wget >/dev/null 2>&1 || die "wget not found"
command -v tar >/dev/null 2>&1 || die "tar not found"

rm -rf "$TMP"
mkdir -p "$TMP"
cd "$TMP" || die "cannot cd to $TMP"

log "Repo: $REPO  version: $VERSION"

API="https://api.github.com/repos/${REPO}/releases/${VERSION}"
URL=""
if html=$(wget -qO- "$API" 2>/dev/null); then
	URL=$(printf '%s\n' "$html" | sed -n "s/.*\"browser_download_url\": *\"\([^\"]*${ASSET}\)\".*/\1/p" | head -n 1)
fi
if [ -z "$URL" ]; then
	URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/dist/${ASSET}"
	log "No release asset found, using branch file"
fi

log "Downloading: $URL"
wget -O "$ASSET" "$URL" || die "download failed"
[ -s "$ASSET" ] || die "downloaded file is empty"

log "Extracting to / ..."
tar -C / -xzf "$ASSET" || die "extract failed"

# Critical: executable bit + remove old ucode backend
chmod 755 /usr/libexec/rpcd/luci.samba_users 2>/dev/null || true
rm -f /usr/share/rpcd/ucode/samba_users.uc

if [ -x /etc/init.d/rpcd ]; then
	log "Restarting rpcd ..."
	/etc/init.d/rpcd restart
else
	log "WARNING: restart rpcd manually"
fi

log ""
log "Installed luci-app-samba-users."
log "Log out of LuCI and log back in."
log "Open: Services -> Samba Users"
log ""
log "If create user fails, install backend tools:"
log "  apk add ksmbd-utils"
log "  # or: apk add samba4-utils"

rm -rf "$TMP"
