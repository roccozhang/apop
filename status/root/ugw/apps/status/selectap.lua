local se = require("se")
local log = require("log")
local js = require("cjson.safe")
local memfile = require("memfile")

local min_intervel = 5 
local mf_report = memfile.ins("report_status")

local function cursec()
	return math.floor(se.time())
end

local last_s = ""
local arr_key = "arr"
local function nextn(ns, n)
	assert(n and n > 0)

	if ns and ns ~= last_s then 
		last_s = ns
		log.debug("ap list change")

		local narr = js.decode(last_s)

		local new_map, old_map = {}, {}
		for _, apid in ipairs(narr) do 
			new_map[apid] = 1
		end

		-- 删掉已经移除的AP
		local ap_arr = mf_report:get(arr_key) or mf_report:set(arr_key, {}):get(arr_key)
		for i = 1, #ap_arr do 
			local item = table.remove(ap_arr, 1)
			local apid = item[1]
			if new_map[apid] then
				old_map[apid] = 1, table.insert(ap_arr, item)
			end
		end

		-- 新增的AP放到列表最后
		local now = cursec()
		for apid in pairs(new_map) do 
			local _ = old_map[apid] or table.insert(ap_arr, {apid, now})
		end

		mf_report:set(arr_key, ap_arr):save()
	end

	local ap_arr = mf_report:get(arr_key) or {}
	if #ap_arr == 0 then 
		return {}
	end

	local res, now = {}, cursec()
	local total = n > #ap_arr and #ap_arr or n
	for i = 1, total do
		local item = ap_arr[1]
		if now - item[2] <= min_intervel then
			break
		end
		local item = table.remove(ap_arr, 1)
		item[2] = now
		local _ = table.insert(res, item[1]), table.insert(ap_arr, item)
	end

	local _ = #res > 0 and mf_report:set(arr_key, ap_arr):save()
	
	return res
end

return {nextn = nextn}
