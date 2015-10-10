local log = require("log")
local ms = require("moses")
local js = require("cjson.safe")
local const = require("constant")  
local pkey = require("key")

local nrds, pcli
local keys = const.keys

local optimal_karr = {
	keys.c_ag_rs_switch,
	keys.c_ag_rs_rate,
	keys.c_ag_rs_mult,
	keys.c_rs_iso,
	keys.c_rs_inspeed,
}

local function get_param(group)
	local varr = pcli:query(group, optimal_karr) 	assert(varr) 
	local kvmap = {}
	for i = 1, #optimal_karr do 
		local k, v = optimal_karr[i], varr[i]

		if not v then 
			log.error("missing %s", k)
			return nil, "param lack"
		end

		kvmap[k] = v
	end

	return kvmap
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

local optimal_map = {}
optimal_map.enable = {
	check = function(val, map)
		assert(map)
		local kvmap = map.kvmap
		if check_num("optimal_map.rs_switch", val, 0, 1) then
			kvmap[keys.c_ag_rs_switch] = val
			return true
		end
	end
}
optimal_map.rate = {
	check = function(val, map)
		assert(map)
		local kvmap = map.kvmap
		if check_num("optimal_map.rs_rate", val, 0, 11) then
			kvmap[keys.c_ag_rs_rate] = val
			return true
		end
	end
}
optimal_map.mult = {
	check = function(val, map)
		assert(map)
		local kvmap = map.kvmap
		if check_num("optimal_map.rs_rate", val, 0, 1) then
			kvmap[keys.c_ag_rs_mult] = val
			return true
		end
	end
}
optimal_map.inspeed = {
	check = function(val, map)
		assert(map)
		local kvmap = map.kvmap
		if check_num("optimal_map.rs_inspeed", val, 0, 54) then
			kvmap[keys.c_rs_inspeed] = val
			return true
		end
	end
}
optimal_map.ienable = {
	check = function(val, map)
		assert(map)
		local kvmap = map.kvmap
		if check_num("optimal_map.rs_iso", val, 0, 1) then
			kvmap[keys.c_rs_iso] = val
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

local function optimization(conn, group, data)
	nrds, pcli = conn.rds, conn.pcli 	assert(nrds and pcli) 
	local map = get_param(group)
	local res = {
		average = {
			enable = map.ag_rs_switch,
		},
		broadcast = {
			mult = map.ag_rs_mult,
			rate = map.ag_rs_rate,
			inspeed = map.ag_rs_inspeed,
		},
		isolation = {
			ienable = map.ag_rs_iso,
		},
	}
	
	return {status = 0, data = res}
end

local function save_optimal_sta(conn, data, str) 
	local map = data
	if not (map and map.data and map.oldData) then 
		log.error("error data %s", data)
		return false
	end

	local nmap, omap = map.data[str], map.oldData[str]
	local modify_map = get_change(nmap, omap)

	local kvmap = {}
	for field, item in pairs(optimal_map) do 
		local val = modify_map[field]
		if val and not item.check(val, {kvmap = kvmap, nmap = nmap}) then 
			log.error("check data fail")
			return false
		end
	end

	return kvmap
end

local function save_optimization(conn, group, data)
	nrds, pcli = conn.rds, conn.pcli 	assert(nrds and pcli)
	local kvmap = save_optimal_sta(conn, data, "average")
	local tmp_map = save_optimal_sta(conn, data, "broadcast")
	local iso_map = save_optimal_sta(conn, data, "isolation")

	if not (kvmap and tmp_map and iso_map) then
		return {status = 1, data = "error"} 
	end
	
	for k, v in pairs(tmp_map) do
		kvmap[k] = v
	end
	
	for k, v in pairs(iso_map) do
		kvmap[k] = v
	end

	if ms.count(kvmap) == 0 then 
		log.debug("nothing changed")
		return {status = 0, data = "ok"} 
	end

	local res = conn.pcli:modify({cmd = "set_opti", data = {group = group, map = kvmap}}) 
	if res then 
		return {status = 0, data = "ok"} 
	end 
	return {status = 1, data = "modify fail"} 
end

return {
	optimization = optimization,
	save_optimization = save_optimization,
}