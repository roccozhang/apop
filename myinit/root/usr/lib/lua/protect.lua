local mt = {}
mt.__index = {
	call = function(ins, f)
		local ret, msg = xpcall(f, function(err)
			local trace = debug.traceback()
			local t = {err}
			for line in trace:gmatch("(.-)\n") do  
				--if not line:find("%[C%]:") then 
					table.insert(t, line)
				--end
			end
			return table.concat(t, "\n")
		end)
		local _ = not ret and ins.handler(msg)
		return ret, msg
	end, 
	sethandler = function(ins, handler)
		ins.handler = handler
	end, 
}

local function default_log(msg)
	io.stderr:write(msg, "\n")
end

local function default_handler(msg)
	local _ = default_log(msg), os.exit(-1)
end

local function new()
	local ins = {
		log = default_log,
		handler = default_handler,
	}
	setmetatable(ins, mt)
	return ins
end

return {new = new}
