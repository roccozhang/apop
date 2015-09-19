local function trans(path, cb)
  local csv = require("csv")
  local fp = csv.open(path)
  for fields in fp:lines() do
    cb(fields)
  end 
end

local field_name
local function validate(lineid, fields)
  local name, pwd, desc, enable, multi, bind, maclist, expire_enable, expire_timestamp, remain_enable, remaining = unpack(fields)
  -- print(name, pwd, desc, enable, multi, bind, maclist, expire_enable, expire_timestamp, remain_enable, remaining)
  if lineid == 1 then 
    field_name = fields
    return 
  end

  if not (name and pwd and desc and enable and multi and bind and maclist and expire_enable and expire_enable and remain_enable and remaining) then 
    return nil, string.format("Invalid format at line %d!", lineid)
  end

  if not (name and #name > 0 and #name <= 16) then 
    return nil, string.format("Invalid format at line %d %s!", lineid, field_name[1])
  end 

  if not (pwd and #pwd >= 4 and #pwd <= 16) then 
    return nil, string.format("Invalid format at line %d %s!", lineid, field_name[2])
  end

  if not (desc and #desc < 16) then 
    return nil, string.format("Invalid format at line %d %s!", lineid, field_name[3])
  end 

  local enable = enable == "" and 1 or tonumber(enable)
  if not (enable and (enable == 0 or enable == 1)) then 
    return nil, string.format("Invalid format at line %d %s!", lineid, field_name[4])
  end

  local multi = multi == "" and 0 or tonumber(multi)
  if not (multi and (multi == 0 or multi == 1)) then 
    return nil, string.format("Invalid format at line %d %s!", lineid, field_name[5])
  end

  local bind = bind == "" and 0 or tonumber(bind)
  if not (bind and (bind == 0 or bind == 1)) then 
    return nil, string.format("Invalid format at line %d %s!", lineid, field_name[6])
  end

  bind = bind == 1 and "mac" or "none"
  local list, s = {}, maclist
  if s ~= "" then 
    s = s:gsub("[ \t\r\n]", "") .. ","
    for part in s:gmatch("(.-),") do 
      local tmp = part:lower()
      if not tmp:find("^[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]$") then 
        return nil, string.format("Invalid format at line %d %s! MAC %s", lineid, field_name[7], part)
      end 
      table.insert(list, tmp)
    end
  end
  maclist = list 

  local expire_enable = expire_enable == "" and 0 or tonumber(expire_enable)
  if not (expire_enable and (expire_enable == 0 or expire_enable == 1)) then 
    return nil, string.format("Invalid format at line %d %s!", lineid, field_name[8])
  end

  local expire_timestamp = expire_timestamp == "" and "20201231 235959" or expire_timestamp
  expire_timestamp = expire_timestamp:gsub("^[ \t\r\n]", "")
  expire_timestamp = expire_timestamp:gsub("[ \t\r\n]$", "")
  if not (expire_timestamp and expire_timestamp:find("^%d%d%d%d%d%d%d%d %d%d%d%d%d%d$")) then 
    return nil, string.format("Invalid format at line %d %s!", lineid, field_name[9])
  end

  local remain_enable = remain_enable == "" and 0 or tonumber(remain_enable)
  if not (remain_enable and (remain_enable == 0 or remain_enable == 1)) then 
    return nil, string.format("Invalid format at line %d %s!", lineid, field_name[10])
  end

  local remaining = remaining == "" and 999999 or tonumber(remaining)
  if not (remaining and remaining >= 0) then 
    return nil, string.format("Invalid format at line %d %s!", lineid, field_name[11])
  end

  return name, pwd, desc, enable, multi, bind, maclist, expire_enable, expire_timestamp, remain_enable, remaining
end

local function check(path)
  local lineid, users = 0, {}
  local err_arr = {}
  trans(path, function(fields)
    lineid = lineid + 1
    local name, pwd, desc, enable, multi, bind, maclist, expire_enable, expire_timestamp, remain_enable, remaining = validate(lineid, fields)
    if not name then 
      local err = pwd 
      if err then 
        table.insert(err_arr, err)
      end 
      return
    end

    local map = {
      name = name, 
      pwd = pwd, 
      desc = desc, 
      enable = enable,
      multi = multi,
      bind = bind,
      maclist = maclist,
      expire = {expire_enable, expire_timestamp},
      remain = {remain_enable, remaining},
    }
    table.insert(users, map)
    --print(name, pwd, desc, enable, multi, bind, maclist, expire_enable, expire_timestamp, remain_enable, remaining)
  end)
  if #err_arr > 0 then 
    return nil, table.concat(err_arr, "\n")
  end
  return users
end

return {check = check}
