include $(TOPDIR)/rules.mk

PKG_NAME:=netutil
PKG_VERSION:=0.1
PKG_RELEASE:=0

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=
PKG_MAINTAINER:=helloshiki <aquariusye@163.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=Applications
	CATEGORY:=Puppies
	TITLE:=netutil
	DEPENDS:=+liblua
endef

define Package/$(PKG_NAME)/description
	lua binding to network utility functions
endef

define Build/Compile
	$(MAKE) -C netutil LUA_INC=$(BUILD_DIR)/lua-5.1.5/src $(TARGET_CONFIGURE_OPTS)
endef

define Package/$(PKG_NAME)/install  
	$(INSTALL_DIR) $(1)/usr/lib/lua/
	$(INSTALL_BIN) netutil/netutil.so $(1)/usr/lib/lua/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
