require("global")
local se = require("se")
local log = require("log")
local pkey = require("key") 
local sandc = require("sandc")
local redis = require("lredis")
local online = require("online")
local js = require("cjson.safe") 
local const = require("constant") 
local cfgmgr = require("cfgmanager")
local dispatch = require("dispatch")


local keys = const.keys

local mqtt, rds
local topic_map = {} 

local function cursec()
	return os.time()
end

local function cfgset(g, k, v)
	cfgmgr.ins(g):set(k, v)
end 

local function cfgget(g, k)
	return cfgmgr.ins(g):get(k)
end

local function mqtt_publish(t, s)
	assert(t and s)
	return mqtt:publish(t, s) 
end

local function replace_notify(apid_map) 
	for apid, map in pairs(apid_map) do 
		local p = {
			mod = "a/local/cfgmgr",
			pld = {cmd = "replace", data = map},
		}
		-- print("a/ap/" .. apid, js.encode(p))
		local _ = mqtt_publish("a/ap/" .. apid, js.encode(p)) or log.fatal("publish fail")
	end
end

topic_map["a/ac/query/version"] = function(map) 
	local data = map.pld 
	local group, apid, ver = data[1], data[2], data[3] 	
	if not (group and apid and #apid == 17 and ver) then
		return 
	end
	
	online.set_online(group, apid)

	local key = pkey.version(apid)
	local curver = cfgget(group, key)
	if not curver then
		log.error("cannot find version %s, regard as delete", key) 
		local p = {
			mod = map.mod,
			-- seq = map.seq,
			pld = {cmd = "delete", data = {"version+"}},
		}
		local _ = mqtt_publish(map.tpc, js.encode(p)) or log.fatal("publish fail")
		return
	end

	if ver == curver then 
		return 
	end

	replace_notify( {[apid] = dispatch.find_ap_config(group, apid)})
end

topic_map["a/ac/cfgmgr/register"] = function(map) 
	-- {"pld":data,"mod":reply_mod,"seq":reply_seq, "tpc":reply_topic}
	local res, apid, apid_map = dispatch.register(map.pld)
	
	local p = {
		mod = map.mod,
		seq = map.seq,
		pld = res,
	}

	local _ = mqtt_publish(map.tpc, js.encode(p)) or log.fatal("publish fail")
	local _ = apid_map and replace_notify(apid_map) 
end

local modify_map = {}

local function update_ap(apid_map)
	for apid, map in pairs(apid_map) do
		local res = {cmd = "update", data = map}
		local p = {
			mod = "a/local/cfgmgr",
			pld = res,
		}
		local _ = mqtt_publish("a/ap/" .. apid, js.encode(p)) or log.fatal("publish fail")
	end
end

modify_map["set_ap"] = function(data, set_done_cb) 
	local _ = set_done_cb(), update_ap(dispatch.set_ap(data))
end

modify_map["del_ap"] = function(map, set_done_cb)
	local _ = dispatch.del_ap(map), set_done_cb()
	
	for _, apid in ipairs(map.arr) do 
		assert(#apid == 17)

		local p = {
			mod = "a/local/cfgmgr", 
			pld = {cmd = "delete", data = {"del_ap+"}},
		}
		
		local _ = mqtt_publish("a/ap/" .. apid, js.encode(p)) or log.fatal("publish fail")
	end
end

modify_map["upgrade"] = function(map, set_done_cb) 
	local group, arr = map.group, map.arr 	assert(group and arr)
	for _, apid in ipairs(arr) do 
		online.set_upgrade(group, apid)
		local p = {
			mod = "a/local/cfgmgr",
			pld = {cmd = "upgrade", data = {host = cfgget(group, keys.c_update_host)}}, 	-- TODO host 
		}
		local _ = mqtt_publish("a/ap/" .. apid, js.encode(p)) or log.fatal("publish fail")
	end

	set_done_cb()
end

modify_map["add_wlan"] = function(map, set_done_cb) 
	local _ = set_done_cb(), update_ap(dispatch.add_wlan(map))
end

modify_map["del_wlan"] = function(map, set_done_cb)  
	local _ = set_done_cb(), update_ap(dispatch.del_wlan(map))
end

modify_map["mod_wlan"] = function(map, set_done_cb)  
	local _ = set_done_cb(), update_ap(dispatch.mod_wlan(map))
end

modify_map["set_ctry"] = function(map, set_done_cb) 
	local _ = set_done_cb(), update_ap(dispatch.set_ctry(map))
end

modify_map["set_load"] = function(map, set_done_cb) 
	local _ = dispatch.set_load(map), set_done_cb() 	
end

modify_map["set_opti"] = function(map, set_done_cb) 
	local _ = set_done_cb(), update_ap(dispatch.set_opti(map))
end

modify_map["wlan_stat"] = function(map, set_done_cb)  
	local _ = set_done_cb(), update_ap(dispatch.wlan_stat(map))
end

modify_map["set_debug"] = function(map, set_done_cb) 
	local _ = set_done_cb(), update_ap(dispatch.set_debug(map))
end

topic_map["a/ac/cfgmgr/modify"] = function(map)
	local cmd = map.pld 
	local func = modify_map[cmd.cmd]

	if func then 
		-- 设置配置文件和数据库完成，在下发通知到AP前调用，通知调用模块
		local done_cb = function()
			local _ = mqtt_publish(map.mod, js.encode({seq = map.seq, pld = true}), 0, false) or log.fatal("publish fail")
		end
		return func(cmd.data, done_cb)
	end

	log.error("not support %s", js.encode(map))
end

topic_map["a/ac/cfgmgr/network"] = function(map)
	update_ap(dispatch.set_network(map.pld))
end

topic_map["a/ac/cfgmgr/query"] = function(map)  
	if not (map and map.pld and map.mod and map.seq) then 
		return
	end 
	
	local m = map.pld
	if not m then 
		return 
	end 
	
	local group, karr = m.group, m.karr
	if not (group and karr) then 
		return 
	end
	
	local varr, idx = {}, 1
	for _, k in ipairs(karr) do
		idx, varr[idx] = idx + 1, cfgget(group, k) 
	end

	local _ = mqtt_publish(map.mod, js.encode({seq = map.seq, pld = varr}), 0, false) or log.fatal("publish fail")
end

topic_map["a/ac/query/will"] = function(map)
	if not (map and map.apid and map.group) then
		return 
	end 
	online.set_offline(map.group, map.apid)
end

topic_map["a/ac/query/connect"] = function(map)
	local arr = map.pld
	if not arr then 
		return 
	end  

	local group, apid = arr[1], arr[2] 	assert(#apid == 17)
	if not (group and apid) then 
		return
	end 

	online.set_online(group, apid)

	local t = os.date("*t") 
	local s = string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year, t.month, t.day, t.hour, t.min, t.sec) 
	local hkey = string.format("login/%s", group) 
	local ret = rds:hset(hkey, apid, s)  
end
 
topic_map["a/ac/query/noupdate"] = function(map)
	local map = map.pld
	if not (map and map.group and map.apid) then 
		return 
	end
	online.set_noupgrade(map.group, map.apid)
end

local function on_message(topic, data)   
	local func = topic_map[topic] 
	if func then 
		local map = js.decode(data)
		local _ = map and func(map)
		return
	end

	log.error("invalid topic %s %s", topic, data)
end

local function connect_rds()
	rds = redis.connect("127.0.0.1", 6379) 	assert(rds)  
end

local function create_mqtt()
	local this_module = "a/ac/cfgmgr"
	local mqtt = sandc.new(this_module)
	mqtt:set_auth("ewrdcv34!@@@zvdasfFD*s34!@@@fadefsasfvadsfewa123$", "1fff89167~!223423@$$%^^&&&*&*}{}|/.,/.,.,<>?")

	mqtt:pre_subscribe("a/ac/query/version",
					"a/ac/cfgmgr/register",
					"a/ac/cfgmgr/modify",
					"a/ac/cfgmgr/network",
					"a/ac/cfgmgr/query",
					"a/ac/query/will",
					"a/ac/query/connect",
					"a/ac/query/noupdate")
	local ret, err = mqtt:connect("127.0.0.1", 61886)
	local _ = ret or log.fatal("connect fail %s", err)
	mqtt:set_callback("on_message", on_message)
	mqtt:set_callback("on_disconnect", function(st, err)  
		log.fatal("mqtt close %s %s", st, err) 
	end)
	mqtt:run()

	return mqtt
end

local function set_timeout(timeout, again, cb)
	se.sleep(timeout)
	while true do 
		cb()
		se.sleep(again)
	end
end

local function main()
	log.info("start cfgmgr")

	connect_rds()
	online.set_rds(rds)

	mqtt = create_mqtt()
	set_timeout(3, 3, cfgmgr.save_all)
end

log.setdebug(true)
log.setmodule("cm")
se.run(main)