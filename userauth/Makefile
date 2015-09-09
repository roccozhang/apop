#
# Copyright (C) 2006-2015 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=userauth
PKG_VERSION:=2015-08-20
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=
PKG_MAINTAINER:=helloshiki <aquariusye@163.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=Applications
	CATEGORY:=Puppies
	TITLE:=user auth daemon
endef

define Package/$(PKG_NAME)/description
	user auth daemon
endef


define Build/Prepare
	true
endef

define Build/Compile
	true
endef

define Package/$(PKG_NAME)/install
	$(CP) -a ./root/* $(1)/
endef

define Package/$(PKG_NAME)/postinst
	true
	exit 0
endef

define Package/$(PKG_NAME)/prerm
	true
	exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
