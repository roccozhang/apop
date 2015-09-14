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

local function check(map)
	local ip_pattern = "^[0-9]+%.[0-9]+%.[0-9]+%.[0-9]+$"
	local name, ip1, ip2, tp = map.name, map.ip1, map.ip2, map.type 
	if not (name and #name > 0 and #name <= 16) then 
		return nil, "invalid name"
	end 

	if not (ip1 and ip1:find(ip_pattern) and ip2 and ip2:find(ip_pattern)) then 
		return nil, "invalid ip"
	end 

	if not (tp and (tp == "web" or tp == "auto")) then 
		return nil, "invalid type"
	end  
	
	return true
end


return {
	new = new, 
	check = check,
	setmeta = setmeta,
	AUTO = "auto",
	WEB = "web",
}