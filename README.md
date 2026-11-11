# luci-app-samba-users

LuCI application to manage **Samba4** and/or **ksmbd** users from the web UI.

## Highlights

* **No shadow-* packages required** – system accounts are created by editing `/etc/passwd` and `/etc/group` directly (same approach as the OpenWrt wiki).
* Supports **both** backends:
  * ksmbd → `ksmbd.adduser` (from `ksmbd-utils`)
  * Samba4 → `smbpasswd` / `pdbedit` (from `samba4-utils`)
* Automatic free UID/GID (≥ 1000), locked shell (`/bin/false`), no home directory
* Password never placed on a long-lived command line (temp file + short-lived shell)
* Restricted rpcd methods only – no arbitrary shell execution
* List / add / change password / remove

## Dependencies

**Hard dependency (package):** only `luci-base`.

**Runtime (install what you use):**

| Backend | Package needed for passwords |
|---------|------------------------------|
| ksmbd   | `ksmbd-utils` (provides `ksmbd.adduser`) |
| Samba4  | `samba4-utils` (provides `smbpasswd`) |

You already have the server itself (`luci-app-ksmbd` / `ksmbd-server` or `luci-app-samba4` / `samba4-server`).

## Space comparison (shadow packages)

Approximate installed sizes on a typical OpenWrt target:

| Package            | Installed size (approx.) |
|--------------------|--------------------------|
| shadow-common      | ~20–40 KB                |
| shadow-useradd     | ~32–38 KB                |
| shadow-userdel     | ~24–26 KB                |
| shadow-groupadd    | ~20–25 KB                |
| **Total if all used** | **~100–130 KB**       |

This version avoids those packages entirely, so you save roughly **100–130 KB** of flash compared with a design that depends on them. The LuCI app itself is a few tens of KB of JS + ucode.

## Install (development)

```sh
./install.sh 192.168.1.1
# or manually:
scp -r root/* root@192.168.1.1:/
scp -r htdocs/* root@192.168.1.1:/www/
ssh root@192.168.1.1 "/etc/init.d/rpcd restart"
```

Then log out of LuCI and back in. Page: **Services → Samba Users**.

## Security notes

* ACL grants only the five methods this app needs.
* Protected accounts (`root`, `nobody`, `daemon`) cannot be removed.
* Username validation: `^[a-z_][a-z0-9_-]*$` (1–32 chars).
* System user lines look like:  
  `foo:x:1001:1001:smb user:/dev/null:/bin/false`

## Licence

GPL-2.0-or-later

## One-command install (SSH)

After you push this repo to GitHub and attach
`dist/luci-app-samba-users-files.tar.gz` to a Release (or keep it under `dist/`
on the default branch):

```sh
# Replace YOUR_USER/luci-app-samba-users with your repo
sh -c "$(wget -qO- https://raw.githubusercontent.com/YOUR_USER/luci-app-samba-users/main/scripts/online-install.sh)"
```

Optional:

```sh
REPO=you/luci-app-samba-users VERSION=latest \
  sh -c "$(wget -qO- https://raw.githubusercontent.com/you/luci-app-samba-users/main/scripts/online-install.sh)"
```

The script downloads the files tarball, extracts to `/`, and restarts `rpcd`.
Then log out of LuCI and open **Services → Samba Users**.

### Maintainers: publish a release asset

```sh
./scripts/make-dist.sh
# upload dist/luci-app-samba-users-files.tar.gz to the GitHub Release
# keep scripts/online-install.sh on the default branch (raw URL)
```

Set `REPO` inside `scripts/online-install.sh` (default placeholder
`YOUR_GITHUB_USER/luci-app-samba-users`) or pass `REPO=...` when running.
