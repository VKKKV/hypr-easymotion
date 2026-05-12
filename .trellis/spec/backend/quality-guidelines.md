# Quality Guidelines

> Code quality standards for backend development.

---

## Overview

hypr-easymotion backend code is the Zig renderer plus low-level system integration around Wayland, Cairo/Pango, xkbcommon, and the Lua-generated JSON contract.

Backend changes must keep the Lua JSON producer and Zig JSON consumer in lockstep. Any change to fields, defaults, action semantics, or coordinate meaning must update README and the relevant spec in the same task.

---

## Forbidden Patterns

- Do not execute user-controlled JSON values through a shell without validation. Window addresses used in `{}` substitution must be restricted to safe characters before command execution.
- Do not leave generated build outputs unignored or committed unless they are intentional source artifacts. Zig build outputs belong in `.zig-cache/`, `zig-cache/`, or `zig-out/` and must be ignored.
- Do not silently diverge Lua defaults from Zig defaults. Defaults are part of the cross-layer contract and must match.
- Do not assume a single monitor-sized output when rendering window coordinates. Hyprland window coordinates are global compositor coordinates; renderer code must account for output offsets or document a deliberate limitation.
- Do not render a layer-shell overlay before Wayland output geometry/mode and layer-surface configure have produced real dimensions. A keyboard-grabbing overlay with a 1x1 or stale buffer appears as a frozen blank screen.

---

## Required Patterns

### Scenario: Lua JSON to Zig Renderer Contract

#### 1. Scope / Trigger

- Trigger: Any change to Lua label generation, renderer JSON parsing, action execution, style fields, or coordinate behavior.

#### 2. Signatures

- Lua entrypoint: `require("easymotion").activate(overrides?) -> true | nil, err`
- Renderer CLI: `easymotion-render <json-file>`
- Default action template: `hyprctl eval 'hl.dispatch(hl.dsp.focus({window = "address:{}"}))'`

#### 3. Contracts

- JSON root must be an object with `action`, `labels`, and `style`.
- `action` is a string command template. If it contains `{}`, the selected label address replaces that token.
- `labels` is an array of objects with `key`, `text`, `address`, `x`, `y`, `w`, and `h`.
- `key` is the keyboard input string matched by the renderer.
- `text` is the label text rendered by Pango/Cairo.
- `address` is the Hyprland window address used by action substitution.
- `x` and `y` are the Hyprland global top-left window coordinates.
- `w` and `h` are the window size in pixels; the renderer centers the label within this rectangle.
- `style.textsize`, `textpadding`, `rounding`, and `bordersize` are numeric values.
- `style.textcolor`, `bgcolor`, and `bordercolor` are RGBA arrays with four numeric values.
- `style.textfont` is the Pango font family string.

#### 4. Validation & Error Matrix

- Missing CLI argument -> print usage and exit non-zero.
- Missing or invalid JSON file -> print parse/read error and exit non-zero.
- Missing `labels` array -> renderer error.
- Malformed label entries -> skip invalid entries instead of crashing.
- Unsafe action replacement value -> reject action and exit non-zero.
- Action command returns non-zero -> renderer exits non-zero.
- Wayland connection/display failure -> renderer exits non-zero.

#### 5. Good/Base/Bad Cases

- Good: Lua emits multiple non-fullscreen windows with full style; Zig renders labels and action focuses the selected address.
- Base: Empty eligible window list emits an empty `labels` array; renderer should not crash.
- Bad: Address contains shell metacharacters; renderer must reject it before executing `system()`.

#### 6. Tests Required

- `zig build` must pass.
- `zig fmt --check build.zig src/main.zig src/Layer.zig src/Labels.zig` must pass for Zig source changes.
- Lua module load and JSON round-trip checks must pass for Lua contract changes.
- Label filtering tests must assert fullscreen windows are skipped and `only_special` filters correctly.
- Renderer failure-path checks must assert missing files and unavailable Wayland display exit non-zero.

#### 7. Wrong vs Correct

##### Wrong

```zig
const command = try std.mem.replaceOwned(u8, allocator, action_template, "{}", address);
_ = c.system(command.ptr);
```

##### Correct

```zig
if (std.mem.indexOf(u8, action_template, "{}") != null and !isSafeActionValue(address)) {
    return error.InvalidActionValue;
}
const command = try std.mem.replaceOwned(u8, allocator, action_template, "{}", address);
if (c.system(command_z.ptr) != 0) return error.ActionFailed;
```

---

## Testing Requirements

- Run `zig build` after any Zig, C shim, protocol, or build config change.
- Run `zig fmt --check` for changed Zig files.
- Run a Lua load/contract check after changing `easymotion/*.lua`.
- For Wayland behavior, at minimum verify failure paths non-interactively; live overlay testing should be done manually in Hyprland because exclusive keyboard can steal focus.

---

## Code Review Checklist

- Does the README JSON contract match Lua generation and Zig parsing?
- Are action replacement values validated before shell execution?
- Do action failures propagate to a non-zero renderer exit?
- Are generated artifacts ignored or intentionally committed?
- Do multi-monitor coordinates account for global positions and output offsets?
- Are fullscreen and `only_special` behaviors preserved across Lua filtering changes?

### Scenario: Wayland Layer-Shell Overlay Rendering

#### 1. Scope / Trigger

- Trigger: Changes to `src/Layer.zig`, Wayland output handling, layer-surface configure handling, or shared-memory buffer lifecycle.

#### 2. Signatures

- Renderer app entrypoint: `Layer.App.run() !void`
- Output render path: `tryRenderOutput(app, output) !void`
- Wayland callbacks: `outputGeometry`, `outputMode`, and `layerConfigure`

#### 3. Contracts

- The renderer must wait for registry globals and output events before treating output size and position as authoritative.
- Labels must render only after the output has real dimensions greater than the 1x1 initialization fallback.
- A layer-surface configure may provide zero width/height; zero means keep the known output dimensions, not render at zero size.
- Rendered label positions are Hyprland global coordinates offset by the target output's `x` and `y`.
- If output geometry or size changes after initial render, the renderer must re-render with fresh offsets and buffer dimensions.
- The renderer may grab keyboard input, but it must not leave a blank full-screen layer when labels exist and Wayland has supplied usable dimensions.

#### 4. Validation & Error Matrix

- Missing output globals -> `MissingOutput` -> non-zero renderer exit.
- Output dimensions still fallback-sized (`<= 1`) -> defer rendering, continue dispatching Wayland events.
- Shared-memory file, mmap, pool, or buffer creation failure -> render error -> non-zero renderer exit.
- Layer surface closed by compositor -> stop the event loop without running an action.

#### 5. Good/Base/Bad Cases

- Good: output geometry, mode, and layer configure arrive; renderer allocates a correctly sized buffer, draws labels with output offsets, and commits damage.
- Base: configure reports zero width/height; renderer uses the current output mode dimensions once available.
- Bad: renderer commits a buffer while output dimensions are still the 1x1 fallback, causing an invisible keyboard-grabbing overlay.

#### 6. Tests Required

- `zig build` must pass after any renderer lifecycle change.
- `zig fmt --check build.zig src/main.zig src/Layer.zig src/Labels.zig` must pass for Zig source changes.
- Non-interactive failure-path checks should cover missing Wayland display or invalid inputs where feasible.
- Live Hyprland overlay visibility still requires manual testing because the renderer intentionally grabs exclusive keyboard input.

#### 7. Wrong vs Correct

##### Wrong

```zig
fn layerConfigure(output: *Output) void {
    renderOutput(output); // may still use 1x1 fallback output dimensions
}
```

##### Correct

```zig
fn layerConfigure(output: *Output) void {
    if (output.width <= 1 or output.height <= 1) return;
    tryRenderOutput(output); // renders only after real output dimensions are known
}
```
