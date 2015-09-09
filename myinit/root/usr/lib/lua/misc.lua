local log = require("log")
local pkey = require("key") 
local js = require("cjson.safe")
local const = require("constant")
local protect = require("protect") 

local keys = const.keys

 local function bexec(cmd, cb)
	local fp, err = io.popen(cmd, "r")
	if not fp then 
		return nil, err
	end
	local s = fp:read("*a")
	fp:close()
	return s
end

local function next_batch(ks, total)
	local res = {}
	for i = 1, total do 
		local tmp = table.remove(ks, 1)
		if not tmp then 
			return res
		end
		table.insert(res, tmp)
	end
	return res, true
end

local function classify(res)
	local class = {}
	for _, t in ipairs(res) do 
		local k, s = t[1], t[2]
		local k = k:match(".+/(.+)") or log.fatal("error msg key %s", k)
		local item = class[k] or {}
		table.insert(item, s)
		class[k] = item
	end
	return class
end 

local function device_mac()
	local cmd = "ifconfig eth0 | grep ether | awk '{print $2}'"
	local wid, err = bexec(cmd)
	if not wid then 
		return wid, err 
	end 
	return wid:gsub("\n", "")
end

return {bexec = bexec, 
		next_batch = next_batch, 
		classify = classify, 
		device_mac = device_mac, 
	}
