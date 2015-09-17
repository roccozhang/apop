local log = require("log") 
local js = require("cjson.safe")
local const = require("constant")  
local pkey = require("key")

local rds, pcli
local keys = const.keys
local mac_pattern = string.rep("[0-9a-x][0-9a-x]:", 5) .. "[0-9a-x][0-9a-x]"

local function errmsg(fmt, ...)
	return string.format(fmt, ...)
end

local function get_band_support(conn, group, data)
	return js.encode({"2g", "5g"})
end

local function notify_wac(cmd_map)
	log.fatal("not implement notify_wac %s", js.encode(cmd_map))
end

local function set_band_support(conn, group, data)
	return js.encode({status = 0, msg = "success"})
end

local function set_country(conn, group, data)
	assert(conn and conn.rds and group)
	rds, pcli = conn.rds, conn.pcli  			assert(rds and pcli)
	local ctry = data 		assert(ctry)

	local country = require("country")
	if not country.short(ctry) then 
		log.error("invlid country %s", ctry)
		return js.encode({status = 1, msg = errmsg("invalid country")})
	end

	local res = pcli:modify({cmd = "set_ctry", data = {group = "default", ctry = ctry}}) 
	return js.encode({status = 0, msg = "success"})
end

local function hide_columns(conn, group, data)
	assert(conn and conn.rds and group)
	rds, pcli = conn.rds, conn.pcli  			assert(rds and pcli) 

	local param = js.decode(data)
	if not (param and param.page ) then 
		return js.encode({state = 1, msg = "invlid param"})
	end

	local page, arr = param.page, param.data or {}
	local s = #arr == 0 and "[]" or js.encode(arr)
	log.debug("set %s %s", page, s)
	rds:set(page, s)
	return js.encode({state = 0, msg = "success"})
end

local function get_hide_columns(conn, group, data)
	assert(conn and conn.rds and group)
	rds, pcli = conn.rds, conn.pcli  			assert(rds and pcli) 
	local page = data	

	if not page then 
		return "false"
	end

	local s = rds:get(page)
	if not s then
		return "false"
	end
	return s
end

local function execute_cmd(conn, group, data)
	assert(conn and conn.rds)
	rds, pcli = conn.rds, conn.pcli  			assert(rds and pcli) 
	local cmditem = js.decode(data)
	if not (cmditem and cmditem.cmd and cmditem.data) then 
		log.error("invalid data %s", data or "")
		return js.encode({status = 1, msg = errmsg("error data")})
	end

	for _, apid in ipairs(cmditem) do 
		if #apid ~= 17 then 
			log.error("invalid data %s", data or "")
			return js.encode({status = 1, msg = errmsg("error data")})
		end
	end

	local cmdmap = {rebootErase = 1, rebootAps = 1} 
	if not cmdmap[cmditem.cmd] then 
		log.error("invalid data %s", cmditem.cmd)
		return js.encode({status = 1, msg = errmsg("error data")})
	end

	local data = {cmd = cmditem.cmd, data = {}}
	for _, apid in ipairs(cmditem.data) do 
		pcli:sendcmd(apid, data)
	end
end

local function online_ap_list(conn, group, data)
	assert(conn and conn.rds)
	rds, pcli = conn.rds, conn.pcli  			assert(rds and pcli) 
	log.fatal("not imlement online_ap_list")
	local aparr = js.decode(rds:get(keys.cfg_ap_list))	assert(aparr)

	local online_map = {}
	for _, apid in ipairs(aparr) do 
		assert(#apid == 17)
		local hkey = pkey.hash_time(apid)
		local active = rds:hget(hkey, keys.as_h_active)
		if active then 
			online_map[apid] = 1
		end 
	end

	return online_map
end

local function set_debug(conn, group, data)
	assert(conn and conn.rds and group)
	rds, pcli = conn.rds, conn.pcli  			assert(rds and pcli)
	local debug = data 		assert(debug)
	local res = pcli:modify({cmd = "set_debug", data = {group = "default", debug = debug}}) 
	return js.encode({status = 0, msg = "success"})
end

return {
	execute_cmd = execute_cmd,
	set_country = set_country,
	hide_columns = hide_columns, 
	online_ap_list = online_ap_list,
	get_hide_columns = get_hide_columns,
	set_band_support = set_band_support,
	get_band_support = get_band_support, 
	set_debug		= set_debug
}
