all:
	$(CC) luv.c -fPIC -shared -o luv.so -I../../../lua53/lua-5.3.1/src/ -L$(LUA_SO_DIR) -llua53 -I$(LIBUV_INC) -L$(LIBUV_LIB) -luv 