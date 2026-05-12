# Research: reference-comparison

- **Query**: Why the local Lua → temp JSON → renderer flow can still fail after the overlay rendering fix, compared with `/home/kita/code/hyprland-easymotion/`.
- **Scope**: mixed
- **Date**: 2026-05-12

## Findings

### Files Found

| File Path | Description |
|---|---|
| `easymotion/init.lua` | Local activation path that builds a temp JSON file and launches the renderer. |
| `easymotion/config.lua` | Local defaults for renderer command and background launch behavior. |
| `README.md` | Local runtime notes that mention stale-path failure modes. |
| `src/main.zig` | Local renderer CLI: reads and deletes the JSON file immediately, then starts Wayland UI. |
| `src/Layer.zig` | Local overlay lifecycle and action execution after config load. |
| `hyprland-easymotion/main.cpp` | Reference plugin’s in-process dispatch and label lifecycle. |
| `hyprland-easymotion/README.md` | Reference config/bind examples and default behavior. |

### Code Patterns

- Local activation creates a temp JSON path from `HYPRLAND_INSTANCE_SIGNATURE` or `os.time()` plus `math.random()`, writes the payload, then launches the renderer with that path (`easymotion/init.lua:20-23`, `76-100`).
- The launch path varies by hook: `cfg.exec(cmd)`, `_G.hl.exec_cmd(cmd)`, or `os.execute(cmd)`, and only the non-`hl.exec_cmd` branches append `&` (`easymotion/init.lua:82-100`).
- Local defaults keep `renderer = "easymotion-render"` and `spawn_background = true` (`easymotion/config.lua:3-18`). The README also warns that a hand-written binding like `easymotion-render /tmp/does-not-exist` will fail before any overlay appears (`README.md:71-78`).
- The renderer consumes a file path CLI argument, reads it, then deletes the same file immediately (`src/main.zig:14-30`). That means any stale path or premature file reuse becomes a hard startup failure rather than a recoverable overlay issue.
- The overlay code itself only runs after config parsing and Wayland setup succeed; it is not the place where a stale-path bug would originate (`src/Layer.zig:56-82`, `236-245`).
- The reference repo does not spawn a separate renderer or pass a temp JSON path at all. It handles easymotion entirely inside the Hyprland plugin process: `easymotionDispatch()` populates labels, then enters the submap (`hyprland-easymotion/main.cpp:127-249`). The selected action is executed in-process via `g_pKeybindManager->m_dispatchers["exec"](...)` (`main.cpp:42-54`).
- Reference defaults/binds are static Hyprland config values, not temp-file-driven CLI state. The README examples bind directly to the dispatcher with inline `action:` overrides (`hyprland-easymotion/README.md:7-12`, `73-75`), and plugin defaults are registered in `PLUGIN_INIT` (`main.cpp:277-295`).

### External References

- None.

### Related Specs

- `.trellis/spec/backend/quality-guidelines.md` — Lua/renderer contract, CLI expectations, and overlay lifecycle constraints.
- `.trellis/spec/backend/error-handling.md` — renderer failure semantics for missing JSON files and action execution.

## Caveats / Not Found

- No equivalent temp-file or external renderer lifecycle exists in the reference repository, so the comparison is structural rather than line-for-line.
- I did not find any reference-side equivalent of `tmp_path()` / temp JSON cleanup; that whole failure class is local to the Lua+Zig split.

## Short recommended fix

- Ensure the activation path is the only entrypoint to `easymotion-render`: write the JSON first, pass that exact path through the chosen launcher, and avoid any stale hard-coded `/tmp/...` renderer binds or bypasses of `activate()`.
