package.path = "./?.lua;" .. package.path
require("global")
local se = require("se")
local log = require("log")
local lfs = require("lfs")
local pkey = require("key")
local redis = require("redis")
local js = require("cjson.safe")
local const = require("constant")
local selectap = require("selectap")
local statclient = require("statclient")
local update = require("update")

local pcli, rds 
local keys = const.keys
local rds_addr = "tcp://127.0.0.1:6379"
local max_in_flight = 9
local cur_in_flight = {count = 0, map = {}}
local cur_ap_list, enable_collect
local apid_group_map = {}

local function cursec()
	return math.floor(se.time())
end

local function connect_rds()
	local ins = redis.connect("127.0.0.1", 6379) 	assert(ins)
	return ins
end

local function is_online(apid)
	local group = apid_group_map[apid]
	if not group then 
		return false 
	end 

	local key = "ol/" .. group
	local v = rds:hget(key, apid)
	return tostring(v) == "1" 
end 

local function send_request(apid)
	local p = {
		mod = "a/local/report",
		pld = {cmd = "report", data = {"basic", "radio","assoc","wlan"}},
	}
	pcli:publish("a/ap/" .. apid, js.encode(p), 0, false)
	print(os.date(), "request", apid)
end

local function collect()
	if not enable_collect then
		return 
	end 

	local left = max_in_flight - cur_in_flight.count
	if left <= 0 then 
		return 
	end

	local arr = selectap.nextn(cur_ap_list, left)
	if #arr == 0 then
		return
	end 

	for _, apid in ipairs(arr) do
		if cur_in_flight.map[apid] then
			print(os.date(), "not reply yet, skip", apid)
		elseif is_online(apid) then
			send_request(apid)
			cur_in_flight.map[apid], cur_in_flight.count = {apid = apid, time = cursec()}, cur_in_flight.count + 1
		end
	end
end


local function on_message(data) 
	local arr = data
	local group, apid, kvmap = arr[1], arr[2], arr[3]
	if not (group and apid and kvmap) then 
		print("invalid", js.encode(data))
		return 
	end

	local item = cur_in_flight.map[apid]
	if not item then 
		print("cannot find", apid)
	else
		cur_in_flight.map[apid] = nil
		cur_in_flight.count = cur_in_flight.count - 1 	assert(cur_in_flight.count >= 0)
		collect()
	end

	update.update(group, apid, kvmap)
end

local function loop_param()
	local karr = {keys.c_ap_list}

	while true do 
		local group_map = js.decode(rds:get("collect/ap"))
		if group_map then 
			local group_arr = {}
			enable_collect = false
			for k in pairs(group_map) do 
				enable_collect = true
				table.insert(group_arr, k)
			end 

			local new_arr = {}
			for _, group in ipairs(group_arr) do 
				local varr = pcli:query(group, karr)
				if varr and varr[1] then
					local arr = js.decode(varr[1]) 	assert(arr)
					for _, apid in ipairs(arr) do 
						table.insert(new_arr, apid)
						apid_group_map[apid] = group
					end 
				end 
			end

			table.sort(new_arr)
			cur_ap_list = js.encode(new_arr)
		end

		se.sleep(2)
	end
end

local function loop_collect() 
	while true do
		collect()
		se.sleep(1)
	end
end

local function loop_timeout()
	while true do 
		local del, now = {}, cursec()
		for apid, item in pairs(cur_in_flight.map) do 
			if now - item.time > 20 then 
				print(os.date(), "timeout, remove", apid)
				table.insert(del, apid)
			end
		end

		for _, apid in ipairs(del) do 
			cur_in_flight.map[apid] = nil 
		end 

		cur_in_flight.count = cur_in_flight.count - #del 	assert(cur_in_flight.count >= 0)
		collect()

		se.sleep(5)
	end
end

local function main() 
	log.setmodule("st")
	rds = connect_rds()

	update.set_rds(rds)
	pcli = statclient.new()
	pcli:set_callback("on_message", on_message)
	pcli:run()

	se.go(loop_param)
	se.go(loop_collect)
	se.go(loop_timeout)
end

se.run(main)

