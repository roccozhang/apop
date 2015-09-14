package.path = "./?.lua;"..package.path
local log = require("log")
local js = require("cjson.safe")
local mosquitto = require("mosquitto")
local dispatcher = require("dispatcher")

local mqtt
local function cursec()
	return os.time()
end

local cmd_map = {
	auth = dispatcher.auth,

	user_set = dispatcher.user_set,
	user_del = dispatcher.user_del,
	user_add = dispatcher.user_add,
	
	policy_set = dispatcher.policy_set,
	policy_add = dispatcher.policy_add,
	policy_del = dispatcher.policy_del,
	policy_adj = dispatcher.policy_adj,

	online_del = dispatcher.online_del,
}

local function on_message(mid, topic, data, qos, retain)
	local map = js.decode(data)
	if not (map and map.pld) then 
		print("invalid data", data)
		return 
	end

	local cmd = map.pld 
	local func = cmd_map[cmd.cmd]
	if not func then 
		print("invalid data", data)
		return
	end

	local res = func(cmd.data)
	if map.mod and map.seq then 
		local res = mqtt:publish(map.mod, js.encode({seq = map.seq, pld = res}), 0, false)
		local _ = res or log.fatal("publish %s fail", map.mod)
	end
end

local function subscribe()
	local _ = mqtt:subscribe("a/ac/userauth", 0) or log.fatal("subscribe fail")
end

local function timeout_save()
	dispatcher.save()
end

local function set_timeout(timeout, cb)
	local last = cursec()
	return function()
		local now = cursec()
		if last <= now and now - last < timeout then 
			return
		end

		last = now, cb()
	end
end

local function main() 
	mosquitto.init()

	mqtt = mosquitto.new("a/ac/userauth", false)
	mqtt:login_set("#qmsw2..5#", "@oawifi15%") 
	local _ = mqtt:connect("127.0.0.1", 61883) or log.fatal("connect fail")

	mqtt:callback_set("ON_MESSAGE", on_message)
	mqtt:callback_set("ON_DISCONNECT", function(...)  
		log.fatal("mqtt disconnect %s", js.encode({...}))
	end)

	subscribe()
	local step = 10

	local timeout_arr = {
		set_timeout(10, timeout_save), 
		set_timeout(120, dispatcher.update_user),
		set_timeout(20, dispatcher.update_online),
	}

	while true do
		mqtt:loop(step) 
		for _, func in ipairs(timeout_arr) do 
			func()
		end
	end
end

log.setdebug(true)
log.setmodule("ua")
main()
