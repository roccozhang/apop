local se = require("se")  
local mongoose = require("mongoose")

local MG_FALSE, MG_TRUE, MG_MORE = mongoose.MG_FALSE, mongoose.MG_TRUE, mongoose.MG_MORE
local MG_REQUEST, MG_CLOSE, MG_POLL = mongoose.MG_REQUEST, mongoose.MG_CLOSE, mongoose.MG_POLL

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

local function get(ev)
	for k, v in pairs(mongoose) do 
		if v == ev then 
			return k
		end 
	end 
end

local function dispatcher(conn, ev)
	print(conn:uri(), get(ev))
	conn:write(os.date())
	return MG_MORE
end

local function main() 
	local server = mongoose.create_server()
	server:set_ev_handler(dispatcher)
	local web_root, http_port = "/www/webui", "8080"
	server:set_option("document_root", web_root)
	server:set_option("listening_port", http_port)
	while true do
		server:poll_server(20)
		se.sleep(0.01)
	end
end

se.run(main)