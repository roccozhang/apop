local log = require("log")
local myutil = require("myutil")
local js = require("cjson.safe") 
local policy = require("policy")
local memfile = require("memfile")
local policies = require("policies")

local read = myutil.read

local function get_iface()
	local cmd = "lua /ugw/apps/userauth/tool.lua iface"
	local s, err = read(cmd, io.popen)
	local _ = s or log.error("cmd fail %s %s", cmd, err or "")
	return js.decode(s) or {}
end

local function get_policy()
	local pols = policies.ins():data()
	local pri, polarr = 100, {}
	for _, item in ipairs(pols) do 
		local authtype = item:get_type() == "web" and 0 or 1
		local map = {
			AuthPolicyName = item:get_name(),
			Enable = 1, 
			AuthType = authtype,
			Priority = pri,
			IpRange = {{Start = item:get_ip1(), End = item:get_ip2()}},
		}
		table.insert(polarr, map)
		pri = pri - 1 	assert(pri >= 0)
	end 
	return polarr
end

local function get_global()
	return {CheckOffline = 10}
end

local function reset()
	local cfg = {
		AuthPolicy = get_policy(),
		InterfaceInfo = get_iface(), 
		GlobaleAuthOption = get_global(),
	}
	
	local cmd = string.format("auth_tool '%s' 2>&1", js.encode(cfg))
	print(cmd)
	read(cmd, io.popen)
end

local function update_user_status(mac_arr, action)
	local st_arr = {}
	for _, mac in ipairs(mac_arr) do 
		table.insert(st_arr, {UserMac = mac, Action = action})
	end
	local cmd = string.format("auth_tool '%s'", js.encode({UpdateUserStatus = st_arr}))
	print(cmd)
	read(cmd, io.popen)
end

local function online(mac)
	update_user_status({mac}, 1)
end

local function offline(mac_arr)
	update_user_status(mac_arr, 0)
end

local function get_all_user()
	local cmd = string.format("auth_tool '%s' 2>/dev/null", js.encode({GetAllUser = 1}))
	local s = read(cmd, io.popen)
	s = s .. "\n"

	local user = {}
	for part in s:gmatch(".-\n") do 
		local ip, st, jf, mac = part:match("ip:(.-) st:(%d) jf:(%d+) mac:(%S+)")
		if ip then 
			user[mac] = {ip = ip, st = tonumber(st), jf = tonumber(jf)}
		end
	end

	return user
end

local function check_modify(path)
	local attr = lfs.attributes(path)
	if not attr then 
		return 
	end 

	local size, mtime = attr.size, attr.modification
	local ins = memfile.ins("authnetwork")
	local map = ins:get(path) or ins:set(path, {size = 0, mtime = 0}):get(path)
	local change = false 
	if not (map.size == size and map.mtime == mtime) then 
		map.size, map.mtime, change = size, mtime, true
		ins:set(path, map):save()
		log.debug("network change %s", path)
	end 
	return change
end

local files = {"/etc/config/firewall", "/etc/config/network"}
local function check_network()
	local change = false 
	for _, path in ipairs(files) do 
		change = check_modify(path) and true or change
	end
	local _ = change and reset()
end

return {
	reset = reset, 
	online = online, 
	offline = offline, 
	get_all_user = get_all_user, 
	check_network = check_network,
}