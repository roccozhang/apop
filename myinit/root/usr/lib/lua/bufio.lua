local se = require("se")

local function reader_bufsize(r)
	return #r.buf + 1 - r.pos
end

local function reader_consume(r, n)
	local last = n and r.pos + n - 1 or #r.buf
	local data
	if r.pos == 1 and last == #r.buf then
		data = r.buf
	else
		data = string.sub(r.buf, r.pos, last)
	end
	r.pos = last + 1
	return data
end

local function reader_fill_buffer(r)
	if r.err then
		return false
	end
	if reader_bufsize(r) > 0 then
		return true
	end
	r.buf, r.err = se.read(r.fd, -r.fillsize, r.timeout)
	if r.err then
		r.buf = nil
		r.pos = 0
		return false
	end
	r.pos = 1
	return true
end

local function reader_read(r, n)
	assert(n > 0)
	local data = ''
	while reader_fill_buffer(r) do
		local bufsize = reader_bufsize(r)
		if n <= bufsize then
			return data .. reader_consume(r, n)
		end
		n = n - bufsize
		data = data .. reader_consume(r)
	end
	return nil, r.err
end

local function reader_read_until(r, pat)
	local data = ''
	while reader_fill_buffer(r) do
		local start, stop = string.find(r.buf, pat, r.pos, true)
		if start then
			return data .. reader_consume(r, stop + 1 - r.pos)
		end
		data = data .. reader_consume(r)
	end
	return nil, r.err	
end

local reader_metatable = {
	__index = {
		read = reader_read,
		read_until = reader_read_until,
	},
}

local function reader_new(fd, option)
	local fillsize = option and option.bufsize
	if not fillsize or fillsize <= 0 then
		fillsize = 4096
	end
	local timeout = option and option.timeout or -1
	local r = {
		fd = fd,
		buf = '',
		pos = 1,
		fillsize = fillsize,
		timeout = timeout,
	}
	setmetatable(r, reader_metatable)
	return r
end

local bufio = {
	new_reader = reader_new,
}

return bufio