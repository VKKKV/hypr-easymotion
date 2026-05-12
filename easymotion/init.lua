local config = require("easymotion.config")
local labels = require("easymotion.labels")
local json = require("easymotion.json")

local M = {}

local function get_hl()
  local api = rawget(_G, "hl")
  if type(api) ~= "table" then
    return nil
  end
  return api
end

local function tmp_path()
  local sig = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or tostring(os.time())
  return string.format("/tmp/easymotion-%s-%s.json", sig, tostring(math.random(100000, 999999)))
end

local function shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function write_file(path, data)
  local f, err = io.open(path, "w")
  if not f then
    return nil, err
  end
  f:write(data)
  f:close()
  return true
end

local function build_payload(cfg, rendered_labels)
  return {
    action = cfg.action,
    labels = rendered_labels,
    style = {
      textsize = cfg.textsize,
      textcolor = cfg.textcolor,
      bgcolor = cfg.bgcolor,
      textfont = cfg.textfont,
      textpadding = cfg.textpadding,
      rounding = cfg.rounding,
      bordersize = cfg.bordersize,
      bordercolor = cfg.bordercolor,
    },
  }
end

-- Convert HL API window userdata to the table format labels.from_tables expects
local function window_to_client(w)
  return {
    address = w.address,
    mapped = w.mapped,
    hidden = w.hidden,
    fullscreen = w.fullscreen or 0,
    at = {
      w.at and w.at.x or 0,
      w.at and w.at.y or 0,
    },
    size = {
      w.size and w.size.x or 0,
      w.size and w.size.y or 0,
    },
    workspace = {
      id = w.workspace and w.workspace.id,
      name = w.workspace and w.workspace.name,
    },
  }
end

function M.activate(user_config)
  local cfg = config.merge(user_config or {})
  local hl_api = get_hl()
  if not hl_api then
    return nil, "Hyprland Lua API unavailable: expected global hl table"
  end
  if type(hl_api.get_windows) ~= "function" then
    return nil, "Hyprland Lua API unavailable: hl.get_windows() missing"
  end

  -- Use native Hyprland Lua API (no subprocess needed)
  local ok, raw_windows = pcall(hl_api.get_windows)
  if not ok then
    return nil, "hl.get_windows() failed: " .. tostring(raw_windows)
  end
  if type(raw_windows) ~= "table" then
    return nil, "hl.get_windows() returned unexpected value"
  end
  if #raw_windows == 0 then
    return nil, "no windows"
  end

  local clients = {}
  for _, w in ipairs(raw_windows) do
    clients[#clients + 1] = window_to_client(w)
  end

  local active = {}
  do
    if type(hl_api.get_active_workspace) == "function" then
      local ok2, raw_aw = pcall(hl_api.get_active_workspace)
      if ok2 and raw_aw then
        active = { id = raw_aw.id, name = raw_aw.name }
      end
    end
  end

  local rendered_labels, err = labels.from_tables(clients, active, cfg)
  if not rendered_labels then
    return nil, err
  end
  if #rendered_labels == 0 then
    return nil, "no eligible windows for easymotion"
  end

  local path = tmp_path()
  local ok3, write_err = write_file(path, json.encode(build_payload(cfg, rendered_labels)))
  if not ok3 then
    return nil, write_err
  end

  -- Use hl.exec_cmd for non-blocking spawn
  local quoted_path = shell_quote(path)
  local cmd = cfg.renderer .. " " .. quoted_path
  if type(cfg.exec) == "function" then
    if cfg.spawn_background then
      cmd = cmd .. " &"
    end
    cfg.exec(cmd)
  elseif type(hl_api.exec_cmd) == "function" then
    hl_api.exec_cmd(cmd)
  else
    if cfg.spawn_background then
      cmd = cmd .. " &"
    end
    os.execute(cmd)
  end

  return true
end

return M
