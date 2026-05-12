local config = require("easymotion.config")
local labels = require("easymotion.labels")
local json = require("easymotion.json")

local M = {}

local function read_all(cmd)
  local f, err = io.popen(cmd, "r")
  if not f then
    return nil, err or ("failed to run: " .. cmd)
  end
  local data = f:read("*a")
  local ok, reason, code = f:close()
  if ok == nil then
    return nil, string.format("command failed: %s (%s %s)", cmd, tostring(reason), tostring(code))
  end
  return data
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

function M.activate(user_config)
  local cfg = config.merge(user_config or {})
  local clients_text, clients_err = read_all("hyprctl clients -j")
  if not clients_text then
    return nil, clients_err
  end

  local active_text = "{}"
  if cfg.only_special then
    active_text = read_all("hyprctl activeworkspace -j") or "{}"
  end

  local rendered_labels, err = labels.from_hyprctl(clients_text, active_text, cfg)
  if not rendered_labels then
    return nil, err
  end
  if #rendered_labels == 0 then
    return nil, "no eligible windows for easymotion"
  end

  local path = tmp_path()
  local ok, write_err = write_file(path, json.encode(build_payload(cfg, rendered_labels)))
  if not ok then
    return nil, write_err
  end

  if type(cfg.exec) == "function" then
    local cmd = cfg.renderer .. " " .. shell_quote(path)
    if cfg.spawn_background then
      cmd = cmd .. " &"
    end
    cfg.exec(cmd)
  elseif _G.hl and type(_G.hl.exec_cmd) == "function" then
    -- Hyprland's Lua exec helper is already fire-and-forget.  Do not append a
    -- shell background marker here; some wrappers do not evaluate a shell and
    -- would pass the extra token through to the renderer instead.
    local cmd = cfg.renderer .. " " .. shell_quote(path)
    _G.hl.exec_cmd(cmd)
  else
    local cmd = cfg.renderer .. " " .. shell_quote(path)
    if cfg.spawn_background then
      cmd = cmd .. " &"
    end
    os.execute(cmd)
  end

  return true
end

return M
