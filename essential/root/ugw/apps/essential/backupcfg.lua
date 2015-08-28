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
		local path = item.path
		local attr = lfs.attributes(path)

		if attr then
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


local function backup_diff(change_map)
	local change = false
	for path, md5 in pairs(change_map) do
		local omd5 = cm.get(path)
		if md5 ~= omd5 then 
			print("change", path)
			local dir = path:match("(.+)/")
			local tmp = path .. ".tmp"
			local cmd = string.format([[
					mkdir -p %s%s >/dev/null 2>&1
					cp -f %s %s%s >/dev/null 2>&1
					md5sum %s%s | awk '{print $1}'
				]], backup_root, dir, path, backup_root, tmp, backup_root, tmp)

			se.sleep(0.1)
			local nmd5 = read(cmd, io.popen):gsub("[ \t\r\n]", "") 	
			local _ = md5 == nmd5 or error("backup %s fail", path)
			if md5 == nmd5 then 
				local ret = os.execute(string.format("mv %s%s %s%s", backup_root, tmp, backup_root, path))
				local _ = ret == 0 or error("backup %s fail 2", path)
				if ret == 0 then 
					cm.set(path, md5)
					cm.save()
					change = true	
					print("backup ok", path)
				end
			end
		end
	end

	local _ = change and os.execute("sync")
end

local function mount_ready()
	local s = read("/proc/self/mountinfo")
	for _, p in ipairs({"overlay", "backup"}) do 
		if not s:find(p) then 
			error("not mount %s, skip check restore", p)
			return false
		end 
	end
	return true
end

local function restore(path)
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

local function upgrading_exit()
	if lfs.attributes(upgrade_flag) then 
		error("upgrading, skip restore")
		local _ = se.sleep(5), os.exit(0) 
	end
end

local config_normal_flag = "/etc/config/config_normal_flag_do_not_delete"
local function check_restore()
	upgrading_exit()

	-- if overlay or backup is not mount, skip
	if not mount_ready() then 
		return 
	end

	-- if there's no md5.json, skip
	local config_ok = lfs.attributes(config_normal_flag) ~= nil
	if not cm.md5exist() then
		if not config_ok then 
			upgrading_exit()
			error("not find %s, touch", config_normal_flag)
			os.execute("touch " .. config_normal_flag)
		end
		return 
	end

	if config_ok then
		return 
	end

	error("md5.json exist, but missing %s. restore!!!", config_normal_flag)

	local change = false
	for _, item in pairs(cfg) do 
		local path = item.path
		local backup_path = string.format("%s%s", backup_root, path)
		local md5 = md5.sumhexa(read(backup_path))
		local cmd5 = cm.get(path) or ""

		upgrading_exit()
		if md5 ~= cmd5 then
			error("ERROR backup. remove %s %s %s", md5, cmd5, backup_path)
			os.remove(backup_path)
			cm.set(path, nil)
			cm.save()
		else
			local cmd = string.format("cp %s %s; md5sum %s | awk '{print $1}'", backup_path, path, path)
			local nmd5 = read(cmd, io.popen):gsub("[ \t\r\n]", "")
			local flag = nmd5 == md5 and "ok" or "fail"
			error("restore %s %s", flag, path)
			change = true
		end
	end

	if change then 
		error("restore finish, touch %s. reboot", config_normal_flag)
		os.execute("touch " .. config_normal_flag)
		os.execute("sync; reboot; sleep 5")
		se.sleep(5)
		os.exit(0)
	end 
end

local function main()
	while true do
		local change = get_change_files()
		local _ = change and backup_diff(change)
		se.sleep(30)
	end
end

local function loop_check_restore()
	while true do 
		se.sleep(30)
		check_restore()
	end
end

local function run()
	check_restore()
	se.go(main)
	se.go(loop_check_restore)
end

return {run = run}
