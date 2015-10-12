local log = require("log") 
local pkey = require("key")  
local js = require("cjson.safe") 
local const = require("constant")  

local rds, pcli
local keys = const.keys 

-- 获取所有AP {["00:00:00:00:00:00"] = {["2g"] = 1, ["5g"] = 1}, ...}
local function get_aps_country(group)
	local karr = {keys.c_ap_list, keys.c_g_country}
	local varr = pcli:query(group, karr)
	local _ = varr or log.fatal("query fail")
	return js.decode(varr[1]), varr[2]
end
 
local cfg_kparr = {
	keys.c_desc,
	keys.c_gw,
	keys.c_distr,
	keys.c_mask,
	keys.c_mode,
	keys.c_hbd_cycle,
	keys.c_hbd_time,
	keys.c_mnt_time,
	keys.c_scan_chan,
	keys.c_ac_host,
	keys.c_ip,
	keys.c_dns,
	keys.c_barr,
	keys.c_proto,
	keys.c_chanid,
	keys.c_bandwidth,
	keys.c_power,
	keys.c_bswitch,
	keys.c_usrlimit,
	keys.c_rts,
	keys.c_beacon,
	keys.c_dtim,
	keys.c_leadcode,
	keys.c_shortgi,
	keys.c_remax,
	keys.c_ampdu,
	keys.c_amsdu,
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

local function get_config(group, apid)
	local karr = get_karr(apid, cfg_kparr)
	local varr = pcli:query(group, karr)
	if not varr then 
		log.error("query fail")
		return {}
	end 

	local kvmap = {}
	for i = 1, #karr do
		local k, v = karr[i], varr[i]
		local short = k:match("([25]g#.+)") or k:match(".+#(.+)") 	assert(short and kvmap[short] == nil)
		kvmap[short] = v ~= nil and v or "-"
	end 

	return kvmap
end 

local state_kparr = {
	keys.s_fireware,
	keys.s_uptime, 
	keys.s_naps,
	keys.s_users, 
}

local function get_state(group, apid)
	local karr = get_karr(apid, state_kparr)
	local hkey = pkey.state_hash(apid) 		assert(hkey)
	local varr = rds:hmget(hkey, karr)

	local kvmap = {}
	for i = 1, #karr do 
		local k, v = karr[i], varr[i]
		if v then 
			local short = k:match("([25]g#.+)") or k 	assert(short and kvmap[short] == nil) 
			kvmap[short] = v
		end
	end 

	return kvmap
end

local function get_online(group, aparr)
	local hkey = "ol/" .. group
	local varr = rds:hmget(hkey, aparr)

	local olmap = {}
	for i = 1, #aparr do 
		local k, v = aparr[i], varr[i]
		v = v == false and 0 or v
		olmap[k] = v
	end 
	return olmap
end

local function nap_info(kvmap, stmap)
	local nap = {}
	local dec = function(band, s)
		if not s then return {} end 
		local t = js.decode(s)
		if not t then return {} end 
		for _, item in ipairs(t) do 
			local tmp = nap[item.apid] or {}
			local b = tmp[band] or {}

			b.channel_id = item.channel_id
			b.radio = band 
			b.rssi = string.format("%4d", item.rssi)
		
			tmp[band] = b
			nap[item.apid] = tmp
		end
	end

	local _ = stmap["2g#nap"] and dec("2g", stmap["2g#nap"])
	local _ = stmap["5g#nap"] and dec("5g", stmap["5g#nap"])

	local res = {}
	for k, v in pairs(nap) do  
	 	local desc = kvmap.desc or ""
	 	table.insert(res, {apid = k, desc = desc, ["2g"] = v["2g"], ["5g"] = v["5g"]})
	end

	return res
end

local function get_login_time(group, aparr)
	local hkey = string.format("login/%s", group)
	local varr = rds:hmget(hkey, aparr)

	if not varr then 
		return {}
	end

	local map  = {}
	for i = 1, #aparr do 
		local k, v = aparr[i], varr[i]
		map[k] = v == false and "" or v
	end

	return map
end

local function apinfo(group, aparr)   
	local apid_map = {}
	if #aparr == 0 then 
		return apid_map
	end 
	
	local olmap = get_online(group, aparr)
	local login_map = get_login_time(group, aparr) 
	for _, apid in pairs(aparr) do
		local kvmap = get_config(group, apid) 
		local stmap = get_state(group, apid)	

		apid_map[apid] = {
			ip_address = kvmap.ip, 	
			ap_describe = kvmap.desc, 	
			mac = apid,
			current_users = tonumber(stmap["2g#users"] or "0") + tonumber(stmap["5g#users"] or "0"),
			radio = table.concat(js.decode(kvmap.barr) or {}, ","),
			boot_time = stmap.uptime or "",
			online_time = login_map[apid] or "",
			firmware_ver = stmap.fireware or "",
			state = {status = olmap[apid]},
			naps = nap_info(kvmap, stmap),
			edit = {
				nick_name = kvmap.desc,
				ip_address = kvmap.ip,
				ip_distribute = kvmap.distr, 
				gateway = kvmap.gw, 
				netmask = kvmap.mask,
				ac_host = kvmap.ac_host,
				work_mode = kvmap.mode,
				dns = kvmap.dns,

				hybrid_scan_cycle = kvmap.hbd_cycle,
				hybrid_scan_time = kvmap.hbd_time,
				monitor_scan_cycle = kvmap.mnt_cycle,
				monitor_scan_time = kvmap.mnt_time,
				scan_channels = kvmap.scan_chan,

				radio_2g = {
					switch = kvmap["2g#bswitch"],
					wireless_protocol = kvmap["2g#proto"],
					channel_id = kvmap["2g#chanid"],
					bandwidth = kvmap["2g#bandwidth"],
					power = kvmap["2g#power"],
					users_limit = kvmap["2g#usrlimit"],
					
					rts = kvmap["2g#rts"],
					beacon = kvmap["2g#beacon"],
					dtim = kvmap["2g#dtim"],
					leadcode = kvmap["2g#leadcode"],
					shortgi = kvmap["2g#shortgi"],
					remax = kvmap["2g#remax"],
					ampdu = kvmap["2g#ampdu"],
					amsdu = kvmap["2g#amsdu"],
				},

				radio_5g = {
					switch = kvmap["5g#bswitch"],
					wireless_protocol = kvmap["5g#proto"],
					channel_id = kvmap["5g#chanid"],
					bandwidth = kvmap["5g#bandwidth"],
					power = kvmap["5g#power"],
					users_limit = kvmap["5g#usrlimit"],
					
					rts = kvmap["5g#rts"],
					beacon = kvmap["5g#beacon"],
					dtim = kvmap["5g#dtim"],
					leadcode = kvmap["5g#leadcode"],
					shortgi = kvmap["5g#shortgi"],
					remax = kvmap["5g#remax"],
					ampdu = kvmap["5g#ampdu"],
					amsdu = kvmap["5g#amsdu"],
				},
			}
		}
	end

	return apid_map
end

local function apmlistaps(conn, group, data)
	rds, pcli = conn.rds, conn.pcli  
	local aparr, ctry = get_aps_country(group) 
	local res = {
		APs = apinfo(group, aparr), 
		country = ctry,
	} 
	return {status = 0, data = res}
end

return {apmlistaps = apmlistaps}

