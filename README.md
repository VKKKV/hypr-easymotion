hypr-easymotion
================

hypr-easymotion is a window easymotion for Hyprland. A Lua module collects
the candidate windows of the active workspace and writes them to a JSON
file; a small Wayland client draws one label per window on a full screen
layer shell overlay, grabs the keyboard exclusively, and focuses the
window whose label was typed.

The Lua module runs inside the Hyprland Lua configuration runtime and
needs no process of its own. The renderer is a standalone binary and
needs no Hyprland plugin API.

Requirements
------------

    zig 0.17
    wayland
    wayland-protocols
    cairo
    pango
    libxkbcommon
    pkgconf

wayland-scanner (from the wayland package) generates the bundled
wlr-layer-shell glue during the build. The Lua module needs a Hyprland
build with Lua configuration support.

Build
-----

    zig build -Doptimize=ReleaseSafe

The binary is written to zig-out/bin/easymotion-render. To install it
into a prefix:

    zig build -Doptimize=ReleaseSafe --prefix /usr/local

AUR packaging files live in packaging/aur.

Install
-------

Copy the Lua module into a directory that is on the Hyprland Lua package
path, for example:

    cp -r easymotion ~/.config/hypr/easymotion

and require it from the Hyprland configuration:

    local easymotion = require("easymotion")
    hl.bind("SUPER + R", function()
      local ok, err = easymotion.activate()
      if not ok then print("easymotion: " .. tostring(err)) end
    end)

Call activate() from the binding. The binding must not point at
easymotion-render directly, because activate() writes the payload file
first.

Configuration
-------------

activate() takes an optional table that overrides the defaults from
easymotion/config.lua:

    easymotion.activate({
      motionkeys = "arstneio",
      only_special = false,
      renderer = "/usr/bin/easymotion-render",
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

motionkeys assigns one key per window; windows are ordered by workspace,
then y, then x, so labels stay stable between invocations. The action
string is run through the shell after {} is replaced with the address of
the selected window. only_special restricts labels to the special
workspace while one is focused.

Notes
-----

- renderer must be an absolute path. hl.exec_cmd() runs with the
  compositor environment, where ~/.local/bin is not on PATH and ~ is not
  expanded.
- The payload file is written to $XDG_RUNTIME_DIR when it is set, and to
  /tmp otherwise. The renderer deletes it before rendering.
- Window positions are used in logical pixels; outputs with a scale other
  than 1 place labels at compositor coordinates, which may differ from
  what the label assumes.
- Because the renderer takes exclusive keyboard focus, verify changes
  inside a live Hyprland session.

License
-------

GNU General Public License v3.0 or later. See LICENSE.
