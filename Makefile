# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copyright (C) 2025

include $(TOPDIR)/rules.mk

LUCI_TITLE:=Samba / ksmbd User Manager
LUCI_DESCRIPTION:=Manage Samba4 and ksmbd users from LuCI. Creates system accounts by editing /etc/passwd and /etc/group (no shadow-* packages required).
LUCI_DEPENDS:=+luci-base
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-samba-users
PKG_VERSION:=1.1.0
PKG_RELEASE:=1

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
