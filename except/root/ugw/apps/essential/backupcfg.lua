local se = require("se") 
local cfg = require("cfg")
local lfs = require("lfs")
local md5 = require("md5")
local cm = require("cfgmd5")
local js = require("cjson.safe")

local backup_root = "/backup/root"
local upgrade_flag = "/tmp/sysupgrade"
local last_map = {}

local function read(path, func)
	func = func and func or io.open
	local fp = func(path, "rb")
	if not fp then 
		return 
	end 
	local s = fp:read("*a")
	fp:close()
	return s
end

local function error(fmt, ...)
	local s = string.format("e %s " .. fmt, os.date("%m%d %H%M%S"), ...) 
	local cmd = string.format("echo '%s' >> /backup/essential.log", s)
	os.execute(cmd)
	print(s)
end 

local function get_change_files()
	local change, flag = {}
	for _, item in ipairs(cfg) do 
		local path, attr = item.path

		for i = 1, 5 do 
			attr = lfs.attributes(path)
			if attr then 
				break 
			end 
			se.sleep(1)
		end

		if not attr then
			error("missing %s", path)
			change[path], flag = "0", true
			last_map[path] = nil
		else 
			local op = last_map[path]
			if not op then  
				local md5 = md5.sumhexa(read(path))
				change[path], flag = md5, true
				last_map[path] = {modification = attr.modification, md5 = md5}
			elseif op.modification ~= attr.modification then
				local md5 = md5.sumhexa(read(path))
				if md5 ~= op.md5 then 
					change[path], flag = md5, true
					last_map[path] = {modification = attr.modification, md5 = md5}
				end
			end
		end
	end

	return flag and change or nil
end

local function restore(path)
	if lfs.attributes(upgrade_flag) then 
		error("upgrading, skip restore")
		local _ = se.sleep(5), os.exit(0)
	end
	
	local backup_path = string.format("%s%s", backup_root, path)
	local md5 = md5.sumhexa(read(backup_path))
	local cmd5 = cm.get(path) or ""
	if md5 ~= cmd5 then  
		error("ERROR backup. remove %s %s %s", md5, cmd5, backup_path)
		os.remove(backup_path)
		cm.set(path, nil)
		cm.save()
		return false
	end

	local cmd = string.format("cp %s %s; md5sum %s | awk '{print $1}'", backup_path, path, path)
	local nmd5 = read(cmd, io.popen):gsub("[ \t\r\n]", "")
	local flag = nmd5 == md5 and "ok" or "fail"
	error("restore %s %s", flag, path)
	return true
end

local function backup_diff(change)
	local need_restart, change = false, change
	for path, md5 in pairs(change) do
		if md5 == "0" then 
			need_restart = restore(path) and true or need_restart
		else
			local omd5 = cm.get(path)
			if md5 ~= omd5 then 
				print("change", path)
				local dir = path:match("(.+)/")
				local cmd = string.format([[
						mkdir -p %s%s >/dev/null 2>&1
						cp -f %s %s%s >/dev/null 2>&1
						md5sum %s%s | awk '{print $1}'
					]], backup_root, dir, path, backup_root, path, backup_root, path)

				se.sleep(0.1)
				local nmd5 = read(cmd, io.popen):gsub("[ \t\r\n]", "") 	assert(md5 == nmd5)
				cm.set(path, md5)
				cm.save()
				change = true
				print("backup ok", path)
			end
		end
	end

	local _ = change and os.execute("sync")

	return need_restart
end

local function main()
	while true do
		local change = get_change_files()
		if change then
			local need_restart = backup_diff(change)
			if need_restart then 
				error("reboot")
				-- os.execute("reboot") 
			end
		end
		se.sleep(60)
	end
end

local function run()
	se.go(main)
end

return {run = run}
