local log = require("log")  
local lfs = require("lfs")
local js = require("cjson.safe")
local const = require("constant")   
local pkey = require("key")

local rds, pcli
local keys = const.keys 

local function getaplog(conn, group, data)  
	rds, pcli = conn.rds, conn.pcli 	assert(rds and pcli) 
	local apid = data
	local res = pcli:getlog(apid) or ""
	return {status = 0, data = res}
end


local function downloadaplog(conn, group, data) 
	rds = conn.rds 								assert(rds)

	local aparr = data
	for _, apid in pairs(aparr) do
		if #apid ~= 17 then 
			log.error("error data")
			return {status = 1, data = "invalid apid"}
		end
	end

	local cmd_arr = {}
	local logdir = "/tmp/ugw/log/aplog/"
	
	table.insert(cmd_arr, string.format("cd %s || exit -1\nrm -f /www/aplog.tar\ntar -cf /www/aplog.tar ", logdir))
	for _, apid in pairs(aparr) do 
		local dirpath = logdir .. apid 
		local _ = lfs.attributes(dirpath) and table.insert(cmd_arr, apid)
	end

	table.insert(cmd_arr, "/tmp/ugw/log/wac")

	local cmd = table.concat(cmd_arr, " ")
	local ret, err = os.execute(cmd)
	local _ = ret == 0 or log.error("execute %s fail %s", cmd, err or "") 

	return {status = 0, data = "ok"}
end

return {
	getaplog = getaplog,
	downloadaplog = downloadaplog,
}
