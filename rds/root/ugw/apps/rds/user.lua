local log = require("log") 
local js = require("cjson.safe")
local const = require("constant") 
local pkey = require("key")

local rds, pcli
local keys = const.keys

local function apmdelusers(conn, group, data) 
	log.fatal("not implement apmdelusers")
end

local function get_user_map(group)
	local karr = {keys.c_ap_list}
	local varr = pcli:query(group, karr) 	assert(varr)
	local aparr = js.decode(varr[1]) 			assert(aparr)

	if #aparr == 0 then
		return {}
	end

	local band_apmap, desc_karr = {}, {}
	for _, apid in ipairs(aparr) do
		table.insert(desc_karr, pkey.desc(apid))

		local karr = {}
		for _, band in ipairs({"2g", "5g"}) do 
			table.insert(karr, pkey.key(keys.s_sta, {BAND = band}))
		end 

		local hkey = pkey.state_hash(apid)
		local varr = rds:hmget(hkey, karr) or {}
		for i = 1, #karr do 
			local k, v = karr[i], varr[i]
			if v then
				local band, k = k:match("([25]g)#(.+)")
				local apmap = band_apmap[band] or {}
				for _, map in pairs(js.decode(v) or {}) do 
					local aparr = apmap[apid] or {}
					table.insert(aparr, map)
					apmap[apid] = aparr 
				end
				band_apmap[band] = apmap 
			end
		end 
	end

	local desc_map = {}
	local desc_varr = pcli:query(group, desc_karr) or {}
	for i = 1, #aparr do 
		local k, v = aparr[i], desc_varr[i] or ""
		desc_map[k] = v
	end 

	return band_apmap, desc_map
end

-- heavy cpu consume TODO 
local function predhcpleases()
	local fp = io.open("/tmp/dhcpd.leases")
	if not fp then 
		return {}
	end

	local s = fp:read("*a")
	fp:close()

	local map = {}
	for part in s:gmatch("(lease.-})") do 
		local ip, mac = part:match("lease (%d+.-) {.-ethernet (.-);") 
		if ip then 
			map[mac] = ip
		end  
	end 

	return map
end

local function conflict_resolve(userarr, conflict_arr)
	if #conflict_arr == 0 then 
		return userarr
	end 

	local conflict_map = {}

	local varr = rds:hmget(keys.ws_hash_user, conflict_arr)
	for i = 1, #conflict_arr do
		local k, v = conflict_arr[i], varr[i]
		if v then 
			conflict_map[k] = v
		end
	end

	local exist_map, arr = {}, {}
	for _, item in ipairs(userarr) do
		if conflict_map[item.mac] then
			if item.ap == conflict_map[item.mac] then 
				table.insert(arr, item)
			end 
		else
			table.insert(arr, item)
		end
	end

	return arr
end

local function apmlistusers(conn, group, data) 
	rds, pcli = conn.rds, conn.pcli 	assert(rds and pcli)

	local adrmap = predhcpleases()
	local band_apmap, desc_map = get_user_map(group) 
	local userarr, exist_map, conflict_arr = {}, {}, {}
	for band, apmap in pairs(band_apmap) do 
		for apid, aparr in pairs(apmap) do
			for _, map in ipairs(aparr) do 
				local ipadr = map.ip_address == '0.0.0.0' and adrmap[map.mac] or map.ip_address 
				local item = {
					status = "1",
					mac = map.mac,
					dualband = map.isdual,
					band = band,
					rssi = map.rssi,
					ssid = map.ssid,
					ip = ipadr,
					ap = apid,
					ap_describe = desc_map[apid],
				}

				table.insert(userarr, item)

				local _ = exist_map[map.mac] and table.insert(conflict_arr, map.mac)
				exist_map[map.mac] = 1
			end
		end
	end

	return {status = 0, data = conflict_resolve(userarr, conflict_arr)}
end

return {
	apmdelusers = apmdelusers,
	apmlistusers = apmlistusers, 
}
