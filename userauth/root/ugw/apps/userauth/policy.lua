local expand = require("expand")
local netutil = require("netutil")

local fields = {
	name = "",
	ip1 = "",
	ip2 = "",
	type = "",
}

local new, setmeta, method = expand.expand(fields)

local AUTO = "auto"
local WEB = "web"

function method.show(ins)
	print("-------------------policy")
	for k, v in pairs(ins) do 
		print(k, v)
	end
end

function method.in_range(ins, ip) 
	return netutil.in_range(ip, ins:get_ip1(), ins:get_ip2())
end

return {
	new = new, 
	setmeta = setmeta,
	AUTO = "auto",
	WEB = "web",
}