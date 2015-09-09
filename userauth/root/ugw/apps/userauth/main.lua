local se = require("se")   
local function read(path, func)
	func = func and func or io.open
	local fp = func(path, "rb")
	if not fp then 
		return 
	end 
	local s = fp:read("*a")
	fp:close()
	return s
end
 
local function main()  
	while true do
		print(os.date())
		se.sleep(10)
	end
end

se.run(main)