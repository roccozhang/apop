local log = require("log")
local ms = require("moses")
local js = require("cjson.safe")
local const = require("constant")  
local pkey = require("key")

local rds, pcli
local keys = const.keys 

local h_radio_keys = {
	keys.s_users,
	keys.s_chanid,
	keys.s_chanuse,
	keys.s_power,
	keys.s_noise,
	keys.s_maxpow,
	keys.s_proto,
	keys.s_bandwidth,
	keys.s_run,
	keys.s_nwlans
}

local function get_karr(apid, kparr)
	local kmap, karr = {}, {}
	for _, band in ipairs({"2g", "5g"}) do 
		local rt = {APID = apid, BAND = band}
		for _, kp in ipairs(kparr) do 
			local k = pkey.key(kp, rt)
			kmap[k] = 1
		end
	end
	for k in pairs(kmap) do 
		table.insert(karr, k)
	end 
	return karr
end

local function get_band_apmap(group)
	local karr = {keys.c_ap_list}
	local varr = pcli:query(group, karr) 	assert(varr) 
	local aparr = js.decode(varr[1]) 			assert(aparr)

	local band_apmap, desc_karr = {}, {}
	for _, apid in ipairs(aparr) do
		table.insert(desc_karr, pkey.desc(apid))

		local hkarr = get_karr(apid, h_radio_keys)
		local hkey = pkey.state_hash(apid)
		local hvarr = rds:hmget(hkey, hkarr)

		for i = 1, #hkarr do 
			local k, v = hkarr[i], hvarr[i]
			if v then 
				local band, k = k:match("([25]g)#(.+)")

				local map = band_apmap[band] or {}
				
				local tmp = map[apid] or {}
				tmp[k] = v
				map[apid] = tmp 

				band_apmap[band] = map 
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

local function radiolist(conn, group, data) 
	rds, pcli = conn.rds, conn.pcli 	assert(rds and pcli) 

	local band_apmap, desc_map = get_band_apmap(group) 

	local resarr = {}
	for band, apmap in pairs(band_apmap) do  
		for apid, map in pairs(apmap) do 
			local item = {
				ap = apid,
				band = band,
				bandwidth = map.bandwidth or "",
				channel_id = map.chanid or "",
				channel_use = map.chanuse or "",
				noise = map.noise or "",
				nwlan = #(js.decode(map.nwlan) or {}),
				power = map.power or "",
				prototol = map.proto or "",
				user_num = map.users or "",
				wlanstate = ms.count(js.decode(map.run or "{}") or {}),
				ap_describe = desc_map[apid],
			}
			table.insert(resarr, item)
		end 
	end 

	return {status = 0, data = resarr}
end

local function nwlan(conn, group, data) 
	rds, pcli = conn.rds, conn.pcli 			assert(rds and pcli) 
	local data = data 							assert(data)
	local band, apid = data.band, data.apid 	assert(band and apid)
 
	local hkey = pkey.state_hash(apid)
	local hvarr = js.decode(rds:hget(hkey, pkey.key(keys.s_nwlans, {BAND = band}))) 	assert(hvarr)
	for _, map in pairs(hvarr) do
		map.rssi = map.rssi and string.format("%4d", map.rssi) 
	end
	
	return {status = 0, data = hvarr}
end

local function wlanstate(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(rds and pcli) 

	local data = data 					assert(data) 
	local hkey = pkey.state_hash(data.apid)
	local karr = {
		pkey.key(keys.s_sta, {BAND = data.band}),
		pkey.key(keys.s_run, {BAND = data.band}),
	}

	local varr = rds:hmget(hkey, karr) 	assert(varr)
	local ha_arr = js.decode(varr[1] or "{}")	assert(ha_arr)

	local essidmap = {}
	for k, vmap in ipairs(ha_arr) do
		essidmap[vmap.ssid] = essidmap[vmap.ssid] and essidmap[vmap.ssid] + 1 or 1
	end

	local hr_map = js.decode(varr[2] or "{}")

	local res = {}
	for ath, map in pairs(hr_map) do
		table.insert(res, {
			ath = ath,
			rate = map.bitrate,
			bssid = map.bssid,
			essid = map.essid,
			users = essidmap[map.essid] or 0,
		})
	end
	
	return {status = 0, data = res}
end

return {
	nwlan = nwlan,
	radiolist = radiolist, 
	wlanstate = wlanstate,
}