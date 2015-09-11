#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <time.h>
#include <string.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h> 

#include "lua.h"
#include "lauxlib.h" 

#include "dump.c"
#define MODULE_NETUTIL "netutil"


static int l_inet_addr(lua_State *L) {
	struct in_addr ia;
	const char *s = luaL_checkstring(L, 1);
	int ret = inet_aton(s, &ia);
	if (!ret) {
		lua_pushnil(L);
		lua_pushstring(L, "invalid ip");
		return 2;
	}
	printf("%u\n", (unsigned int)ia.s_addr);
	lua_pushinteger(L, (unsigned int)ia.s_addr);
	return 1;
}

static int l_ntohl(lua_State *L) {
	unsigned int ip = luaL_checkinteger(L, 1);
	lua_pushinteger(L, ntohl(ip));
	return 1;
}

static int l_in_range(lua_State *L) {
	unsigned int ip1, ip2, ip3;
	const char *s1 = luaL_checkstring(L, 1);
	const char *s2 = luaL_checkstring(L, 2);
	const char *s3 = luaL_checkstring(L, 3);
	
	struct in_addr ia1, ia2, ia3;
	if (!inet_aton(s1, &ia1))
		goto error_ret;
	if (!inet_aton(s2, &ia2))
		goto error_ret;
	if (!inet_aton(s3, &ia3))
		goto error_ret;
	
	ip1 = ntohl(ia1.s_addr);
	ip2 = ntohl(ia2.s_addr);
	ip3 = ntohl(ia3.s_addr);
	if (ip1 >= ip2 && ip1 <= ip3)
		lua_pushboolean(L, 1);
	else 
		lua_pushboolean(L, 0);
	
	return 1;
error_ret:
	lua_pushnil(L);
	lua_pushstring(L, "invalid param");
	return 2;
}

static luaL_Reg reg[] = {
	{ "inet_addr", l_inet_addr },
	{ "ntohl", l_ntohl },
	{ "in_range", l_in_range },
	{ NULL, NULL }
};

LUALIB_API int luaopen_netutil(lua_State *L) { 
	luaL_register(L, MODULE_NETUTIL, reg); 
	lua_pushnil(L);
	lua_setglobal(L, MODULE_NETUTIL); 
	return 1;
}
