local se = require("se")
local lfs = require("lfs")

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

local function checklog(max)
	local path = "/tmp/ugw/log/apmgr.error"
	local attr = lfs.attributes(path)
	if not attr then 
		return 
	end 

	if attr.size < max then 
		return 
	end 

	local fp = io.open(path, "rb")
	if not fp then 
		return 
	end 

	fp:seek("set", math.floor(max * 2 / 3))
	local s = fp:read("*a")
	fp:close()

	local tmp = "/tmp/log.tmp"
	local fp = io.open(tmp, "wb")
	fp:write(s)
	fp:flush()
	fp:close()

	os.execute(string.format("cat %s > %s", tmp, path))
	os.remove(tmp)
end

local function watchlog()
	local max = 256*1024
	while true do  
		checklog(max)
		se.sleep(20)
	end
end



local function main()
	se.go(watchlog)
end

se.run(main)