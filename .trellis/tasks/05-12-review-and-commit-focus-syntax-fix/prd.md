# Review And Commit Focus Syntax Fix

## Goal

Review the current local change that updates the window-focus action syntax for newer Hyprland versions, verify it is correct and consistent, and commit it if it checks out.

## What I already know

- The working tree currently has modifications in `easymotion/config.lua` and `src/Labels.zig`.
- The user reports they found the right way to focus windows under the new Hyprland syntax.
- The likely scope is the default action template used by both Lua and Zig fallback configuration.

## Assumptions

- The current dirty changes were made intentionally by the user and should be reviewed, not overwritten.

## Open Questions

- None at the moment.

## Requirements

- Inspect the current focus-syntax changes in the repo.
- Verify the Lua default action and Zig fallback stay aligned.
- Commit the verified fix using the repository's existing commit style.

## Acceptance Criteria

- [ ] The new focus syntax is reviewed for correctness.
- [ ] Lua and Zig defaults remain in sync.
- [ ] The verified changes are committed cleanly.

## Definition of Done

- Diff reviewed.
- Any needed consistency fix applied.
- Commit created.

## Out of Scope

- Broader refactoring beyond the focus syntax change.

## Technical Notes

- Relevant files are `easymotion/config.lua` and `src/Labels.zig`.
- This task is primarily a review-plus-commit pass over an already-small diff.
