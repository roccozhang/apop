local expand = require("expand")

local BIND_NONE = "none"
local BIND_MAC = "mac"

local fields = {
	name = "",
	passwd = "",
	desc = "",
	mac = "",

	enable = true,

	multi_enable = true,

	bind = BIND_NONE,
	maclist = {},

	expire_enable = true,
	expire = "",

	remain_enable = true,
	remain = 0,
}

local new, setmeta, method = expand.expand(fields)

function method.allow(ins, mac) 
	for _, m in ipairs(ins:get_maclist()) do
		if m == mac then 
			return true
		end
	end
	return false
end

function method.show(ins)
	print("---------------------user")
	for k, v in pairs(ins) do 
		print(k, v)
	end 
end

return {new = new, setmeta = setmeta, BIND_MAC = BIND_MAC, BIND_NONE = BIND_NONE}
