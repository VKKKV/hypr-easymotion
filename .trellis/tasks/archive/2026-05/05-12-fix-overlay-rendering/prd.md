# fix easymotion overlay rendering

## Goal

Fix the Hyprland easymotion overlay so `SUPER + R` reliably shows selectable letter labels instead of leaving the screen blocked by an invisible full-screen layer.

## What I already know

* The README says `SUPER + R` should call `easymotion.activate()` and launch `easymotion-render`.
* Pressing `SUPER + R` currently freezes interaction until `Esc`, which means the renderer starts and grabs keyboard input.
* No label letters are visible, so the failure is likely in render timing, surface sizing, or drawing visibility rather than in the Lua binding.
* The renderer uses a Wayland layer-shell overlay and only draws after `configure` arrives.
* Existing filtering can also produce an empty label list when all windows are excluded.

## Requirements

* The overlay must visibly render label text and remain interactive until a selection or `Esc`.
* The renderer must not leave the user with a blank full-screen block when labels exist.
* The current activation flow and key handling should remain intact.
* Existing filtering behavior may stay as-is unless it directly prevents valid labels from appearing.

## Acceptance Criteria

* [ ] Activating with eligible windows displays visible selectable letters on the overlay.
* [ ] `Esc` still closes the overlay without running an action.
* [ ] If no eligible windows exist, the activation path returns a clear error instead of silently showing a blank overlay.
* [ ] `zig build` and `zig fmt --check` pass after the fix.

## Definition of Done

* Renderer behavior is fixed and verified in code.
* Relevant backend specs stay aligned with the implementation.
* Build and formatting checks pass.

## Technical Approach

Focus on the renderer lifecycle in `src/Layer.zig`: ensure label rendering happens when the surface size is known and the output is ready, and make the visible overlay state explicit if the current configure path is too early or too small. Preserve the existing Lua contract unless a bug in the contract is proven.

## Decision (ADR-lite)

**Context**: The overlay appears to consume keyboard input before its labels are visible.

**Decision**: Treat this as a renderer visibility/lifecycle bug and fix the Wayland render path rather than changing the Lua activation entrypoint.

**Consequences**: Keeps the user-facing API stable, but requires careful handling of Wayland configure/output readiness.

## Out of Scope

* Reworking the label-matching UX.
* Changing the default key bindings or motion key set.
* Redesigning the special-workspace filtering rules unless they are proven to be the direct cause.

## Technical Notes

* Files inspected: `README.md`, `easymotion/init.lua`, `easymotion/labels.lua`, `easymotion/config.lua`, `src/main.zig`, `src/Layer.zig`, `src/Labels.zig`.
* Relevant specs: `.trellis/spec/backend/error-handling.md`, `.trellis/spec/backend/quality-guidelines.md`.
* Likely failure mode: renderer enters dispatch loop and grabs keyboard before labels are visibly painted, or paints into an effectively 1x1/incorrectly configured surface.
