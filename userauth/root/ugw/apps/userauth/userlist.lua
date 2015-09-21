local usr = require("user")
local util = require("myutil")
local js = require("cjson.safe")

local read, write = util.read, util.write 

local method = {}
local mt = {__index = method}

function method.add(ins, user)
	local name = user:get_name()
	if ins:exist(name) then 
		return false 
	end 
	ins.usermap[name], ins.change = user, true
	return true
end

function method.del(ins, user)	
	ins.usermap[type(user) == "string" and user or user:get_name()] = nil
	ins.change = true
end

function method.set(ins, name, user)
	if not ins.usermap[name] then 
		return 
	end
	ins.usermap[name], ins.change = user, true
end

function method.get(ins, user)
	return ins.usermap[user]
end

function method.exist(ins, user)
	return ins:get(user) ~= nil
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
		usr.setmeta(user)
	end
end

function method.save(ins)
	if not ins.change then 
		return
	end 
	ins.change = false
	local s = js.encode(ins.usermap)
	local tmp = ins.path .. ".tmp"
	local _ = write(tmp, s) or error("save fail")
	os.execute(string.format("mv %s %s; sync", tmp, ins.path))
end

function method.show(ins)
	print("----------show userlist")
	for k, v in pairs(ins.usermap) do 
		print(k, js.encode(v))
	end
end

function method.data(ins)
	return ins.usermap
end

function method.filter(ins, match)
	local res = {}
	for k, v in pairs(ins.usermap) do 
		if match(v) then 
			res[k] = v
		end
	end 
	return res
end

function method.set_change(ins, b)
	ins.change = b 
end

local function new(path)
	assert(path)
	local obj = {
		path = path,
		usermap = {},
		change = false,
	}
	setmetatable(obj, mt)
	return obj
end 

local g_ins = new("/etc/config/user.json")
g_ins:load()
local function ins()
	return g_ins
end

return {ins = ins}
