local lfs = require("lfs")
local log = require("log")
local util = require("myutil")
local online = require("online")
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
	-- user:show()
end

function method.del_mac(ins, mac)
	if ins.usermap[mac] then 
		ins.usermap[mac], ins.change = nil, true
	end
end

function method.del_user(ins, name)
	local del = {}
	for _, user in pairs(ins.usermap) do 
		local _ = user:get_name() == name and table.insert(del, user:get_mac())
	end 
	for _, mac in ipairs(del) do 
		ins.usermap[mac], ins.change = nil, true
	end
	return del
end

function method.load(ins)
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
	print("----------show online")
	for k, v in pairs(ins.usermap) do 
		print(k, js.encode(v))
	end
end

function method.foreach(ins, cb)
	for _, user in pairs(ins.usermap) do 
		cb(user)
	end 
end

function method.set_change(ins, b)
	ins.change = b
end

function method.data(ins)
	return ins.usermap
end

function method.adjust(ins, users)
	local usermap = ins.usermap

	-- remove out of date
	local del = {}
	for mac, item in pairs(usermap) do 
		if not users[mac] then 
			log.debug("%s already deleted in kernel, remove", js.encode(item))
			table.insert(del, mac)
		end
	end

	for _, mac in ipairs(del) do 
		ins:del_mac(mac)
	end 

	-- sync 
	for mac, item in pairs(users) do
		if item.st == 1 then -- online
			local user = usermap[mac] 	assert(user)
			local _ = user:get_ip() ~= item.ip and log.debug("ip change %s->%s", js.encode(user), js.encode(item))
			user:set_jf(item.jf):set_ip(item.ip)
		else 
			ins:del_mac(mac) -- offline
		end
	end 

	ins:set_change(true)
	ins:save()
	print("adjust users from kernel done")
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

local _ = lfs.attributes("/tmp/memfile/") or lfs.mkdir("/tmp/memfile/")
local g_ins = new("/tmp/memfile/online.json")
g_ins:load()

local function ins()
	return g_ins
end 

return {ins = ins}