#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include "lua.h"
#include "lauxlib.h"
#include "mongoose.h"  

#include "dump.c"

#define MODULE_HTTPAUTH "httpauth"
#define META_HTTPAUTH	"httpauth{obj}"
#define META_CONN		"conn{obj}"

struct httpserver {
	struct mg_server *server;
};

struct connection {
	struct mg_connection *conn;
};

static int l_conn_uri(lua_State *L) {
	const char *msg;
	struct connection *user_conn;
	user_conn = (struct connection *)luaL_checkudata(L, 1, META_CONN);
	if (!user_conn) {
		msg = "invalid user_conn";
		goto error_ret;
	}
	if (user_conn->conn->uri)
		lua_pushfstring(L, "%s", user_conn->conn->uri);
	else 
		lua_pushnil(L);
	return 1;
error_ret:
	lua_pushnil(L);
	lua_pushfstring(L, "%s", msg);
	return 2;
}
static int l_conn_remote_ip(lua_State *L) {
	const char *msg;
	struct connection *user_conn;
	user_conn = (struct connection *)luaL_checkudata(L, 1, META_CONN);
	if (!user_conn) {
		msg = "invalid user_conn";
		goto error_ret;
	}
	if (user_conn->conn->remote_ip)
		lua_pushfstring(L, "%s", user_conn->conn->remote_ip);
	else 
		lua_pushnil(L);
	return 1;
error_ret:
	lua_pushnil(L);
	lua_pushfstring(L, "%s", msg);
	return 2;
}
static int l_conn_write(lua_State *L) {
	int ret = 0;
	const char *str;
	const char *msg;
	struct connection *user_conn;
	user_conn = (struct connection *)luaL_checkudata(L, 1, META_CONN);
	if (!user_conn) {
		msg = "invalid user_conn";
		goto error_ret;
	}
	
	str = lua_tostring(L, 2);
	if (!str) {
		msg = "invalid write content";
		goto error_ret;
	} 
	ret = mg_printf_data(user_conn->conn, "%s", str);
	lua_pushinteger(L, ret);
	return 1;
error_ret:
	lua_pushnil(L);
	lua_pushfstring(L, "%s", msg);
	return 2;
}

static int l_conn_addr(lua_State *L) {
	const char *msg;
	struct connection *user_conn;
	user_conn = (struct connection *)luaL_checkudata(L, 1, META_CONN);
	if (!user_conn) {
		msg = "invalid user_conn";
		goto error_ret;
	}
	lua_pushfstring(L, "%p", user_conn->conn);
	return 1;
error_ret:
	lua_pushnil(L);
	lua_pushfstring(L, "%s", msg);
	return 2;
}
static int l_conn_get(lua_State *L) {
	int ret;
	const char *key;
	const char *msg;
	static char varbuff[1024];
	struct connection *user_conn;
	user_conn = (struct connection *)luaL_checkudata(L, 1, META_CONN);
	if (!user_conn) {
		msg = "invalid user_conn";
		goto error_ret;
	}
	key = lua_tostring(L, 2);
	if (!key) {
		msg = "invalid param";
		goto error_ret;
	}

	mg_get_var(user_conn->conn, key, varbuff, sizeof(varbuff));
	ret = strlen(varbuff);
	if (!ret)
		lua_pushnil(L);
	else 
		lua_pushlstring(L, varbuff, ret);
	return 1;
error_ret:
	lua_pushnil(L);
	lua_pushfstring(L, "%s", msg);
	return 2;
}

static int ev_handler(struct mg_connection *conn, enum mg_event ev) {
	if (!(conn && conn->uri) || strncmp(conn->uri, "/cgi.", 5))
		return MG_FALSE; 
	lua_State *L = (lua_State *)conn->server_param;
	lua_getfenv(L, 1);
	lua_rawgeti(L, -1, 1);
	lua_remove(L, -2);
	struct connection *user_conn = lua_newuserdata(L, sizeof(struct connection));
	if (!user_conn)
		fprintf(stderr, "lua_newuserdata fail\n"), exit(-1);
	user_conn->conn = conn;
	luaL_getmetatable(L, META_CONN);
	lua_setmetatable(L, -2);
	lua_pushinteger(L, ev);
	int ret = lua_pcall(L, 2, 1, 0);
	if (ret) {
		fprintf(stderr, "lua_pcall fail %s\n", lua_tostring(L, 2));
		goto error_pop;
	}
	if (!lua_isnumber(L, 2)) {
		fprintf(stderr, "return value is not number %s\n", lua_typename(L, lua_type(L, 2)));
		goto error_pop;
	}
	ret = lua_tointeger(L, 2);
	if (ret < 0 || ret > 2) {
		fprintf(stderr, "return value is invalid %d\n", ret);
		goto error_pop;
	}
	lua_pop(L, 1);
	return ret;
error_pop:
	lua_pop(L, 1);
	return MG_FALSE; 
}

static int l_set_ev_handler(lua_State *L) {
	const char *msg; 
	struct httpserver *hs = (struct httpserver *)luaL_checkudata(L, 1, META_HTTPAUTH);
	if (!hs || !hs->server) {
		msg = "invalid userdata";
		goto error_ret;
	}
	if (0 == lua_isfunction(L, 2)) {
		msg = "param 1 is not function";
		goto error_ret;
	}
	lua_getfenv(L, 1);
	lua_pushvalue(L, 2);
    lua_rawseti(L, -2, 1);
	return 0;
error_ret:
	lua_pushnil(L);
	lua_pushfstring(L, "%s", msg);
	return 2;
}

static int l_create_server(lua_State *L) {
	const char *msg = NULL;
	struct httpserver *hs = NULL;
	struct mg_server *server = NULL;
	hs = (struct httpserver*)lua_newuserdata(L, sizeof(struct httpserver));
	memset(hs, 0, sizeof(struct httpserver));
	server = mg_create_server(L, ev_handler);
	if (!hs || !server) {
		msg = "mg_create_server fail";
		goto error_ret;
	}
	hs->server = server; 
	luaL_getmetatable(L, META_HTTPAUTH);
	lua_setmetatable(L, -2);
	lua_createtable(L, 1, 0);
    lua_setfenv(L, -2);
	return 1;
error_ret:
	if (server) 
		mg_destroy_server(&server);
	lua_pushnil(L);
	lua_pushfstring(L, "%s", msg);
	return 2;
}

static int l_set_option(lua_State *L) {
	const char *msg, *key, *val; 
	struct httpserver *hs = (struct httpserver *)luaL_checkudata(L, 1, META_HTTPAUTH);
	if (!hs || !hs->server) {
		msg = "invalid userdata";
		goto error_ret;
	}
	key = lua_tostring(L, 2);
	val = lua_tostring(L, 3);
	if (!key || !val) {
		msg = "invalid key or val";
		goto error_ret;
	}
	mg_set_option(hs->server, key, val);
	lua_pushboolean(L, 1);
	return 1;
error_ret:
	lua_pushnil(L);
	lua_pushfstring(L, "%s", msg);
	return 2;
}

static int l_get_option(lua_State *L) {
	const char *msg, *key, *val; 
	struct httpserver *hs = (struct httpserver *)luaL_checkudata(L, 1, META_HTTPAUTH);
	if (!hs || !hs->server) {
		msg = "invalid userdata";
		goto error_ret;
	}
	key = lua_tostring(L, 2);
	if (!key) {
		msg = "invalid key";
		goto error_ret;
	}
	val = mg_get_option(hs->server, key);
	if (val)
		lua_pushfstring(L, "%s", val);
	else 
		lua_pushnil(L);
	return 1;
error_ret:
	lua_pushnil(L);
	lua_pushfstring(L, "%s", msg);
	return 2;
}

static int l_poll_server(lua_State *L) {
	int ms;
	const char *msg; 
	struct httpserver *hs = (struct httpserver *)luaL_checkudata(L, 1, META_HTTPAUTH);
	if (!hs || !hs->server) {
		msg = "invalid userdata";
		goto error_ret;
	}
	ms = lua_tointeger(L, 2);
	if (ms <= 0)
		ms = 1000;
	lua_settop(L, 1); 
	mg_poll_server(hs->server, ms);
	return 0;
error_ret:
	lua_pushnil(L);
	lua_pushfstring(L, "%s", msg);
	return 2;
}

static int l_destroy_server(lua_State *L) {
	struct httpserver *hs = (struct httpserver *)luaL_checkudata(L, 1, META_HTTPAUTH);
	if (!hs)
		return 0;
	if (hs->server)
		mg_destroy_server(&hs->server);
	hs->server = NULL;
	return 0;
}

static luaL_Reg fns[] = { 
	{ "set_option", 	l_set_option }, 
	{ "get_option", 	l_get_option }, 
	{ "poll_server", 	l_poll_server }, 
	{ "set_ev_handler",	l_set_ev_handler }, 
	{ "destroy_server", l_destroy_server }, 
	{ "__gc", 			l_destroy_server }, 
	{ NULL, NULL }
};

static luaL_Reg reg[] = {
	{ "create_server", l_create_server }, 
	{ NULL, NULL }
};

static luaL_Reg conn_fns[] = {
	{ "uri", l_conn_uri }, 
	{ "remote_ip", l_conn_remote_ip }, 
	{ "write", l_conn_write }, 
	{ "get", l_conn_get }, 
	{ "addr", l_conn_addr }, 
	{ NULL, NULL }
}; 

static void create_metatable(lua_State *L, luaL_Reg *reg, const char *mt_name, int pop) {
	luaL_newmetatable(L, mt_name);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	luaL_register(L, NULL, reg);
	if (pop)
		lua_pop(L, 1);
}

struct constant {
	const char *key;
	int val;
};

static struct constant s_const[] = {
	{"MG_FALSE", MG_FALSE},
	{"MG_TRUE", MG_TRUE},
	{"MG_MORE", MG_MORE},
	{"MG_POLL", MG_POLL},
	{"MG_CONNECT", MG_CONNECT},
	{"MG_AUTH", MG_AUTH},
	{"MG_REQUEST", MG_REQUEST},
	{"MG_REPLY", MG_REPLY},
	{"MG_CLOSE", MG_CLOSE},
	{"MG_WS_HANDSHAKE", MG_WS_HANDSHAKE},
	{"MG_WS_CONNECT", MG_WS_CONNECT},
	{"MG_HTTP_ERROR", MG_HTTP_ERROR},
	{NULL, 0}
};
static void register_constant(lua_State *L) {
	int i;
	for (i = 0; s_const[i].key; i++) {
		lua_pushstring(L, s_const[i].key);
		lua_pushinteger(L, s_const[i].val);
		lua_rawset(L, -3);
	}
}

LUALIB_API int luaopen_mongoose(lua_State *L) {
	create_metatable(L, fns, META_HTTPAUTH, 1);
	create_metatable(L, conn_fns, META_CONN, 1);
	luaL_register(L, MODULE_HTTPAUTH, reg);
	register_constant(L);	
	lua_pushnil(L);
	lua_setglobal(L, MODULE_HTTPAUTH); 
	return 1;
}
