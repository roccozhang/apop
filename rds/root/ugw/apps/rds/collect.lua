local se = require("se")
local log = require("log")
local js = require("cjson.safe")
local rds
local group_map = {}

local function cursec()
	return math.floor(se.time())
end

local function set_rds()
	rds:set("collect/ap", js.encode(group_map))
end

local function clear_timeout()
	local change = false
	local now, timeout = cursec(), 30
	for group, active in pairs(group_map) do 
		local d = now - active
		if d >= timeout then 
			group_map[group], change = nil, true
			log.debug("timeout, stop collect %s", group)
		end 
	end

	return true
end

local function update(r, group)
	rds = r

	local change = false
	if not group_map[group] then 
		change = true
		log.debug("start collect %s", group) 
	end

	group_map[group] = cursec()
	change = clear_timeout() and true or change
	local _ = change and set_rds()
end 

local function start()
	while true do
		se.sleep(3)
		local _ = rds and clear_timeout() and set_rds()
	end 
end

return {update = update, start = start}
