# Fix Shim Fallback and Default Renderer

## Goal

Address the new code review findings in the C shim and Lua default config: make shared-memory fallback names safe for concurrent renderer starts, complete render error cleanup, and use the PATH-resolved renderer command as the default.

## Requirements

* In `src/c/shim.c`, fix the `shm_open` fallback so concurrent renderer instances do not all use the literal `/hypr-easymotion-XXXXXX` name.
* Prefer a minimal correct fallback implementation over removing the fallback entirely.
* Preserve the `memfd_create` fast path and existing `ftruncate` failure cleanup.
* In `src/c/shim.c`, ensure the `em_render_labels` error path for `PangoLayout` or `PangoFontDescription` allocation failure releases any resources already acquired for the loop iteration and the outer Cairo surface/context.
* In `easymotion/config.lua`, change the default renderer from the developer-local absolute path to the bare command name `easymotion-render`.
* Leave the reviewed low-impact findings out of scope: JSON `.5` number parsing, ASCII-only `key:upper()`, and `init.lua` `probe` scope style.

## Acceptance Criteria

* [ ] `em_create_shm_file` fallback does not deterministically collide across concurrent renderer starts.
* [ ] The `memfd_create` path remains unchanged for normal Linux systems.
* [ ] `em_render_labels` does not leak `surface`, `cr`, `layout`, or `font` on layout/font allocation failure.
* [ ] Default Lua config uses `renderer = "easymotion-render"`.
* [ ] Build and syntax checks pass.

## Definition of Done

* Implementation remains localized to `src/c/shim.c` and `easymotion/config.lua` unless checks reveal a necessary adjacent change.
* `zig build` passes.
* C/Lua formatting or syntax checks are run where available.
* Spec updates are considered before commit.

## Technical Approach

Use a small retry loop around `shm_open` with a generated name that includes process identity and a counter/random component, unlinking immediately after successful open. For the render allocation failure, replace the early return with cleanup of per-label resources plus the outer Cairo context/surface. Change the Lua default renderer to the bare command name now that launch preflight supports PATH-resolved commands.

## Decision (ADR-lite)

**Context**: `memfd_create` usually avoids the fallback, but the fallback should still be correct. The renderer config default should not reference a developer-specific home directory.

**Decision**: Keep the `shm_open` fallback but make names unique enough for concurrent starts, clean all acquired render resources on allocation failure, and default the renderer to `easymotion-render`.

**Consequences**: Older systems without `memfd_create` remain supported without deterministic name collisions. New installs work when the renderer is installed on PATH and still allow users to override absolute paths.

## Out of Scope

* Removing the `shm_open` fallback entirely.
* Changing JSON number parsing behavior.
* Changing label key casing behavior.
* Style-only cleanup in `easymotion/init.lua`.

## Technical Notes

* `src/c/shim.c` is included by `build.zig` as `src/c/shim.c`.
* `em_create_shm_file` currently uses the literal fallback name `/hypr-easymotion-XXXXXX`.
* `em_render_labels` currently returns directly when `layout` or `font` allocation fails inside the loop.
* `easymotion/config.lua` currently defaults to `/home/kita/.local/bin/easymotion-render`.
