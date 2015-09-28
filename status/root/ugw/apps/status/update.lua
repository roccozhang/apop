local se = require("se")
local log = require("log") 
local pkey = require("key")
local js = require("cjson.safe") 
local const = require("constant")  
local memfile = require("memfile")

local rds
local keys = const.keys 

local function cursec()
	return math.floor(se.time())
end 

local function current_time(apid, isnew)
	local t = os.date("*t") 
	return string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year, t.month, t.day, t.hour, t.min, t.sec) 
end

local function update_basic(apid, map, kvmap) 
	kvmap[keys.s_fireware] = map.fire
	kvmap[keys.s_uptime] = map.uptime 
	-- kvmap[keys.s_login] = current_time(apid) 	-- 更新AP上线时间 
end

local function update_assoc(apid, map, kvmap) 
	for band, arr in pairs(map) do  
		kvmap[pkey.key(keys.s_sta, {BAND = band})] = js.encode(arr) 
	end
end 

local function update_wlan(apid, map, kvmap)  
	for band, map in pairs(map) do 
		local narr, warr = {}, {}

		-- {"bd":"c0:61:18:f6:c0:27","sd":"ZTKAP","ch":"1","rs":-98}
		for _, item in ipairs(map.nap or {}) do 
			table.insert(narr, {apid = item.bd, rssi = item.rs, channel_id = item.ch})
		end 
		for _, item in ipairs(map.nwlan or {}) do 
			table.insert(warr, {bssid = item.bd, rssi = item.rs, channel_id = item.ch, ssid = item.sd})
		end 

		kvmap[pkey.key(keys.s_naps, {BAND = band})] = js.encode(narr)
		kvmap[pkey.key(keys.s_nwlans, {BAND = band})] = js.encode(warr)  
	end 
end 

local function update_radio(apid, map, kvmap) 
	for band, map in pairs(map) do  
		kvmap[pkey.key(keys.s_users, {BAND = band})] = map.usr 
		kvmap[pkey.key(keys.s_chanid, {BAND = band})] = map.cid
		kvmap[pkey.key(keys.s_chanuse, {BAND = band})] = map.use
		kvmap[pkey.key(keys.s_power, {BAND = band})] = map.pow
		kvmap[pkey.key(keys.s_maxpow, {BAND = band})] = map.max
		kvmap[pkey.key(keys.s_proto, {BAND = band})] = map.pro
		kvmap[pkey.key(keys.s_noise, {BAND = band})] = map.nos
		kvmap[pkey.key(keys.s_bandwidth, {BAND = band})] = map.bdw
		kvmap[pkey.key(keys.s_run, {BAND = band})] = js.encode(map.run)  
	end 
end 

-- 获取待删除的日志文件
local function get_delete_files(apid_dir)
	local cmd = string.format("cd %s && ls -t log_end* 2>/dev/null", apid_dir)

	local fp = io.popen(cmd, "r")
	if not fp then 
		return {}
	end 

	local file_arr = {}
	while true do 
		local line = fp:read("*l")
		if not line then 
			break 
		end
		table.insert(file_arr, line)
	end
	fp:close()

	local maxfiles = 10
	if #file_arr <= maxfiles then 
		return {}
	end
	
	local del_arr = {}
	for i = maxfiles + 1, #file_arr do 
		table.insert(del_arr, file_arr[i])
	end

	return del_arr
end

local function save_log(apid, map)
	local aplog_dir = "/ugw/log/aplog/"
	local apid_dir = aplog_dir .. apid 

	for _, dir in ipairs({aplog_dir, apid_dir}) do 
		local _ = lfs.attributes(dir) or lfs.mkdir(dir) 
	end

	for filename, content in pairs(map) do
		local filepath = string.format("%s/%s", apid_dir, filename)
		if filename:find("log_end") and lfs.attributes(filepath) then
			filepath = nil
		end

		if filepath then
			local fp, err = io.open(filepath, "wb")
			if not fp then 
				log.error("open %s fail %s", filepath, err)
			else
				fp:write(content)
				fp:flush()
				fp:close()
			end
		end
	end

	local del_arr = get_delete_files(apid_dir)
	for _, filename in ipairs(del_arr) do 
		local filepath = string.format("%s/%s", apid_dir, filename)
		local ret, err = os.remove(filepath)
		local _ = ret or log.error("remove %s fail %s", filepath, err) 
	end
end

local function set_rds(r)
	rds = r
end

local basic_func_map = {
	log = save_log,
	basic = update_basic,
}

local band_func_map = {
	assoc = update_assoc, 
	wlan = update_wlan,
	radio = update_radio,
}

local function isempty(map)
	for k in pairs(map) do 
		return false 
	end 
	return true 
end

local last_expire = {}
local expire_time = 180
local function update(group, apid, map)
	local kvmap = {}
	for t, func in pairs(basic_func_map) do  
		local data = map[t]
		local _ = data and func(apid, data, kvmap) 
	end 

	for t, func in pairs(band_func_map) do 
		local data = map[t]
		local _ = data and func(apid, data, kvmap) 
	end

	if isempty(kvmap) then 
		return
	end

	local hkey = pkey.state_hash(apid)
	local ret = rds:hmset(hkey, kvmap) 	assert(ret)
	local last, now = last_expire[hkey] or 0, cursec()
	if now - last > expire_time / 3 * 2 then 
		local ret = rds:expire(hkey, expire_time) 	assert(ret)
		last_expire[hkey] = now
	end
end

return {
	set_rds = set_rds, 
	update = update, 
}