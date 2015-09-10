local online = require("online")
local util = require("myutil")
local js = require("cjson.safe")

local read, write = util.read, util.write 

local method = {}
local mt = {__index = method}

function method.exist_mac(ins, mac)
	return ins.usermap[mac] ~= nil
end

function method.exist_user(ins, name)
	for _, user in pairs(ins.usermap) do 
		if user:get_name() == name then 
			return true 
		end 
	end 
	return false
end

function method.add(ins, mac, ip, name)
	assert(not ins.usermap[mac])
	local user = online.new()
	user:set_mac(mac)
	user:set_ip(ip)
	user:set_name(name)
	ins.usermap[mac], ins.change = user, true
	user:show()
end

function method.load(ins)
	-- TODO check path exist
	local s = read(ins.path)
	if not s then 
		ins.usermap = {}
		return 
	end 
	ins.usermap = js.decode(s) or error("decode fail")
	for _, user in pairs(ins.usermap) do  
		online.setmeta(user)
	end
end

function method.save(ins)
	local s = js.encode(ins.usermap)
	local tmp = ins.path .. ".tmp"
	local _ = write(tmp, s) or error("save fail")
	os.execute(string.format("mv %s %s; sync", tmp, ins.path))
end

function method.show(ins)
	for k, v in pairs(ins.usermap) do 
		print(k, js.encode(v))
	end
end

function method.foreach(ins, cb)
	for _, user in pairs(ins.usermap) do 
		cb(user)
	end 
end

local function new(path)
	local obj = {
		usermap = {}, 
		path = path,
		change = false,
	}
	setmetatable(obj, mt)
	return obj
end

local g_ins = new("online.json")
g_ins:load()

local function ins()
	return g_ins
end 

return {ins = ins}