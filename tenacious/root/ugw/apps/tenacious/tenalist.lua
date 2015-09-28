local se = require("se")
local log = require("log") 
local js = require("cjson.safe") 
local const = require("constant") 
local memfile = require("memfile")

--[[
{
	param = {
		total = xx, 
		interval = xx, 
		rssi_limit = xx,
		flow_limit = xx, 
		black_time = xx,
	},
	tenacious_2g = {
		[apid1] = {
			[sta_mac1] = {arr = {}, black = nil/time, active = time}
		},
	}
--]]

local function cursec()
	return math.floor(se.time())
end

-- 清除超时的记录
local function clear_timeout_rec(arr, timeout)
	local newarr = {}
	local now = cursec()
	
	for _, item in ipairs(arr) do 
		if now - item.active < timeout then 
			table.insert(newarr, item)
		-- else 
		-- 	print("timeout -- ", timeout, js.encode(item))
		end
	end

	return newarr
end

local mt = {}
mt.__index = {
	get_sample_interval = function(ins)
		return ins.sample_interval
	end,

	set_sample_interval = function(ins, i)
		ins.sample_interval = i
	end,

	set_param = function(ins, n)
		assert(ins and n)
		assert(n.total and n.interval and n.rssi_limit and n.flow_limit and n.black_time)

		local change, o = false, ins.mf:get("param")
		
		for k, v in pairs(o) do 
			assert(n[k])
			if n[k] ~= v then 
				log.debug("tenacious %s change %s -> %s", k, v, n[k])
				change = true
			end
		end

		if not change then 
			return 
		end 

		-- 配置改变了，清空所有的记录(清空tenacious_2g和tenacious_5g)
		ins.mf:set("tenacious_2g", nil):set("tenacious_5g", nil):set("param", n):save() 
	end,

	get_param = function(ins, k)
		local p = ins.mf:get("param")
		return p[k]
	end,

	get_apid_map = function(ins, apid, band)
		local bkey = "tenacious_" .. band 

		local band_map = ins.mf:get(bkey) or ins.mf:set(bkey, {}):get(bkey) --key不存在，则添加
		if not band_map[apid] then 
			band_map[apid] = {}
		end

		return band_map[apid]
	end,

	incr = function(ins, apid, band, sta)
		assert(ins and #apid == 17 and band and sta)

		local apid_map = ins:get_apid_map(apid, band)
		--没有则填充一个空的sta_map
		local sta_map = apid_map[sta.mac] or {arr = {}, black_deadline = nil} 	assert(not sta_map.black)

		table.insert(sta_map.arr, {rx = sta.rx, rssi = sta.rssi, active = cursec()})
		-- 记录超时时间设为2倍采样时间*次数，足够了，此处相当于滑动窗口
		sta_map.arr = clear_timeout_rec(sta_map.arr, ins:get_param("total") * 2 * ins.sample_interval)
	
		apid_map[sta.mac] = sta_map
		ins.mf:setchange()
	
		return #sta_map.arr --返回数组长度，也即返回记录的次数，用于判断是否应该加入黑名单
	end,

	-- 删除终端信息
	clear_sta = function(ins, apid, band, sta_mac)
		assert(ins and #apid == 17 and band and sta_mac)
		
		local apid_map = ins:get_apid_map(apid, band)
		if apid_map[sta_mac] then
			apid_map[sta_mac] = nil
			ins.mf:setchange()
		end
	end,

	-- 删除AP和关联的终端信息
	clear_apid = function(ins, apid, band)
		assert(ins and #apid == 17 and band)
		
		local bkey = "tenacious_" .. band 
		local map = ins.mf:get(bkey) 
		if not (map and map[band] and map[band][apid]) then 
			return ins
		end
	
		map[band][apid] = nil 
		ins.mf:set(bkey, map)
	
		return ins 
	end,

	-- 如果已经踢掉，并且在 连续两次踢除的最小时间间隔 内，忽略本次
	shoud_skip = function(ins, apid, band, sta_mac)
		assert(ins and #apid == 17 and band and #sta_mac == 17)
	
		local apid_map = ins:get_apid_map(apid, band)	--<apid, sta_mac>
		local sta_map = apid_map[sta_mac] 	

		if not sta_map then
			return false 
		end 
		
		-- 此处顺带处理黑名单的超时
		if sta_map.black_deadline then 
			local now = cursec()
			-- 黑名单超超时，清除终端黑名单信息
			if now > sta_map.black_deadline then 
				ins:clear_sta(apid, band, sta_mac)
			end
			assert(#sta_map.arr == 0)
			log.debug("ignore sta %s", sta_mac)
			return true	
		end

		return false
	end,

	-- 设置终端黑名单
	set_black = function(ins, apid, band, sta_mac, interval)
		assert(#apid == 17 and #sta_mac == 17 and band and interval)

		local apid_map = ins:get_apid_map(apid, band)
		local sta_map = apid_map[sta_mac] 	 	assert(sta_map and not sta_map.black_deadline)
		
		sta_map.arr = {}	--清空数组
		sta_map.black_deadline = interval + cursec() 	-- interval秒后超时
		ins.mf:setchange()
		
		return ins
	end,

	clear_timeout = function(ins)
		local now, change = cursec(), false
		local maxtimeout = ins:get_param("total") * 2 * ins.sample_interval 	assert(maxtimeout < 600)

		for _, band in ipairs({"2g", "5g"}) do 
			local bkey = "tenacious_" .. band 
			local band_map = ins.mf:get(bkey) 

			if band_map then
				for apid, apid_map in pairs(band_map) do
					local delarr = {}
					for sta_mac, sta_map in pairs(apid_map)  do 
						-- 如果有black_deadline, 超时后删除。此时,sta_map.arr为{}，不需要检查
						if sta_map.black_deadline then
							if sta_map.black_deadline < now then 
								sta_map.black_deadline, change = nil, true
							end
						else 
							-- 删除超时的记录项
							local delidx = 0
							for i, item in ipairs(sta_map.arr) do 
								if now - item.active > maxtimeout then 
									delidx = i
									--break 	--now - item.active < maxtimeout直接break，时间升序排列，此处处理有误
								end
							end

							for i = 1, delidx do 
								table.remove(sta_map.arr, 1)
								change = true
							end

							local _ = #sta_map.arr == 0 and table.insert(delarr, sta_mac)
						end						
					end

					-- 删除apid下，记录数为0的sta
					for _, sta_mac in ipairs(delarr) do 
						apid_map[sta_mac], change = nil, true
					end
				end
			end
		end

		local _ = change and ins.mf:force_save()
	end,

	save = function(ins)
		ins.mf:save()
	end,
}

local instance
local function ins()
	if not instance then
		local mf = memfile.ins("tenacious")
		local _ = mf:get("param") or mf:set("param", {total = 0, interval = 0, flow_limit = 0, rssi_limit = 0, black_time = 0}):save()

		instance = {
			mf = mf,
			sample_interval = 5,
		}
		setmetatable(instance, mt)
	end
	return instance
end

return {ins = ins}

