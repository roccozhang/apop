local util = require("myutil")
local policy = require("policy")
local js = require("cjson.safe")


local read, write = util.read, util.write 

local method = {}
local mt = {__index = method}

-- add first 
function method.add(ins, pol)
	if ins:exist(pol:get_name()) then 
		return false 
	end 
	
	table.insert(ins.polarr, 1, pol)
	print(111, js.encode(ins.polarr))
	return true
end

function method.del(ins, name)
	if not ins:exist(name) then 
		return 
	end 
	
	local arr = ins.polarr
	for i = 1, #arr do 
		if arr[i]:get_name() == name then 
			table.remove(ins.polarr, i)
			return
		end
	end
end

function method.adjust(ins, name_arr)
	assert(#ins.polarr == #name_arr)
	
	local new_arr, omap = {}, {}
	for _, pol in ipairs(ins.polarr) do 
		local name = pol:get_name()
		assert(not omap[name])
		omap[name] = pol
	end

	for _, name in ipairs(name_arr) do 
		local pol = omap[name] 	assert(pol)
		table.insert(new_arr, pol)
	end
	print(js.encode(new_arr))
	ins.polarr = new_arr
end

function method.find(ins, name)
	local arr = ins.polarr
	for i = 1, #arr do 
		if arr[i]:get_name() == name then 
			return arr[i], i
		end
	end 
end

function method.set(ins, name, pol)
	local o, i = ins:find(name)
	if o then 
		ins.polarr[i] = pol
	end
end

function method.get(ins, name)
	return (ins:find(name))
end

function method.count(ins)
	return #ins.polarr
end

function method.exist(ins, name) 
	for _, v in ipairs(ins.polarr) do 
		if v:get_name() == name then 
			return true 
		end 
	end 
	return false 
end

function method.load(ins)
	-- TODO check path exist
	local s = read(ins.path)
	if not s then 
		ins.polarr = {}
		return 
	end 
	ins.polarr = js.decode(s) or error("decode fail")
	for _, pol in pairs(ins.polarr) do 
		policy.setmeta(pol)
	end
end

function method.save(ins)
	local s = js.encode(ins.polarr)
	local tmp = ins.path .. ".tmp"
	local _ = write(tmp, s) or error("save fail")
	os.execute(string.format("mv %s %s; sync", tmp, ins.path))
end

function method.show(ins)
	for k, v in pairs(ins.polarr) do 
		print(k, js.encode(v))
	end
end

function method.data(ins)
	return ins.polarr
end

function method.check_auto(ins, ip)
	for _, pol in ipairs(ins.polarr) do 
		if pol:in_range(ip) then 
			return pol:get_type() == policy.AUTO
		end
	end
	print("logical error")
	return true
end

local function new(path)
	assert(path)
	local obj = {
		path = path,
		polarr = {},
	}
	setmetatable(obj, mt)
	return obj
end 

local g_ins
local function ins()
	return g_ins
end 

g_ins = new("/etc/config/policy.json")
g_ins:load()

return {
	new = new,	
	ins = ins, 
}
