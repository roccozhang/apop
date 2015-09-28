require("global")
local se = require("se")
local log = require("log")
local lfs = require("lfs")
local auth = require("auth")
local user = require("user") 
local radio = require("radio")
local aplog = require("aplog")
local struct = require("struct")
local mredis = require("mredis") 
local js = require("cjson.safe")
local wlan = require("wlanssid")
local const = require("constant")
local aps = require("apmlistaps") 
local collect = require("collect")
local glbcfg = require("globalcfg")
local load = require("loadbalance") 
local upaps = require("apmupdateaps")
local cfgclient = require("cfgclient")
local optimal = require("optimization")
local firelist = require("apmfirewarelist")

local pcli
local is_ac
local tcp_addr = "tcp://0.0.0.0:9997"
local rds_addr = "tcp://127.0.0.1:6379"

local cmd_func = {
	ApmListAPs = aps.apmlistaps,
	ApmDeleteAps = upaps.apmdeleteaps,
	ApmUpdateAps = upaps.apmupdateaps,
	ApmFirewareList = firelist.apmfirewarelist,
	ApmUpdateFireware = firelist.apmupdatefireware,
	WLANList = wlan.wlanlist,
	WLANAdd = wlan.wlanadd,
	WLANDelete = wlan.wlandelete,
	WLANModify = wlan.wlanmodify,
	WLANListAps = wlan.wlanlistaps,
	RadioList = radio.radiolist,
	NWLAN = radio.nwlan,
	WLANState = radio.wlanstate, 
	ApmListUsers = user.apmlistusers,
	GetHideColumns = glbcfg.get_hide_columns,
	DtHideColumns = glbcfg.hide_columns,
	GetBandSupport = glbcfg.get_band_support,
	SetCountry = glbcfg.set_country,
	GetApLog = aplog.getaplog,
	DownloadApLog = aplog.downloadaplog,
	ApmExecCommands = glbcfg.execute_cmd,
	OnlineAplist = glbcfg.online_ap_list,
	GetLoadBalance = load.load_balance,
	SaveLoadBalance = load.save_load_balance,
	GetOptimization = optimal.optimization,
	SaveOptimization = optimal.save_optimization,
	DebugSwitch		 = glbcfg.set_debug,
	UserImport = auth.userimport,
	UserAdd = auth.useradd,
	UserDel = auth.userdel,
	UserSet = auth.userset,
	UserGet = auth.userget,
	PolicyAdd = auth.policyadd,
	PolicyDel = auth.policydel,
	PolicySet = auth.policyset,
	PolicyAdj = auth.policyadj,
	PolicyGet = auth.policyget,
	OnlineDel = auth.onlinedel,
	OnlineGet = auth.onlineget,
}

local function init_rds()
	mredis.connect_blpop(rds_addr):go()
	mredis.connect_normal(rds_addr):go() 
end

local function read(path, func)
	func = func and func or io.open
	local fp = func(path, "rb")
	if not fp then 
		return 
	end 
	local s = fp:read("*a")
	fp:close()
	return s
end

local function get_group_data(t) 
	if is_ac then 
		-- return "default", t[1]
		local map = t[1]	assert(map.group, t[1])
		return map.group, map.data
	end 
	
	local map = t[1]	assert(map.group, t[1])
	return map.group, map.data
end

local function handle_client(cli)
	local brds, nrds = mredis.blpop_rds(), mredis.normal_rds() 
	
	local content, err = se.read(cli, 4, 5)
	if not content then 
		log.error("read len fail %s", err)
		return se.close(cli)
	end

	local total = struct.unpack("<I", content)
	if total > 1024 * 1024 * 10 then 
		log.error("invalid content len %s", total)
		return se.close(cli)
	end

	local data, err = se.read(cli, total, 5)
	if not data or #data ~= total then 
		return se.close(cli)
	end
	
	local result
	local t = js.decode(data)
	if not t then 
		return se.close(cli)
	end 

	local cmd = table.remove(t, 1)
	local func = cmd_func[cmd] 
	if not func then
		result = js.encode({status = 1, data = "invalid cmd " .. cmd})
		log.error("error cmd %s", result)
	else 
		local group, data = get_group_data(t) 		assert(group)
		collect.update(nrds, group)
		result = func({rds = nrds, pcli = pcli},  group, data) or "error"
		result = type(result) == "string" and result or js.encode(result)
	end

	local data = struct.pack("<I", #result) .. result
	local err = se.write(cli, data)
	local _ = err and log.error("send len %s fail %s", #data, err) 
	se.close(cli) 
end

local function check_ac()
	local s = read("uname -a", io.popen) or "" 
	if s:find("3%.") then 
		is_ac = true 
	end 
end 

local function main()
	log.debug("start rds web ...")
	check_ac()

	local unique = "a/local/rds"
	pcli = cfgclient.new({clientid = unique, topic = unique, port = 61883}) 	assert(pcli)
	pcli:run()

	init_rds()

	local srv, err = se.listen(tcp_addr) 
	local _ = srv or log.fatal("listen %s fail %s", tcp_addr, err)

	-- se.go(function()
	-- 	se.sleep(1)
	-- 	while true do 
	-- 		auth.policyget({rds = "xx", pcli = pcli}, "default", "xxx")
	-- 		se.sleep(3)
	-- 	end
	-- end)

	while true do
		local cli, err = se.accept(srv, 1)
		if cli then
			handle_client(cli)
		elseif err ~= "TIMEOUT" then
			log.fatal("accept error %s", err)
		end
	end
end

local function check_debug()
	while true do  
		log.setdebug(lfs.attributes("/tmp/wac_debug") and true or false) 
		se.sleep(3)
	end
end

log.setmodule("cgi")
se.go(check_debug)
se.go(collect.start)
se.run(main)

