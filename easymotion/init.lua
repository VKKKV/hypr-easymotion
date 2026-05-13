local config = require("easymotion.config")
local labels = require("easymotion.labels")
local json = require("easymotion.json")

local M = {}

-- Forward declarations: these helpers are defined below but referenced
-- earlier in the file. Lua local function scope begins at the declaration
-- point, not the block top, so explicit forward stubs are required.
local build_payload

local function get_hl()
  local api = rawget(_G, "hl")
  if type(api) ~= "table" then
    return nil
  end
  return api
end

local function shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Generate a unique temp file path in /tmp. Tries up to 10 random names.
-- The caller is responsible for eventual cleanup if the renderer fails to start.
local function tmpfile()
  local sig = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or tostring(os.time())
  for _ = 1, 10 do
    local name = string.format("/tmp/easymotion-%s-%08d.json", sig, math.random(0, 99999999))
    local probe = io.open(name, "r")
    if not probe then
      return name
    end
    probe:close()
  end
  return nil, "failed to generate unique temp filename after 10 attempts"
end

-- Atomic write of JSON payload to path. Returns true on success, nil+error on failure.
local function write_payload(path, cfg, rendered_labels)
  local f, err = io.open(path, "w")
  if not f then
    return nil, "failed to open temp file: " .. err
  end
  local ok, write_err = pcall(function()
    f:write(json.encode(build_payload(cfg, rendered_labels)))
  end)
  f:close()
  if not ok then
    os.remove(path)
    return nil, "failed to write temp file: " .. tostring(write_err)
  end
  return true
end

-- Spawn the renderer process, handling backend-specific path quoting.
-- hl.exec_cmd: NO quoting (it passes args directly, not through a shell).
-- os.execute: quoting required (goes through /bin/sh), always backgrounded.
-- cfg.exec: quoting + background handled by cfg.spawn_background as before.
local function spawn_renderer(cfg, hl_api, path)
  -- Verify renderer binary exists (catches the most common silent-failure case)
  local probe = io.open(cfg.renderer, "r")
  if not probe then
    os.remove(path)
    return nil, "renderer binary not found: " .. cfg.renderer
  end
  probe:close()

  if type(cfg.exec) == "function" then
    local cmd = cfg.renderer .. " " .. shell_quote(path)
    if cfg.spawn_background then
      cmd = cmd .. " &"
    end
    cfg.exec(cmd)
  elseif type(hl_api.exec_cmd) == "function" then
    -- hl.exec_cmd does NOT use a shell — quoting would embed literal
    -- quotes in the path and cause FileNotFound. See the known pitfall
    -- in the hyprland-development skill.
    hl_api.exec_cmd(cfg.renderer .. " " .. path)
  else
    -- os.execute uses shell; quote path. Always background to avoid
    -- freezing the compositor thread (os.execute blocks until child exits).
    os.execute(cfg.renderer .. " " .. shell_quote(path) .. " &")
  end
  return true
end

build_payload = function(cfg, rendered_labels)
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

  local path, tmp_err = tmpfile()
  if not path then
    return nil, tmp_err
  end

  local ok3, write_err = write_payload(path, cfg, rendered_labels)
  if not ok3 then
    return nil, write_err
  end

  local ok4, spawn_err = spawn_renderer(cfg, hl_api, path)
  if not ok4 then
    return nil, spawn_err
  end

  return true
end

return M
