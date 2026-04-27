# CLAUDE.md — simple-workflow

## Language

The following MUST be written in English:

- **Git / GitHub artifacts**: commit messages, branch names, tag names and annotations, PR titles and bodies, PR review comments, Issue titles and bodies, Issue comments, Discussions posts, GitHub Release notes.
- **Every tracked file** (anything not matched by `.gitignore`): documentation, code, code comments, skill / agent prompts, hooks, tests, CHANGELOG, this file, and any other committed artifact.

Conversations with the user may be in any language — translate before writing to any of the above. Non-English content is allowed only in gitignored paths: `.simple-workflow/`, `.docs/`, `CLAUDE.local.md`, `.claude/settings.local.json`, `.claude/worktrees/`, `.env*`.

## Releases

- SemVer with the `v` prefix (`v6.0.0`, never `6.0.0`).
- `.claude-plugin/plugin.json` `version` MUST match the newest `## [X.Y.Z]` in `CHANGELOG.md` (enforced by CT-MODE-14).
- CHANGELOG headers use a real ISO date — `YYYY-MM-DD` placeholders are rejected by CT-MODE-13.
- Group entries under `### BREAKING CHANGES`, `### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`, `### Security` (Keep a Changelog).
- For breaking changes, write a concrete migration sentence. Do not claim "semantically identical" when the behavior shifted.
- Commit subject: `release(vX.Y.Z): <summary>` for non-breaking, `release(vX.Y.Z)!: <summary>` for breaking (`!` required).
- Use **annotated** tags: `git tag -a vX.Y.Z -m "vX.Y.Z: <summary>" && git push origin vX.Y.Z`. Lightweight tags are not propagated to forks and are ignored by `git describe`. Legacy lightweight tags stay as-is — switch only for new releases.
- Every released tag needs a matching GitHub Release: `gh release create vX.Y.Z --title vX.Y.Z --notes-file <notes>`. Mark the newest stable as `--latest`.
- For breaking releases, post a migration guide under GitHub Discussions `Announcements` and link it from the Release notes.

### Pre-flight, before merging a release PR

1. `bash tests/test-skill-contracts.sh` exits 0.
2. `bash tests/test-path-consistency.sh` exits 0.
3. `plugin.json` version equals the newest CHANGELOG entry, dated with a real ISO date.

### Post-merge

1. Create the annotated tag on the merge commit and push.
2. Create the GitHub Release for that tag.
3. Audit `git tag -l` against `grep -E '^## \[[0-9]' CHANGELOG.md` and backfill any missing tag or Release.
4. Post the Discussions migration guide for breaking changes.

When in doubt about whether a change is breaking, treat it as breaking.

## PII

Never write personally identifying machine paths into tracked files. Specifically, an **absolute home path** of the form `/Users/<username>/...` (macOS) or `/home/<username>/...` (Linux) leaks the contributor's local username and directory layout, and is rejected by the `pre-write-safety.sh` and `pre-edit-safety.sh` hooks.

- Use the `<repo>` placeholder for repository-relative documentation paths (e.g. `<repo>/.simple-workflow/backlog/active/...`).
- Use `~`, `$HOME`, or relative paths inside code and shell snippets where a literal home prefix would otherwise appear.
- Triple-backtick fenced code blocks are exempt from the absolute-home-path scan, so verbatim CI logs (e.g. `/Users/runner/work/...`) may be quoted inside fenced blocks. Do not abuse this exemption for project-authored paths.
- The `.gitignore` file is allowlisted because it legitimately stores absolute paths.
- The detection regex is case-sensitive and POSIX-only: lowercase `/users/` and Windows-style `C:\Users\...` paths are out of scope.
