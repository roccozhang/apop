local log = require("log")
local pkey = require("key")
local ms = require("moses") 
local js = require("cjson.safe")
local const = require("constant")

local rds, pcli
local keys = const.keys
local mac_pattern = string.rep("[a-f0-9][a-f0-9]:", 5) .. "[a-f0-9][a-f0-9]"

local function errmsg(fmt, ...)
	return string.format(fmt, ...)
end

local function get_status(s, d)
	return {status = s, data = d or "ok"}
end

local function get_wlanlist(pcli, group) 
	local karr = {}
	table.insert(karr, keys.c_wlan_list) 
	local varr = pcli:query(group, karr)
	local _ = varr or log.fatal("query fail")
	return js.decode(varr[1])
end

local function listwlanid(group) 
	local wlan_map = {}
	local arr = get_wlanlist(pcli, group)
	for _, wlanid in ipairs(arr) do 
		assert(#wlanid == 5)
		wlan_map[wlanid] = 1
	end

	return wlan_map
end

local function wlaninfo(group, wlanid)
	local st = {
		{k = keys.c_wssid, 			desc = "ssid"},
		{k = keys.c_whide, 			desc = "hide"},
		{k = keys.c_wstate, 			desc = "state"},
		{k = keys.c_wencry, 		desc = "encryption"},
		{k = keys.c_wpasswd, 		desc = "password"},
		{k = keys.c_wband, 			desc = "band"}, 
	}
	
	local karr, rt = {}, {WLANID = wlanid}
	for i, item in ipairs(st) do 
		table.insert(karr, pkey.key(item.k, rt))
	end
	
	local rarr = pcli:query(group, karr)
	if type(rarr) ~= "table" then 
		log.error("mget %s fail %s", js.encode(karr), err or "")
		return {}
	end 

	local resmap = {}
	for i = 1, #karr do 
		local k, v, desc = karr[i], rarr[i], st[i].desc
		assert(not resmap[desc]) 
		if st[i].cb then 
			resmap[desc] = st[i].cb(v)
		else 
			resmap[desc] = type(v) == "number" and tostring(v) or v 
		end
		local _ = v or log.error("missing %s", k)
	end
	resmap.ext_wlanid = wlanid
	return resmap
end

local function get_aps_check(group, wlan_map)
	local list_arr, check_arr, wlanid_arr = {}, {}, {}
	
	for _, map in pairs(wlan_map) do
		table.insert(list_arr, pkey.waplist(map.ext_wlanid))
		table.insert(wlanid_arr, map.ext_wlanid)
	end
	local varr = pcli:query(group, list_arr)
	if not varr then 
		log.error("error get wacid get_aps_check")
		return nil, errmsg("error rds")
	end
	
	for i = 1, #wlanid_arr do
		check_arr[wlanid_arr[i]] = #js.decode(varr[i]) or 0
	end

	return check_arr
end

local function wlanlist(conn, group, data) 
	rds, pcli = conn.rds, conn.pcli 	assert(rds and pcli)

	local wlanid_map = listwlanid(group)
	if not wlanid_map then 
		return get_status(0, {})
	end
	
	local wlan_map = {}

	-- wlan_map = {["00001"] = 1, ["00002"] = 1}
	for wlanid in pairs(wlanid_map) do
		assert(type(wlanid) == "string")

		local map = wlaninfo(group, wlanid) 
		if not map.ssid then 
			log.error("not find ssid")
		else 
			assert(type(map.ssid) == "string" and not wlan_map[map.ssid])
			wlan_map[map.ssid] = map
		end
	end
	-- wlan_map = {ssid = {desc1 = v1, desc2 = v2},}
	local checkarr = get_aps_check(group, wlan_map)
	local resmap = {}
	for _, map in pairs(wlan_map) do 
		assert(not resmap[map.ssid]) 
		resmap[map.ssid] = {
			SSID = map.ssid or "",
			hide = map.hide or "",
			enable = (function()
						if type(map.state) ~= "string" then
							return ""
						end
						return map.state
					end) (),
			encrypt = map.encryption or "",
			password = map.password or "",
			band = map.band or "", 
			ext_wlanid = assert(map.ext_wlanid),
			checkAps = checkarr[map.ext_wlanid] or '0',
		}
	end 

	return get_status(0, resmap)  
end 

local web_map = {}
web_map.SSID = {
		k = keys.c_wssid,
		func = function(ssid) 
			if not ssid or type(ssid) ~= "string" or #ssid > 32 or #ssid == 0 then
				log.error("error ssid %s", ssid or "")
				return nil, errmsg("invalid ssid")
			end
			return ssid
		end
	}
web_map.encrypt = {
		k = keys.c_wencry, 
		func = function(mode)
			local valid = {none = 1, psk2 = 1, psk = 1}
			if not mode or type(mode) ~= "string" or not valid[mode] then 
				log.error("error encrypt %s", mode or "")
				return nil, errmsg("invalid encryption")
			end
			return mode
		end
	}
web_map.band = {
		k = keys.c_wband, 
		func = function(band)
			local valid = {["2g"] = 1, ["5g"] = 1, ["all"] = 1}
			if not band or type(band) ~= "string" or not valid[band] then 
				log.error("error band %s", band or "")
				return nil, errmsg("invalid band")
			end
			return band
		end
	}

web_map.enable = {
		k = keys.c_wstate, 
		func = function(s)
			local valid = {["0"] = 1, ["1"] = 1} 
			local enable = tostring(s)
			if not enable or type(enable) ~= "string" or not valid[enable] then 
				log.error("error enable %s", s or "")
				return nil, errmsg("invalid enable")
			end
			return enable
		end
	}
web_map.password = {
		k = keys.c_wpasswd, 
		func = function(password) 
			if not password or type(password) ~= "string" or #password > 32 then 
				log.error("error password %s", password or "")
				return nil, errmsg("invalid password")
			end
			return password
		end
	}
web_map.hide = {
		k = keys.c_whide, 
		func = function(s)
			local valid = {["0"] = 1, ["1"] = 1} 
			local hide = tostring(s)
			if not hide or type(hide) ~= "string" or not valid[hide] then 
				log.error("error hide %s", s or "")
				return nil, errmsg("invalid hide")
			end 
			return hide
		end
	}
web_map.apList = {
		k = keys.c_waplist, 
		func = function(t)
			if type(t) ~= "table" then 
				log.error("error apList %s", js.encode(t or {}))
				return nil, errmsg("invalid ap_list")
			end
			local p = string.format("^%s$", mac_pattern)
			for _, apid in pairs(t) do 
				if type(apid) ~= "string" or not apid:find(p) then 
					log.error("error apList %s", js.encode(t or {}))
					return nil, errmsg("invalid ap_list")
				end 
			end 
			return t
		end
	}	
 
local function param_validate(o) 
	assert(type(o) == "table")

	local map = {}
	for k, v in pairs(o) do 
		if not k:find("^ext_") then 
			local item = web_map[k]
			if not item then 
				log.error("not find %s %s", k, v and js.encode(v) or "")
				return nil, errmsg("no such key %s %s", k, v or "")
			end 
			local res, err = item.func(v)
			if not res then
				return nil, err
			end
			assert(not map[item.k], "exist " .. item.k)
			map[item.k] = res
		end
	end

	if ms.count(web_map) ~= ms.count(map) then 
		log.error("not enough param %s", js.encode(map))
		return nil, errmsg("not enough param")
	end
	
	return map
end

local function password_validate(group, o) 
	local encrypt = o[web_map.encrypt.k]	assert(type(encrypt) == "string")
	if encrypt == "none" then
		log.debug("encrypt none, skip check password")
		return true 
	end

	local password = o[web_map.password.k] 	assert(type(password) == "string")
	if #password == 0 then 
		log.error("error encrypt %s password %s", encrypt, password)
		return nil, errmsg("password empty")
	end 

	return true 
end 

local function scan_ssid(group)
	local arr = get_wlanlist(pcli, group)
	if #arr == 0 then 
		return {}, {}
	end

	local karr = {}
	for _, wlanid in ipairs(arr) do 
		assert(#wlanid == 5)
		table.insert(karr, pkey.wssid(wlanid))
	end

	local varr = pcli:query(group, karr) or log.fatal("mget %s fail", js.encode(karr))
	return karr, varr
end

local function ssid_validate(group, o)
	local newssid = o[web_map.SSID.k]

	assert(type(newssid) == "string" and #newssid > 0, js.encode(o))
	local karr, varr = scan_ssid(group)
	if #karr == 0 then 
		return true 
	end 

	for i, v in ipairs(varr) do 
		if v == newssid then 
			log.error("duplicate ssid %s %s", karr[i], newssid)
			return nil, errmsg("duplicate SSID")
		end
	end

	return true
end

local function ssid_modify_validate(group, wlanid, ssid) 
	local karr, varr = scan_ssid(group)
	
	if #karr == 0 then
		log.error("not find any ssid")
		return nil, errmsg("no ssid")
	end 
	
	for i, v in ipairs(varr) do
		if v == ssid then 
			local tmpwlanid = karr[i]:match("#(%d%d%d%d%d)#") 	assert(tmpwlanid)
			if tmpwlanid ~= wlanid then 
				log.error("exist ssid %s %s", karr[i], ssid)
				return nil, errmsg("ssid duplicate")
			end
		end 
	end 

	return true
end

local function wlanid_ssid_validate(group, wlanid_ssid_map)
	assert(type(wlanid_ssid_map) == "table")
	local karr, ssid_arr = {}, {}
	for wlanid, ssid in pairs(wlanid_ssid_map) do 
		assert(#wlanid == 5 and #ssid > 0)
		local k = pkey.wssid(wlanid)
		table.insert(ssid_arr, {k = k, ssid = ssid})
		table.insert(karr, k)
	end 

	local varr = pcli:query(group, karr)
	if type(varr) ~= "table" then 
		log.error("rds get %s fail", js.encode(karr))
		return nil, errmsg("error rds")
	end 
	
	for i = 1, #karr do 
		if varr[i] ~= ssid_arr[i].ssid then
			log.error("wlanid ssid not match %s %s %s", ssid_arr[i].k, ssid_arr[i].ssid, varr[i])
			return nil, errmsg("error wlanid")
		end
	end 

	return true 
end

local function wlanadd(conn, group, data) 
	rds, pcli = conn.rds, conn.pcli 	assert(rds and pcli)  

	local map, err = param_validate(data)
	if not map then 
		return get_status(1, err) 
	end 

	-- for _, func in ipairs({password_validate, vlan_validate, ssid_validate}) do 
	for _, func in ipairs({password_validate, ssid_validate}) do 
		local ret, err = func(group, map)
		if not ret then 
			return get_status(1, err) 
		end
	end

	local res = pcli:modify({cmd = "add_wlan", data = {group = group, map = map}})
	return res and get_status(0) or get_status(1, "modify fail") 
end

local function delete_validate(ssidarr)
	assert(type(ssidarr) == "table" and #ssidarr > 0)

	local karr, varr = scan_ssid()
	if #karr == 0 then 
		return {}
	end

	local map = {}
	for i, ssid in ipairs(varr) do
		map[ssid] = i
	end
	
	local res = {}
	for _, ssid in ipairs(ssidarr) do
		local idx = map[ssid]
		if not idx then
			log.error("not find %s", ssid)
			return nil, errmsg("not find %s", ssid)
		end
		
		local wlanid = karr[idx]:match("#(%d%d%d%d%d)#")	assert(wlanid and not res[ssid])
		res[wlanid] = ssid
	end

	return res
end

local function wlandelete(conn, group, data) 
	rds, pcli = conn.rds, conn.pcli 		assert(rds and pcli) 
	local ssidarr = data 	assert(type(ssidarr) == "table")
	
	-- ssidarr = {{ssid = "ssid", wlanid = "00001"}}
	if #ssidarr == 0 then 
		log.debug("empty delete list")
		return get_status(1, "empty") 
	end

	local wlanid_ssid_map = {}
	for _, item in ipairs(ssidarr) do 
		local wlanid, ssid = item.ext_wlanid, item.SSID
		if type(wlanid) ~= "string" or type(ssid) ~= "string" or #wlanid ~= 5 or #ssid <= 0 then
			log.error("error delete %s", data)
			return get_status(1, "error wlanid") 
		end
		wlanid_ssid_map[wlanid] = ssid
	end

	local ret, err = wlanid_ssid_validate(group, wlanid_ssid_map)
	if not ret then 
		return get_status(1, err) 
	end

	local res = pcli:modify({cmd = "del_wlan", data = {group = group, map = wlanid_ssid_map}})
	return res and get_status(0) or get_status(1, "modify fail") 
end 

local modify_map = {}
function modify_map.setwlan(group, data)
	assert(type(data) == "table" and type(data.SSID) == "string" and type(data.enable) == "string")

	-- {enable = "0"/"1", ssid = "SSID", wlanid = "00001"} 
	local enable, wlanid, ssid = data.enable, data.ext_wlanid, data.SSID
	if not (enable ~= "0" or enable ~= "1") 
		or type(wlanid) ~= "string" or #wlanid ~= 5 or not ssid or #ssid == 0
	then 
		log.error("error data %s", js.encode(data))
		return nil, errmsg("error param")
	end

	local ret, err = wlanid_ssid_validate(group, {[wlanid] = ssid})
	if not ret then 
		return nil, err 
	end
	
	local res = pcli:modify({cmd = "wlan_stat", data = {group = group, arr = {wlanid, enable}}})
	return true
end

local function get_kp_val_map(map)
	local key_pattern_val_map = {
		[web_map.enable.k] = map[web_map.enable.k],
		[web_map.encrypt.k] = map[web_map.encrypt.k],
		[web_map.band.k] = map[web_map.band.k],
		[web_map.hide.k] = map[web_map.hide.k], 
		[web_map.apList.k] = map[web_map.apList.k],
		[web_map.SSID.k] = map[web_map.SSID.k],
	}
	
	if map[web_map.encrypt.k] ~= "none"	then 
		key_pattern_val_map[web_map.password.k] = map[web_map.password.k]
	end
	
	return key_pattern_val_map
end

local function check_change(group, kvmap)
	assert(type(kvmap) == "table")
	local karr, varr = {}, {}
	for k, v in pairs(kvmap) do 
		table.insert(karr, k)
		table.insert(varr, v)
	end 
	
	local rarr = pcli:query(group, karr)
	if not rarr then 
		log.error("mget %s fail", js.encode(karr))
		return nil, errmsg("error rds")
	end

	local change_kvmap, change_karr = {}, {}
	for i = 1, #karr do 
		if not rarr[i] then 
			log.error("missing %s", karr[i])
			return errmsg("error rds")
		end

		assert(type(rarr[i]) == "string")

		if rarr[i] ~= varr[i] then
			if type(varr[i]) == "table" then 
				local old, new = js.decode(rarr[i]), varr[i]
				table.sort(old) table.sort(new)
				if not ms.isEqual(old, new) then
					local s = js.encode(new)
					log.debug("change %s from %s to %s", karr[i], rarr[i], s)
					change_kvmap[karr[i]] = s
					table.insert(change_karr, karr[i])
				end
			else 
				log.debug("modify change %s from %s to %s", karr[i], rarr[i], varr[i])
				change_kvmap[karr[i]] = varr[i]
				table.insert(change_karr, karr[i])
			end
		end
	end
	return change_kvmap, change_karr
end

local function collect_aparr(group, o, wlanid)
	local new_aparr = o.apList 	assert(type(new_aparr) == "table")

	local karr = {pkey.waplist(wlanid)}
	local varr = pcli:query(group, karr)
	local old_aparr = js.decode(varr and varr[1] or nil)
	if type(old_aparr) ~= "table" then 
		log.error("rds get fail")
		return nil, errmsg("error rds")
	end

	local find = function(arr, e)
		for _, v in ipairs(arr) do 
			if e == v then 
				return true 
			end 
		end 
		return false 
	end

	local cmd_map = {add = {}, del = {}, modify = {}}
	
	for _, apid in ipairs(new_aparr) do 
		if not find(old_aparr, apid) then
			-- 增加的ap
			table.insert(cmd_map.add, apid)
		else 
			-- 修改的ap
			table.insert(cmd_map.modify, apid)
		end 
	end
	
	for _, apid in ipairs(old_aparr) do 
		if not find(new_aparr, apid) then
			-- 删除的ap
			table.insert(cmd_map.del, apid) 
		end
	end

	return cmd_map
end 

function modify_map.modify(group, o)
	assert(type(o) == "table")
	
	local wlanid, ssid = o.ext_wlanid, o.SSID 
	if type(wlanid) ~= "string" or type(ssid) ~= "string" or #wlanid ~= 5 or #ssid == 0 then 
		log.error("invalid wlanid %s %s", wlanid or "", ssid or "")
		return nil, errmsg("error wlanid")
	end 

	local map, err = param_validate(o)
	if not map then 
		return nil, err
	end

	-- for _, func in ipairs({password_validate, vlan_validate}) do 
	for _, func in ipairs({password_validate}) do 
		local ret, err = func(group, map)
		if not ret then 
			return nil, err
		end
	end

	local ret, err = ssid_modify_validate(group, wlanid, ssid) 
	if not ret then 
		return nil, err
	end

	log.error("not implement ap list exclusive check")

	local kvmap = {}
	for kp, v in pairs(get_kp_val_map(map)) do 
		local k = pkey.key(kp, {WLANID = wlanid})
		kvmap[k] = v 
	end

	local change_kvmap, change_karr = check_change(group, kvmap)
	if not change_kvmap then 
		return nil, change_karr 
	end

	if 0 == ms.count(change_kvmap) then 
		log.debug("modify nothing changed")
		return true 
	end

	local cmd_map, err = collect_aparr(group, o, wlanid)
	if not cmd_map then 
		return nil, err
	end
	
	local res = pcli:modify({cmd = "mod_wlan", data = {group = group, change = change_kvmap, wlanid = wlanid, op_map = cmd_map}})
	return true
end

local function wlanmodify(conn, group, data)  
	rds, pcli = conn.rds, conn.pcli 		assert(rds and pcli and group)

	local map = data

	local cmd, data = map.cmd, map.data
	local func = modify_map[cmd]	
	if not func then
		log.error("error modify %s", data)
		return get_status(1, "invalid " .. cmd or "")  
	end

	local res, err = func(group, data)
	return res and get_status(0) or get_status(1, err) 
end 

local function get_ap_des(group, apmap)
	assert(group and apmap)
	local karr, ap_arr, ap_des = {}, {}, {}
	for _, apid in pairs(apmap) do
		table.insert(karr, pkey.desc(apid))
		table.insert(ap_arr, apid)
	end
	local varr = pcli:query(group, karr)
	for i = 1, #ap_arr do
		ap_des[ap_arr[i]] = varr[i]
	end
	
	return ap_des
end

local function get_aplist_bandlist(pcli, group) 
	assert(pcli and group)
	local karr = {}
	table.insert(karr, keys.c_ap_list) 
	local varr = pcli:query(group, karr)
	local _ = varr or log.fatal("query fail")
	local aparr, bands = js.decode(varr[1]), {"2g", "5g"}
	return aparr, bands
end

local function listaps(group)
	assert(group)
	local aparr, bands = get_aplist_bandlist(pcli, group)
	if not aparr or #aparr == 0 then 
		log.debug("empty ap list")
		return {}
	end
	
	local desarr = get_ap_des(group, aparr)
	local apid_check_arr = {}
	for _, apid in ipairs(aparr) do 
		table.insert(apid_check_arr, {apid = apid, check = "0", ap_des = desarr[apid]}) 
	end

	return apid_check_arr
end 

local function list_check_ssid(group, wlanid)
	assert(#wlanid == 5)

	local karr = {pkey.waplist(wlanid)}
	local varr = pcli:query(group, karr)
	if not varr then 
		return nil, errmsg("error mqtt")
	end 

	local aparr = js.decode(varr[1])
	if not aparr then 
		log.error("get %s fail", k)
		return nil, errmsg("error rds")
	end
	return aparr
end 

--[[
{
	["00:00:00:00:00:00"] = {check = 0/1, reason = "xxx"},
}
]]
local function wlanlistaps(conn, group, data) 
	rds, pcli = conn.rds, conn.pcli 	assert(rds and pcli)
	local item = data 	assert(type(item) == "table") 

 	local wlanid, ssid = item.ext_wlanid, item.SSID
 	if type(wlanid) ~= "string" or type(ssid) ~= "string" then 
		log.error("invalid wlanid %s %s", wlanid or "", ssid or "")
		return get_status(1, "error wlanid")
	end 

	local apid_check_arr = listaps(group)
 	if not apid_check_arr then 
 		return get_status(1, "error rds")
 	end

	if wlanid == "" and ssid == "" then
 		return get_status(0, apid_check_arr) 
 	end

 	local check_aparr = list_check_ssid(group, wlanid)
 	if not check_aparr then 
 		return get_status(1, "error rds")
 	end 

 	local nmap = {}
 	for _, apid in ipairs(check_aparr) do 
 		nmap[apid] = 1
 	end 

 	for _, item in ipairs(apid_check_arr) do 
 		if nmap[item.apid] then 
 			item.check = "1"
 		end 
 	end 

	return get_status(0, apid_check_arr) 
end 

return {
	wlanlist = wlanlist,
	wlanadd = wlanadd,
	wlandelete = wlandelete,
	wlanmodify = wlanmodify,
	wlanlistaps = wlanlistaps,
}
