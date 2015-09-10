local function read(path, func)
	local func = func and func or io.open 
	local fp, err = func(path, "rb")
	if not fp then 
		return nil, err 
	end
	local s = fp:read("*a")
	fp:close()
	return s
end

local function write(path, s)
	local fp, err = io.open(path, "wb")
	if not fp then 
		return false, err
	end 
	fp:write(s)
	fp:flush()
	fp:close()
	return true
end

return {read = read, write = write}