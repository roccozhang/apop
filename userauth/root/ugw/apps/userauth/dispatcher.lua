local log = require("log")
local usr = require("user")
local js = require("cjson.safe")
local policy = require("policy")
local policies = require("policies")
local kernelop = require("kernelop")
local userlist = require("userlist")
local onlinelist = require("onlinelist")

local function status(msg, ok)
	return {status = ok and 0 or 1, data = msg}
end

local function get_timestamp()
	return  os.date("%Y%m%d %H%M%S") 
end

local function login_success(mac, ip, username)
	kernelop.online(mac)
	local ol = onlinelist.ins()
	ol:add(mac, ip, username)
	ol:show()
end 

local function auth(map)
	local username, password, ip, mac = map.username, map.password, map.ip, map.mac
	if not (username and password and ip and mac) then 
		return status("missing login param")
	end

	local ol = onlinelist.ins()
	if ol:exist_mac(mac) then
		return status("already online", true)
	end

	local ul = userlist.ins()
	local user = ul:get(username)
	if not user then
		return status("user not exist")
	end

	if 0 == user:get_enable() then
		return status("user disabled")
	end

	if not user:check_expire() then 
		return status("expired")
	end

	if not user:check_remain() then 
		return status("no remaining")
	end 

	local is_auto = policies:ins():check_auto(ip)
	local _ = is_auto and print("why auto", ip)
	if not (is_auto or user:check_user_passwd(username, password)) then  
		return status("invalid username/password")
	end 

	if not user:check_multi() then
		return status("multi disabled")
	end

	if not user:check_mac(mac) then
		return status("mac disabled")
	end

	login_success(mac, ip, username)

	return status("ok", true)
end

local function setup_update_online()
	local last_check_time = os.time()
	return function()
		local now = os.time() 
		local d = now - last_check_time
		last_check_time = now
		
		local ol = onlinelist.ins()
		ol:foreach(function(user)
			local _ = user:set_elapse(user:get_elapse() + d), user:set_part(user:get_part() + d)
		end)

		ol:set_change(true)
	end
end

local function kick_online_user(username)
	local mac_arr = onlinelist.ins():del_user(username)
	local _ = #mac_arr > 0 and kernelop.offline(mac_arr)
end

local function scan_expire()
	local ol, ul = onlinelist.ins(), userlist.ins()
	local expired_map = {}
	ol:foreach(function(user)
		local name = user:get_name()
		local u = ul:get(name)
		if not u:check_expire() then
			expired_map[name] = 1 
		end
	end)

	for username in pairs(expired_map) do 
		log.info("expired %s", username)
		local _ = kick_online_user(username), ol:set_change(true)
	end
end

local function scan_remain()
	local ol, ul = onlinelist.ins(), userlist.ins()
	local minus_map = {}
	ol:foreach(function(user) 
		local name = user:get_name()
		minus_map[name] = user:get_part(), user:set_part(0)
	end)
	for username, n in pairs(minus_map) do 
		local user = ul:get(username)
		if user and user:get_remain_enable() == 1 then
			local left = user:get_remain_time() - n 
			left = left > 0 and left or 0 
			local _ = user:set_remain(1, left), ul:set_change(true)
			if left <= 0 then 
				local _ = kick_online_user(username), ol:set_change(true)
			end
		end
	end
end

local function update_user() 
	scan_remain()
	scan_expire()
end

local function user_set(map)  
	local group, map = map.group, map.data 
	local ul = userlist.ins() 

	for name, item in pairs(map) do
		local ret, err = usr.check(item) 
		if not ret then 
			return status(err)
		end

		if not ul:exist(name) then 
			return status("miss " .. name)
		end 
		if name ~= item.name and ul:exist(item.name) then 
			return status("dup " .. item.name)
		end
	end

	for name, item in pairs(map) do 
		local name, pwd, desc, enable, multi, bind, maclist = item.name, item.pwd, item.desc, item.enable, item.multi, item.bind, item.maclist
		local expire, remain = item.expire, item.remain

		assert(name and pwd and desc and enable and multi and bind and maclist and expire and remain)

		local n = usr:new()
		n:set_name(name):set_pwd(pwd):set_desc(desc):set_enable(enable):set_multi(multi)
		n:set_bind(bind):set_maclist(maclist)
		n:set_expire(expire):set_remain(remain)

		ul:set(name, n)
	end

	ul:save()
	return {status = 0}
end 

local function user_del(map) 
	local group, arr = map.group, map.data 
	local ol, ul = onlinelist.ins(), userlist.ins()
	for _, name in ipairs(arr) do 
		ul:del(name)
		local mac_arr = ol:del_user(name)
		local _ = #mac_arr > 0 and kernelop.offline(mac_arr)
	end 

	ul:save()
	return {status = 0}
end

local function user_add(map) 
	local group, arr = map.group, map.data
	local ul = userlist.ins()
	for _, map in ipairs(arr) do 
		local ret, err = usr.check(map) 
		if not ret then 
			return {status = 1, msg = err}
		end 
		if ul:exist(map.name) then 
			return {status = 1, msg = "dup " .. map.name} 
		end
	end

	for _, map in ipairs(arr) do 
		local name, pwd, desc, enable, multi, bind, maclist = map.name, map.pwd, map.desc, map.enable, map.multi, map.bind, map.maclist
		local expire, remain = map.expire, map.remain 

		assert(name and pwd and desc and enable and multi and bind and maclist and expire and remain)

		local n = usr:new()
		n:set_name(name):set_pwd(pwd):set_desc(desc):set_enable(enable)
		n:set_multi(multi):set_bind(bind):set_maclist(maclist) 
		n:set_expire(expire):set_remain(remain)

		ul:add(n)
	end

	ul:save()
	return {status = 0}
end

local function user_get(data)
	local arr = {}
	for _, user in pairs(userlist.ins():data()) do 
		table.insert(arr, user)
	end

	return {status = 0, data = arr}
end

local function policy_set(map)
	-- local map = {["hello"] = {name = "hello", ip1 = "192.162.0.1", ip2 = "192.168.0.255", type = "auto"}}
	local group, map = map.group, map.data
	local pols = policies.ins()
	for name, item in pairs(map) do 
		local ret, err = policy.check(item)
		if not ret then 
			return {status = 1, msg = err} 
		end

		if not pols:exist(name) then 
			return {status = 1, msg = "miss " .. name} 
		end 
		
		if name ~= item.name and pols:exist(item.name) then 
			return {status = 1, msg = "dup " .. item.name} 
		end
	end

	for name, item in pairs(map) do
		local name, ip1, ip2, tp = item.name, item.ip1, item.ip2, item.type 
		assert(name and ip1 and ip2 and tp)

		local n = policy.new()
		n:set_name(name):set_ip1(ip1):set_ip2(ip2):set_type(tp) 
		pols:set(name, n)
	end

	pols:save()
	kernelop.reset()
	return {status = 0}
end 

local function policy_add(map) 
	-- local map = {name = "pol1", ip1 = "192.168.0.1", ip2 = "192.168.0.255", type = "auto"}
	local group, map = map.group, map.data
	local name, ip1, ip2, tp = map.name, map.ip1, map.ip2, map.type 
	local ret, err = policy.check(map)
	if not ret then 
		return {status = 1, msg = err}  
	end 

	local pols = policies.ins()
	if pols:exist(name) then 
		return {status = 1, msg = "dup " .. name}  
	end

	local n = policy.new()
	n:set_name(name):set_ip1(ip1):set_ip2(ip2):set_type(tp)
	pols:add(n)

	pols:save()
	kernelop.reset()
	return {status = 0}
end 

local function policy_del(map) 
	-- local arr = {"hello", "worldc"}
	local group, arr = map.group, map.data
	local pols = policies.ins() 
	for _, name in ipairs(arr) do 
		pols:del(name)
	end

	pols:save()
	kernelop.reset()
	return {status = 0}
end

local function policy_adj(map)  
	local group, arr = map.group, map.data
	local pols = policies.ins() 
	for _, name in ipairs(arr) do 
		if not pols:exist(name) then 
			return {status = 1, msg = "miss " .. name}   
		end 
	end

	pols:adjust(arr)
	pols:save()
	kernelop.reset()
	return {status = 0}
end

local function policy_get(data) 
	return {status = 0, data = policies.ins():data()}
end

local function online_del(map) 
	local group, arr = map.group, map.data
	local ol = onlinelist.ins()
	for _, mac in ipairs(arr) do 
		ol:del_mac(mac)
		kernelop.offline({mac})
	end

	return {status = 0}
end 

local function online_get(data)
	return {status = 0, data = onlinelist.ins():data()}
end

local function save()
	local ol, ul = onlinelist.ins(), userlist.ins()
	local _ = ol:save(), ul:save()
end

local function adjust_elapse() 
	local ol = onlinelist.ins()
	ol:adjust(kernelop.get_all_user())
end

return {
	save = save,
	auth = auth, 
	
	update_user = update_user,
	update_online = setup_update_online(), 

	user_set = user_set,
	user_del = user_del,
	user_add = user_add,
	user_get = user_get,

	policy_set = policy_set,
	policy_add = policy_add,
	policy_del = policy_del,
	policy_adj = policy_adj,
	policy_get = policy_get,

	online_del = online_del,
	online_get = online_get,

	adjust_elapse = adjust_elapse,
}
