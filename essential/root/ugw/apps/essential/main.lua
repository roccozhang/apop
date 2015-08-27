local se = require("se") 
local backupcfg = require("backupcfg")
local watchubus = require("watchubus")

local function main()
	-- watchubus.run()
	-- backupcfg.run()
	while true do 
		se.sleep(1)
	end
end

se.run(main)