all:
	$(CC) luv.c -fPIC -shared -o uv.so -I$(LUA_INC) -llua -I$(LIBUV_INC) -L$(LIBUV_LIB) -luv 