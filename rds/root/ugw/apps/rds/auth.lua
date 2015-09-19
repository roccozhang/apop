local log = require("log") 
local js = require("cjson.safe")

local rds, pcli

local function useradd(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
end 

local function userdel(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
end 

local function userset(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
end 

local function userget(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
end 

local function userimport(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
end 

local function policyadd(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
end 

local function policydel(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
end 

local function policyset(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
end

local function policyadj(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
end 

local function policyget(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
end 

local function onlinedel(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
end 

local function onlineget(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
end 

return {
	useradd = useradd,
	userdel = userdel,
	userset = userset,
	userget = userget,
	userimport = userimport,
	policyadd = policyadd,
	policydel = policydel,
	policyset = policyset,
	policyadj = policyadj,
	policyget = policyget,
	onlinedel = onlinedel,
	onlineget = onlineget,
}