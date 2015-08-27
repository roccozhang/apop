local js = require("cjson.safe")
local md5path = "/backup/md5.json"
local map = {}

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

local function load()
	local s = read(md5path) or "{}"
	map = js.decode(s) or {}
end

local function save()
	local tmp = md5path .. ".tmp"
	local fp = io.open(tmp, "wb")
	local s = js.encode(map):gsub('","', '",\n"')
	fp:write(s)
	fp:flush()
	fp:close()
	local cmd = string.format("mv %s %s", tmp, md5path)
	os.execute(cmd)
end

local function get(path)
	return map[path]
end

local function set(path, md5)
	assert(#md5 == 32)
	map[path] = md5
end

load()
return {set = set, get = get, save = save}

