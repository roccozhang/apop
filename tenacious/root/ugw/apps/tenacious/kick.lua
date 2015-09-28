local se = require("se")
local log = require("log")  
local mredis = require("mredis")
local js = require("cjson.safe")
local const = require("constant")
local memfile = require("memfile")

local nrds, brds
local keys = const.keys 
local kick_sta_key = "kick_sta_key"
local mf_kick_sta = memfile.ins("kick_sta")

local function cursec()
	return math.floor(se.time())
end

local function clear_timeout_sta(map, cycle) 
	assert(map and map.arr and cycle)

	local narr = {}
	local now = cursec()  

	for _, t in ipairs(map.arr) do  
		local _ = now - t < cycle and table.insert(narr, t) 
	end

	map.arr = narr 
	return map 
end

--[[
每个sta在条件满足后，从第一个时间开始完后滚动，直到时间失效
sta_map = {
	["00:00:00:00:00:01"] = {arr = {time1, time2}, begin = xxx/nil},
	...
}
]]
local function kick(sta_mac)
	assert(#sta_mac == 17)
	do return end -- TODO 
	local sta_map = mf_kick_sta:get(kick_sta_key) or mf_kick_sta:set(kick_sta_key, {}):get(kick_sta_key)
	local max_kick = tonumber(nrds:get(keys.cfg_ld_kick_num)) 	assert(max_kick)
	local cycle = tonumber(nrds:get(keys.cfg_ld_kick_cycle)) 	assert(cycle) 
	local map = sta_map[sta_mac] 
	map = map and clear_timeout_sta(map, cycle) or {arr = {}, begin = nil} 
	
	assert(not map.begin)

	table.insert(map.arr, cursec())
	if #map.arr >= max_kick then 
		log.debug("too many kicks %s %s %s, begin through", #map.arr, max_kick, sta_mac)
		map.begin = map.arr[1]
	end

	sta_map[sta_mac] = map 
	local ret = mf_kick_sta:set(kick_sta_key, sta_map):save() 	assert(ret) 
end

local function should_pass(sta_mac)
	assert(#sta_mac == 17)
	do return false end -- TODO 
	local sta_map = mf_kick_sta:get(kick_sta_key)
	if not sta_map then 
		return false 
	end 

	local map = sta_map[sta_mac] 
	if not (map and map.begin) then 
		return false  	-- 次数不够, 或者没被踢过
	end

	local now = cursec()
	local cycle = tonumber(nrds:get(keys.cfg_ld_kick_cycle)) 	assert(cycle)

	if now - map.begin < cycle then 
		log.debug("sta_mac %s %s %s should pass directly %s", now - map.begin, cycle, sta_mac, js.encode(map))
		return true 
	end

	log.debug("kick alg for %s timeout, clear. %s", sta_mac, js.encode(map))

	-- 周期已经结束，清理
	sta_map[sta_mac] = nil
	local ret = mf_kick_sta:set(kick_sta_key, sta_map):save() 	assert(ret)

	return false
end

local function clear_timeout()
	while true do
		local nsta_map = {}
		local sta_map = mf_kick_sta:get(kick_sta_key)
		if not sta_map then 
			return 
		end 

		local cycle = tonumber(nrds:get(keys.cfg_ld_kick_cycle)) 	assert(cycle)

		for sta_mac, map in pairs(sta_map) do 
			local nmap = clear_timeout_sta(map, cycle)
			local _ = #nmap.arr == 0 and print("empty kick arr for", sta_mac, "remove")
			nsta_map[sta_mac] = #nmap.arr > 0 and nmap or nil
		end

		local ret = mf_kick_sta:set(kick_sta_key, nsta_map):save() 	assert(ret)
		se.sleep(10)
	end
end

local function start()
	nrds, brds = mredis.normal_rds(), mredis.blpop_rds()		assert(nrds and brds)
	se.go(clear_timeout)
end

return {
	kick = kick,
	start = start,
	should_pass = should_pass, 
}
