# hypr-easymotion

Hyprland window easymotion implemented with Lua config modules plus a standalone Zig Wayland layer-shell renderer.

This project is inspired by and references [`zakk4223/hyprland-easymotion`](https://github.com/zakk4223/hyprland-easymotion), but reimplements the flow around Hyprland Lua config plus an external Zig renderer instead of a C++ Hyprland plugin.

## What it does

- gathers candidate windows from the Hyprland Lua API
- filters them to the current workspace and optional special-workspace scope
- writes a temporary JSON payload to `/tmp`
- launches a full-screen Wayland layer-shell overlay renderer
- grabs keyboard input exclusively until you press a motion key or `Escape`

## Demo

https://github.com/user-attachments/assets/5558df25-0f7e-4cd3-9393-b550afc97801

Use it to quickly verify the intended interaction model before installing: trigger easymotion, see labels appear over eligible windows, then press the matching key to focus the target window.

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

-- Call activate() from the binding. Do not bind SUPER+R directly to
-- `easymotion-render /tmp/...`: activate() writes the fresh JSON config first.
hl.bind("SUPER + R", function()
  local ok, err = easymotion.activate()
  if not ok then
    print("easymotion: " .. tostring(err))
  end
end)
```

This module expects Hyprland's Lua API globals (for example `hl.get_windows()`, `hl.get_active_workspace()`, and `hl.exec_cmd()`) to be available in that config environment.

## Configuration

Configuration can be overridden per call:

```lua
easymotion.activate({
  motionkeys = "arstneio",
  only_special = true,
  renderer = "/home/kita/.local/bin/easymotion-render",
  action = "hyprctl eval 'hl.dispatch(hl.dsp.focus({window = \"address:{}\"}))'",
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

Current defaults live in `easymotion/config.lua`.

`spawn_background` remains available for shell-based fallback launchers (`cfg.exec` / `os.execute`). It is intentionally ignored when the native Hyprland helper `hl.exec_cmd()` is used, because that path is already fire-and-forget.

## Runtime behavior

- Lua calls `hl.get_windows()` from the Hyprland Lua API, converts window userdata into plain Lua tables, filters eligible windows, assigns motion keys in a deterministic order (workspace → y → x → address), writes a high-entropy `/tmp/easymotion-<sig>-<random>.json` temp file, then spawns `easymotion-render`.
- `activate()` returns `true` on success, or `nil, reason` on any failure (no HL API, no windows, renderer binary missing, temp file write error). This makes it easy to log errors from the keybind.
- The spawn path auto-selects backend: `hl.exec_cmd()` (native, unquoted path), `os.execute` (shell, quoted path + background), or a custom `cfg.exec` function. The renderer binary is checked for existence before spawning; if missing, the temp file is cleaned up and an error returned.
- `easymotion-render` expects the JSON path created by `activate()`. It deletes the file after reading. If the renderer never starts, the temp file remains in `/tmp` (cleared on reboot).
- Fullscreen windows are skipped.
- When `only_special = true` and the active workspace is special, only special-workspace windows receive labels.
- Label coordinates use Hyprland global window coordinates and sizes, rendered on a full-screen layer-shell overlay surface with namespace `easymotion`.
- The renderer requests exclusive keyboard interactivity. `Escape` exits. Pressing a matching motion key tears down the overlay, then runs the configured action after replacing `{}` with the selected window address.
- The renderer warns on stderr when MAX_OUTPUTS (16) is exceeded, when labels have missing required fields, or when rendering fails.

## JSON contract

The Lua side writes:

```json
{
  "action": "hyprctl eval 'hl.dispatch(hl.dsp.focus({window = \"address:{}\"}))'",
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

## Notes and limitations

- This repository intentionally keeps its `.trellis/` workflow and task/spec history in-tree.
- **Renderer path must be absolute.** `hl.exec_cmd()` runs in the compositor's environment which has a minimal `PATH` (typically `/usr/local/bin:/usr/bin`). `~/.local/bin` is not on it, and `~/` tilde expansion does not happen (no shell). Bare command names and `~/` paths will fail silently — the only sign is that labels never appear. Always use the full path: `/home/you/.local/bin/easymotion-render`. Override `renderer` in your config if your install path differs.
- The Lua entrypoint requires the Hyprland Lua config runtime; calling `require("easymotion").activate()` in a plain standalone Lua interpreter will fail because the global `hl` API is not present there.
- Because the renderer grabs keyboard input exclusively, live validation is best done manually inside a real Hyprland session.

## License

This repository is licensed under the GNU General Public License v3.0 or later. See [`LICENSE`](./LICENSE).
