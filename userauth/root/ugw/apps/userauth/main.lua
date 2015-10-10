local se = require("se")
local log = require("log")
local sandc = require("sandc")
local js = require("cjson.safe")
local kernelop = require("kernelop") 
local dispatcher = require("dispatcher")

local mqtt
local function cursec()
	return math.floor(se.time())
end

local cmd_map = {
	auth = dispatcher.auth,

	user_set = dispatcher.user_set,
	user_del = dispatcher.user_del,
	user_add = dispatcher.user_add,
	user_get = dispatcher.user_get,
	
	policy_set = dispatcher.policy_set,
	policy_add = dispatcher.policy_add,
	policy_del = dispatcher.policy_del,
	policy_adj = dispatcher.policy_adj,
	policy_get = dispatcher.policy_get,

	online_del = dispatcher.online_del,
	online_get = dispatcher.online_get,
}

local function on_message(topic, data)
	local map = js.decode(data)
	if not (map and map.pld) then 
		print("invalid data 1", data)
		return 
	end

	local cmd = map.pld 
	local func = cmd_map[cmd.cmd]
	if not func then 
		print("invalid data 2", data)
		return
	end

	local res = func(cmd.data)
	if map.mod and map.seq then 
		local res = mqtt:publish(map.mod, js.encode({seq = map.seq, pld = res}), 0, false)
		local _ = res or log.fatal("publish %s fail", map.mod)
	end
end

local function timeout_save()
	dispatcher.save()
end

local function create_mqtt()
	local auth_module = "a/ac/userauth"
	local mqtt = sandc.new(auth_module)
	mqtt:set_auth("ewrdcv34!@@@zvdasfFD*s34!@@@fadefsasfvadsfewa123$", "1fff89167~!223423@$$%^^&&&*&*}{}|/.,/.,.,<>?")
	mqtt:pre_subscribe(auth_module)
	local ret, err = mqtt:connect("127.0.0.1", 61886)
	local _ = ret or log.fatal("connect fail %s", err)
	mqtt:set_callback("on_message", on_message)
	mqtt:set_callback("on_disconnect", function(...) 
		print("on_disconnect", ...)
		log.fatal("mqtt disconnect")
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
	kernelop.reset()

	mqtt = create_mqtt()

	set_timeout(10, 10, timeout_save)
	set_timeout(5, 5, kernelop.check_network)
	set_timeout(120, 120, dispatcher.update_user)
	set_timeout(1, 20, dispatcher.update_online)
	set_timeout(0.1, 1800, dispatcher.adjust_elapse)
end

log.setdebug(true)
log.setmodule("ua")

se.run(main)

