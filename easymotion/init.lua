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

-- Payload directory: the per-user runtime dir is private (0700); /tmp is the
-- fallback for systems that do not set XDG_RUNTIME_DIR.
local function payload_dir()
  local dir = os.getenv("XDG_RUNTIME_DIR")
  if dir and dir ~= "" then
    return dir
  end
  return "/tmp"
end

-- Generate a unique temp file path. Tries up to 10 random names.
-- The caller is responsible for eventual cleanup if the renderer fails to start.
local function tmpfile()
  local sig = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or tostring(os.time())
  local dir = payload_dir()
  for _ = 1, 10 do
    local name = string.format("%s/easymotion-%s-%08d.json", dir, sig, math.random(0, 99999999))
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
    assert(f:write(json.encode(build_payload(cfg, rendered_labels))))
  end)
  local closed = f:close()
  if not ok then
    os.remove(path)
    return nil, "failed to write temp file: " .. tostring(write_err)
  end
  if not closed then
    os.remove(path)
    return nil, "failed to close temp file"
  end
  return true
end

-- Spawn the renderer process. Path handling is backend-specific:
-- hl.exec_cmd: NO quoting (passes args directly, no shell). Fast but uses
--   the compositor's minimal PATH — absolute path required.
-- os.execute: goes through /bin/sh — quoting required. Always backgrounded.
-- cfg.exec: user-provided function, quoting + background as before.
local function spawn_renderer(cfg, hl_api, path)
  -- Preflight: verify path-like renderer exists. Bare names skip this check
  -- since they rely on PATH resolution by the launcher.
  local probe
  if cfg.renderer:find("/", 1, true) then
    probe = io.open(cfg.renderer, "r")
    if not probe then
      os.remove(path)
      return nil, "renderer binary not found: " .. cfg.renderer
    end
    probe:close()
  end

  if type(cfg.exec) == "function" then
    local cmd = shell_quote(cfg.renderer) .. " " .. shell_quote(path)
    if cfg.spawn_background then
      cmd = cmd .. " &"
    end
    local ok, exec_err = pcall(cfg.exec, cmd)
    if not ok then
      os.remove(path)
      return nil, "custom exec failed: " .. tostring(exec_err)
    end
  elseif type(hl_api.exec_cmd) == "function" then
    hl_api.exec_cmd(cfg.renderer .. " " .. path)
  else
    local suffix = cfg.spawn_background and " &" or ""
    os.execute(shell_quote(cfg.renderer) .. " " .. shell_quote(path) .. suffix)
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

-- Hyprland reports geometry either as numbers or as vectors; accept both.
local function coord(value, axis, default)
  if type(value) == "number" then return value end
  if type(value) == "table" then
    local v = value[axis]
    if v == nil then v = value[axis == "x" and 1 or 2] end
    if type(v) == "number" then return v end
  end
  return default
end

-- Convert HL API window userdata to the table format labels.from_tables expects
local function window_to_client(w)
  return {
    address = w.address,
    mapped = w.mapped,
    hidden = w.hidden,
    fullscreen = w.fullscreen or 0,
    at = { coord(w.at, "x", 0), coord(w.at, "y", 0) },
    size = { coord(w.size, "x", 0), coord(w.size, "y", 0) },
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
