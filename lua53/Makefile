include $(TOPDIR)/rules.mk

PKG_NAME:=lua53
PKG_VERSION:=0.2
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=
PKG_MAINTAINER:=

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)
SRC_DIR=lua-5.3.1
include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=Applications
	CATEGORY:=Puppies
	TITLE:=lua 5.3.1
endef

define Package/$(PKG_NAME)/description
	lua 5.3.1
endef

define Build/Compile
	$(MAKE) -C $(SRC_DIR) linux $(TARGET_CONFIGURE_OPTS)
endef

define Package/$(PKG_NAME)/install  
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_DIR) $(1)/usr/lib
	cd $(SRC_DIR)/src/ && cp lua53 $(1)/usr/sbin/
	cd $(SRC_DIR)/src/ && cp liblua53.so $(1)/usr/lib/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
