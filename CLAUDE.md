# CLAUDE.md — simple-workflow

## Dependencies

The plugin assumes the following CLIs are available on `PATH`:

- `git` — repository inspection used by every skill (status, diff, branch, log).
- `gh` — GitHub interactions (PR creation, release publishing, issue queries).
- `jq` — JSON parsing inside hooks and shell helpers.
- `yq` (mikefarah/yq v4) — YAML mutation used by hooks that append to `autopilot-state.yaml` (e.g. `runtime_metrics:`). Hooks degrade gracefully to a `python3 + PyYAML` fallback, then to a pure-shell append, when `yq` is missing.

`hooks/lib/*.sh` holds shared helpers sourced by multiple hooks. Each helper MUST be a standalone Bash file with no top-level side effects, exported functions only, and (where it manipulates YAML) a three-tier fallback strategy (`yq` → `python3 + PyYAML` → pure-shell). Enumerate the current set via `ls hooks/lib/`; per-helper purpose lives in each file's leading comment block.

## Hooks

### hooks.json: ordering-dependent hooks MUST be top-level entries

Anthropic's hook ordering contract guarantees **strict sequential execution only between top-level entries** of any hook array. A `hooks: []` array nested inside a single top-level entry does NOT guarantee ordering between its inner hooks — they may execute in parallel within the same tick.

**Rule**: if two hooks have an ordering dependency (one writes state that the next reads, one sets a sentinel the next checks, etc.), each MUST be its own **top-level entry** in the array. Never group ordering-dependent hooks inside a shared nested `hooks: []` array.

This rule was distilled from a v6.7.0 dogfood incident in which a verify hook nested with `autopilot-continue.sh` inside one Stop entry ran for 59 ms with zero artifacts written — the symptom of a same-tick race. The fix in v6.7.1 (commit `12266241`) split the entries to top-level. The downstream research feature that surfaced the bug was later abandoned, but the structural rule generalises and stands on its own.

### Runtime env knobs

- `SW_AUTO_COMPACT_ON_SHIP_MODE` — controls the v7 auto-`/compact` between autopilot tickets. Values: `on` (default inside autopilot context, off outside), `metric-only` (log intent without injecting), `off` (disable both `hooks/pre-next-scout-auto-compact.sh` and `hooks/post-ship-state-auto-compact.sh`). Set in the shell before launching `claude`.
- `INJECT_KEYS_DRY_RUN=1` — test-only knob for `hooks/lib/inject-keys.sh`; logs the would-be backend + target + text instead of invoking. Do NOT export in user shell profiles or every auto-`/compact` becomes a silent no-op.
- `SW_INJECT_KEYS_VERIFY` — default `1`. Controls the P1-1 post-inject verify step inside `hooks/lib/inject-keys.sh` (tmux backend only): after `tmux send-keys` returns rc=0, run `tmux capture-pane -p -S -3 -E -` on `$TMUX_PANE` to confirm the injected text echoed back to the TUI; if not, set rc=1 and emit `[INJECT-VERIFY] missed: ...` to stderr so the calling hook (`pre-next-scout-auto-compact.sh` / `post-ship-state-auto-compact.sh`) skips the `.auto-compact-pending` sentinel and the `runtime_metrics` write. Set `0` to disable the verify block entirely and restore pre-P1-1 behaviour where `inject_keys` rc matches `tmux send-keys` rc verbatim (useful when capture-pane is unreliable on the host).
- `SW_INJECT_KEYS_VERIFY_SLEEP_MS` — default `150`. Sleep (milliseconds) between `tmux send-keys` and `tmux capture-pane` inside the P1-1 verify block. Raise (e.g. `300`) for high-latency SSH or loaded hosts where TUI echo-back exceeds 150ms; lower (e.g. `50`) only when the host is known fast and you want to minimise auto-compact latency at ticket boundaries. Honoured only when `SW_INJECT_KEYS_VERIFY` is not `0`.
- `SW_NEXT_COMPACT_PENDING_TTL_SEC` — default `21600` (6 hours). Lifetime (seconds) of the `<state_dir>/.next-compact-pending` sentinel written by the P2-1 auto-compact retry path. The sentinel is dropped before every `inject_keys '/compact'` call by `hooks/pre-next-scout-auto-compact.sh` and `hooks/post-ship-state-auto-compact.sh`; on rc=1 it survives the turn so `hooks/session-start.sh` can replay the `/compact` injection on the next `source=startup` / `source=resume` boot (with the timestamp refreshed before the replay). Sentinels older than this TTL are deleted without retry — stale attempts (>6h) likely belong to an abandoned context, and re-injecting `/compact` 24 hours later would land in unrelated work. Shorten (e.g. `600`) during dogfood / debugging to force-expire test sentinels; lengthen with caution. Honoured only when `SW_AUTO_COMPACT_ON_SHIP_MODE` is not `off` — the kill-switch path short-circuits the entire P2-1 block.
- `AUTOPILOT_LEGACY_LOOPGUARD=1` — restore the pre-Plan-02 loop-guard semantics in `hooks/autopilot-continue.sh` (FILE_COUNT alone gates release, NOTOOL_COUNT is forced to threshold).
- `SW_POST_SHIP_INTEGRITY` — controls `hooks/post-ship-state-auto-compact.sh` Gate 5.5 (post-ship integrity self-heal, P3-5). Values: `on` (default — when the brief-side `autopilot-state.yaml` write flips a ticket's `steps.ship` to `completed`, the hook reads the per-ticket `phase-state.yaml` and rewrites `overall_status` / `current_phase` / `last_completed_phase` / `phases.ship.status` to their terminal values whenever `overall_status: in-progress` is left behind by a skipped or interrupted `/ship` Step 15a write), `metric-only` (emit the `[POST-SHIP-INTEGRITY] self-healing <dir>` warning to stderr only, no write — forensic mode), `off` (silent skip; unknown values collapse here so a typo fails closed for the rewrite). The rewrite tries `yq -i` first then a `python3 + PyYAML` tempfile + rename; the awk tier is intentionally not exercised for YAML mutation (ticket Risk R3) so the original file is preserved on writer-absence.
- `SW_AUTOPILOT_ASK_GUARD` — controls `hooks/pre-askuserquestion-guard.sh`. Values: `on` (default; matrix active), `metric-only` (compute the matrix and log `[ASK-GUARD] metric-only: would deny ...` to stderr without denying), `off` (disable the guard; unknown values collapse here so a typo fails open). The hook implements the 3-tier `risk_tolerance` allow-list documented in `skills/autopilot/SKILL.md ## Non-interactive orchestrator contract (3-tier, risk_tolerance-aware)`; when `autopilot-policy.yaml` is absent or carries an unknown `risk_tolerance:` value, `hooks/lib/parse-state-file.sh::get_risk_tolerance` returns `conservative` (deliberate fail-open so the six known gate-id headers remain answerable).
- `SW_AUTOPILOT_DONE_GATE_TTL_SEC` — default `86400` (24 hours). TTL window for `hooks/scout-checkpoint-guard.sh` Step 2a (the autopilot-completion gate added in v8.0.1). The gate silent-exits the hook when (1) no `autopilot-state.yaml` exists under `briefs/active/` or `product_backlog/` (no active autopilot), (2) `briefs/done/<parent>/autopilot-state.yaml` exists with mtime within this TTL, AND (3) every `tickets[].status` equals `completed`. Required because the existing Step 3 phase-state.yaml lookup uses `find_phase_state_file` which scans `active/` only — after `/ship` moves the brief to `briefs/done/`, the moved `phase-state.yaml` becomes invisible and the 3-AND (a)(b)(c) would otherwise false-block on stale transcript artifacts. Set `0` to disable the TTL bound (the gate fires on any all-completed `briefs/done/` state regardless of age — useful for replay scenarios where a session is resumed long after autopilot finished). Shorten (e.g. `600`) during dogfood / regression debugging when you want stale done state to fall through immediately. Non-numeric values fall back to `86400` with a one-line `[SCOUT-AUTOPILOT-DONE-GATE]` stderr warning. Honoured only when `SW_SCOUT_CHECKPOINT_MODE` is not `off` — the kill switch in Step 2 short-circuits the entire hook including Step 2a.
- `SW_AUTOPILOT_POLICY_STOP_HONOR` — default `on`. Controls whether the three autopilot Stop hooks (`hooks/autopilot-continue.sh`, `hooks/impl-checkpoint-guard.sh`, `hooks/scout-checkpoint-guard.sh`) HONOUR a model-declared hard-stop instead of forcing the loop to continue. When the orchestrator legitimately hard-stops it emits `[AUTOPILOT-POLICY] gate=<name> action=stop reason=<...>` in its last assistant turn (mandated by `skills/autopilot/SKILL.md`); the shared detector `hooks/lib/detect-policy-gate-stop.sh::last_turn_declares_policy_gate_stop` scans only that LAST assistant turn's `text` content blocks for the marker. Values: `on` (default — honour: `autopilot-continue.sh` allows `end_turn` and appends a `boundary: session_end` / `stop_reason: policy_gate_stop` `runtime_metrics` entry, the two checkpoint guards stand down without blocking and clear their own counter, none of the three re-injects "Do NOT stop"), `metric-only` (detect and log a `[POLICY-GATE-STOP]`-prefixed stderr line stating it WOULD honour, but still emit `decision: block` — forensic mode), `off` (ignore the declaration entirely; block exactly as before). Unknown values fail **closed** to `off` semantics so a typo never silently widens the honour behaviour. This knob is purely additive: with it `off` OR no marker present, the existing loop guards (autopilot-continue's `FILE_COUNT>=5 && NOTOOL_COUNT>=5`; the checkpoint guards' 3× counters) remain the sole backstop and every hook behaves exactly as before. Detection is independent of `AUTOPILOT_LEGACY_LOOPGUARD`. Fixes a dogfood thrash where a hard-stop was re-injected 11× because the hooks ignored the model's declared `policy_gate_stop`.
- `SW_SAFETY_JQ_MISSING_MODE` — default `metric-only`. Controls the jq-missing preflight at the top of the three safety hooks (`hooks/pre-bash-safety.sh`, `hooks/pre-write-safety.sh`, `hooks/pre-edit-safety.sh`). `jq` is a documented hard dependency; when it is absent these guards cannot parse the tool payload and previously died with a silent `exit 127` (which Claude Code treats as a non-blocking error — a fail-OPEN). Values: `on` (fail **closed** — `exit 2` with an explicit `[SAFETY-JQ-MISSING] <hook>: jq not found …` message, blocking the tool call), `metric-only` (default — log `[SAFETY-JQ-MISSING] metric-only: … would fail closed …` to stderr and ALLOW the call with `exit 0`, so the shipped fail-open behaviour is unchanged but now observable), `off` (silently allow, `exit 0`, no message). Unknown values collapse to `metric-only` (the observe-only default — a typo never silently flips the guard to fail-closed). **Promotion**: ship at `metric-only`; after one dogfood confirms no false trips on a jq-present host, set `=on` to enforce fail-closed. The `[SAFETY-JQ-MISSING]` exit-2 path is verified under a PATH-restricted (no-jq) test in `tests/test-pre-bash-safety.sh` / `tests/test-pre-write-safety.sh` / `tests/test-pre-edit-safety.sh` with the knob set to `on`.
- `SW_BASH_STATE_GUARD_MODE` — default `metric-only`. Controls detection 3 of `hooks/pre-bash-contract-guard.sh` (the autopilot-context PreToolUse:Bash guard): a Bash-mediated state-file status mutation — `yq -i` / `sed -i` / shell-redirect on `autopilot-state.yaml` / `phase-state.yaml` that drives a `status:` (or `steps.<phase>`) to `skipped` / `completed` / `failed` / `in_progress`. The Write/Edit skip-transition guard (`hooks/pre-state-transition.sh`) is wired only to Write/Edit, so this closes the Bash bypass (ST-04). Values: `on` (emit `decision:block` with `unauthorized_state_mutate_bash` — deny the call), `metric-only` (default — log `[PRE-BASH-CONTRACT-GUARD] metric-only: would deny ...` to stderr and ALLOW), `off` (skip detection 3 entirely). Unknown values collapse to `metric-only`. Detections 1 (forbidden manual_bash_fallbacks rationale) and 2 (direct `git commit`) are NOT gated by this knob — the hook's existing NAC posture is preserved. **Promotion**: ship at `metric-only`; after one dogfood confirms no false trips, set `=on` to enforce. Read-only commands (`grep`/`cat`/`yq` without `-i`) and `runtime_metrics` appends (no status transition) are not matched.
- `SW_STATE_FIELD_GUARD_MODE` — default `metric-only`. Gates the **HOOK_OWNED_FIELDS enforcement** in `hooks/pre-write-safety.sh` / `hooks/pre-edit-safety.sh`. The registry now ships with `.runtime_metrics` (an append-only telemetry list written exclusively by the six runtime-metrics writer hooks — Foundation 3 / ST-03), so a model Write/Edit that would clobber hook-appended `runtime_metrics` entries (a lost-update) is detectable. Values: `on` (emit `decision:block` whose reason NAMES the violated field — e.g. `.runtime_metrics` — and references `docs/state-schema.md`), `metric-only` (default — log `[STATE-FIELD-GUARD] metric-only: would block ...` to stderr and ALLOW, so populating the registry does NOT change the shipped allow-by-default behaviour), `off` (allow silently). Unknown values collapse to `metric-only`. **Promotion**: ship at `metric-only`; after one dogfood confirms no false trips, set `=on` to enforce. Detection covers the inline `runtime_metrics: []` → `[…]` (and blank-out) form; a multi-line list mutation expressed without an inline value change is not detected (acceptable under the metric-only default).

## Language

**IMPORTANT**: every tracked file (anything not matched by `.gitignore`) AND every Git / GitHub artifact (commit messages, branch names, tag names and annotations, PR titles and bodies, PR review comments, Issue titles and bodies, Issue comments, Discussions posts, GitHub Release notes) MUST be written in English. Translate before writing if the conversation is in another language.

Non-English content is allowed only in gitignored paths: `.simple-workflow/`, `.docs/`, `CLAUDE.local.md`, `.claude/settings.local.json`, `.claude/worktrees/`, `.env*`.

## Product/Language/Domain Agnosticism

**IMPORTANT**: the plugin's normative content — everything under `skills/`,
`agents/`, and `hooks/` that instructs the model how to build, verify, or ship —
MUST serve every user's needs without baking in dependence on a specific
product, programming language, or problem domain. Triggers, rubrics, gates, and
examples MUST key off **properties** (a computed numeric/algorithmic value; a
shared input/validation boundary; an irreversible side-effect; a behaviour the
spec advertises as strict / canonical / lossless / or bounded by a limit), never
off membership in a named-product / named-language / named-domain list.

### The (A) / (B) substrate line

Two substrates, two different rules:

- **(A) The user-product substrate** — the source, tests, and artifacts a user
  builds *with* the plugin. This MUST be treated agnostically. The harness may
  not assume the user's language, framework, test runner, or domain. A named
  language / framework / domain may appear ONLY as clearly-labelled,
  non-exhaustive **illustration** ("e.g. …", "illustrative only") — never as the
  operative trigger, an exhaustive checklist, or a recognition cue the mechanism
  depends on.
- **(B) The harness-own substrate** — the plugin's *own* operating dependencies:
  `git`, `gh`, `jq`, `yq`, the Claude Code runtime (hooks, skills, agents, the
  `Agent` / `Workflow` tools, the state-file machinery), and the PR / release
  delivery path. These are legitimately FIXED and are NOT subject to the (A)
  rule. Depending on `git` for repo inspection or `gh` for PR creation is
  harness plumbing, not a domain dependency.

### Agnosticism must never lower product quality

Agnosticism constrains *how* the harness is written; it is not a licence to
verify less. The harness (subagents / skills / hooks) MUST **meet or beat** its
prior defect catch-rate. Where an agnostic formulation cannot guarantee the same
quality a product/domain-specific one did, the answer is NOT to retreat to the
specific cue: thoroughly explore and **generate** an innovative agnostic
mechanism, **verify** it catches the baseline defect classes by construction,
gain confidence, and only THEN implement and update the plan. A property- /
grammar- / oracle-driven mechanism that catches a defect class for ALL inputs is
strictly stronger than a keyword cue that catches it only when a known token is
recalled.

### Enforcement boundary (HARD-LINE vs JUDGMENT)

Normative-prose agnosticism is primarily a **review standard**, not a fully
grep-enforced invariant. Only specific, stable **product-instance token**
denylists are mechanised as contract tests (e.g. `CT-DECONTAM-1`, whose
denylist is product instances ONLY — abstract failure-class names and bare
domain vocabulary are deliberately excluded). Judgment criteria ("is this
example illustrative or load-bearing?") MUST NOT be faked as contract tests.
When in doubt, prefer a property-based formulation and leave the final
agnosticism call to review.

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

## Plans

### Cross-agent contracts MUST enumerate every Skill-bearing subagent and its caller

When a ticket introduces a contract that crosses agent boundaries — a new section in `ticket.md` / `plan.md`, a new spawn-prompt block, a new return-envelope row, or any other shared protocol between an orchestrator skill and a subagent (or between two subagents) — the Scope table MUST enumerate **every** `Skill`-bearing subagent AND the caller that spawns it, not only the agents on the motivating regression path. Scoping from the motivating path alone produces asymmetric wiring where one path is deterministic and every other path silently bypasses the new contract via the prior fallback.

This rule was distilled from a v7.1.0 partial-wiring incident: the original plan fully wired `/impl` → `ac-evaluator` (the motivating `### Capabilities` regression path) with per-AC deterministic handoff, but 6 of 8 `Skill`-bearing subagents and 7 of 9 spawner skills received only a generic "prefer the section" preference bullet. The asymmetry was detected during post-commit review and required an immediate amend to add `## Bound Capabilities` body sections to the 7 consumer agents and to upgrade the handoff bullet across all 9 spawners to require deterministic inlining under `## Bound capabilities (per AC)`.

Audit Scope before drafting: `grep -l '^[[:space:]]*-[[:space:]]Skill[[:space:]]*$' agents/*.md` lists every `Skill`-bearing agent; cross-reference each against `grep -rln '<agent-name>' skills/*/SKILL.md` to find its callers. The full caller↔callee matrix should appear in the Scope table; whichever cells are intentionally left out should carry a one-line rationale in `### Implementation Notes` so the asymmetry is deliberate rather than incidental.

## Modifications

### Any change to `skills/`, `agents/`, or `hooks/` MUST audit sibling artifacts before commit

Before declaring a change to any file under `skills/`, `agents/`, or `hooks/` complete, audit whether sibling artifacts in the same tree that play an analogous role need the same change. The asymmetry that the `## Plans` rule catches at Scope-authoring time also manifests at implementation time: a bullet added to one SKILL.md, a tool added to one agent's `tools:` field, or a contract added to one hook may need to flow to 3-9 siblings that weren't part of the immediate ticket.

Concrete audits to run before commit:

- **skills/***: `ls skills/*/SKILL.md` then grep for shared section headings (`## Subagent Skill-Access Handoff`, `## Pre-computed Context`, `## Guardrails`, etc.) — changes to one usually apply to all peers carrying the same heading.
- **agents/***: `ls agents/*.md` and compare `tools:` fields and shared body sections — agents in the same role (generator / evaluator / author / hermetic) should evolve symmetrically.
- **hooks/***: `ls hooks/*.sh` and `ls hooks/lib/*.sh` — related lifecycle hooks (pre-write/pre-edit, pre-tool/post-tool, Stop/SubagentStop) often need parallel changes; library helpers in `hooks/lib/` are sourced by multiple hooks, so a contract change there ripples to every caller.

For any intentional omission, record a one-line rationale in the commit message (or in the ticket's `### Implementation Notes` if the omission is plan-authored). This rule complements the planning-side `## Plans` rule above by enforcing the same uniformity at implementation time.

## PII

**IMPORTANT**: never write personally identifying machine paths into tracked files. An **absolute home path** of the form `/Users/<username>/...` (macOS) or `/home/<username>/...` (Linux) leaks the contributor's local username and directory layout and is rejected by `pre-write-safety.sh` / `pre-edit-safety.sh`.

- Use the `<repo>` placeholder for repository-relative documentation paths (e.g. `<repo>/.simple-workflow/backlog/active/...`).
- Use `~`, `$HOME`, or relative paths inside code and shell snippets where a literal home prefix would otherwise appear.
- Triple-backtick fenced code blocks are exempt from the absolute-home-path scan, so verbatim CI logs (e.g. `/Users/runner/work/...`) may be quoted inside fenced blocks. Do not abuse this exemption for project-authored paths.
- The `.gitignore` file is allowlisted because it legitimately stores absolute paths.
- The detection regex is case-sensitive and POSIX-only: lowercase `/users/` and Windows-style `C:\Users\...` paths are out of scope.
- **Known limitation — unclosed fences**: the scan toggles fence state on each fence line (a line beginning with three backticks), so an **unclosed** (odd-count) fence extends to end-of-file per CommonMark and exempts every following line from the absolute-home-path scan. An accidental unbalanced fence in generated Markdown can therefore let a home path slip past the guard, which does not validate fence pairing — keep fences balanced.
- **Known limitation — Bash write sinks**: the PII / sensitive-file guards run only on the `Write` and `Edit` tools. The same content written through `Bash` (`echo > file`, `tee`, `python3 -c`, a heredoc) is **not** inspected — `pre-bash-safety.sh` checks `git add` staging plus the destructive / network / identity / privilege denylist, not write sinks. A PII string or sensitive filename created via a shell redirect bypasses these guards by design (best-effort defense-in-depth); prefer `Write` / `Edit` for files that may carry PII.
