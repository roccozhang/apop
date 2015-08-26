local ubus = require("ubus") 
local nixio = require("nixio")

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

local function error(fmt, ...)
	local s = string.format("e %s " .. fmt, os.date("%m%d %H%M%S"), ...) 
	local cmd = string.format("echo '%s' >> /ugw/log/error.log", s)
	os.execute(cmd)
	-- print(s)
end 

local function ubusd_alive()
	local ins = ubus.connect()
	if ins then 
		ins:close()
		return true 
	end
end

local function main()
	while true do
		local count, max = 0, 10
		for i = 1, max do
			if not ubusd_alive() then
				count = count + 1
				error("ubusd connect fail %d", i)
				nixio.nanosleep(1)
			end
		end

		if count == max then 
			error("ubusd dead, reboot")
			error("%s", read("ls -lh /tmp", io.popen))
			os.execute("reboot")
		end 

		nixio.nanosleep(10)
	end
end

main()