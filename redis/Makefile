include $(TOPDIR)/rules.mk

PKG_NAME:=redis
PKG_VERSION:=0.2
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=
PKG_MAINTAINER:=

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)
SRC_DIR=redis-3.0.4
include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=Applications
	CATEGORY:=Puppies
	TITLE:=redis
endef

define Package/$(PKG_NAME)/description
	redis
endef

define Build/Compile
	$(MAKE) -C $(SRC_DIR) $(TARGET_CONFIGURE_OPTS)
endef

define Package/$(PKG_NAME)/install  
	$(INSTALL_DIR) $(1)/usr/sbin 
	$(INSTALL_BIN) $(SRC_DIR)/src/redis-cli $(1)/usr/sbin
	$(INSTALL_BIN) $(SRC_DIR)/src/redis-server $(1)/usr/sbin
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
