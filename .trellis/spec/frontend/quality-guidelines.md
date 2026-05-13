# Quality Guidelines

> Code quality standards for frontend development.

---

## Overview

hypr-easymotion frontend code is the Hyprland Lua module that discovers windows, builds label payloads, writes JSON handoff files, and launches the Zig renderer.

Lua changes must preserve the launcher-specific quoting rules and the JSON contract consumed by the renderer.

---

## Forbidden Patterns

- Do not quote arguments passed through `hl.exec_cmd`; it does not invoke a shell, so quote characters become literal path characters.
- Do not require renderer command names to exist as filesystem paths. Bare names such as `easymotion-render` must be left for PATH resolution by the launcher.

---

## Required Patterns

### Scenario: Renderer Launch Contract

#### 1. Scope / Trigger

- Trigger: Any change to `spawn_renderer`, renderer configuration, temp payload handoff, or launcher selection.

#### 2. Signatures

- Lua entrypoint: `require("easymotion").activate(overrides?) -> true | nil, err`
- Renderer config field: `renderer: string`
- Renderer invocation: `<renderer> <json-file>`

#### 3. Contracts

- A renderer value containing `/` is path-like and may be checked with `io.open` before launch.
- A path-like renderer that cannot be opened must remove the temp JSON file and return `nil, "renderer binary not found: <renderer>"`.
- The default renderer value is `easymotion-render`.
- A renderer value with no `/` is a command name. Do not preflight it with `io.open`; the selected launcher resolves it through PATH or reports the failure.
- `hl.exec_cmd` receives an unquoted `<renderer> <json-file>` string because it passes arguments directly.
- Shell-backed launchers (`os.execute` and user `cfg.exec`) require shell quoting for the JSON path.

#### 4. Validation & Error Matrix

- Path-like renderer missing -> remove temp payload, return renderer-binary error.
- Bare command renderer missing from PATH -> launcher failure, not Lua preflight failure.
- Temp payload write failure -> remove temp payload if created, return write error.
- Missing Hyprland Lua API -> return API availability error before writing a payload.

#### 5. Good/Base/Bad Cases

- Good: `renderer = "/usr/bin/easymotion-render"` exists; Lua writes payload and launches the absolute path.
- Base: `renderer = "easymotion-render"`; Lua skips filesystem preflight and lets PATH resolve the command.
- Bad: `renderer = "easymotion-render"` is rejected by `io.open` before the launcher can resolve PATH.
- Bad: default config points to a developer-local absolute path such as `/home/<user>/.local/bin/easymotion-render`.

#### 6. Tests Required

- `luac -p easymotion/init.lua easymotion/config.lua easymotion/json.lua easymotion/labels.lua` must pass after Lua changes.
- Launch-contract tests should cover bare command names and missing path-like renderer values when a Lua test harness is available.

#### 7. Wrong vs Correct

##### Wrong

```lua
local probe = io.open(cfg.renderer, "r")
if not probe then
  return nil, "renderer binary not found: " .. cfg.renderer
end
```

##### Correct

```lua
if cfg.renderer:find("/", 1, true) then
  local probe = io.open(cfg.renderer, "r")
  if not probe then
    os.remove(path)
    return nil, "renderer binary not found: " .. cfg.renderer
  end
  probe:close()
end
```

---

## Testing Requirements

- Run `luac -p` for changed Lua modules.
- Run `zig build` when Lua payload fields, defaults, or renderer invocation behavior may affect the Zig renderer.

---

## Code Review Checklist

- Does launch behavior preserve the difference between path-like renderer values and PATH-resolved command names?
- Are `hl.exec_cmd` arguments left unquoted while shell launchers quote payload paths?
- Does any Lua payload field/default change stay in lockstep with Zig parsing and README documentation?
