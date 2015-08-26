#
# Copyright (C) 2006-2015 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=myinit
PKG_VERSION:=2015-08-20
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=
PKG_MAINTAINER:=helloshiki <aquariusye@163.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/myinit
	SECTION:=Applications
	CATEGORY:=Puppies
	TITLE:=self init script
endef

define Package/myinit/description
	myinit system 
endef


define Build/Prepare
	true
endef

define Build/Compile
	true
endef

define Package/myinit/install
	#install -d -m0755 /home/opmt.git/staging_dir/target-mipsel_1004kc+dsp_musl-1.1.10/root-ramips/tmp-chkubus/usr/bin 
	$(CP) -a ./root/* $(1)/
endef

define Package/myinit/postinst
	true
	exit 0
endef

define Package/myinit/prerm
	true
	exit 0
endef

$(eval $(call BuildPackage,myinit))
