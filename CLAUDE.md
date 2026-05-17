# CLAUDE.md — simple-workflow

## Dependencies

The plugin assumes the following CLIs are available on `PATH`:

- `git` — repository inspection used by every skill (status, diff, branch, log).
- `gh` — GitHub interactions (PR creation, release publishing, issue queries).
- `jq` — JSON parsing inside hooks and shell helpers.
- `yq` (mikefarah/yq v4) — YAML mutation used by hooks that append to `autopilot-state.yaml` (e.g. `runtime_metrics:`). Hooks degrade gracefully to a `python3 + PyYAML` fallback, then to a pure-shell append, when `yq` is missing.

The `hooks/lib/` directory contains shared helpers that are sourced by multiple hooks. Each helper is a standalone Bash file with no top-level side effects, exported functions only, and a three-tier fallback strategy (yq → python3+PyYAML → pure-shell) where applicable. The five current libraries are:

- `forbidden-rationale-patterns.sh` — array of ERE patterns that classify forbidden stop-reason rationales.
- `parse-state-file.sh` — YAML parse and autopilot-context detection helpers (`is_autopilot_context`, `parse_phase_status`, `parse_ticket_statuses`, `find_state_file`).
- `jsonl-tail-audit.sh` — JSONL transcript tail reader for tool-use detection.
- `state-authority.sh` — registry-driven field-ownership enforcement (`is_hook_owned_field`, `state_field_change_blocked`).
- `runtime-metrics.sh` — shared `append_runtime_metrics_entry` helper for writing `runtime_metrics:` entries to autopilot-state.yaml files.

## Hooks

### hooks.json: ordering-dependent hooks MUST be top-level entries

Anthropic's hook ordering contract guarantees **strict sequential execution only between top-level entries** of any hook array. A `hooks: []` array nested inside a single top-level entry does NOT guarantee ordering between its inner hooks — they may execute in parallel within the same tick.

**Rule**: if two hooks have an ordering dependency (one writes state that the next reads, one sets a sentinel the next checks, etc.), each MUST be its own **top-level entry** in the array. Never group ordering-dependent hooks inside a shared nested `hooks: []` array.

This rule was distilled from a v6.7.0 dogfood incident in which a verify hook nested with `autopilot-continue.sh` inside one Stop entry ran for 59 ms with zero artifacts written — the symptom of a same-tick race. The fix in v6.7.1 (commit `12266241`) split the entries to top-level. The downstream research feature that surfaced the bug was later abandoned, but the structural rule generalises and stands on its own.

### Runtime env knobs

- `SW_AUTO_COMPACT_ON_SHIP_MODE` — controls the v7 auto-`/compact` between autopilot tickets. Values: `on` (default inside autopilot context, off outside), `metric-only` (log intent without injecting), `off` (disable both `hooks/pre-next-scout-auto-compact.sh` and `hooks/post-ship-state-auto-compact.sh`). Set in the shell before launching `claude`.
- `INJECT_KEYS_DRY_RUN=1` — test-only knob for `hooks/lib/inject-keys.sh`; logs the would-be backend + target + text instead of invoking. Do NOT export in user shell profiles or every auto-`/compact` becomes a silent no-op.
- `AUTOPILOT_LEGACY_LOOPGUARD=1` — restore the pre-Plan-02 loop-guard semantics in `hooks/autopilot-continue.sh` (FILE_COUNT alone gates release, NOTOOL_COUNT is forced to threshold).

## Language

The following MUST be written in English:

- **Git / GitHub artifacts**: commit messages, branch names, tag names and annotations, PR titles and bodies, PR review comments, Issue titles and bodies, Issue comments, Discussions posts, GitHub Release notes.
- **Every tracked file** (anything not matched by `.gitignore`): documentation, code, code comments, skill / agent prompts, hooks, tests, CHANGELOG, this file, and any other committed artifact.

Conversations with the user may be in any language — translate before writing to any of the above. Non-English content is allowed only in gitignored paths: `.simple-workflow/`, `.docs/`, `CLAUDE.local.md`, `.claude/settings.local.json`, `.claude/worktrees/`, `.env*`.

## Releases

- SemVer with the `v` prefix (`v6.0.0`, never `6.0.0`).
- `.claude-plugin/plugin.json` `version` MUST match the newest `## [X.Y.Z]` in `CHANGELOG.md` (enforced by CT-MODE-14).
- CHANGELOG headers use a real ISO date — `YYYY-MM-DD` placeholders are rejected by CT-MODE-13.
- Group entries under `### BREAKING CHANGES`, `### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`, `### Security` (Keep a Changelog). Plus a project-specific `### Verification` group documenting test-run evidence (test suite counts, baseline comparisons, PATH-restricted matrix runs) — this is an accepted extension to Keep a Changelog and is exercised by every release entry from v6.4.1 onwards.
- For breaking changes, write a concrete migration sentence. Do not claim "semantically identical" when the behavior shifted.
- Commit subject: `release(vX.Y.Z): <summary>` for non-breaking, `release(vX.Y.Z)!: <summary>` for breaking (`!` required).
- Use **annotated** tags: `git tag -a vX.Y.Z -m "vX.Y.Z: <summary>" && git push origin vX.Y.Z`. Lightweight tags are not propagated to forks and are ignored by `git describe`. Legacy lightweight tags stay as-is — switch only for new releases.
- Every released tag needs a matching GitHub Release: `gh release create vX.Y.Z --title vX.Y.Z --notes-file <notes>`. Mark the newest stable as `--latest`.
- For breaking releases, post a migration guide under GitHub Discussions `Announcements` and link it from the Release notes.

### CHANGELOG and release-note style

- One block per change type per version (a single `### Added`, `### Changed`, etc.) — never one section per Plan / topic. Bullets nest inside.
- CHANGELOG bullet: 1-3 lines for the user-visible change and minimal impact context. Implementation narration belongs in the commit message, not the CHANGELOG.
- Release notes ≠ CHANGELOG verbatim: open with a one-paragraph TL;DR, group highlights by user-facing feature (not internal Plan numbers), use tables for tier / test data, and link back to `CHANGELOG.md` + the PR.
- Surface migration / kill switch in the same paragraph as the change it modifies, naming the env var or flag and the prior-version behaviour it preserves — even for non-breaking releases that flip a default.
- Skip per-fixture / per-assertion lists in release notes; `X / Y pass` suffices, with full enumeration kept in CHANGELOG `### Added`.

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
