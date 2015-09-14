local log = require("log")
local js = require("cjson.safe") 
local usr = require("user")
local userlist = require("userlist")
local onlinelist = require("onlinelist")
local policy = require("policy")
local policies = require("policies")

local function status(msg, ok)
	return (ok and "302 " or "404 ") .. msg
end

local function get_timestamp()
	return  os.date("%Y%m%d %H%M%S") 
end

local function login_success(mac, ip, username)
	print("login ok. TODO notify kernel", ip, mac, username)
	local ol = onlinelist.ins()
	ol:add(mac, ip, username)
	ol:show()
end 

local function auth(map)
	local username, password, ip, mac = map.username, map.password, map.ip, map.mac or "00:00:00:00:00:ae"
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
	onlinelist.ins():del_user(username)
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
	local ul = userlist.ins() 
	for name, item in pairs(map) do
		local ret, err = usr.check(map) 
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
		local expire_enable, expire_timestamp = item.expire_enable, item.expire_timestamp
		local remain_enable, remaining = item.remain_enable, item.remaining

		assert(name and pwd and desc and enable and multi and bind and maclist and expire_enable and expire_timestamp and remain_enable and remaining)

		local n = usr:new()
		n:set_name(name):set_pwd(pwd):set_desc(desc):set_enable(enable):set_multi(multi)
		n:set_bind(bind):set_maclist(maclist)
		n:set_expire(expire_enable, expire_timestamp):set_remain(remain_enable, remaining)

		ul:set(name, n)
	end

	return status("set user ok")
end 

local function user_del(arr) 
	local ol, ul = onlinelist.ins(), userlist.ins()
	for _, name in ipairs(arr) do 
		local _ = ul:del(name), ol:del_user(name)
	end 

	return status("del users ok", true)
end

local function user_add(arr) 
	local ul = userlist.ins()
	for _, map in ipairs(arr) do 
		local ret, err = usr.check(map) 
		if not ret then 
			return status(err)
		end 
		if ul:exist(map.name) then 
			return status("dup " .. map.name)
		end
	end

	for _, map in ipairs(arr) do 
		local name, pwd, desc, enable, multi, bind, maclist = map.name, map.pwd, map.desc, map.enable, map.multi, map.bind, map.maclist
		local expire_enable, expire_timestamp = map.expire_enable, map.expire_timestamp
		local remain_enable, remaining = map.remain_enable, map.remaining

		assert(name and pwd and desc and enable and multi and bind and maclist and expire_enable and expire_timestamp and remain_enable and remaining)

		local n = usr:new()
		n:set_name(name):set_pwd(pwd):set_desc(desc):set_enable(enable)
		n:set_multi(multi):set_bind(bind):set_maclist(maclist)
		n:set_expire(expire_enable, expire_timestamp):set_remain(remain_enable, remaining)

		ul:add(n)
	end

	return status("add new user ok", true)
end

local function policy_set(map)
	-- local map = {["hello"] = {name = "hello", ip1 = "192.162.0.1", ip2 = "192.168.0.255", type = "auto"}}
	local pols = policies.ins()
	for name, item in pairs(map) do 
		local ret, err = policy.check(map)
		if not ret then 
			return status(err)
		end 

		if not pols:exist(name) then 
			return status("miss " .. name)
		end 
		
		if name ~= item.name and pols:exist(item.name) then 
			return status("dup " .. item.name)
		end
	end

	for name, item in pairs(map) do
		local name, ip1, ip2, tp = item.name, item.ip1, item.ip2, item.type 
		assert(name and ip1 and ip2 and tp)

		local n = policy.new()
		n:set_name(name):set_ip1(ip1):set_ip2(ip2):set_type(tp) 
		pols:set(name, n)
	end

	return status("set policy ok", true)
end 

local function policy_add(map) 
	-- local map = {name = "pol1", ip1 = "192.168.0.1", ip2 = "192.168.0.255", type = "auto"}
	local name, ip1, ip2, tp = map.name, map.ip1, map.ip2, map.type 
	local ret, err = policy.check(map)
	if not ret then 
		return status(err)
	end 

	local pols = policies.ins()
	if pols:exist(name) then 
		return status("dup " .. name)
	end

	local n = policy.new()
	n:set_name(name):set_ip1(ip1):set_ip2(ip2):set_type(tp)
	pols:add(n)

	return status("add new policy ok")
end 

local function policy_del(arr) 
	-- local arr = {"hello", "worldc"}
	local pols = policies.ins()
	pols:show()	
	for _, name in ipairs(arr) do 
		pols:del(name)
	end
	pols:show()

	return status("del users ok", true)
end

local function policy_adj(arr) 
	-- local arr = {"hello", "world", "default"}
	local pols = policies.ins() 
	for _, name in ipairs(arr) do 
		if not pols:exist(name) then 
			return "404 minss " .. name
		end 
	end

	pols:adjust(arr)

	return status("del users ok", true)
end

local function online_del(arr) 
	local ol = onlinelist.ins()
	for _, mac in ipairs(arr) do 
		ol:del_mac(mac)
	end

	return status("del online ok", true)
end 

local function save()
	local ol, ul = onlinelist.ins(), userlist.ins()
	local _ = ol:save(), ul:save()
end

return {
	save = save,
	auth = auth, 
	
	update_user = update_user,
	update_online = setup_update_online(), 

	user_set = user_set,
	user_del = user_del,
	user_add = user_add,

	policy_set = policy_set,
	policy_add = policy_add,
	policy_del = policy_del,
	policy_adj = policy_adj,

	online_del = online_del,
}
