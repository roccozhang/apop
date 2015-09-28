local expand = require("expand")

local BIND_NONE = "none"
local BIND_MAC = "mac"

local fields = {
	name = "",
	pwd = "",
	desc = "", 

	enable = 1,
	multi = 0,

	bind = BIND_NONE,
	maclist = {},

	expire = {0, ""}, 
	remain = {0, 0},
}

local new, setmeta, method = expand.expand(fields)

local function get_timestamp()
	return  os.date("%Y%m%d %H%M%S") 
end


function method.check_mac(ins, mac) 
	if ins:get_bind() == BIND_NONE then
		return true 
	end 

	for _, m in ipairs(ins:get_maclist()) do
		if m == mac then 
			return true
		end
	end

	return false
end

function method.check_expire(ins)
	local expire = ins:get_expire()
	if expire[1] == 1 and expire[2] < get_timestamp() then
		return false
	end
	return true
end

function method.check_remain(ins)
	local remain = ins:get_remain()
	for k, v in pairs(remain) do print(k, v) end
	if remain[1] == 1 and remain[2] <= 0 then 
		return false
	end 
	
	return true
end

function method.get_remain_enable(ins)
	local remain = ins:get_remain() 
	return remain[1]
end

function method.get_remain_time(ins)
	local remain = ins:get_remain() 
	return remain[2]
end

function method.check_multi(ins, online)
	if ins:get_multi() == 1 then 
		return true 
	end 

	if online then 
		return false 
	end 

	return true
end

function method.check_user_passwd(ins, username, password)
	return username == ins:get_name() and password == ins:get_pwd()
end

function method.show(ins)
	print("---------------------user")
	for k, v in pairs(ins) do
		print(k, v)
	end 
end

local mac_part = "[0-9a-z][0-9a-z]"
local mac_pattern = string.format("^%s:%s:%s:%s:%s:%s$", mac_part, mac_part, mac_part, mac_part, mac_part, mac_part)	
local function check(map)
	local name, pwd, desc, enable, multi, bind, maclist = map.name, map.pwd, map.desc, map.enable, map.multi, map.bind, map.maclist
	local expire, remain = map.expire, map.remain 

	if not (name and #name > 0 and #name <= 16) then 
		return nil, "invalid name"
	end 

	if not (pwd and #pwd >= 4 and #pwd <= 16) then 
		return nil, "invalid password"
	end

	if not (desc and #desc < 16) then 
		return nil, "invalid desc"
	end 

	if not (enable and (enable == 0 or enable == 1)) then 
		return nil, "invalid enable"
	end

	if not (multi and (multi == 0 or multi == 1)) then 
		return nil, "invalid multi"
	end

	if not (bind and (bind == "mac" or bind == "none")) then 
		return nil, "invalid bind"
	end

	if not (maclist and type(maclist) == "table") then 
		return nil, "invalid maclist"
	end 

	for _, mac in ipairs(maclist) do 
		if not (mac and mac:find(mac_pattern)) then 
			return nil, "invalid mac " .. mac
		end
	end

	if not (expire and (expire[1] == 0 or expire[1] == 1)) then 
		return nil, "invalid expire " .. tostring(expire[1])
	end

	if not (expire and expire[2]:find("%d%d%d%d%d%d%d%d %d%d%d%d%d%d")) then 
		return nil, "invalid expire"
	end 

	if not (remain and (remain[1] == 0 or remain[1] == 1)) then 
		return nil, "invalid remain"
	end

	if not (remain and remain[2] >= 0) then 
		return nil, "invalid remain"
	end

	return true
end

return {
	new = new, 
	check = check,
	setmeta = setmeta, 
	BIND_MAC = BIND_MAC, 
	BIND_NONE = BIND_NONE,
}
