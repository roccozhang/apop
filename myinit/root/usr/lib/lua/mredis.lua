require("global")
local se = require("se")
local log = require("log")
local nredis = require("nredis")
local js = require("cjson.safe")

local function arr2strarr(karr)
	local arr = {}
	for k, v in ipairs(karr) do 
		table.insert(arr, tostring(v)) 
	end
	return arr 
end

local function map2strarr(kvmap)
	local arr = {}
	for k, v in pairs(kvmap) do
		table.insert(arr, tostring(k))
		table.insert(arr, tostring(v)) 
	end 
	return arr
end

local function check_ret(ins, ret, err)
	if ret then 
		return ret 
	end
	-- if err == "EOF" or err == "Broken pipe" then
	-- 	log.fatal("socket error %s, exit", err)
	-- 	os.exit(-1)
	-- end
	-- local _ = err and log.fatal("error %s", err)
	-- return nil, err 
	-- local _ = err and log.fatal("connection error %s", err)
	-- return nil
	if not err then 
		return nil 
	end 
	local s = ""
	if ins and ins.current_item then 
		s = js.encode(ins.current_item)
	end
	log.fatal("redis error %s %s", err, s)
end

local mt = {}
mt.__index = {
	next_item = function(ins)
		if not ins.current_item then 
			local item = table.remove(ins.cache, 1)
			if item then 
				ins.current_item = item
				local _ = #ins.cache > 100 and log.error("too many cmd %s", #ins.cache)
				return true
			end
		end
		return false
	end,

	-- 实际上已经没用了
	check = function(ins)
		while true do 
			if not ins.current_item then
				ins:next_item()
			end

			se.sleep(0.1)
		end
	end,

	go = function(ins)
		se.go(ins.check, ins)
		ins.check = nil
	end,

	call = function(ins, cmd, ...)
		local args = {...}
		local id = ins.current_id
		ins.current_id = ins.current_id + 1

		-- 按照调用call的顺序，把查询语句缓存起来，每次取一条，查询完毕后，再取下一条
		table.insert(ins.cache, {cmd = cmd, args = args, current_id = id})

		ins:next_item() 	-- 如果当前没有在查询的语句，把cmd设置上，可以马上查询

		while true do 
			local current_item = ins.current_item
			if current_item and current_item.current_id == id then 
				break 
			end
			se.sleep(0.01)
		end

		if ins.isblpop then
			assert(cmd == "blpop" or cmd == "auth")
			-- print(cmd, table.concat(args, " ")) 
		else
			assert(cmd ~= "blpop")
		end 
		local res, err = ins.rds:call(cmd, unpack(args)) 
		ins.current_item = nil
		
		ins:next_item() 	-- 查询完毕，如果查询队列中还有其他的语句，取下一条设置上
		
		return res, err
	end,

	set = function(ins, k, v) 
		return check_ret(ins, ins:call("set", k, tostring(v)))
	end,

	get = function(ins, k)  
		return check_ret(ins, ins:call("get", k))
	end,

	rpush = function(ins, key, val)
		return check_ret(ins, ins:call("rpush", key, tostring(val)))
	end,

	blpop = function(ins, karr, sec)
		local narr = arr2strarr(karr)
		table.insert(narr, tostring(sec))
		return check_ret(ins, ins:call("blpop", unpack(narr)))
	end,

	lpop = function(ins, karr)
		local narr = arr2strarr(karr)
		return check_ret(ins, ins:call("lpop", unpack(narr)))
	end,

	keys = function(ins, pattern)
		return check_ret(ins, ins:call("keys", pattern))
	end,

	mset = function(ins, kvmap)  
		return check_ret(ins, ins:call("mset", unpack(map2strarr(kvmap))))
	end,

	mget = function(ins, karr)
		return check_ret(ins, ins:call("mget", unpack(arr2strarr(karr))))
	end,

	hset = function(ins, hkey, k, v)
		return check_ret(ins, ins:call("hset", hkey, k, tostring(v)))
	end,

	hget = function(ins, hkey, k)
		return check_ret(ins, ins:call("hget", hkey, k))
	end,

	hmset = function(ins, hkey, kvmap)
		return check_ret(ins, ins:call("hmset", hkey, unpack(map2strarr(kvmap))))
	end,

	hmget = function(ins, hkey, karr)
		return check_ret(ins, ins:call("hmget", hkey, unpack(arr2strarr(karr))))
	end,	

	expire = function(ins, key, sec)
		return check_ret(ins, ins:call("expire", key, tostring(sec)))
	end,

	scan = function(ins, cursor, pattern)
		return check_ret(ins, ins:call("scan", tostring(cursor), "match", pattern, "count", "1000"))
	end,

	setnx = function(ins, key, val)
		return check_ret(ins, ins:call("setnx", key, tostring(val)))
	end,

	incr = function(ins, key)
		return check_ret(ins, ins:call("incr", key))
	end,

	del = function(ins, karr)
		return check_ret(ins, ins:call("del", unpack(arr2strarr(karr))))
	end,

	select = function(ins, id)
		return check_ret(ins, ins:call("select", id))
	end,


	rds_addr = function(ins)
		return ins.rds_addr
	end,
}

local function connect(rds_addr, isblpop)
	assert(rds_addr)
	local timeout = {
		connect_timeout = 5,
		read_timeout = 30,
		write_timeout = 30,
	} 
	local rds = nredis.new(rds_addr, timeout)
	local err = rds:connect()
	if err then 
		log.error("connect redis %s fail %s", rds_addr, err)
		return nil, err
	end

	local obj = {rds = rds, current_item = nil, current_id = 0, cache = {}, isblpop = isblpop, rds_addr = rds_addr}
	setmetatable(obj, mt)
	return obj
end

local inscache = {}

local function connect_blpop(rds_addr)
	assert(rds_addr and not inscache["blpop"])
	local ins, err = connect(rds_addr, true)
	if not ins then 
		return nil, err 
	end
	inscache["blpop"] = ins
	return ins
end

local function connect_normal(rds_addr)
	assert(rds_addr and not inscache["normal"])
	local ins, err = connect(rds_addr)
	if not ins then 
		return nil, err 
	end
	inscache["normal"] = ins
	return ins
end

local function blpop_rds()
	return inscache["blpop"]
end

local function normal_rds()
	return inscache["normal"]
end

return {
	connect = connect,
	blpop_rds = blpop_rds,
	normal_rds = normal_rds,
	connect_blpop = connect_blpop,
	connect_normal = connect_normal,
}

