local log = require("log")
local js = require("cjson.safe") 
local usr = require("user")
local userlist = require("userlist")
local onlinelist = require("onlinelist")
local policy = require("policy")
local policies = require("policies")

local function get_timestamp()
	return  os.date("%Y%m%d %H%M%S") 
end

local function login_success(mac, ip, username)
	print("login ok", ip, mac, username)
	local ol = onlinelist.ins()
	ol:add(mac, ip, username)
end 

local function auth(map)
	local username, password, ip, mac = map.username, map.password, map.ip, map.mac or "00:00:00:00:00:ae"
	if not (username and password and ip and mac) then 
		return "404 missing login param"
	end 

	if policy.is_auto(ip) then
		return "202 auto"
	end

	local ol = onlinelist.ins()
	if ol:exist_mac(mac) then 
		return "202 already online"
	end

	local ul = userlist.ins()
	local user = ul:get(username)
	if not user then 
		return "404 user not exist"
	end 

	if not user:get_enable() then 
		return "404 user disabled"
	end 

	if user:get_expire_enable() and user:get_expire() < get_timestamp() then
		return "404 expired"
	end

	if user:get_remain_enable() and user:get_remain() <= 0 then 
		return "404 no remaining"
	end 

	if not (username == user:get_name() and password == user:get_passwd()) then 
		return "404 invalid username/password"
	end 

	if not user:get_multi_enable() then
		if ol:exist_user(username) then
			return "404 multi disabled"
		end
	end

	if user:get_bind() == usr.BIND_MAC and not user:allow(mac) then 
		return "404 mac disabled"
	end

	login_success(mac, ip, username)

	return "404 ok"
end

local function setup_update_elapse()
	local last_check_time
	return function()
		local now = os.time()
		if not last_check_time then 
			last_check_time = now
			return 
		end
		local d
		d, last_check_time = now - last_check_time, now 
		
		local ol = onlinelist.ins()
		ol:foreach(function(user)
			user:set_elapse(user:get_elapse() + d)
		end)
		ol:show()
	end
end

local function setup_update_remain()
	local last_check_time
	return function()
		local now = os.time()
		if not last_check_time then 
			last_check_time = now
			return 
		end
		local d
		d, last_check_time = now - last_check_time, now 
		
		print(d)
	end
end

return {
	auth = auth, 
	update_elapse = setup_update_elapse(), 
	update_remain = setup_update_remain(),
}
