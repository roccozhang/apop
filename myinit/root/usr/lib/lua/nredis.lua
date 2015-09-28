local se = require('se')
local bufio = require('bufio')

local function redis_close(r)
	if r.fd then
		local err = se.close(r.fd)
		r.fd = nil
		r.reader = nil
		return err
	end
	return nil
end

local function redis_connect(r)
	if r.fd then
		assert(r.reader)
		return nil
	end
	local fd, err = se.connect(r.addr, r.connect_timeout)
	if err then
		return err
	end
	r.fd = fd
	r.reader = bufio.new_reader(fd, { timeout = r.read_timeout })
	return nil
end

local function redis_format_command(args)
	local cmd = string.format('*%d\r\n', #args)
	for _, arg in ipairs(args) do
		arg = tostring(arg)
		cmd = cmd .. string.format('$%d\r\n%s\r\n', #arg, arg)
	end
	return cmd
end

local function redis_read_status(reader)
	local line, err = reader:read_until('\r\n')
	if err then
		return nil, err
	end
	return { ok = string.sub(line, 1, -3) }
end

local function redis_read_error(reader)
	local line, err = reader:read_until('\r\n')
	if err then
		return nil, err
	end
	return { err = string.sub(line, 1, -3) }
end

local function redis_read_number(reader)
	local line, err = reader:read_until('\r\n')
	if err then
		return nil, err
	end
	local number = tonumber(string.sub(line, 1, -3))
	if not number then
		return nil, 'redis error, bad number: ' .. line
	end
	return number
end

local function redis_read_string(reader)
	local len, err = redis_read_number(reader)
	if err then
		return nil, err
	end
	if len < 0 then
		return false
	end
	local data, err = reader:read(len + 2)
	if err then
		return nil, err
	end
	if string.sub(data, -2) ~= '\r\n' then
		return nil, 'redis error, bad string: ' .. data
	end
	return string.sub(data, 1, -3)
end

local redis_read_object

local function redis_read_array(reader)
	local len, err = redis_read_number(reader)
	if err then
		return nil, err
	end
	if len < 0 then
		return false
	end
	local arr = {}
	for i = 1, len do
		local obj, err = redis_read_object(reader)
		if err then
			return nil, err
		end
		table.insert(arr, obj)
	end
	return arr
end

redis_read_object = function(reader)
	local prefix, err = reader:read(1)
	if err then
		return nil, err
	end
	if prefix == '+' then
		return redis_read_status(reader)
	elseif prefix == '-' then
		return redis_read_error(reader)
	elseif prefix == ':' then
		return redis_read_number(reader)
	elseif prefix == '$' then
		return redis_read_string(reader)
	elseif prefix == '*' then
		return redis_read_array(reader)
	end
	return nil, 'redis error, bad prefix: ' .. prefix
end

local function redis_parse(str)
	local r = bufio.new_reader(-1, { initbuf = str })
	return redis_read_object(r)
end

local function redis_format(obj)
	local objtype = type(obj)
	if objtype == 'string' then
		return string.format('$%d\r\n%s\r\n', #obj, obj)
	elseif objtype == 'number' then
		return string.format(':%d\r\n', obj)
	elseif objtype == 'boolean' then
		if obj == false then
			return string.format('$-1\r\n')
		else
			return ':1\r\n'
		end
	elseif objtype == 'table' then
		if obj.ok then
			return string.format('+%s\r\n', obj.ok)
		elseif obj.err then
			return string.format('-%s\r\n', obj.err)
		else
			local res = string.format('*%d\r\n', #obj)
			for _, elem in ipairs(obj) do
				res = res .. redis_format(elem)
			end
			return res
		end
	else
		error('redis_format() not support type: ' .. objtype)
	end
end

local function redis_write(r, obj)
	return se.write(r.fd, redis_format(obj), r.write_timeout)
end

local function redis_read(r)
	return redis_read_object(r.reader)
end

local function redis_call(r, ...)
	local err = se.write(r.fd, redis_format_command({...}), r.write_timeout)
	if err then
		return nil, err
	end
	return redis_read_object(r.reader)
end

local redis_metatable = {
	__index = {
		close = redis_close,
		connect = redis_connect,
		write = redis_write,
		read = redis_read,
		call = redis_call,
	},
}

local function redis_new(addr, option)
	local r = {
		addr = addr,
		connect_timeout = option and option.connect_timeout or -1,
		read_timeout = option and option.read_timeout or -1,
		write_timeout = option and option.write_timeout or -1,
	}
	setmetatable(r, redis_metatable)
	return r
end

local redis = {
	new = redis_new,
	format = redis_format,
	parse = redis_parse,
}

return redis
