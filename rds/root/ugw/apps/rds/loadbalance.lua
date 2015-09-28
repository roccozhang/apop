local log = require("log")
local ms = require("moses")
local js = require("cjson.safe")
local const = require("constant")  
local pkey = require("key")

local nrds, pcli
local keys = const.keys

local load_karr = {
	keys.c_g_ld_switch,

	keys.c_tena_switch,
	keys.c_rssi_limit,
	keys.c_flow_limit,
	keys.c_sensitivity,
}

local function get_param(group) 
	local varr = pcli:query(group, load_karr)	assert(varr)
	local kvmap = {}
	for i = 1, #load_karr do 
		local k, v = load_karr[i], varr[i]

		if not v then 
			log.error("missing %s", k)
			return nil, "data lack"
		end

		local kk = k:match(".+#(.+)") or k 
		kvmap[kk] = v
	end

	return kvmap
end 

local function load_balance(conn, group, data)
	nrds, pcli = conn.rds, conn.pcli 	assert(nrds and pcli) 
	local map = get_param(group)
	local res = {
		load_balance = {
			load_enable = 0,
			userbase = 10,
			user_diff = 5,
			rssi_diff = 20,
			priority_5g = 0,
		},
		sta_tenacious = {
			sta_enable = map.wg_tena_switch,
			rssi_limit = map.wg_rssi_limit,
			flow_limit = map.wg_flow_limit,
			sensitivity = map.wg_sensitivity,
		}
	}
	
	return res
end

local function check_num(field, val, min, max)
	val = tonumber(val)

	if not val then
		log.error("invalid %s %s %s %s", field, val or "", min or "", max or "")
		return nil 
	end 

	if min and val < min then 
		log.error("invalid %s %s %s %s", field, val or "", min or "", max or "")
		return nil 
	end

	if max and val > max then 
		log.error("invalid %s %s %s %s", field, val or "", min or "", max or "")
		return nil 
	end

	return true 
end

local load_map = {}

load_map.load_enable = {
	check = function(enable, val, map)
		assert(map)
		local kvmap = map.kvmap
		if check_num("load_map.load_enable", val, 0, 1) then
			kvmap[keys.g_ld_switch] = val
			return true
		end
	end
}

load_map.userbase = {
	check = function(enable, val, map)
		if tostring(enable) == "0" then return true end
		assert(map)
		local kvmap = map.kvmap
		if check_num("load_map.userbase", val, 1, 30) then 
			return true
		end
	end
}

load_map.user_diff = {
	check = function(enable, val, map)
		if tostring(enable) == "0" then return true end
		assert(map)
		local kvmap = map.kvmap
		if check_num("load_map.user_diff", val, 1, 20) then 
			return true
		end
	end
}

load_map.rssi_diff = {
	check = function(enable, val, map)
		if tostring(enable) == "0" then return true end
		assert(map)
		local kvmap = map.kvmap
		if check_num("load_map.rssi_diff", val, 5, 50) then 
			return true
		end
	end
}

load_map.priority_5g = {
	check = function(enable, val, map)
		if tostring(enable) == "0" then return true end
		assert(map)
		local kvmap = map.kvmap
		if check_num("load_map.priority_5g", val, 0, 1) then 
			return true
		end
	end
}

load_map.sta_enable = {
	check = function(enable, val, map)
		assert(map)
		local kvmap = map.kvmap
		if check_num("load_map.sta_enable", val, 0, 1) then
			kvmap[keys.c_tena_switch] = val
			return true
		end
	end
}

load_map.rssi_limit = {
	check = function(enable, val, map)
		if tostring(enable) == "0" then return true end
		assert(map)
		local kvmap = map.kvmap
		if check_num("load_map.rssi_limit", val, -110, -75) then
			kvmap[keys.c_rssi_limit] = val
			return true
		end
	end
}

load_map.flow_limit = {
	check = function(enable, val, map)
		if tostring(enable) == "0" then return true end
		assert(map)
		local kvmap = map.kvmap
		if check_num("load_map.flow_limit", val, 0, 102400) then
			kvmap[keys.c_flow_limit] = val
			return true
		end
	end
}

load_map.sensitivity = {
	check = function(enable, val, map)
		if tostring(enable) == "0" then return true end
		assert(map)
		local kvmap = map.kvmap
		if check_num("load_map.sensitivity", val, 0, 2) then
			kvmap[keys.c_sensitivity] = val
			return true
		end
	end
}


local function cmpobj(old, new, res)
	
	for k, v in pairs(new) do
		if type(v) == "table" then
			res[k] = {}
			cmpobj(old[k], v, res[k])
		else
			if tostring(v) ~= tostring(old[k]) then 
				print("find change", k, old[k], v)
				res[k] = v
			end
		end
	end
end

local function get_change(newedit, obj)
	local res = {}
	cmpobj(obj, newedit, res)
	return res
end

local function save_load_sta(conn, data, str)
	assert(conn and conn.rds and data)
	nrds = conn.rds  			assert(nrds)
	
	local map = data
	if not (map and map.data and map.oldData) then 
		log.error("error data %s", data)
		return false
	end
	
	local nmap, omap = map.data[str], map.oldData[str]
	local modify_map = get_change(nmap, omap)
	
	-- 判断 不启用不修改 
	local enable
	if str == "load_balance" then
		enable = nmap.load_enable
	else
		enable = nmap.sta_enable
	end
	
	local kvmap = {}
	for field, item in pairs(load_map) do 
		local val = modify_map[field]
		if val and not item.check(enable, val, {kvmap = kvmap, nmap = nmap}) then 
			log.error("check param fail")
			return false
		end
	end
	
	return kvmap
end

local function save_load_balance(conn, group, data)
	nrds, pcli = conn.rds, conn.pcli 	assert(nrds and pcli) 

	local kvmap = save_load_sta(conn, data, "load_balance")
	local tmp_map = save_load_sta(conn, data, "sta_tenacious")
	
	if not (kvmap and tmp_map) then 
		return {status = 1, data = "error"} 
	end

	for k, v in pairs(tmp_map) do
		kvmap[k] = v
	end
	
	if ms.count(kvmap) == 0 then 
		log.debug("nothing changed")
		return {status = 0, data = "ok"} 
	end
	
	local res = conn.pcli:modify({cmd = "set_load", data = {group = group, map = kvmap}})
	if res then 
		return {status = 0, data = "ok"} 
	end 
	return {status = 1, data = "modify fail"} 
end


return {
	load_balance = load_balance,
	save_load_balance = save_load_balance,
}