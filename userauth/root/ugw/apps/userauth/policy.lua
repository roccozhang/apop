local expand = require("expand")

local fields = {
	name = "",
	ip1 = "",
	ip2 = "",
	type = "",
}

local new, setmeta = expand.expand(fields)

local AUTO = "auto"
local WEB = "web"
function is_auto(ip)
	print("TODO", is_auto)
	return false
end

return {
	new = new, 
	setmeta = setmeta,
	is_auto = is_auto,
	AUTO = "auto",
	WEB = "web",
}