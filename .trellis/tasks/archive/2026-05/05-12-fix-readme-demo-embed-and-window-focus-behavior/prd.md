# Fix README Demo Embed And Window Focus Behavior

## Goal

Fix the public-facing demo presentation in `README.md` so the demo is presented as a playable/embedded element instead of only a plain file link, and fix the runtime behavior so selecting a label moves actual window focus to the chosen window instead of only moving the cursor or otherwise failing to focus correctly.

## What I already know

- `README.md` currently references the demo as a plain repository link: [`show.mkv`](./show.mkv).
- The upstream project README uses a GitHub-hosted asset URL for an inline/playable demo reference.
- The current default action in `easymotion/config.lua` is `hyprctl eval 'hl.dispatch(hl.dsp.focus({window = "address:{}"}))'`.
- The renderer executes the configured `action` template after replacing `{}` with the selected window address.
- The user observed that selecting a label does not actually focus the target window as intended.

## Assumptions

- The focus bug should be fixed in code, not merely documented around.
- The README change should target GitHub README rendering behavior, since the issue is specifically about the demo not being directly playable there.

## Open Questions

- None at the moment.

## Requirements

- Diagnose and fix the action/focus behavior so selecting a label focuses the chosen window.
- Update `README.md` so the demo is presented via a GitHub-hosted asset URL rather than only a plain repository file link.
- Keep the README description aligned with the actual runtime behavior after the focus fix.
- Use `https://github.com/user-attachments/assets/5558df25-0f7e-4cd3-9393-b550afc97801` as the README demo asset URL.

## Acceptance Criteria

- [ ] Selecting a label triggers a focus action that targets the chosen window instead of only moving the cursor or failing to focus.
- [ ] `README.md` uses a GitHub-hosted asset URL for the demo section.
- [ ] README action examples and behavior text match the actual default implementation.
- [ ] README references the provided GitHub asset URL and no longer depends on the old local `show.mkv` link.

## Definition of Done

- Relevant code/docs changes are implemented.
- Build/check commands that apply to the changed code pass.
- Public docs reflect actual behavior.

## Out of Scope

- Re-recording the demo itself.
- Broad UI or renderer redesign unrelated to focus execution.

## Technical Notes

- `easymotion/config.lua` defines the default action template.
- `easymotion/init.lua` serializes the action into the JSON payload.
- `src/Labels.zig` reads the action template and executes it after label selection.
- `README.md` currently uses a local `.mkv` link, which is visible but not embedded as a player-like demo element.
- The selected direction is to use a GitHub-hosted asset URL similar to the upstream project.
- The user has provided the asset URL and renamed the local demo file from `show.mkv` to `show.mp4`.
