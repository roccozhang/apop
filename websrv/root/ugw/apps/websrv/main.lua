local log = require("log")
local js = require("cjson.safe")
local mongoose = require("mongoose")
local mosquitto = require("mosquitto")

local websrv_module = "a/ac/websrv"
local auth_module = "a/ac/userauth"
local MG_FALSE = mongoose.MG_FALSE
local MG_TRUE = mongoose.MG_TRUE
local MG_MORE = mongoose.MG_MORE
local MG_REQUEST = mongoose.MG_REQUEST
local MG_CLOSE = mongoose.MG_CLOSE 
local MG_POLL = mongoose.MG_POLL
local MG_RECV = mongoose.MG_RECV

local resmap_mt = {}
resmap_mt.__index = {
	set_field = function(ins, seq, k, v)
		local item = ins.map[seq] or {}
		item[k] = v 
		ins.map[seq] = item
	end,

	exist = function(ins, seq)
		return ins.map[seq] ~= nil
	end,

	get_field = function(ins, seq, k)
		return ins.map[seq] and ins.map[seq][k]
	end,

	del = function(ins, seq)
		ins.map[seq] = nil
	end,

	clear_timeout = function(ins)
		local del, now = {}, os.time()
		for k, item in pairs(ins.map) do 
			local _ = now - item.t > 3 and table.insert(del, k)
		end
		for _, k in ipairs(del) do 
			log.error("logical error clear timeout %s", k)
			ins.map[k] = nil
		end
	end,
}

local function resmap_new()
	local obj = {map = {}}
	setmetatable(obj, resmap_mt)
	return obj
end

local mqtt
local resins = resmap_new()
local function send_request(map) 
	mqtt:publish(auth_module, js.encode(map), 0, false)
end

local uri_map = {}
uri_map["/c.login"] = function(conn)
	local username = conn:get("username")
	local password = conn:get("password")

	if not (username and password) then
		return false
	end

	local map = {
		cmd = "auth",
		seq = conn:addr(),
		username = username,
		password = password,
		ip = conn:remote_ip(),
	}

	send_request(map)

	return true
end

local handler_map = {}

-- step 1 : recv request data. parse input data here. do not reply data here
handler_map[MG_RECV] = function(conn) 
	local seq, uri = conn:addr(), conn:uri() 	assert(not resins:exist(seq))
	resins:set_field(seq, "t", os.time()) 	-- update request time

	local func = uri_map[uri]
	if not (func and func(conn)) then 
		resins:set_field(seq, "r", "404 invalid uri " .. uri)
	end

	return MG_MORE
end

-- step 2 
handler_map[MG_REQUEST] = function(conn)
	local seq = conn:addr() 	assert(resins:exist(seq))
	local r = resins:get_field(seq, "r")

	if r then 
		local _ = conn:write(r), resins:del(seq)
		return MG_TRUE
	end 

	return MG_MORE
end

-- step 3, poll
handler_map[MG_POLL] = function(conn)
	local seq = conn:addr() 	assert(resins:exist(seq))

	-- try get response
	local r = resins:get_field(seq, "r")
	if r then 
		local _ = conn:write(r), resins:del(seq)
		return MG_TRUE
	end

	-- check timeout
	if os.time() - resins:get_field(seq, "t") > 1 then
		local _ = conn:write("404 auth timeout"), resins:del(seq) 
		return MG_TRUE
	end

	return MG_MORE
end

-- step 4. user close web page
handler_map[MG_CLOSE] = function(conn)
	resins:del(conn:addr()) 
	return MG_TRUE
end

local function dispatcher(conn, ev)
	local func = handler_map[ev]
	if func then 
		return func(conn)
	end

	for k, v in pairs(mongoose) do 
		if v == ev then 
			print("not register", k)
			break
		end
	end
	
	return MG_FALSE
end

local function on_message(mid, topic, data, qos, retain)
	local map = js.decode(data)
	if not (map and map.seq and map.r) then 
		return 
	end 

	resins:set_field(map.seq, "r", map.r)
end

local function create_mqtt()
	mosquitto.init()
	local mqtt = mosquitto.new(websrv_module, false)
	mqtt:login_set("#qmsw2..5#", "@oawifi15%") 
	local _ = mqtt:connect("127.0.0.1", 61883) or log.fatal("connect fail")
	mqtt:callback_set("ON_MESSAGE", on_message)
	mqtt:callback_set("ON_DISCONNECT", function(...) log.fatal("mqtt disconnect %s", js.encode({...})) end)
	local _ = mqtt:subscribe(websrv_module, 0) or log.fatal("subscribe fail")
	return mqtt
end

local function create_server()
	local server = mongoose.create_server()
	server:set_ev_handler(dispatcher)
	local web_root, http_port = "/www/webui", "8080"
	server:set_option("document_root", web_root)
	server:set_option("listening_port", http_port)
	return server
end

local function main() 
	local server
	server, mqtt = create_server(), create_mqtt()

	local count, step = 0, 5
	local maxcount = 1000 / (step + step)
	while true do
		mqtt:loop(10) 
		server:poll_server(10)

		count = count + 1 
		if count > maxcount then
			count = 0, resins:clear_timeout()
		end 
	end
end

log.setdebug(true)
log.setmodule("wb")
main()