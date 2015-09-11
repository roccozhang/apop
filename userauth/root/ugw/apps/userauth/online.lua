local expand = require("expand")

local fields = {
	mac = "", 		-- key 
	ip = "",
	mac = "",
	name = "",
	elapse = 0,
	part = 0,
}

local new, setmeta, method = expand.expand(fields)

function method.show(ins)
	print("---------------------online")
	for k, v in pairs(ins) do 
		print(k, v)
	end 
end

return {new = new, setmeta = setmeta}

