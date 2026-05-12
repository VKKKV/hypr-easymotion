# Prepare Public Repo Release

## Goal

Prepare the current `hypr-easymotion` project for a public GitHub release by preserving the recent working code fixes, refining project and Trellis-facing documentation, including `show.mkv` as a demo artifact referenced by docs, licensing the repository under GPLv3, and publishing the result with `gh`.

## What I already know

- The repository currently has local code changes in `easymotion/config.lua`, `easymotion/init.lua`, and `easymotion/labels.lua`.
- `show.mkv` exists in the repo root and is intended to be committed as a demo file for the public repo.
- The user wants the project docs refined and aligned with Trellis documentation.
- The repository does not currently contain a license file.
- `gh` is authenticated and available for creating/publishing a public GitHub repository.
- `README.md` already describes the Zig renderer, Lua integration, runtime behavior, and JSON contract.

## Assumptions

- The current uncommitted Lua changes are intended to be kept and committed as part of this release-prep task.
- The repository can be published from the current branch after release hygiene is complete.

## Open Questions

- None at the moment.

## Requirements

- Preserve and commit the current working project changes.
- Include `show.mkv` in the public repository as a demo artifact.
- Reference or explain the demo video in the project documentation.
- Add GPLv3 licensing for the repository.
- Refine project documentation for public consumption.
- Keep the full Trellis content in the public repository.
- Align Trellis documentation with the current project state where needed.
- Add an acknowledgment in `README.md` that this project references `https://github.com/zakk4223/hyprland-easymotion`.
- Publish the repository to GitHub as a public repository using `gh`.

## Acceptance Criteria

- [ ] Repository contains a GPLv3 license file.
- [ ] Docs explain the project clearly enough for public users to build, install, and understand the demo artifact.
- [ ] `show.mkv` is committed and referenced in docs.
- [ ] Trellis-facing docs that remain in-repo are consistent with the current project state.
- [ ] `README.md` includes an attribution/reference to `https://github.com/zakk4223/hyprland-easymotion`.
- [ ] Code and docs changes are committed cleanly.
- [ ] Repository is pushed to GitHub and visible as a public repository.

## Definition of Done

- Relevant code/docs changes are committed.
- Public-facing docs are updated.
- Trellis docs/specs and task artifacts intended for publication are preserved and updated if needed.
- GitHub repo is created or configured and pushed publicly.

## Out of Scope

- Rewriting the implementation architecture beyond the current fix set.
- Re-recording the demo video.

## Technical Notes

- Existing public-facing docs live in `README.md`.
- The current repository already contains Trellis-managed task/spec structure under `.trellis/`.
- Demo artifact size is approximately 8.4 MB, which is acceptable for normal git history.
- README should include a clear attribution/reference note for the upstream inspiration project named by the user.
