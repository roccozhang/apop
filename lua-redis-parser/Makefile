include $(TOPDIR)/rules.mk

PKG_NAME:=lua-redis-parser
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
	TITLE:=lua-mongoose
	DEPENDS:=+lua53 +liblua
endef

define Package/$(PKG_NAME)/description
	lua-redis-parser
endef

define Build/Compile
	$(MAKE) -C lua-redis-parser LUA53_SO_DIR=$(BUILD_DIR)/lua53/src  LUA_INC=$(BUILD_DIR)/lua-5.1.5/src $(TARGET_CONFIGURE_OPTS)
endef

define Package/$(PKG_NAME)/install  
	$(INSTALL_DIR) $(1)/usr/lib/lua/redis/
	$(INSTALL_BIN) lua-redis-parser/parser.so $(1)/usr/lib/lua/redis/
	$(INSTALL_BIN) lua-redis-parser/parser53.so $(1)/usr/lib/lua/redis/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
