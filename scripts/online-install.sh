#!/bin/sh
# luci-app-samba-users - one-command install
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
command -v tar  >/dev/null 2>&1 || die "tar not found"

rm -rf "$TMP"
mkdir -p "$TMP"
cd "$TMP" || die "cannot cd $TMP"

log "Repo: $REPO"

API="https://api.github.com/repos/${REPO}/releases/${VERSION}"
URL=""
if html=$(wget -qO- "$API" 2>/dev/null); then
	URL=$(printf '%s\n' "$html" | sed -n "s/.*\"browser_download_url\": *\"\([^\"]*${ASSET}\)\".*/\1/p" | head -n 1)
fi
if [ -z "$URL" ]; then
	URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/dist/${ASSET}"
	log "Using branch file: $URL"
fi

log "Downloading..."
wget -O "$ASSET" "$URL" || die "download failed"
[ -s "$ASSET" ] || die "empty download"
log "Size: $(wc -c < "$ASSET") bytes"

log "Extracting to / ..."
tar -C / -xzf "$ASSET" || die "extract failed"

# Always force permissions
chmod 755 /usr/libexec/rpcd/luci.samba_users 2>/dev/null || true
chmod 755 /etc/uci-defaults/80_luci-samba-users 2>/dev/null || true

# Drop any leftover ucode backend
rm -f /usr/share/rpcd/ucode/samba_users.uc

if [ -x /etc/init.d/rpcd ]; then
	log "Restarting rpcd..."
	/etc/init.d/rpcd restart
fi

log ""
log "Installed. Log out of LuCI and log back in."
log "Open: Services -> Samba Users"
log ""
log "Quick check:"
ubus call luci.samba_users list_users 2>/dev/null || log "(ubus list failed - re-login to LuCI)"

rm -rf "$TMP"
