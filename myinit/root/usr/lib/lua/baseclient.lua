local se = require("se")
local log = require("log")
local js = require("cjson.safe") 
local mosq = require("mosquitto")  

local function yield()
	se.sleep(0.000001)
end

local function numb() return true end

local function try_connect(host, port)
	local addr = string.format("tcp://%s:%s", host, tostring(port))

	for i = 1, 3 do 	
		local cli = se.connect(addr, 3)
		if cli then 
			return true, se.close(cli)
		end
		
		se.sleep(1)
	end

	return false
end

local mt = {}
mt.__index = { 
	publish_internel = function(ins, mqtt)
		while true do 
			local item = ins.publish_cache[1]
			if not item then 
				return 
			end

			if not ins.on_check_out(item) then
				log.error("abandon %s", js.encode(item))
				table.remove(ins.publish_cache, 1)
			else
				local topic, payload, qos = item[1], item[2], item[3]
				local ret = mqtt:publish(topic, payload, qos, false)
				mqtt:loop(1)

				if not ret then 
					log.error("publish fail")
					return
				end 

				local _ = yield(), table.remove(ins.publish_cache, 1)
			end
		end
	end,

	connect_internel = function(ins, mqtt)
		if not try_connect(ins.host, ins.port) then 
			ins.on_connect_fail()
			return se.sleep(1)
		end 
		
		local _ = ins.will_topic and mqtt:will_set(ins.will_topic, ins.will_payload)

		local st = se.time()
		mqtt:login_set("#qmsw2..5#", "@oawifi15%")
		local ret = mqtt:connect(ins.host, ins.port, ins.keepalive)
		local d = se.time() - st
		if ret then
			ins.status = true
			local ret = mqtt:subscribe(ins.topic, 2) 	assert(ret)
			log.debug("reconnect and subscribe ok %s %s", d, ins.topic)
			return ins.on_connect()
		end

		log.error("connect mosquitto fail %s", d)
		ins.on_connect_fail()
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

	set_will = function(ins, topic, payload)
		assert(topic and payload)	
		ins.will_topic, ins.will_payload = topic, payload
	end,
}

local function new_base(map)
	local obj = {
		clientid = map.clientid,
		topic = map.topic,
		keepalive = map.keepalive or 10,
		loop_timeout = 5,
		host = map.host or "127.0.0.1",
		port = map.port or 1883,
		clean = map.clean or false,

		will_topic = nil,
		will_payload = nil,

		status = false,
		publish_cache = {},

		on_message = numb,
		on_connect = numb,
		on_disconnect = numb,
		on_check_out = numb,
		on_connect_fail = numb,
		
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