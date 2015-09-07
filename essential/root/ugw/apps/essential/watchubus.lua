local se = require("se")
local lfs = require("lfs")
local ubus = require("ubus")
local summary = require("summary")

local upgrade_flag = "/tmp/sysupgrade"

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
	local cmd = string.format("echo '%s' >> /tmp/backup/essential.log", s)
	os.execute(cmd)
	print(s)
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
				se.sleep(1)
			end
		end

		if count == max then 
			if lfs.attributes(upgrade_flag) then 
				error("upgrading, skip check ubusd")
				local _ = se.sleep(5), os.exit(0)
			end

			summary.report_now("ubusd dead at " .. (read("uptime", io.popen) or ""))

			error("ubusd dead, reboot")
			error("%s", read("ls /tmp", io.popen))
			os.execute("sleep 5; reboot")
		end

		se.sleep(30)
	end
end

local function run()
	se.go(main)
	print("ubusd dead at " .. (read("uptime", io.popen) or ""))
end

return {run = run}
