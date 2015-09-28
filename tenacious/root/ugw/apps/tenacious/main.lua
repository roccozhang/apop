require("global")
local se = require("se")
local log = require("log") 
local lfs = require("lfs")   
local pkey = require("key")
local js = require("cjson.safe")
local mredis = require("mredis")
local tena = require("tenacious")  
local const = require("constant") 

local nrds, brds
local keys = const.keys 

local function check_debug()
	while true do  
		log.setdebug(lfs.attributes("/tmp/wac_debug") and true or false) 
		se.sleep(3)
	end
end

local function main() 
	log.setmodule("ta")
	log.debug("start tenacious-reject ...")
	se.go(tena.start)
	se.go(check_debug)
end

se.run(main)
