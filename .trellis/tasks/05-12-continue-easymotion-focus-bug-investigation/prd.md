# Continue Easymotion Focus Bug Investigation

## Goal

Continue investigating the easymotion runtime bug where labels render and keypresses are accepted, but selecting a label still does not change window focus in a real Hyprland session.

## What I already know

- The user can see overlay letters and press a matching key.
- After keypress, window focus still does not change.
- The cursor position also does not change.
- The current default action is `hyprctl dispatch focuswindow address:{}`.
- Previous fixes already changed the default action string away from the earlier `hyprctl eval ...` path.
- Previous fixes also changed the runtime order so the overlay tears down before the action runs, and waits for compositor teardown acknowledgement with a Wayland roundtrip.
- The upstream reference project at `../hyprland-easymotion` focuses windows via dispatcher logic rather than cursor warping.

## Assumptions

- The remaining bug is likely in one of these areas: the selected window address value, command execution visibility/failure handling, or a mismatch between the address format Hyprland expects and the one passed through the JSON/action path.

## Open Questions

- Does the exact `hyprctl dispatch focuswindow address:<address>` command succeed when run manually with one of the addresses emitted by this project?

## Requirements

- Determine why the real Hyprland session still does not focus the selected window after label selection.
- Preserve the working overlay/render/input behavior while fixing the focus path.
- Keep Lua, Zig, and docs/specs aligned with the actual action contract.

## Acceptance Criteria

- [ ] Selecting a label in Hyprland changes actual focus to the chosen window.
- [ ] The root cause is identified clearly enough to explain why prior fixes were insufficient.
- [ ] Any contract/doc/spec changes needed by the final fix are updated.

## Definition of Done

- Root cause identified.
- Minimal fix implemented.
- Relevant checks pass.
- Manual validation guidance is explicit if runtime confirmation is still needed.

## Out of Scope

- Reworking the broader renderer architecture unless the bug proves impossible to fix incrementally.

## Technical Notes

- Current likely hot paths: `easymotion/config.lua`, `easymotion/init.lua`, `src/Layer.zig`, and `src/Labels.zig`.
- Current dirty files from the unfinished previous task overlap heavily with this investigation and should be treated carefully rather than reverted.
