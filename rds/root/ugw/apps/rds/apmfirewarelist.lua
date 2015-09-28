local log = require("log")
local lfs = require("lfs")
local log = require("log")
local pkey = require("key") 
local js = require("cjson.safe")  

local rds, pcli 

local function apmupdatefireware(conn, group, data)
	assert(conn and conn.rds and group)
	rds, pcli = conn.rds, conn.pcli
	
	local apid_arr = data
	if type(apid_arr) ~= "table" then
		log.debug("error %s", data);
		return {status = 1, data = "error"}
	end

	pcli:modify({cmd = "upgrade", data = {group = "default", arr = apid_arr}})
	return {status = 0, data = ""}
end

local function apmfirewarelist(conn, group, data) 
	if not lfs.attributes("/www/rom") then 
		return {status = 0, data = {}}	
	end 

	local vers = {}
	for filename in lfs.dir("/www/rom/") do 
		local version = filename:match("(.+%.%d%d%d%d%d%d%d%d%d%d%d%d)")
		local _ = version and table.insert(vers, version)
	end
	return {status = 0, data = vers}	
end

return {
	apmfirewarelist = apmfirewarelist,
	apmupdatefireware = apmupdatefireware,
}

