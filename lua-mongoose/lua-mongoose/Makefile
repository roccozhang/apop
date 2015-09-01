all:
	$(CC) -fPIC -shared *.c -o mongoose.so -I$(LUA_INC) -L$(LUA_INC) -llua -DMONGOOSE_NO_AUTH 
	#-I$(MONGOOSE_INC)