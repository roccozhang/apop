local se = require("se")
local log = require("log")
local pkey = require("key")
local ms = require("moses")
local cfgmgr = require("cfgmanager")
local mredis = require("mredis")
local js = require("cjson.safe")
local const = require("constant") 
local online = require("online")

local keys = const.keys 

local function cfgset(g, k, v)
	return cfgmgr.ins(g):set(k, v)
end 

local function cfgget(g, k)
	return cfgmgr.ins(g):get(k)
end


local function ap2ac(apid, kvmap)
	local nmap = {}
	for k, v in pairs(kvmap) do 
		if k:find("^a#") then 
			nmap[apid .. "#" .. k] = v
		else 
			nmap[k] = v 
		end 
	end 
	return nmap
end

local function ac2ap(apid, kvmap)
	local nmap = {}
	local prefix = "^" .. apid
	for k, v in pairs(kvmap) do 
		if k:find(prefix) then 
			nmap[k:sub(19)] = v 
		else 
			nmap[k] = v
		end 
	end 
	return nmap
end 

local function aplist(group) 
	local s = cfgget(group, keys.c_ap_list) or "{}"
	local arr = js.decode(s) 							assert(arr) 
	return arr 
end

local function find_apid(apid, aparr)
	for _, mac in ipairs(aparr) do 
		if apid == mac then 
			return true 
		end
	end 	
	return false
end

local function find_ap_config(group, apid)
	assert(group and #apid == 17)
	local aparr = aplist(group)

	local kparr = {}
	for _, kp in pairs(keys) do
		local _ = kp:find("^APID") and table.insert(kparr, kp)
	end
	
	local fix = {}
	for _, band in ipairs({"2g", "5g"}) do
		local rt = {APID = apid, BAND = band}
		for _, kp in pairs(kparr) do 
			local k = pkey.key(kp, rt)
			local v = cfgget(group, k)
			local _ = v or log.error("missing %s %s", group, k)
			fix[k] = v 
		end
	end

	-- 公共配置
	local extra = {
		keys.c_g_country,
		keys.c_g_ld_switch,
		keys.c_ag_reboot,
		keys.c_ag_sta_cycle,
		keys.c_ag_rdo_cycle, 
		keys.c_ag_rs_switch,
		keys.c_ag_rs_rate,
		keys.c_ag_rs_mult,
		keys.c_upload_log,
		keys.c_rs_iso,
		keys.c_rs_inspeed,
		keys.c_g_debug,
	}

	for _, k in ipairs(extra) do  
		local v = cfgget(group, k)
		local _ = v or log.fatal("missing %s", k)
		fix[k] = v
	end

	-- WLAN 配置
	local kparr = {}
	for _, kp in pairs(keys) do
		local _ = kp:find("^w#WLANID") and table.insert(kparr, kp)
	end

	local wlan_map = {}
	local wlan_belong_k = pkey.wlanids(apid)

	local wlanlist = js.decode(cfgget(group, wlan_belong_k)) 	assert(wlanlist)
	for _, wlanid in ipairs(wlanlist) do 
		local map = wlan_map[wlanid] or {}
		for _, kp in ipairs(kparr) do
			local k = pkey.key(kp, {WLANID = wlanid})
			local v = cfgget(group, k)
			local _ = v or log.fatal("missing %s", k)
			map[k] = v
		end
		wlan_map[wlanid] = map
	end

	return {fix = ac2ap(apid, fix), wlan = wlan_map}
end

local function register(cmd)
	local data = cmd.data 						assert(data)
	local apid, group = data[1], data[2]		assert(#apid == 17 and group)
	local aparr = aplist(group)
	local exist = find_apid(apid, aparr)
	local version_k = pkey.version(apid) 

	online.set_noupgrade(group, apid)

	if cmd.cmd == "check" then 	-- 检查apid的配置是否存在
		if not exist then
			log.debug("apid %s %s not exist", apid, group)
			return 0
		end

		local ver = data[3] 		assert(ver)
		local curver = cfgget(group, version_k)			assert(curver)
		if ver == curver then
			return 1
		end
		
		-- version不一样，用AC的配置替换AP的配置
		log.debug("diff cfg %s %s", apid, group)
		local cfg_map = find_ap_config(group, apid)  
		return 1, {[apid] = cfg_map}
	end

	assert(cmd.cmd == "upload")
	local group = data[2] 		
	local kvmap = data[3] 		assert(type(kvmap) == "table")

	local ver = os.date("%Y%m%d %H%M%S")
	kvmap[version_k] = ver

	-- 加入AP列表
	if not exist then 
		log.debug("new apid %s %s %s", apid, group, ver)

		table.insert(aparr, apid) 
		cfgset(group, keys.c_ap_list, js.encode(aparr))
	end
	for k, v in pairs(kvmap) do
		k = k:find("^a#") and apid .. "#" .. k or k
		local _ = cfgget(group, k) == nil and cfgset(group, k, v) 	-- 可能AP有新增配置，此时补上。已经存在的配置以AC为准
	end

	return 1
end

local function del_ap(map) 
	local group, apid_arr = map.group, map.arr
	
	-- 关联key ：wlan_belong，g_ap_list，g_wlan_list 
	local k = keys.c_ap_list
	local s = cfgget(group, k) 						assert(s)
	local aplist = js.decode(s) 					assert(aplist)
	for _, apid in ipairs(apid_arr) do 
		-- 从wlan的ap列表中删除apid 
		local c_belong_s = cfgget(group, pkey.wlanids(apid)) 		assert(c_belong_s)
		local c_wlan = js.decode(c_belong_s) 			assert(c_wlan)
		for _, wlanid in ipairs(c_wlan) do 
			assert(#wlanid == 5)
						
			local waplist_k = pkey.waplist(wlanid)
			local s = cfgget(group, waplist_k)
			local wlan_aplist = js.decode(s) 	assert(type(wlan_aplist) == "table")

			local find = false
			for i = 1, #wlan_aplist do 
				local tmp = table.remove(wlan_aplist, 1)
				if tmp == apid then 
					find = true
					break
				end
				table.insert(wlan_aplist, tmp)
			end

			local _ = find or log.error("missing %s in %s", apid, s)
			if find then  
				cfgset(group, waplist_k, js.encode(wlan_aplist))
			end
		end

		-- 从g_ap_list删除apid 
		for i = 1, #aplist do 
			local tmp = table.remove(aplist, 1)
			if tmp == apid then 
				break
			end
			table.insert(aplist, tmp)
		end 

		-- 删除所有apid的配置
		for _, kp in pairs(keys) do 
			if kp:find("^APID") then 
				for _, band in ipairs({"2g", "5g"}) do 
					local k = pkey.key(kp, {APID = apid, BAND = band}) 
					cfgset(group, k, nil)
				end
			end
		end
	end
	
	local k, v = keys.c_ap_list, js.encode(aplist)
	cfgset(group, k, v)
end

local function set_ap(map)
	local group, kpmap, aparr, batch = map.group, map.kpmap, map.aparr, map.batch 	assert(group and map and aparr and batch)
	
	local apid_map = {}
	local allap = aplist(group)
	local ver = os.date("%Y%m%d %H%M%S")

	for _, apid in pairs(aparr) do 
		assert(#apid == 17)
 		
		local exist = find_apid(apid, allap)
		if exist then 
	 		local change = false
			for kp, v in pairs(kpmap.fix) do 
				local k = pkey.key(kp, {APID = apid})
				change = cfgset(group, k, v) and true or change 
			end

			for band, rmap in pairs(kpmap.radio) do
				local skip_chanid = batch["batch_" .. band] == "0"
				for kp, v in pairs(rmap) do 
					local update = true
					if kp == "APID#a#BAND#chanid" and skip_chanid then
						update = false
					end
					if update then 
						local k = pkey.key(kp, {APID = apid, BAND = band}) 
						change = cfgset(group, k, v) and true or change 
					end
				end
			end

			if change then  
				cfgset(group, pkey.version(apid), ver)  
				apid_map[apid] = find_ap_config(group, apid)
			end
		end 
	end 

	return apid_map
end

local function set_network(map) 
	local apid_map = {}
	local ver = os.date("%Y%m%d %H%M%S")
	
	local group = "default" -- TODO
	local apid, kvmap = map.apid, map.data

	local aparr = aplist(group)
	local exist = find_apid(apid, aparr)

	if not exist then 
		log.error("not exist %s", apid)
		return {}
	end

	kvmap = ap2ac(apid, kvmap)
	local versionk = pkey.version(apid)
	kvmap[versionk] = ver 
	
	for k, v in pairs(kvmap) do
		local ov = cfgget(group, k)
		if not ov then 
			log.error("missing %s", k)
			return {}
		end

		cfgset(group, k, v)
	end
		
	return {[apid] = find_ap_config(group, apid)}
end

local function next_wlanid(group)
	local s = cfgget(group, keys.c_wlan_list) or "{}"
	local wlanlist = js.decode(s)	assert(wlanlist)
	
	local max = 0
	for _, wlanid in ipairs(wlanlist) do 
		local d = tonumber(wlanid) 
		if d > max then 
			max = d 
		end 
	end 
	
	local s = cfgget(group, keys.c_wlan_current) or "0"
	local cur = tonumber(s)
	max = max > cur and max or cur 
	local new = string.format("%05d", max + 1)
	table.insert(wlanlist, new)
	return new, js.encode(wlanlist)
end

local function add_wlan(map)
	local group, map = map.group, map.map  	assert(group and map)
	local change_map, newmap = {}, {}

	-- 选出下一个wlanid
	local wlanid, new_wlanlist = next_wlanid(group)

	-- 选出WLAN配置
	for kp, v in pairs(map) do 
		local k = pkey.key(kp, {WLANID = wlanid})
		change_map[k] = type(v) == "table" and js.encode(v) or v
		if kp:find("^w#WLANID") then 
			newmap[k] = change_map[k]
		end
	end

	local aplist_k = pkey.waplist(wlanid)
	change_map[aplist_k] = js.encode(map[keys.c_waplist])
	change_map[keys.c_wlan_current] = "" .. tonumber(wlanid)
	
	-- 更新版本号
	local ver = os.date("%Y%m%d %H%M%S") 
	local aparr = js.decode(change_map[aplist_k]) 	assert(aparr)
	for _, apid in ipairs(aparr) do 
		assert(#apid == 17)
		
		local wlan_belong_k = pkey.wlanids(apid)
		local wlanlist = js.decode(cfgget(group, wlan_belong_k)) 	assert(wlanlist)
		table.insert(wlanlist, wlanid)

		local version_k = pkey.version(apid)
		change_map[version_k] = ver
		change_map[wlan_belong_k] = js.encode(wlanlist)
	end

	-- 更新wlan_list
	change_map[keys.c_wlan_list] = new_wlanlist

	-- 更新配置文件和数据库
	for k, v in pairs(change_map) do
		cfgset(group, k, v)
	end

	local apid_map = {}
	for _, apid in ipairs(aparr) do
		apid_map[apid] = find_ap_config(group, apid)
	end

	return apid_map
end

local function del_wlan(map)
	local group, map = map.group, map.map  	assert(group and map)
	
	-- 关联key ：wlan_belong，g_wlan_list
	local change_map, del_map = {}, {}
	local s = cfgget(group, keys.c_wlan_list) or "{}"
	local arr = js.decode(s)						assert(arr)

	-- 修改g_wlan_list
	for i = 1, #arr do 
		local tmp = table.remove(arr, 1)
		local _ = map[tmp] or table.insert(arr, tmp)			
	end

	change_map[keys.c_wlan_list] = js.encode(arr)

	-- 找到WLAN的所有key pattern
	local del_kp = {}
	for _, kp in pairs(keys) do 
		local _ = kp:find("^w+#WLANID") and table.insert(del_kp, kp) 
	end
	
	-- 找出所有要删除的key
	local delkmap = {}
	for wlanid, ssid in pairs(map) do 
		assert(#wlanid == 5)
		for _, kp in ipairs(del_kp) do
			local k = pkey.key(kp, {WLANID = wlanid})
			delkmap[k] = 1
			print("del", k)
		end

		local k = pkey.waplist(wlanid) 
		local aparr = js.decode(cfgget(group, k))	assert(aparr)
		for _, apid in ipairs(aparr) do 
			assert(#apid == 17)
			local tmp_map = del_map[apid] or {}  
			tmp_map[wlanid] = 1 
			del_map[apid] = tmp_map
		end
	end

	-- 修改AP对应的wlanids
	for apid, wlanid_map in pairs(del_map) do
		local wlan_belong_k = pkey.wlanids(apid)
		local wlanlist = js.decode(cfgget(group, wlan_belong_k)) 	assert(wlanlist)
		for i = 1, #wlanlist do 
			local tmp = table.remove(wlanlist, 1)	assert(#tmp == 5)
			local _ = wlanid_map[tmp] or table.insert(wlanlist, tmp)
		end
		change_map[wlan_belong_k] = js.encode(wlanlist)
	end

	-- 修改AP配置版本号
	local ver = os.date("%Y%m%d %H%M%S")
	for apid in pairs(del_map) do
		local version_k = pkey.version(apid)
		change_map[version_k] = ver
	end
	
	-- 修改cfg
	for k, v in pairs(change_map) do 
		cfgset(group, k, v)
	end

	for k in pairs(delkmap) do 
		cfgset(group, k, nil)
	end

	-- 组织
	local apid_map = {}
	for apid in pairs(del_map) do
		apid_map[apid] = find_ap_config(group, apid)
	end

	return apid_map
end

local function mod_wlan(map) 
	local group, change, wlanid, op_map = map.group, map.change, map.wlanid, map.op_map 	assert(group and change and #wlanid == 5 and op_map)

	-- WLAN配置修改
	local karr = {}
	for _, kp in pairs(keys) do 
		local _ = kp:find("^w#WLANID") and table.insert(karr, pkey.key(kp, {WLANID = wlanid}))
	end

	-- 收集wlanid对应的所有配置
	local change_map = {}
	for _, k in ipairs(karr) do
		if change[k] ~= nil then 
			change_map[k] = change[k]
		else
			change_map[k] = cfgget(group, k)
		end
	end

	local apid_map = {}
	local ver = os.date("%Y%m%d %H%M%S") 

	-- add
	for _, apid in ipairs(op_map.add) do 
		assert(#apid == 17)
		apid_map[apid] = {}
		
		local version_k = pkey.version(apid)
		local belong_k = pkey.wlanids(apid)
		local wlanlist = js.decode(cfgget(group, belong_k)) 	assert(wlanlist)
		table.insert(wlanlist, wlanid)

		change[version_k] = ver
		change[belong_k] = js.encode(wlanlist) 
	end

	-- del 
	for _, apid in ipairs(op_map.del) do 
		assert(#apid == 17)
		apid_map[apid] = {}
		
		local version_k = pkey.version(apid)
		local belong_k = pkey.wlanids(apid)
		local wlanlist = js.decode(cfgget(group, belong_k)) 	assert(wlanlist)
		for i = 1, #wlanlist do 
			local tmp = table.remove(wlanlist, 1)	assert(#tmp == 5)
			local _ = wlanid == tmp or table.insert(wlanlist, tmp)
		end

		change[version_k] = ver
		change[belong_k] = js.encode(wlanlist) 
	end	

	-- mod
	for _, apid in ipairs(op_map.modify) do 
		assert(#apid == 17)
		apid_map[apid] = {}
		
		local version_k = pkey.version(apid)
		change[version_k] = ver 
	end

	-- 设置配置和数据库
	for k, v in pairs(change) do
		cfgset(group, k, v)
	end
	
	local nmap = {}
	for apid in pairs(apid_map) do 
		nmap[apid] = find_ap_config(group, apid)
	end
	
	return nmap
end

local function set_ctry(map)
	local group, ctry = map.group, map.ctry  	assert(group and ctry)

	local change_map = {}
	change_map[keys.c_g_country] = ctry

	local ver = os.date("%Y%m%d %H%M%S") 
	local s = cfgget(group, keys.c_ap_list) or "{}"
	local aparr = js.decode(s) 	assert(aparr)
	
	for _, apid in ipairs(aparr) do 
		local version_k = pkey.version(apid)
		change_map[version_k] = ver
	end

	for k, v in pairs(change_map) do 
		cfgset(group, k, v)
	end 
	
	local apid_map = {}
	for _, apid in ipairs(aparr) do 
		apid_map[apid] = find_ap_config(group, apid)
	end 
	
	return apid_map
end

local function set_load(map)
	local group, change_map = map.group, map.map 	assert(group and change_map)

	for k, v in pairs(change_map) do 
		cfgset(group, k, v)
	end 
end

local function set_opti(map)
	local group, map = map.group, map.map  	assert(group and map)
	
	local change_map = {}

	local ver = os.date("%Y%m%d %H%M%S") 
	local aparr = js.decode(cfgget(group, keys.c_ap_list)) 	assert(aparr)

	for k, v in pairs(map) do 
		change_map[k] = v
	end

	for _, apid in pairs(aparr) do 
		local fix = {}
		local version_k = pkey.version(apid)
		change_map[version_k], fix[version_k] = ver, ver
		for k, v in pairs(map) do 
			fix[k] = v
		end 
	end

	for k, v in pairs(change_map) do 
		cfgset(group, k, v)
	end 
	
	local apid_map = {}
	for _, apid in ipairs(aparr) do 
		apid_map[apid] = find_ap_config(group, apid)
	end 

	return apid_map
end

local function wlan_stat(map)
	local group, arr = map.group, map.arr  	assert(group and arr)
	local wlanid, state = arr[1], arr[2] 	assert(#wlanid == 5 and state ~= nil)
	local ver = os.date("%Y%m%d %H%M%S")  

	local change_map = {}
	local wlan_state_k = pkey.wstate(wlanid)
	change_map[wlan_state_k] = state

	local aplist_k = pkey.waplist(wlanid)
	local s = cfgget(group, aplist_k)

	local aparr = js.decode(s) 	assert(aparr)
	for _, apid in pairs(aparr) do 
		local fix = {}
		local version_k = pkey.version(apid)
		change_map[version_k], fix[version_k], fix[wlan_state_k] = ver, ver, state
	end

	for k, v in pairs(change_map) do 
		cfgset(group, k, v)
	end 
	
	local apid_map = {}
	for _, apid in ipairs(aparr) do 
		apid_map[apid] = find_ap_config(group, apid)
	end 

	return apid_map
end

local function set_debug(map)
	local group, debug = map.group, map.debug  	assert(group and debug)

	local change_map = {}
	change_map[keys.c_g_debug] = debug

	local ver = os.date("%Y%m%d %H%M%S") 
	local s = cfgget(group, keys.c_ap_list) or "{}"
	local aparr = js.decode(s) 	assert(aparr)
	
	for _, apid in ipairs(aparr) do 
		local version_k = pkey.version(apid)
		change_map[version_k] = ver
	end

	for k, v in pairs(change_map) do 
		cfgset(group, k, v)
	end 
	
	local apid_map = {}
	for _, apid in ipairs(aparr) do 
		apid_map[apid] = find_ap_config(group, apid)
	end 
	
	return apid_map
end


return {
	register = register,
	del_ap = del_ap,
	set_ap = set_ap,
	add_wlan = add_wlan,
	del_wlan = del_wlan,
	mod_wlan = mod_wlan,
	set_ctry = set_ctry,
	set_load = set_load,
	set_opti = set_opti,
	wlan_stat = wlan_stat,
	set_network = set_network,
	find_ap_config = find_ap_config,
	set_debug = set_debug,
}
