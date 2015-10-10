all: 
	$(CC) redis-parser.c -fPIC -shared -o parser53.so -I../../lua53/lua-5.3.1/src/ -L$(LUA53_SO_DIR) -llua53 -D BY_LUA_53=1
	$(CC) redis-parser.c -fPIC -shared -o parser.so -I$(LUA_INC) -L$(LUA_INC) -llua 