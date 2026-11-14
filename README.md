hypr-easymotion
================

hypr-easymotion is a window easymotion for Hyprland. A Lua module collects
the candidate windows of the active workspace and writes them to a JSON
file; a small Wayland client draws one label per window on a full screen
layer shell overlay, grabs the keyboard exclusively, and focuses the
window whose label was typed. It needs no Hyprland plugin.

Requirements
------------

    zig 0.17
    wayland
    cairo
    pango
    libxkbcommon
    pkgconf

The Lua module needs a Hyprland build with Lua configuration support.

Build
-----

    zig build -Doptimize=ReleaseSafe --prefix /usr/local

Install
-------

Copy the Lua module into a directory on the Hyprland Lua package path:

    cp -r easymotion ~/.config/hypr/easymotion

and bind activate() from the Hyprland configuration:

    local easymotion = require("easymotion")
    hl.bind("SUPER + R", function()
      local ok, err = easymotion.activate()
      if not ok then print("easymotion: " .. tostring(err)) end
    end)

Configuration
-------------

activate() takes an optional table that overrides easymotion/config.lua.
The keys worth setting:

    motionkeys   keys assigned to windows, one per window
    only_special restrict labels to the special workspace while focused
    renderer     absolute path to easymotion-render
    action       shell command run for the selected window, {} is the address

Windows are ordered by workspace, then y, then x, so labels stay stable
between invocations.

Notes
-----

- renderer must be an absolute path: hl.exec_cmd() runs in the compositor
  environment, where ~/.local/bin is not on PATH and ~ is not expanded.
- The payload file is written to $XDG_RUNTIME_DIR, or /tmp when that is
  unset, and is unlinked after it has been read.

License
-------

GNU General Public License v3.0 or later. See LICENSE.
