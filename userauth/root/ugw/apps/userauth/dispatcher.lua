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
	print("login ok. TODO notify kernel", ip, mac, username)
	local ol = onlinelist.ins()
	ol:add(mac, ip, username)
	ol:show()
end 

local function auth(map)
	local username, password, ip, mac = map.username, map.password, map.ip, map.mac or "00:00:00:00:00:ae"
	if not (username and password and ip and mac) then 
		return "404 missing login param"
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

	if 0 == user:get_enable() then
		return "404 user disabled"
	end

	if not user:check_expire() then 
		return "404 expired"
	end 

	if not user:check_remain() then 
		return "404 no remaining"
	end 

	local is_auto = policies:ins():check_auto(ip)
	local _ = is_auto and print("why auto", ip)
	if not (is_auto or user:check_user_passwd(username, password)) then  
		return "404 invalid username/password"
	end 

	if not user:check_multi() then
		return "404 multi disabled"
	end

	if not user:check_mac(mac) then 
		return "404 mac disabled"
	end

	login_success(mac, ip, username)

	return "404 ok"
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
	local del = {}
	local ol = onlinelist.ins()
	ol:foreach(function(user)
		local _ = user:get_name() == username and table.insert(del, user:get_mac())
	end)
	for _, mac in ipairs(del) do 
		log.info("kick %s %s", username, mac)
		ol:del(mac)
	end
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

	local ol, ul = onlinelist.ins(), userlist.ins()
	ul:show()
	ol:show()
end

return {
	auth = auth, 
	update_user = update_user,
	update_online = setup_update_online(), 
}
