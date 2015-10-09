local uci = require("uci")
local js = require("cjson.safe") 
local myutil = require("myutil")

local read = myutil.read

local function get_firewall()
	local ret = uci.load("firewall")
	if not ret then 
		return
	end 

	local cursor = uci.cursor()
	local iface = {}
	cursor:foreach("firewall", "zone", function(sec)
		local name, network = sec.name, sec.network
		iface[name] = network
	end)
	return iface
end

local function get_network()
	local ret = uci.load("network")
	if not ret then 
		return
	end 
	local cursor = uci.cursor() 
	local netw = {}
	cursor:foreach("network", "interface", function(sec)
		local name, ifname = sec[".name"], sec.ifname
		if sec.type == "bridge" then 
			ifname = "br-" .. name 
		end 
		netw[name] = ifname
	end)
	return netw
end

local cmd_map = {}

function cmd_map.iface(arg)
	local firewall_map, network_map = get_firewall(), get_network()
	if not (firewall_map and network_map) then 
		io.stderr:write("read firewall or network fail\n")
		os.exit(-1)
	end 

	local type_map = {wan = 1, lan = 0}
	local arr = {}
	for ftype, network in pairs(firewall_map) do 
		for _, network_name in ipairs(network) do 
			local ifname = network_map[network_name]
			if ifname then 
				table.insert(arr, {
					InterfaceName = ifname,
					InterfaceType = type_map[ftype],
				})
			end 
		end 
	end 

	local s = js.encode(arr)
	print(s)
end 

local arg = {...}
local cmd = table.remove(arg, 1)
cmd_map[cmd](arg)


