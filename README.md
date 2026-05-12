# hypr-easymotion

Hyprland window easymotion implemented with Lua config modules plus a standalone Zig Wayland layer-shell renderer.

## Dependencies

Arch Linux packages:

```sh
sudo pacman -S zig wayland wayland-protocols cairo pango libxkbcommon
```

`wayland-scanner` is used during `zig build` to generate the bundled wlr layer-shell client protocol glue.

## Build

```sh
zig build
```

The renderer binary is produced at `zig-out/bin/easymotion-render`.

Install it somewhere in `PATH`, for example:

```sh
install -Dm755 zig-out/bin/easymotion-render ~/.local/bin/easymotion-render
```

## Lua installation

Copy the `easymotion/` directory into a Lua package path visible to Hyprland's Lua config, for example:

```sh
cp -r easymotion ~/.config/hypr/easymotion
```

Then load it from Hyprland Lua config:

```lua
local easymotion = require("easymotion")

-- Example binding shape; adapt to your Hyprland Lua config helpers.
hl.bind("SUPER + R", function()
  local ok, err = easymotion.activate()
  if not ok then
    print("easymotion: " .. tostring(err))
  end
end)
```

Configuration can be overridden per call:

```lua
easymotion.activate({
  motionkeys = "arstneio",
  only_special = true,
  action = "hyprctl dispatch focuswindow address:{}",
  textsize = 128,
  textcolor = {0.98, 0.85, 0.18, 1.0},
  bgcolor = {0.23, 0.22, 0.20, 0.80},
  textfont = "JetBrains Mono",
  textpadding = 8,
  rounding = 6,
  bordersize = 2,
  bordercolor = {0.40, 0.36, 0.33, 1.0},
})
```

## Runtime behavior

- Lua calls `hyprctl clients -j`, filters eligible windows, truncates to `motionkeys`, writes `/tmp/easymotion-*.json`, then starts `easymotion-render`.
- Fullscreen windows are skipped for the MVP.
- When `only_special = true` and the active workspace is special, only special-workspace windows receive labels.
- Label coordinates use Hyprland global window coordinates from `hyprctl`, rendered on one full-screen layer-shell overlay surface with namespace `easymotion`.
- The renderer requests exclusive keyboard interactivity. `Escape` exits. Pressing a matching motion key runs the configured action after replacing `{}` with the window address.

## JSON contract

The Lua side writes:

```json
{
  "action": "hyprctl dispatch focuswindow address:{}",
  "labels": [
    { "key": "a", "text": "A", "address": "0x...", "x": 640, "y": 360, "w": 1280, "h": 720 }
  ],
  "style": {
    "textsize": 128,
    "textcolor": [0.98, 0.85, 0.18, 1.0],
    "bgcolor": [0.23, 0.22, 0.20, 0.80],
    "textfont": "JetBrains Mono",
    "textpadding": 8,
    "rounding": 6,
    "bordersize": 2,
    "bordercolor": [0.40, 0.36, 0.33, 1.0]
  }
}
```
