local json = require("easymotion.json")

local M = {}

local function starts_with(s, prefix)
  return type(s) == "string" and s:sub(1, #prefix) == prefix
end

local function is_special_workspace(workspace)
  if type(workspace) ~= "table" then return false end
  return starts_with(workspace.name or "", "special") or (tonumber(workspace.id) or 0) < 0
end

local function active_special(active)
  return type(active) == "table" and is_special_workspace(active)
end

local function eligible(client, want_special, active_workspace)
  if type(client) ~= "table" then return false end
  if client.mapped == false or client.hidden == true then return false end
  if tonumber(client.fullscreen or 0) ~= 0 then return false end
  -- Only show windows on the active workspace
  local active_workspace_id = active_workspace and tonumber(active_workspace.id)
  if active_workspace_id then
    local client_ws_id = client.workspace and tonumber(client.workspace.id)
    if client_ws_id and client_ws_id ~= active_workspace_id then
      return false
    end
  end
  if want_special and not is_special_workspace(client.workspace) then return false end
  if not client.address or type(client.at) ~= "table" or type(client.size) ~= "table" then return false end
  return true
end

local function client_sort_key(client)
  local ws_id = 0
  if client.workspace and client.workspace.id then
    ws_id = tonumber(client.workspace.id) or 0
  end
  local at_y = tonumber((client.at or {})[2]) or 0
  local at_x = tonumber((client.at or {})[1]) or 0
  local addr = client.address or ""
  return ws_id, at_y, at_x, addr
end

function M.from_tables(clients, active_workspace, cfg)
  -- Sort clients deterministically so label keys are stable between
  -- invocations. Order: workspace id, y position, x position, address.
  -- Without this, muscle memory breaks when Hyprland returns windows in a
  -- different order (e.g. after a compositor restart).
  local sorted = {}
  for _, c in ipairs(clients or {}) do
    sorted[#sorted + 1] = c
  end
  table.sort(sorted, function(a, b)
    local a_ws, a_y, a_x, a_addr = client_sort_key(a)
    local b_ws, b_y, b_x, b_addr = client_sort_key(b)
    if a_ws ~= b_ws then return a_ws < b_ws end
    if a_y ~= b_y then return a_y < b_y end
    if a_x ~= b_x then return a_x < b_x end
    return a_addr < b_addr
  end)

  local out = {}
  local keys = cfg.motionkeys or "arstneio"
  local want_special = cfg.only_special and active_special(active_workspace)
  local key_index = 1
  for _, client in ipairs(sorted) do
    if eligible(client, want_special, active_workspace) then
      local key = keys:sub(key_index, key_index)
      if key == "" then break end
      local x = tonumber(client.at[1]) or 0
      local y = tonumber(client.at[2]) or 0
      local w = tonumber(client.size[1]) or 1
      local h = tonumber(client.size[2]) or 1
      out[#out + 1] = {
        key = key,
        text = key:upper(),
        address = client.address,
        x = x,
        y = y,
        w = w,
        h = h,
      }
      key_index = key_index + 1
    end
  end
  return out
end

function M.from_hyprctl(clients_json, active_workspace_json, cfg)
  local clients, err = json.decode(clients_json or "[]")
  if not clients then return nil, err end
  local active = {}
  if active_workspace_json and active_workspace_json ~= "" then
    active = json.decode(active_workspace_json) or {}
  end
  return M.from_tables(clients, active, cfg)
end

return M
