# Error Handling

> How errors are handled in this project.

---

## Overview

hypr-easymotion errors are reported at two boundaries: Lua activation errors returned to Hyprland config code, and renderer process failures printed to stderr with non-zero exits.

The renderer must fail closed for input, Wayland, and action execution errors. It should not report success after failing to focus a selected window.

---

## Error Types

- Lua activation errors return `nil, err` from `activate()` so Hyprland config can log the failure.
- Zig renderer errors use Zig error unions and propagate to `main`, which prints a clear failure reason and exits non-zero.
- Action execution errors include invalid replacement values and non-zero shell command status.

---

## Error Handling Patterns

### Scenario: Renderer CLI and Action Failure Behavior

#### 1. Scope / Trigger

- Trigger: Changes to `easymotion-render`, JSON parsing, Wayland setup, keyboard handling, or action execution.

#### 2. Signatures

- CLI: `easymotion-render <json-file>`
- Action runner: `runAction(allocator, action_template, address) !void`

#### 3. Contracts

- No JSON file argument is a usage error.
- JSON read/parse failures are fatal.
- Wayland connection, registry, layer-shell, shm, or keyboard setup failures are fatal.
- Escape exits without running an action.
- Matching a label key must run the configured action; if the action fails, the process must exit non-zero.
- If action template replacement is used, the replacement value must be validated before shell execution.

#### 4. Validation & Error Matrix

- `argc < 2` -> print `usage: easymotion-render <json-file>` -> exit non-zero.
- unreadable JSON path -> print read error -> exit non-zero.
- invalid JSON root or missing `labels` -> print parse error -> exit non-zero.
- Wayland display unavailable -> print connection/setup error -> exit non-zero.
- unsafe action replacement value -> return `InvalidActionValue` -> exit non-zero.
- shell command returns non-zero -> return `ActionFailed` -> exit non-zero.

#### 5. Good/Base/Bad Cases

- Good: valid JSON, Wayland available, selected key action returns `0` -> renderer exits successfully.
- Base: user presses Escape -> renderer exits without action and without treating cancellation as action failure.
- Bad: action command returns non-zero -> renderer must not exit as success.

#### 6. Tests Required

- Missing JSON file path test asserts non-zero exit.
- Invalid or absent Wayland display test asserts non-zero exit.
- Unit-level or scripted action failure test asserts `ActionFailed` propagates.
- Unsafe address test asserts action is rejected before shell execution.

#### 7. Wrong vs Correct

##### Wrong

```zig
Labels.runAction(allocator, action, address) catch |err| {
    std.log.err("action failed: {}", .{err});
};
return;
```

##### Correct

```zig
Labels.runAction(allocator, action, address) catch |err| {
    std.log.err("action failed: {}", .{err});
    self.action_failed = true;
};
return;
```

---

## API Error Responses

Not applicable: this project has no HTTP API. CLI stderr and Lua `nil, err` returns are the public error surfaces.

---

## Common Mistakes

- Logging an action failure but allowing the renderer to exit successfully hides broken focus commands from callers.
- Treating shell command templates as trusted input can make JSON payloads unsafe. Validate replacement values before invoking `system()`.
- Interactive Wayland overlay tests can steal keyboard focus; prefer non-interactive failure-path tests during automated checks and reserve full overlay validation for manual Hyprland testing.
