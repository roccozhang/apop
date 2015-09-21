local log = require("log") 
local lfs = require("lfs")
local js = require("cjson.safe")

local rds, pcli

local ip_pattern = "^[0-9]+%.[0-9]+%.[0-9]+%.[0-9]+$"
local mac_part = "[0-9a-z]"
local mac_pattern = string.format("^%s:%s:%s:%s:%s:%s$", mac_part, mac_part, mac_part, mac_part, mac_part, mac_part)	

local function errmsg(msg)
	return {status = 1, msg = msg}
end

local function check_user(map) 
	local name, pwd, desc, enable, multi, bind, maclist = map.name, map.pwd, map.desc, map.enable, map.multi, map.bind, map.maclist
	local expire, remain = map.expire, map.remain 

	if not (name and #name > 0 and #name <= 16) then 
		return nil, "invalid name"
	end 

	if not (pwd and #pwd >= 4 and #pwd <= 16) then 
		return nil, "invalid password"
	end

	if not (desc and #desc < 16) then 
		return nil, "invalid desc"
	end 

	if not (enable and (enable == 0 or enable == 1)) then 
		return nil, "invalid enable"
	end

	if not (multi and (multi == 0 or multi == 1)) then 
		return nil, "invalid multi"
	end

	if not (bind and (bind == "mac" or bind == "none")) then 
		return nil, "invalid bind"
	end

	if not (maclist and type(maclist) == "table") then 
		return nil, "invalid maclist"
	end 

	for _, mac in ipairs(maclist) do 
		if not (mac and mac:find(mac_pattern)) then 
			return nil, "invalid mac"
		end
	end

	if not (expire and (expire[1] == 0 or expire[1] == 1)) then 
		return nil, "invalid expire"
	end

	if not (expire and expire[2]:find("%d%d%d%d%d%d%d%d %d%d%d%d%d%d")) then 
		return nil, "invalid expire"
	end 

	if not (remain and (remain[1] == 0 or remain[1] == 1)) then 
		return nil, "invalid remain"
	end

	if not (remain and remain[2] >= 0) then 
		return nil, "invalid remain"
	end

	return true
end

local function useradd(conn, group, map)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	local ret, err = check_user(map)
	if not ret then 
		return errmsg(err)
	end

	return pcli:query_auth({cmd = "user_add", data = {group = group, data = {map}}}) or errmsg("query_auth fail")
end 

local function userdel(conn, group, arr)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	for _, name in ipairs(arr) do 
		if not (#name > 0 and #name <= 16) then 
			return errmsg("invalid username")
		end 
	end 
	return pcli:query_auth({cmd = "user_del", data = {group = group, data = arr}}) or errmsg("query_auth fail")
end 

local function userset(conn, group, map)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)

	local ret, err = check_user(map)
	if not ret then 
		return errmsg(err)
	end

	return pcli:query_auth({cmd = "user_set", data = {group = group, data = {[map.name] = map}}}) or errmsg("query_auth fail")
end 

local function userget(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	return pcli:query_auth({cmd = "user_get", data = {group = group, data = data}}) or "{}"
end

local function userimport(conn, group, path)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	if not lfs.attributes(path) then 
		return errmsg("not find " .. path)
	end
	local importuesr = require("importuesr")
	local arr, err = importuesr.check(path)
	if not arr then 
		return errmsg(err)
	end 

	return pcli:query_auth({cmd = "user_add", data = {group = group, data = arr}}) or errmsg("query_auth fail")
end

local function check_policy(map)
	local name, ip1, ip2, tp = map.name, map.ip1, map.ip2, map.type 
	if not (name and #name > 0 and #name < 16) then 
		return nil, errmsg("invalid name")
	end 

	if not (ip1 and ip1:find(ip_pattern and ip2 and ip2:find(ip_pattern))) then 
		return nil, errmsg("invalid ip range")
	end 

	if not (tp and (tp == "auto" or tp == "web")) then 
		return nil, errmsg("invalid name")
	end 

	return true 
end

local function policyadd(conn, group, map)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)

	local ret, msg = check_policy(map) 
	if not ret then 
		return msg 
	end 

	return pcli:query_auth({cmd = "policy_set", data = {group = group, data = map}}) or errmsg("query_auth fail")
end 

local function policydel(conn, group, arr)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	for _, name in pairs(arr) do 
		if not (#name > 0 and #name < 16) then 
			return errmsg("invalid param")
		end 
	end
	return pcli:query_auth({cmd = "policy_del", data = {group = group, data = arr}}) or errmsg("query_auth fail")
end 


local function policyset(conn, group, map)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	local ret, msg = check_policy(map) 
	if not ret then 
		return msg 
	end 

	return pcli:query_auth({cmd = "policy_set", data = {group = group, data = {[map.name] = map}}}) or errmsg("query_auth fail") 
end

local function policyadj(conn, group, arr)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	for _, name in pairs(arr) do 
		if not (#name > 0 and #name < 16) then 
			return errmsg("invalid param")
		end 
	end
	
	return pcli:query_auth({cmd = "policy_adj", data = {group = group, data = arr}})
end 

local function policyget(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli) 
	return pcli:query_auth({cmd = "policy_get", data = {group = group}}) or "{}"
end 

local function onlinedel(conn, group, arr)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	for _, mac in ipairs(arr) do 
		if not (#mac == 17 and mac:find(mac_pattern)) then 
			return errmsg("invalid mac")
		end
	end
	return pcli:query_auth({cmd = "online_del", data = {group = group, data = arr}})  or errmsg("query_auth fail")
end 

local function onlineget(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	return pcli:query_auth({cmd = "online_get", data = {group = group, data = data}}) or "{}"
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