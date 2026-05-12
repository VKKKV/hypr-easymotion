local M = {}

M.defaults = {
  motionkeys = "arstneio",
  action = "hyprctl dispatch focuswindow address:{}",
  only_special = true,
  renderer = "easymotion-render",
  spawn_background = true,

  textsize = 128,
  textcolor = { 0.98, 0.85, 0.18, 1.0 },
  bgcolor = { 0.23, 0.22, 0.20, 0.80 },
  textfont = "JetBrains Mono",
  textpadding = 8,
  rounding = 6,
  bordersize = 2,
  bordercolor = { 0.40, 0.36, 0.33, 1.0 },
}

function M.merge(user)
  local out = {}
  for k, v in pairs(M.defaults) do
    out[k] = v
  end
  for k, v in pairs(user or {}) do
    out[k] = v
  end
  return out
end

return M
