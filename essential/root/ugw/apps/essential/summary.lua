local se = require("se")
local lfs = require("lfs")
local struct = require("struct")
local js = require("cjson.safe")

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

local function get_mac()
	local eth0mac = read("ifconfig eth0 | grep HWaddr | awk '{print $5}'", io.popen)
	if not eth0mac then 
		return 
	end 

	eth0mac = eth0mac:gsub("[ \t\r\n]", ""):lower()
	if #eth0mac ~= 17 then 
		return 
	end 

	return eth0mac
end

local function get_remote()
	local host = "cloud.i-wiwi.com"
	local cmd = string.format("nslookup '%s' | grep -A 1 '%s' | grep Address | awk '{print $3}'", host, host)
	local ip = read(cmd, io.popen)
	if not ip then 
		return 
	end 

	ip = ip:gsub("[ \r\t\n]", "")
	if not ip:find("%d+%.%d+%.%d+%.%d+") then 
		return 
	end 

	return ip, 61884
end

local function report()
	local mac = get_mac()
	if not mac then 
		return 
	end 

	local map = {m = mac}
	local s = js.encode(map)

	local ip, port = get_remote()
	local addr = string.format("tcp://%s:%s", ip, port)

	local client = se.connect(addr)
	if not client then
		return
	end 
	
	local data = struct.pack("<I", #s) .. s
	se.write(client, data)
	se.close(client)
end

local function main()
	se.sleep(10)
	while true do 
		report()
		se.sleep(7200)
	end
end

local function run()
	se.go(main)
end

return {run = run}