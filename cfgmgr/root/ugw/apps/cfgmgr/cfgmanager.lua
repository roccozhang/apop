local log = require("log")
local lfs = require("lfs")
local js = require("cjson.safe")

local base_dir = "/etc/config"
local ins_map = {}

local function read(path, func)
	func = func and func or io.open
	local fp = func(path, "rb")
	if not fp then 
		return 
	end 
	local s = fp:read("*a")
	fp:close()
	return s
end

local function recover_default(path)
	local cmd = string.format("cp %s %s", "/etc/config/default_config.json", path)
	log.debug("%s", cmd)
	local ret = os.execute(cmd) 	assert(ret)
	local s = read(path) 			assert(s)
	local map = js.decode(s) 		assert(map)
	return map
end

local function list_files(dir)
	local filearr = {}
	for path in lfs.dir(dir) do 
		local file = path:match("(m%.json%.%d+)")
		if file then
			local id = tonumber(file:match(".+%.(%d+)"))
			table.insert(filearr, {file, id})
		end
	end
	table.sort(filearr, function(a, b) return a[2] > b[2] end)
	return filearr
end

local function load_parse(dir, path)
	local map = js.decode(read(path))
	if map then
		return map 
	end

	log.error("read_parse %s fail. remove", path)
	os.rename(path, path .. ".error." .. os.time())

	while true do
		local arr = list_files(dir)
		if #arr == 0 then 
			return {}
		end
		local cmd = string.format("mv %s/%s %s", dir, arr[1][1], path)
		log.debug("%s", cmd)
		local ret = os.execute(cmd) 	assert(ret)
		local map = js.decode(read(path))
		if map then
			return map 
		end
		log.error("read_parse %s fail", path)
	end
end

local mt = {}
mt.__index = {
	load = function(ins)
		local dir = string.format("%s/%s", base_dir, ins.spec)
		local path = string.format("%s/m.json", dir)

		if lfs.attributes(path) then 
			ins.kvmap = load_parse(dir, path)
			if ins.kvmap then 
				return -- 加载成功
			end
			-- 加载失败
		end
		
		local _ = lfs.attributes(dir) or lfs.mkdir(dir) 			assert(lfs.attributes(dir)) 		
		ins.kvmap = recover_default(path) 	-- 回复全局默认配置
	end,

	get = function(ins, k)
		return ins.kvmap[k]
	end,

	set = function(ins, k, new)
		new = type(new) == 'number' and tostring(new) or new 
		local _ = new and assert(type(new) == "string", js.encode({k, new})) 
		
		local old = ins.kvmap[k]

		if new and old then
			if new == old then 
				return false 
			end 
			local _ = #new < 200 and log.info("%s %s->%s", k, old, new)
			ins.kvmap[k], ins.change = new, true 
			return true 
		end
		
		if new and not old then 
			log.info("add new %s %s", k, new)
			ins.kvmap[k], ins.change = new, true 
			return true 
		end 

		if not new and old then 
			log.info("delete %s %s", k, old)
			ins.kvmap[k], ins.change = nil, true 
			return true 
		end 

		return false
	end,

	save = function(ins)
		if not ins.change then 
			return 
		end 

		ins.change = false 

		local s = js.encode(ins.kvmap)
		s = s:gsub(',"', ',\n"')

		local dir = string.format("%s/%s", base_dir, ins.spec)
		local path = string.format("%s/m.json", dir)

		local tmp = path .. ".tmp"
		local fp, err = io.open(tmp, "wb")
		fp:write(s)
		fp:flush()
		fp:close()

		local maxid = 0
		local arr = list_files(dir)
		maxid = #arr == 0 and 1 or arr[1][2]

		if lfs.attributes(path) then
			local bak = string.format("%s.%d", path, maxid + 1)
			local ret, err = os.rename(path, bak)
			local _ = ret or log.fatal("rename %s %s fail %s", path, bak, err)
		end

		local ret, err = os.rename(tmp, path)
		local _ = ret or log.fatal("rename %s %s fail %s", tmp, path, err)
		
		log.debug("save ok %s", path)

		for i = 1, 2 do 
			table.remove(arr, 1)
		end

		for _, item in ipairs(arr) do 
			os.remove(dir .. "/" .. item[1])
		end
	end,
}

local function new(spec)
	local obj = {spec = spec, kvmap = nil, change = false}
	setmetatable(obj, mt)
	obj:load()
	return obj
end

local function ins(spec)
	assert(spec)
	local ins = ins_map[spec]
	if not ins then 
		ins_map[spec] = new(spec)
		ins = ins_map[spec]
	end
	return ins
end

local function save_all()
	for _, ins in pairs(ins_map) do 
		ins:save()
	end
end

return {ins = ins, save_all = save_all} 