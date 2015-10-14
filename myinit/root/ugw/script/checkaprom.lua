
local function read(path, func)
	func = func and func or io.open
	local fp, err = func(path, "r")
	if not fp then 
		return nil, err 
	end 
	local s = fp:read("*a")
	fp:close()
	return s
end 


local function get_latest_version(host, rtype)
	local cmd, err = string.format("wget -O - 'http://%s/m50?cmd=getlastestfirmwareversion&type=%s' 2>/dev/null", host, rtype)
	local res, err = read(cmd, io.popen)
	if not res then
		return nil
	end

	res = res:gsub("[ \n]", "") 
	if not res:match(rtype .. ".%d%d%d%d%d%d%d%d%d%d%d%d") then  
		return nil 
	end

	res = res:gsub("%.", "-")
	return res
end

local cmdmap = {}

local function check_host_type(host, rtype)
	assert(host and rtype)
	local host = host == "default" and "cloud.i-wiwi.com:8081" or host
	return host, rtype
end

function cmdmap.version(host, rtype)
	local host, rtype = check_host_type(host, rtype)
	local version = get_latest_version(host, rtype)
	local fmt = '{"st":%d,"data":"%s"}'
	if version then 
		io.stdout:write(string.format(fmt, 0, version))
		os.exit(0)
	end
	io.stdout:write(string.format(fmt, 1, "get version fail"))
end

function cmdmap.download(host, rtype)
	local host, rtype = check_host_type(host, rtype)
	local download_dir = "/tmp/tmp_aprom"
	local cmd = string.format([[
			rm -rf %s
			mkdir %s
			wget -O %s/imagex 'http://%s/m50?cmd=getlastestfirmwarefile&type=%s' 2>&1
		]], download_dir, download_dir, download_dir, host, rtype)
	local fmt = '{"st":%d,"data":"%s"}'
	local ret = os.execute(cmd)
	if ret ~= 0 then 
		io.stdout:write(string.format(fmt, 1, "download fail"))
		os.execute("rm -rf " .. download_dir)
		os.exit(1)
	end
	
	local tmp_release = string.format("%s/tmp_release", download_dir)
	os.execute("rm -rf " .. tmp_release) 
	local cmd = string.format("/ugw/script/openssltar.sh untar %s/imagex %s wjrc0409", download_dir, tmp_release)
	local ret = os.execute(cmd)
	if ret ~= 0 then 
		io.stdout:write(string.format(fmt, 1, "download fail 2"))
		os.execute("rm -rf " .. download_dir)
		os.exit(1) 
	end 

	local cmd = string.format("rm /tmp/www/webui/rom/%s*; mv %s/* /tmp/www/webui/rom/", rtype, tmp_release)
	os.execute(cmd)
	os.execute("rm -rf " .. download_dir)
	io.stdout:write(string.format(fmt, 0, "download ok"))
end

local args = {...}
local cmd = table.remove(args, 1)
local func = cmdmap[cmd]
local _ = func and func(unpack(args))