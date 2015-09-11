local expand = require("expand")

local BIND_NONE = "none"
local BIND_MAC = "mac"

local fields = {
	name = "",
	pwd = "",
	desc = "",
	mac = "",

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

function method.set_expire(ins, enable, ts)
	ins.expire = {enable, ts}
end

function method.set_remain(ins, enable, left)
	ins.remain = {enable, left}
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
	print(expire[2], get_timestamp(), expire[2] < get_timestamp())
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

-- local ins = new()
-- ins:set_remain({1, 3600, "20150901 12:00:00"})
-- -- ins:show()

-- print(ins:check_remain())

return {new = new, setmeta = setmeta, BIND_MAC = BIND_MAC, BIND_NONE = BIND_NONE}
