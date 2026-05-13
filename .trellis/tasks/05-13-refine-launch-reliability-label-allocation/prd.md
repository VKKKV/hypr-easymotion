# Refine Launch Reliability and Label Allocation

## Goal

Make renderer launch preflight work for both filesystem paths and PATH-resolved command names, and avoid unnecessary label string allocations for invalid renderer labels.

## Requirements

* In `easymotion/init.lua`, only preflight-check renderer existence when `cfg.renderer` looks path-like by containing `/`.
* Preserve existing cleanup behavior: if a path-like renderer is missing, remove the temp payload file and return the current error style.
* For bare renderer command names with no `/`, skip the `io.open` preflight and let the launcher resolve the command through PATH.
* In `src/Labels.zig`, validate required label string fields before allocating duplicated strings.
* Skip invalid labels with the existing warning behavior when `key`, `text`, or `address` is missing or empty.
* Leave JSON surrogate-pair support out of scope for this task.

## Acceptance Criteria

* [ ] A bare command renderer value such as `easymotion-render` is not rejected by Lua preflight solely because it is not a file path.
* [ ] A path-like renderer value such as `/missing/easymotion-render` still fails early and cleans up the temp payload file.
* [ ] Invalid label entries no longer allocate duplicated `key`, `text`, or `address` strings before being skipped.
* [ ] Existing valid label parsing semantics are unchanged.
* [ ] Project quality checks pass.

## Definition of Done

* Implementation is localized to the renderer launch and label parsing code.
* Lint/typecheck/tests or the closest available project checks are run.
* No documentation changes are required unless behavior differs from current README claims.
* Spec updates are considered before commit.

## Technical Approach

Use the minimal changes from the review: guard the Lua renderer `io.open` preflight behind `cfg.renderer:find("/")`, and in Zig extract source slices first, validate non-empty required fields, then allocate only for valid labels.

## Decision (ADR-lite)

**Context**: The renderer can be configured as an absolute/relative path or as a command name discoverable through PATH. The previous preflight treated all values as direct file paths. Label parsing allocated strings before deciding whether an entry was usable.

**Decision**: Only perform filesystem existence probing for path-like renderer strings, and reorder label parsing to validate required fields before duplication.

**Consequences**: Bare command names rely on the launcher to report missing binaries, while path-like renderer mistakes retain early cleanup and actionable errors. Invalid labels avoid wasted allocations until arena teardown.

## Out of Scope

* Implementing Unicode surrogate-pair handling in `easymotion/json.lua`.
* Changing launch command construction or quoting semantics beyond the preflight condition.
* Changing label ordering, geometry defaults, or valid label payload format.

## Technical Notes

* `easymotion/init.lua` currently probes `cfg.renderer` with `io.open` unconditionally in `spawn_renderer`.
* `src/Labels.zig` currently assigns duplicated fields into `labels[count]` before checking whether required fields are non-empty.
* Relevant specs are currently high-level indexes: `.trellis/spec/backend/index.md` for Zig/runtime logic and `.trellis/spec/frontend/index.md` for Lua/plugin-facing behavior.
