local se = require("se")  
local sandutil = require("sandutil")
local parser = require("redis.parser")
local tomap, toarr, checkarr = sandutil.tomap, sandutil.toarr, sandutil.checkarr

local st_new, st_run, st_stop = "new", "run", "stop"
local function fatal(fmt, ...)
	io.stderr:write(string.format(fmt, ...))
	os.exit(-1)
end

local method = {}
local mt = {__index = method}

function method.set_auth(ins, username, password)
	ins.param.username, ins.param.password = username, password
end

function method.set_will(ins, topic, payload)
	ins.param.will_topic, ins.param.will_payload = topic, payload
end

function method.set_connect(ins, topic, payload)
	ins.param.connect_topic, ins.param.connect_payload = topic, payload
end

function method.pre_subscribe(ins, ...)
	ins.param.topics = {...}
end

function method.set_keepalive(ins, s)
	ins.param.keepalive = s
end

function method.running(ins)
	return ins.state ~= st_stop
end

local function close_client(ins, err)
	print("close on error", err, ins.param.clientid) 
	se.close(ins.client)
	ins.client, ins.state = nil, st_stop
	ins.on_disconnect(1, err)
end

function method.publish(ins, topic, payload)
	if not ins:running() then 
		return false 
	end
	local map = {
		id = "pb",
		tp = topic,
		pl = payload,
	}
	local err = se.write(ins.client, parser.build_query(toarr(map)))
	if err then 
		close_client(ins, err)
		return false
	end
	return true 
end

function method.disconnect(ins)
	if ins.state ~= st_run then 
		return 
	end
	se.write(ins.client, parser.build_query(toarr({id = "dc"})))
	se.close(ins.client)
	ins.client = nil
	ins.state = st_stop
	ins.on_disconnect(0, "close by user")
end

function method.connect(ins, host, port)
	local addr = string.format("tcp://%s:%s", host, port)
	local cli, err = se.connect(addr) 
	if not cli then 
		return nil, err
	end 

	local m = ins.param
	if not (m.clientid and #m.clientid > 0 and m.username and #m.username > 0 and m.password and #m.password > 0
		and m.version and #m.version > 0 and m.keepalive and m.keepalive >= 5 and #m.topics > 0) then 
		return nil, "invalid param"
	end	

	local _ = (m.will_topic or m.will_payload) and assert(#m.will_topic > 0 and #m.will_payload > 0)
	local _ = (m.connect_topic or m.connect_payload) and assert(#m.connect_topic > 0 and #m.connect_payload > 0)

	local map = {
		id = "cn",
		cd = m.clientid,
		vv = m.version,
		un = m.username,
		pw = m.password,
		kp = m.keepalive,
		tp = table.concat(m.topics, "\t"),
		ct = m.connect_topic,
		cp = m.connect_payload,
		wt = m.will_topic,
		wp = m.will_payload,
	}

	local err = se.write(cli, parser.build_query(toarr(map)))
	if err then 
		se.close(cli)
		ins.state = st_stop
		return nil, err 
	end

	ins.client = cli
	ins.state = st_run
	return true 
end

function method.set_callback(ins, name, cb)
	assert(ins[name])
	ins[name] = cb
end

local function timeout_ping(ins)
	local last = se.time()
	local s = parser.build_query(toarr({id = "pi"}))
	local keepalive = ins.param.keepalive
	while ins:running() do
		while ins:running() do
			local now = se.time()

			-- timeout
			if now - ins.active >= keepalive * 2.1 then 
				return close_client(ins, "timeout")  
			end

			if now - last >= keepalive then 
				break
			end
			
			se.sleep(1) 
		end

		last = se.time() 
		if not ins:running() then
			break
		end 

		-- send ping
		local err = se.write(ins.client, s) 
		if err then 
			return close_client(ins, err) 
		end 
	end 
end

local cmd_map = {}
function cmd_map.pb(ins, map)
	ins.on_message(map.tp, map.pl)
	return true 
end

function cmd_map.ca(ins, map)
	if not (map.st and tonumber(map.st) == 0 and map.da) then
		return nil, map.data or "undefined"
	end
	ins.on_connect()
	return true
end

function cmd_map.po(ins, map) 
	return true
end

local function run_internal(ins)
	local dispatch = function(map)
		local id = map.id 
		if not id then 
			print("TODO miss id")
			return true
		end
		local func = cmd_map[id]
		if not func then 
			print("no " .. func)
			return true 
		end
		
		return func(ins, map)
	end

	local on_recv = function()
		while #ins.data > 0 do
			-- check whether data prepared
			local ret, p = parser.parse_ready(ins.data)
			if not ret then
				return nil, p and "parse error" or nil 		-- not prepared
			end 

			-- parse data 
			local arr = parser.parse_reply(ins.data)
			if not checkarr(arr) then  
				return nil, "data error"
			end

			ins.data = ins.data:sub(p + 1) 					-- trim data parsed
			local ret, err = dispatch(tomap(arr))
			if not ret then 
				return nil, err 
			end 
		end

		return true
	end 

	while ins:running() do
		local data, rerr = se.read(ins.client, 8192, 0.01) 
		if data then  
			ins.active = se.time() 			-- recv data, update active time
			ins.data = ins.data .. data 	-- cache data 
		end 

		-- process data
		local ret, err = on_recv()
		if not ret then 
			close_client(ins, err)
			break
		end

		-- check recv error
		if rerr and rerr ~= "TIMEOUT" then 
			close_client(ins, rerr)
			break
		end
	end
end

function method.run(ins)
	se.go(timeout_ping, ins) 			-- ping routine
	se.go(run_internal, ins)
end

local function numb() end
local function new(clientid)
	assert(clientid)
	local obj = {
		-- param 
		param = {
			clientid = clientid,
			username = "",
			password = "",
			version = "v0.1",
			keepalive = 30,
			topics = {},
			connect_topic = nil,
			connect_payload = nil,
			will_topic = nil,
			will_payload = nil,
		},

		-- client conenction 
		client = nil,
		
		data = "",
		state = st_new,
		active = se.time(),

		on_message = numb,
		on_connect = numb,
		on_disconnect = numb,
	}

	setmetatable(obj, mt)
	return obj 
end

return {new = new}
--[[
local function client1()
	local mqtt = new("client1")
	mqtt:set_auth("hello", "world")
	mqtt:set_will("a/local/client1", "client1 disconnect")
	mqtt:set_connect("a/local/client1", "client1 connect")
	mqtt:pre_subscribe("a/local/client1")
	
	mqtt:set_callback("on_disconnect", function(...) print("---", ...) end)
	mqtt:set_callback("on_connect", function() print("connect ok") end)
	mqtt:set_callback("on_message", function(topic, payload) print(topic, payload) end)
	local ret, err = mqtt:connect("127.0.0.1", 61234)
	if not ret then  
		return print(err)
	end 
	mqtt:run()

	while mqtt:running() do  
		mqtt:publish("a/local/client2", "1->2" .. os.date())
		se.sleep(1)
	end
end

local function client2()
	local mqtt = new("client2")
	mqtt:set_auth("hello", "world")
	mqtt:set_will("a/local/client2", "client1 disconnect")
	mqtt:set_connect("a/local/client2", "client1 connect")
	mqtt:pre_subscribe("a/local/client2")
	
	mqtt:set_callback("on_disconnect", function(...) print(...) end)
	mqtt:set_callback("on_connect", function() print("connect ok") end)
	mqtt:set_callback("on_message", function(topic, payload) print(topic, payload) end)
	local ret, err = mqtt:connect("127.0.0.1", 61234)
	if not ret then  
		return print(err)
	end 
	mqtt:run()

	while mqtt:running() do 
		mqtt:publish("a/local/client1", "2->1" .. os.date())
		se.sleep(2)
	end  
end

math.randomseed(os.time())
local function clients()
	local new = function(i)
		local mqtt = new("client" .. i)
		mqtt:set_auth("hello", "world")
		mqtt:set_will("a/local/summary", "client disconnect" .. i)
		mqtt:set_connect("a/local/summary", "client connect" .. i)
		mqtt:pre_subscribe("a/local/client" .. i)
		local ret, err = mqtt:connect("127.0.0.1", 61234)
		if not ret then  
			return print(i, err)
		end 
		mqtt:run()
		se.go(function()
			se.sleep(math.random(21, 90))
			mqtt:disconnect()
		end)
		local s = "client " .. i .. " " .. ("1234567890"):rep(1)
		se.sleep(20)
		while mqtt:running() do 
			se.sleep(5)
			mqtt:publish("a/local/summary", s)
		end

		-- mqtt:disconnect()
	end
	for i = 1, 10000 do
		se.go(new, i)
		se.sleep(0.001)
	end 
end

local function summary()
	local mqtt = new("summary")
	mqtt:set_auth("hello", "world")
	mqtt:pre_subscribe("a/local/summary")
	local ret, err = mqtt:connect("127.0.0.1", 61234)
	if not ret then  
		return print(err)
	end 
	mqtt:run()

	local count = 0
	mqtt:set_callback("on_message", function(topic, payload) 
		count = count + 1
	end)

	se.go(function()
		se.sleep(60)
		print("disconnect summary")
		mqtt:disconnect()
	end)
	local start = se.time()
	local last = 0
	while mqtt:running() do 
		se.sleep(5)
		print(math.floor(se.time() - start), count - last)
		last = count
	end 
	
end

local function main()
	-- se.go(client1)
	-- se.go(client2)
	se.go(summary)
	se.go(clients)
end 

se.run(main)
--]]
