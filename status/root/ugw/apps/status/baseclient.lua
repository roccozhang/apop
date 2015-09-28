local se = require("se") 
local mosq = require("mosquitto")  

local function yield()
	se.sleep(0.000001)
end

local function numb() return true end

local mt = {}
mt.__index = { 
	publish_internel = function(ins, mqtt)
		while true do 
			local item = ins.publish_cache[1]
			if not item then 
				return 
			end

			if not ins.on_check_out(item) then
				print("abandon", unpack(item))
				table.remove(ins.publish_cache, 1)
			else
				local topic, payload, qos = item[1], item[2], item[3]
				local ret = mqtt:publish(topic, payload, qos, false)
				mqtt:loop(1)

				if not ret then 
					print("publish fail", id)
					return
				end 

				local _ = yield(), table.remove(ins.publish_cache, 1)
			end
		end
	end,

	connect_internel = function(ins, mqtt)
		local st = se.time()
		mqtt:login_set("#qmsw2..5#", "@oawifi15%") 
		local ret = mqtt:connect(ins.host, ins.port, ins.keepalive)
		local d = se.time() - st
		if ret then
			ins.status = true
			local ret = mqtt:subscribe(ins.topic, 2) 	assert(ret)
			print("reconnect and subscribe ok %s", d, ins.topic)
			return
		end

		print("connect mosquitto fail %s", d)
		se.sleep(1)
	end,

	run_as_routine = function(ins) 
		local mqtt = mosq.new(ins.clientid, ins.clean)

		mqtt:callback_set("ON_MESSAGE", function(mid, topic, payload, qos, retain) ins.on_message(payload) end)
		mqtt:callback_set("ON_DISCONNECT", function(...) ins.status = false ins.on_disconnect(...) end)

		while ins.running do
			mqtt:loop(ins.loop_timeout)

			if ins.status then
				ins:publish_internel(mqtt)
			else
				ins:connect_internel(mqtt)
			end

			yield()
		end

		mqtt:disconnect()
	end,

	run = function(ins)
		se.go(ins.run_as_routine, ins)
	end,

	publish = function(ins, topic, payload, qos, ...) 
		table.insert(ins.publish_cache, {topic, payload, qos, ...})
	end,

	set_callback = function(ins, name, func)
		assert(ins and name:find("^on_") and func)
		ins[name] = func
	end,

	get_topic = function(ins)
		return ins.topic
	end,

	stop = function(ins)
		ins.running = false
	end,
}

local function new_base(map)
	local obj = {
		clientid = map.clientid,
		topic = map.topic,
		keepalive = map.keepalive or 10,
		loop_timeout = 5,
		host = map.host or "127.0.0.1",
		port = map.port or 61883,
		clean = map.clean or false,

		status = false,
		publish_cache = {},

		on_message = numb,
		on_disconnect = numb,
		on_check_out = numb,
		
		running = true,
	}

	setmetatable(obj, mt)
	return obj
end

local function wait_response(response_map, seq, timeout)
	local st = se.time()
	while true do
		se.sleep(0.005) 
		local res = response_map[seq]
		if res ~= nil then
			response_map[seq] = nil
			return res
		end

		if se.time() - st > timeout then
			return nil, "timeout"
		end
	end
end

return {new = new_base, wait = wait_response}