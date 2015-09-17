local se = require("se")
local log = require("log")
local lfs = require("lfs")
local sk = require("socket") 

local logdir = "/tmp/ugw/log"

if not lfs.attributes(logdir) then
	os.execute("mkdir -p " .. logdir)
	if not lfs.attributes(logdir) then
		io.stderr:write("mkdir fail", logdir)
		os.exit(-1)
	end
end

local max_cache, flush_timeout = 10, 2
local host, port = "127.0.0.1", 9999

local max_logsize = 1024 * 1024 * 4 
local maxfiles = 10

local fp
local gcache = {}
local current_id = 0

local function get_version_stamp()
	local version_file = "/ugw/etc/version"
	local fp = io.open(version_file)
	if not fp then 
		return "0000000000"
	end 
	
	local version = fp:read("*l")
	fp:close()
	
	local pattern = "%-(%d%d%d%d%d%d%d%d%d%d)"
	return version:match(pattern) or "0000000000"
end

local function collect_del_files()
	local arr = {}
	for filename in lfs.dir(logdir) do
		local id = tonumber(filename:match("_(%d%d%d%d%d%d)_"))
		if id then 
			table.insert(arr, filename)
			current_id = id > current_id and id or current_id
		end
	end

	table.sort(arr, function(a, b) return a > b end)

	local del = {}
	for i = maxfiles, #arr do 
		table.insert(del, arr[i])
	end

	return del
end

local function delete_log()
	for _, file in ipairs(collect_del_files()) do 
		local fullpath = string.format("%s/%s", logdir, file)
		print("remove", fullpath)
		os.remove(fullpath) 
	end
end

local function openlog()
	if not fp then
		delete_log()
		local path = string.format("%s/log.current", logdir)
		local err
		fp, err = io.open(path, "a")
		if not fp then 
			io.stderr:write("open fail", path, err)
			os.exit(-1)
		end
	end
end

local function flush()
	local cache
	cache, gcache = gcache, {}
	if #cache == 0 then 
		return
	end

	openlog()

	local size = fp:seek()
	if size > max_logsize then 
		fp:close() fp = nil

		local t = os.date("*t")
		local stamp = get_version_stamp()
		local cmd = string.format("tar -jcf %s/log_end_%s_%06d_%04d%02d%02d_%02d%02d%02d %s/log.current; rm -f %s/log.current", logdir, 
			stamp, current_id + 1, t.year, t.month, t.day, t.hour, t.min, t.sec, logdir, logdir)
		
		if os.execute(cmd) ~= 0 then 
			io.stderr:write("cmd fail", cmd)
		end
	
		openlog()
	end

	for _, v in pairs(cache) do
		fp:write(v)
	end

	fp:flush()
end

local function start_new_server(server)
	server:settimeout(1)
	local count = 0
	while true do 
		local data, err  = server:receivefrom()
		if data then 
			table.insert(gcache, data)
			local _ = #gcache > 10 and flush()
		elseif err ~= "timeout" then 
			return
		else 
			count = count + 1
			if count > flush_timeout then
				count = 0, flush() 
			end
		end 
	end 
end

local function main()
	while true do
		local server, err = sk.udp()
		if not server then 
			io.stderr:write("create udp fail", host, port, err, "\n")
			os.exit(-1)
		end

		server:setsockname(host, port) 
		start_new_server(server)
		server:close() 
		se.sleep(0.1)
	end
end

se.run(main)
