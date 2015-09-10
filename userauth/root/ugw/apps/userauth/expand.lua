local function expand(fields)
	local method = {}
	local mt = {
		__index = method, 
		__newindex = function(t, k, v) 
			error("forbit new field " .. k) 
		end
	}
	
	for k in pairs(fields) do 
		method["set_" .. k] = function(ins, v)
			ins[k] = v
		end

		method["get_" .. k] = function(ins)
			return ins[k]
		end
	end

	method["set"] = function(ins, map)
		for k, v in pairs(map) do  
			local func = method["set_" .. k] or error("no such field " .. k)
			func(ins, v)
		end
	end

	method["get"] = function(ins, ...)
		local res, karr = {}, ...
		for i, k in ipairs(type(karr) == "table" and karr or {...}) do 
			local func = method["get_" .. k] or error("no such field " .. k)
			res[i] = func(ins)
		end
		return res
	end

	local new = function()
		local obj = {}
		for k, v in pairs(fields) do 
			obj[k] = v 
		end 
		setmetatable(obj, mt)
		return obj
	end

	local setmeta = function(obj)
		setmetatable(obj, mt)
	end

	return new, setmeta, method
end

return {expand = expand}
