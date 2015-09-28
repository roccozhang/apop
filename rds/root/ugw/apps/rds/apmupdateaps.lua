local log = require("log") 
local js = require("cjson.safe")
local const = require("constant") 
local pkey = require("key")
 
local rds, pcli
local keys = const.keys 

local function errmsg(fmt, ...)
	return string.format(fmt, ...)
end

-- param = {dhcp = true/false, multi = true/false}
local function collect_all(map, param)
	local group = "default"
	local ismulti, isdhcp = param.multi, param.dhcp

	local fix_kpmap = {}

	local v = map.nick_name 					assert(v)
	fix_kpmap[keys.c_desc] = tostring(v)

	local v = map.ip_address 					assert(v)
	fix_kpmap[keys.c_ip] = tostring(v)

	local v = map.ip_distribute 				assert(v)
	fix_kpmap[keys.c_distr] = tostring(v)

	local v = map.gateway 						assert(v)
	fix_kpmap[keys.c_gw] = tostring(v)
	
	-- 批量修改时，描述名/ip/掩码/网关 不能修改
	if ismulti then 
		fix_kpmap[keys.c_desc] = nil
		fix_kpmap[keys.c_ip] = nil 
		fix_kpmap[keys.c_gw] = nil
	end

	-- 模式为dhcp时，ip/掩码/网关 不能修改
	if isdhcp then 
		fix_kpmap[keys.c_ip] = nil 
		fix_kpmap[keys.c_gw] = nil
	end 

	local v = map.ac_host 						assert(v)
	fix_kpmap[keys.c_ac_host] = tostring(v)

	local v = map.work_mode 					assert(v)
	fix_kpmap[keys.c_mode] = tostring(v)

	if v == "hybrid" then 
		local v = map.hybrid_scan_cycle 		assert(v)
		fix_kpmap[keys.c_hbd_cycle] = tostring(v)
		local v = map.hybrid_scan_time 			assert(v)
		fix_kpmap[keys.c_hbd_time] = tostring(v)
	elseif v == "monitor" then
		local v = map.monitor_scan_time 		assert(v)
		fix_kpmap[keys.c_mnt_time] = tostring(v)
	end 

	local radio_map = {}
	for _, band in ipairs({"2g", "5g"}) do 
		local kpmap, rmap = {}, map["radio_" .. band]

		local v = rmap.switch 					assert(v)
		kpmap[keys.c_bswitch] = tostring(v)

		local v = rmap.wireless_protocol 		assert(v)
		kpmap[keys.c_proto] = tostring(v)

		local v = rmap.channel_id 				assert(v)
		kpmap[keys.c_chanid] = tostring(v)

		local v = rmap.bandwidth 				assert(v)
		kpmap[keys.c_bandwidth] = tostring(v)

		local v = rmap.power 					assert(v)
		kpmap[keys.c_power] = tostring(v)

		local v = rmap.users_limit 				assert(v)
		kpmap[keys.c_usrlimit] = tostring(v)

		local v = rmap.rts 						assert(v)
		kpmap[keys.c_rts] = tostring(v)

		local v = rmap.beacon 					assert(v)
		kpmap[keys.c_beacon] = tostring(v)

		local v = rmap.dtim 					assert(v)
		kpmap[keys.c_dtim] = tostring(v)

		local v = rmap.leadcode 				assert(v)
		kpmap[keys.c_leadcode] = tostring(v)

		local v = rmap.shortgi 					assert(v)
		kpmap[keys.c_shortgi] = tostring(v)

		local v = rmap.remax 					assert(v)
		kpmap[keys.c_remax] = tostring(v)

		local v = rmap.ampdu 					assert(v)
		kpmap[keys.c_ampdu] = tostring(v)

		local v = rmap.amsdu 					assert(v)
		kpmap[keys.c_amsdu] = tostring(v)

		radio_map[band] = kpmap
	end 
	
	return {fix = fix_kpmap, radio = radio_map}
end

local function apmupdateaps(conn, group, data)
	assert(conn and conn.rds and group)
	rds, pcli = conn.rds, conn.pcli 	assert(rds and pcli) 

	local t = data
	local edit, aps = t.edit, t.aps 	assert(edit and aps)

	local kpmap = collect_all(edit, {dhcp = edit.ip_distribute == "dhcp", multi = #aps > 1}) 
	local res = pcli:modify({cmd = "set_ap", data = {group = "default", kpmap = kpmap, aparr = aps}}) 
	if res then 
		return {status = 0, data = "ok"}
	end 
	return {status = 1, data = "modify fail"}
end

local function apmdeleteaps(conn, group, data)
	assert(conn and conn.rds and conn.pcli and group)
	
	rds, pcli = conn.rds, conn.pcli 	assert(rds and pcli)

	local apid_arr = data
	if type(apid_arr) ~= "table" then
		log.debug("error %s", data);
		return {status = 1, data = "error param"} 
	end

	for _, apid in ipairs(apid_arr) do 
		if not (type(apid) == "string" and #apid == 17) then 
			return {status = 1, data = "error param"}  
		end
	end

	local res = pcli:modify({cmd = "del_ap", data = {group = "default", arr = apid_arr}})
	if res then 
		return {status = 0, data = "ok"}
	end 
	return {status = 1, data = "modify fail"}
end

return {apmupdateaps = apmupdateaps, apmdeleteaps = apmdeleteaps}

