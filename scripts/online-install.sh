#!/bin/sh
# luci-app-samba-users – one-command online install (OpenWrt 25.12 / apk era)
#
# Usage on the router:
#   sh -c "$(wget -qO- https://raw.githubusercontent.com/Raduq91/luci-app-samba-users/main/scripts/online-install.sh)"
#
# Or with curl:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/Raduq91/luci-app-samba-users/main/scripts/online-install.sh)"
#
# Optional env overrides:
#   REPO=owner/name   BRANCH=main   VERSION=latest
#
# This installs from a GitHub *release* asset (preferred) or from the
# raw files tarball on the default branch. No OpenWrt SDK required on
# the router.

set -e

REPO="${REPO:-Raduq91/luci-app-samba-users}"
BRANCH="${BRANCH:-main}"
VERSION="${VERSION:-latest}"
TMP="${TMPDIR:-/tmp}/luci-samba-users-$$"
NAME="luci-app-samba-users"

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need() {
	command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

need wget
need tar

cleanup() {
	rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$TMP"
cd "$TMP"

# --- resolve download URL ---------------------------------------------------
# Prefer a release asset named luci-app-samba-users-files.tar.gz
# Fall back to raw branch path scripts/../ release packaging.

ASSET="luci-app-samba-users-files.tar.gz"
API="https://api.github.com/repos/${REPO}/releases/${VERSION}"

log "Repo: ${REPO}  version: ${VERSION}"

download_release_asset() {
	# Parse browser_download_url for our asset without jq
	html=$(wget -qO- "$API" 2>/dev/null) || return 1
	url=$(printf '%s' "$html" | sed -n "s/.*\"browser_download_url\":[[:space:]]*\"\\([^\"]*${ASSET}\\)\".*/\\1/p" | head -1)
	[ -n "$url" ] || return 1
	log "Downloading release asset..."
	wget -qO "$ASSET" "$url" || return 1
	return 0
}

download_raw_fallback() {
	# Fallback: fixed path on branch (you must keep this file in the repo)
	url="https://github.com/${REPO}/raw/${BRANCH}/dist/${ASSET}"
	log "Release asset not found; trying ${url}"
	wget -qO "$ASSET" "$url" || die "download failed: $url"
}

if ! download_release_asset; then
	download_raw_fallback
fi

[ -s "$ASSET" ] || die "empty download"

# --- install ----------------------------------------------------------------
log "Extracting to / ..."
tar -C / -xzf "$ASSET"

log "Restarting rpcd ..."
if [ -x /etc/init.d/rpcd ]; then
	/etc/init.d/rpcd restart
else
	log "warning: /etc/init.d/rpcd not found; reboot or restart rpcd manually"
fi

log ""
log "Installed ${NAME}."
log "Log out of LuCI and log back in."
log "Page: Services → Samba Users"
log ""
log "Optional runtime packages (install only what you use):"
log "  apk add ksmbd-utils     # ksmbd"
log "  apk add samba4-utils    # Samba4"
