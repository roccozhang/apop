local se = require("se")
local log = require("log")
local pkey = require("key") 
local js = require("cjson.safe")
local mredis = require("mredis")
local const = require("constant") 
local memfile = require("memfile")
local tenalist = require("tenalist") 
local tenaclient = require("tenaclient")

local nrds, brds
local rds_addr = "tcp://127.0.0.1:6379"

local pcli

local keys = const.keys 
local tena = tenalist.ins()

local function cur_sec()
return math.floor(se.time())
end

--查询多个配置项
local function cfg_items_get(keys)
	local group = "default"
	local res = pcli:query(group, keys)
	return res
end


--查询单个配置项
local function cfg_get(k)
	local group = "default"
	local res = pcli:query(group, {k})
	return res
end


--下发黑名单到ap
local function kick(apid, blacklist_info) 
	local p = {
	mod = "a/local/blacklist",
	pld = {cmd = "blacklist", data = blacklist_info},
	}	 		 
	pcli:publish("a/ap/" .. apid, js.encode(p), 0, false)
	--print(os.date(), "request", apid)
end


-- 信号强度，流量，灵敏度，黑名单时间，两次黑名单时间差 
--[[
--"state#78:d3:8d:c3:a3:33"  "2g#sta"
--"[{\"isdual\":0,\"rx\":44,\"mac\":\"38:bc:1a:1b:51:62\",\"ip_address\":\"0.0.0.0\",\"rssi\":-40,\"tx\":2,\"ssid\":\"ath2017\"}]"
--]]
local function check_ap_tenacious(apid, band)
	local m_key = pkey.state_hash(apid)
	local s_key = pkey.key(keys.s_sta, {BAND = band})
	local stas = js.decode(nrds:hget(m_key, s_key)) 
	if not stas then  
		tena:clear_apid(apid, band):save()	-- 没有连接终端, 清空map[band][apid] = nil 
		return {}
	end

	--print("sta count:", #stas)
	local total, interval = tena:get_param("total"), tena:get_param("interval")
	local flow_limit, rssi_limit = tena:get_param("flow_limit"), tena:get_param("rssi_limit")
	local black_list = {}
	for _, sta in ipairs(stas) do
		--log.debug("STA(mac:%s, flow:%s, rssi:%s, apid:%s)", sta.mac, (math.floor((sta.rx + sta.tx)) * 4), sta.rssi, apid)
		if not tena:shoud_skip(apid, band, sta.mac) then	-- 如果已经踢掉了，并且连续两次踢除的最小时间间隔还没过，跳过，不要记录
			local flow = math.floor((sta.rx + sta.tx)) * 4	--4为pps与bps转换后的转换因子	
			--print("sta:", sta.mac, "rssi:", sta.rssi, "flow:", flow)		
			if tonumber(flow) < tonumber(flow_limit) and tonumber(sta.rssi) < tonumber(rssi_limit) then
				local count = tena:incr(apid, band, sta)
				log.debug("match tenacious(mac:%s, flow:%s, rssi:%s, count:%s, apid:%s)", sta.mac, flow, sta.rssi, count, apid)
				--print("sta:", sta.mac, "hit:", count)
				if count >= total then						-- 如果连续次数足够了，踢掉
					table.insert(black_list, {mac = sta.mac, ssid = sta.ssid})
					tena:set_black(apid, band, sta.mac, interval)
					log.info("set tenacious black %s %s %s %s %s", apid, band, count, total, sta.mac)
				--	print("sta:", sta.mac, "add to blacklist")
				end
			else
				--print("sta:", sta.mac, "normal, clear black")
				log.debug("sta:%s normal, clear black count.", sta.mac)
				tena:clear_sta(apid, band, sta.mac)
			end
		end
	end
	local blacklist_info = {["blacklist"] = black_list, ["black_time"] = interval}
	if #blacklist_info["blacklist"] > 0 then
		log.debug("there are %s stas match tenacious totally.", #blacklist_info["blacklist"])
	end
	return blacklist_info
end


--参数更新
local sensitivity_times = {[0] = 16, [1] = 6, [2] = 4}
local function check_param()
	local param_keys = {}
	table.insert(param_keys, keys.c_sensitivity)
	table.insert(param_keys, keys.c_kick_interval)
	table.insert(param_keys, keys.c_rssi_limit)
	table.insert(param_keys, keys.c_flow_limit)
	table.insert(param_keys, keys.c_ten_black_time)
	local res = cfg_items_get(param_keys)
	if res then
		local sensitivity = tonumber(res[1]) 			assert(sensitivity)
		local total = sensitivity_times[sensitivity] or log.fatal("invalid sensitivity %s", sensitivity)
		local param = {
			total = 		total,
			interval = 		tonumber(res[2]),
			rssi_limit = 	tonumber(res[3]),
			flow_limit = 	tonumber(res[4]),
			black_time = 	tonumber(res[5]),
		}

		tena:set_param(param)
	end
end


--从字符串中获取mac列表
local function str_to_macs(str)
    local mac_list = {}
    for mac in string.gmatch(str, '(%x+:%x+:%x+:%x+:%x+:%x+)') do
        table.insert(mac_list, mac)
    end
    return mac_list
end


--检测粘滞终端（逐个ap,逐个radio遍历所有sta）
local function check_tenacious() 
	while true do
		local interval, switch 
		local ap_list = {}
		local query_keys = {}

		table.insert(query_keys, keys.c_ag_sta_cycle)
		table.insert(query_keys, keys.c_tena_switch)
		table.insert(query_keys, keys.c_ap_list)
		local res = cfg_items_get(query_keys)
		if res then
			interval = tonumber(res[1])		assert(interval)
			switch = tonumber(res[2])		assert(switch)
			ap_list = str_to_macs(res[3])	assert(ap_list)
		end

		tena:set_sample_interval(interval)	--interval是sta上报周期，采样时间也设置为interval
		if switch == 1 then
			local bands = {"2g", "5g"} 		--硬编码(todo:后续从配置中获取)
			check_param() 					-- 如果配置改变，重新设置参数，并且清空之前的记录
			-- 遍历所有的AP,以射频为单位遍历(2g/5g)
			for _, apid in ipairs(ap_list) do
				for _, band in ipairs(bands) do 
					local blacklist_info = check_ap_tenacious(apid, band)
					if blacklist_info["blacklist"] and #blacklist_info["blacklist"]> 0 then 
						kick(apid, blacklist_info)
					end
				end
			end
			tena:save()
		end
		local sample_intval = tena:get_sample_interval() or 5
		se.sleep(sample_intval)
	end
end


local function clear_timeout()
	while true do 
		se.sleep(10)
		local _ = tena:get_param("total") and tena:clear_timeout()
	end
end


--连接redis及mqtt
local function connect()
	mredis.connect_blpop(rds_addr)
	mredis.connect_normal(rds_addr)
	nrds, brds = mredis.normal_rds(), mredis.blpop_rds()		assert(nrds and brds)
	pcli = tenaclient.new() 
	pcli:run()
end


local function start()
	connect()
	se.go(check_tenacious)
	se.go(clear_timeout)
end

return {start = start}
