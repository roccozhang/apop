include $(TOPDIR)/rules.mk

PKG_NAME:=lua-struct
PKG_VERSION:=0.2
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=
PKG_MAINTAINER:=roberto

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=Applications
	CATEGORY:=Puppies
	TITLE:=lua-struct
	DEPENDS:=+liblua
endef

define Package/$(PKG_NAME)/description
	Lua struct
endef

define Build/Compile
	$(MAKE) -C struct-0.2 LUA_INC=$(BUILD_DIR)/lua-5.1.5/src $(TARGET_CONFIGURE_OPTS)
endef

define Package/$(PKG_NAME)/install  
	$(INSTALL_DIR) $(1)/usr/lib/lua/
	$(INSTALL_BIN) struct-0.2/struct.so $(1)/usr/lib/lua/ 
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
