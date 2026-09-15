# Harness-conformance audit — September 2026

Record of the audit that produced v10.1.0. It captures (1) the design
perspective the plugin was built from, reconstructed from the tracked history
(the gitignored `.docs/` planning notes are not part of the repository), (2)
what the current Claude Code harness contract says where the plugin depended on
older behaviour, (3) what was fixed, and (4) the confirmed problems that were
deliberately left for follow-up tickets, with their evidence. Paths are
repository-relative.

## 1. Design perspective (reconstructed)

- **Three pillars.** Harness engineering (a Generator → Evaluator information
  firewall enforced structurally by fresh subagent contexts, ticket-confined
  artifacts and lifecycle hooks), context conservation (sub-agent returns
  capped at ~500 tokens, artifacts on disk, state that survives compaction),
  and cross-session learning (`/tune` distils evaluation logs into
  `.simple-workflow/kb/`).
- **Loop engineering.** `/autopilot` drives `/scout` → `/impl` → `/ship` per
  ticket inside a closed act → verify → correct loop whose stopping conditions
  are contracts (policy gates, checkpoint markers, loop guards), not model
  judgement. Every mechanism ships behind a `SW_*` kill switch, first at
  `metric-only`, and is promoted to `on` only after a dogfood run.
- **Dogfood-driven hardening.** From v6 to v10 every release records a numbered
  dogfood (`dogfood19` … `dogfood63`) whose observed failure became a contract
  test (`CT-*`) pinning the fix. The 900+ literal contract tests are the
  project's memory of those failures.
- **Agnosticism line.** Normative content keys off properties (computed
  values, shared input boundaries, irreversible side-effects), never named
  products or languages; only the harness's own dependencies (`git`, `gh`,
  `jq`, `yq`, the Claude Code runtime) are fixed.
- **Default flips.** v9.0.0 turned ultracode orchestration (`uc`) and
  wave-parallel execution (`parallel`) on by default; v10.0.0 turned the
  autonomous chain off by default (`/brief` writes and stops unless
  `chain=on`).

## 2. Harness facts the plugin depended on (verified 2026-09-14, CC 2.1.270)

| Area | Current contract | Plugin assumption before v10.1.0 |
| --- | --- | --- |
| Workflow result | only a top-level `return` yields a result (probed live) | trailing expression `merged;` |
| `context: fork` skills | run in the background by default (CC 2.1.218) | synchronous chain-call |
| Subagents in interactive sessions | run in the background (fork mode); the harness pauses the turn and reports in-flight work to Stop hooks as `background_tasks` | foreground barrier; Stop hooks force-continued |
| `isolation: worktree` base | `origin/<default>` unless `worktree.baseRef: "head"` or no remote (CC 2.1.133) | orchestrator HEAD (validated only on a no-remote repo) |
| `SubagentStop` input | `agent_transcript_path` = subagent transcript, `transcript_path` = session | `transcript_path` = executor transcript |
| Stop / SubagentStop input | `last_assistant_message` (CC 2.1.47) | transcript tail scan only |
| Hook execution | all matching hooks run in parallel, no ordering | top-level entries run sequentially |
| PreToolUse output | `hookSpecificOutput.permissionDecision`; top-level `decision` deprecated | top-level `decision: block` |
| SessionStart output | `hookSpecificOutput.additionalContext` (plain stdout also accepted) | top-level `additionalContext` |
| Skill body vs process environment | a skill cannot read env vars except through a `!` probe | prose "read the `SW_*` environment variable" |
| Agent tool | per-invocation `model` outranks frontmatter; no `cwd` | "JSONSchema rejects a per-spawn model" |
| Subagent `tools:` | bare tool names / `mcp__*` / `Agent(type)`; specifiers are not a grammar | `Bash(git diff:*)`, `shell(...)` entries |
| `yq` | the tiers need mikefarah v4; a python `yq` wrapper mis-parses | any `yq` on PATH |
| Models | `opus` → the current Opus generation, `sonnet` → the current Sonnet generation (1M context), `fable` → a higher tier above `opus`; `effort` per agent/skill | "opus is the top tier" |

## 3. Fixed in v10.1.0

See `CHANGELOG.md` `## [10.1.0]`. In short: Workflow `return`; checkpoint-guard
release ordering; `agent_transcript_path`; `background: false`; background
subagent stand-down in the Stop hooks; executor re-point onto
`ap-integration/<parent>`; the unstageable state symlink; bash 5.2 `export -f`
heredoc; the `yq` flavour probe; Workflow-path handoff completeness and merge
rules; plugin-root paths; `chain:` precedence; nested `ticket-dir` lookup;
resilient pre-computed probes; dirty-worktree safety; the R2 detector; the
dev-guard; hook output shapes; `runtime_metrics` append lock; `allowed-tools`
completions; documentation of model aliases, worktree base, no-multiplexer
sessions and the post-compaction skill re-attach budget.

## 4. Confirmed findings

Each item below was reported by an audit reader and survived the independent
adversarial verifiers. Section 4.2 lists the ones deliberately left for
follow-up tickets: each needs a design decision, a dogfood, or a contract-test
rewrite that is out of scope for a conformance pass.

### 4.1 Confirmed, fixed in v10.1.0 (for traceability)

| id | severity | category | location | finding |
| --- | --- | --- | --- | --- |
| H1 | critical | correctness | `hooks/impl-checkpoint-guard.sh:395` | Checkpoint Stop guards never release: own metrics append resets the block counter every tick |
| H28 | critical | harness-conformance | `skills/investigate/SKILL.md:13` | /investigate is context: fork without background: false, but /scout consumes its result synchronously |
| H42 | critical | correctness | `skills/impl/workflows/eval-panel.mjs:393` | eval-panel.mjs ends with a bare `merged;` — the Workflow returns nothing to /impl Step 16 |
| H58 | critical | harness-conformance | `skills/impl/workflows/eval-panel.mjs:393` | eval-panel.mjs returns nothing: trailing `merged;` is not a Workflow return |
| H59 | critical | harness-conformance | `agents/ticket-executor.md:9` | ticket-executor assumes foreground subagent with nested Agent/Workflow; interactive subagents now default to background without them |
| H60 | critical | harness-conformance | `skills/investigate/SKILL.md:13` | context:fork skills now run in the background by default; /scout gates on an inline /investigate return |
| F2 | high | correctness | `skills/audit/SKILL.md:303` | /audit Step 4b sources hooks/lib/audit-coverage.sh by cwd-relative path, which does not exist in a user's product repo |
| F47 | high | correctness | `skills/impl/workflows/eval-panel.mjs:331` | Workflow-path spawn prompt omits mandated fields: `## Bound capabilities (per AC)`, plan path, diff shortstat, soft turn budget, `--- panel:` directive, plan-compliance hint |
| F48 | high | harness-conformance | `skills/impl/workflows/eval-panel.mjs:393` | Script result is a trailing expression statement, not `return` — contrary to the documented Workflow result convention |
| F50 | high | operability | `skills/impl/SKILL.md:141` | No fallback when the Workflow tool is unavailable, although uc=on (Workflow dispatch) is the run default and the harness treats Workflow as an opt-in tool |
| F140 | high | correctness | `tests/test-skill-contracts.sh:3209` | CT-MODE-RM-3 Japanese-character guard is locale-brittle: false-positive under POSIX, vacuous PASS under C.UTF-8 (CI) |
| F174 | high | correctness | `skills/autopilot/SKILL.md:92` | Skill-layer env kill switches are unreadable by the model: no env probe and no echo/env tool in /autopilot |
| F191 | high | security | `skills/ship/SKILL.md:211` | Worktree `.simple-workflow` symlink is not gitignored; /ship can commit it and merging/checkout deletes the whole state tree |
| F204 | high | correctness | `hooks/lib/parse-state-file.sh:683` | Any `yq` on PATH is assumed to be mikefarah v4; python-yq silently empties the Stop-hook step parser so autopilot-continue allows end_turn |
| H2 | high | harness-conformance | `hooks/session-start.sh:231` | SessionStart hook emits undocumented top-level `additionalContext` instead of hookSpecificOutput.additionalContext |
| H5 | high | doc-drift | `CLAUDE.md:18` | CLAUDE.md ordering rule contradicts the harness (all matching hooks run in parallel); tests pin a non-existent top-level order |
| H31 | high | correctness | `skills/catchup/SKILL.md:30` | /catchup pre-computed `git log` and `git diff --shortstat` abort the whole skill on fresh or remote-less repos |
| F1 | medium | harness-conformance | `skills/audit/SKILL.md:14` | /audit body mandates Write and Bash but allowed-tools grants neither |
| F20 | medium | correctness | `skills/brief/SKILL.md:235` | Documented chain=off → autopilot rescue path breaks: /autopilot reads brief `mode:` not `chain:` |
| F45 | medium | harness-conformance | `skills/impl/SKILL.md:134` | Stale claim: Agent tool / Workflow agent() cannot take a per-spawn model override — twin-file ac-evaluator-hi strategy no longer justified — *claim corrected; the twin file is retained deliberately* |
| F64 | medium | correctness | `skills/impl/lib/detect-tautological-assertions.sh:84` | R2 detector flags meaningful positivity/negativity assertions (`> 0`, `< 0`, `>= Number.MIN_VALUE`) as vacuous |
| F78 | medium | operability | `skills/autopilot/SKILL.md:243` | Two competing procedures for PARALLEL_MODE == on: the stale concurrency-1 executor loop is still presented as the `on` path — *precedence note added; the stale section is not deleted* |
| F95 | medium | correctness | `skills/ship/SKILL.md:223` | /ship Step 5 ticket-dir resolution assumes the retired flat active/{NNN-slug} layout |
| F96 | medium | harness-conformance | `agents/ac-evaluator.md:141` | Twin agent file exists only because of a stale 'Agent JSONSchema rejects per-spawn model' claim — *claim corrected; the twin file is retained deliberately* |
| F112 | medium | harness-conformance | `hooks/pre-bash-contract-guard.sh:113` | Five PreToolUse guards emit the deprecated top-level decision:block shape instead of hookSpecificOutput.permissionDecision |
| F128 | medium | harness-conformance | `hooks/lib/detect-policy-gate-stop.sh:352` | Stop-hook turn detection reads the JSONL transcript tail, which the harness documents as lagging; last_assistant_message is never used |
| F142 | medium | doc-drift | `tests/README.md:5` | tests/README.md is badly stale (6 of 19 hooks, 14 of 60 contract categories, 1 of 36 suites, Level-1 tests listed as 'future') |
| F192 | medium | security | `hooks/pre-bash-contract-guard.sh:192` | `.ship-commit-nonce` is trivially forgeable; docs and CHANGELOG call it non-forgeable — *wording corrected; the nonce remains a role-firewall sentinel* |
| H3 | medium | harness-conformance | `hooks/pre-state-transition.sh:99` | Five PreToolUse guards emit the deprecated top-level `decision:"block"` shape instead of permissionDecision:"deny" |
| H7 | medium | design-debt | `hooks/lib/detect-policy-gate-stop.sh:82` | Stop hooks ignore last_assistant_message and re-parse the JSONL transcript with brittle tail/grep assumptions |
| H16 | medium | harness-conformance | `skills/autopilot/SKILL.md:297` | Cross-wave integration assumes isolation worktrees branch from orchestrator HEAD; harness default is origin/HEAD |
| H17 | medium | harness-conformance | `skills/autopilot/SKILL.md:268` | Wave loop assumes foreground executors that inherit the Agent tool; background is the harness default and background subagents have no Agent tool |
| H19 | medium | harness-conformance | `agents/ticket-executor.md:48` | Executor artifact writes route through a symlink into the main checkout, which the harness blocks inside isolation worktrees — *documented as an open risk (needs a live wave-parallel dogfood on CC >= 2.1.232, the supported minimum)* |
| H20 | medium | harness-conformance | `skills/investigate/SKILL.md:13` | context: fork agent-backed skills run in the background by default; /scout reads /investigate's result synchronously |
| H21 | medium | design-debt | `skills/impl/SKILL.md:134` | Strategy-B claim that the Agent tool rejects a per-spawn model is stale; ac-evaluator-hi twin file and eval-panel agentType switch are removable — *claim corrected; the twin file is retained deliberately* |
| H29 | medium | harness-conformance | `skills/test/SKILL.md:18` | /test is context: fork without background: false; its body describes an orchestrator turn that does not exist |
| H36 | medium | operability | `skills/autopilot/SKILL.md:133` | Six SKILL.md files exceed the 5,000-token post-compaction re-attach; the cutoff drops the loop bodies, RE-ANCHOR checkpoints and SW-CHECKPOINT steps the Stop guards then demand — *documented in README (the plugin relies on the session-start re-injection)* |
| H43 | medium | correctness | `skills/impl/SKILL.md:162` | Merge emits `PASS_WITH_CAVEATS` but Step 16 maps only `PASS_WITH_CONCERNS`; EVAL_SCHEMA enum also lacks it |
| H44 | medium | test-gap | `tests/run-all.sh:12` | tests/test-eval-panel-merge.mjs and any script syntax gate never run: run-all.sh globs `test-*.sh` only and CI never installs node |
| H45 | medium | correctness | `skills/impl/SKILL.md:142` | Args contract mismatch: SKILL passes unused `lenses`/`ticket_dir`/`budget` and omits `accept_set_triggered_on`, which the script reads |
| H47 | medium | doc-drift | `skills/impl/SKILL.md:134` | Docs and script header still claim a per-spawn model override is rejected by the Agent JSONSchema; Workflow agent() now accepts model/effort — twin-agent workaround is avoidable |
| H49 | medium | harness-conformance | `skills/impl/SKILL.md:141` | No fallback when the Workflow tool is disabled or unavailable inside ticket-executor, yet `uc=on` × `parallel=on` is the default |
| H54 | medium | doc-drift | `tests/README.md:5` | tests/README.md hook table lists 6 of 22 hooks and a stale A-N category matrix; pre-level1-guard.sh has no test and is wired only in repo-local .claude/settings.json |
| H62 | medium | doc-drift | `skills/create-ticket/references/autopilot-policy-reference.md:19` | Documented model-resolution order is inverted (CLAUDE_CODE_SUBAGENT_MODEL is not top precedence) |
| H63 | medium | design-debt | `agents/ac-evaluator.md:141` | Strategy-B "Agent JSONSchema rejects per-spawn model" is stale; ac-evaluator-hi twin file and agentType model-switch are unnecessary — *claim corrected; the twin file is retained deliberately* |
| H68 | medium | doc-drift | `skills/create-ticket/references/autopilot-policy-reference.md:15` | `opus` pin is documented as 'the stronger model' with a hard-coded price ratio; the `fable` tier now sits above `opus` |
| F11 | low | harness-conformance | `skills/plan2doc/SKILL.md:56` | /plan2doc relies on the Agent tool's per-spawn `model` while sibling references assert the harness rejects it |
| F54 | low | correctness | `skills/impl/workflows/eval-panel.mjs:320` | Workflow prompt uses field names the evaluator does not recognise (`Self-documentation verification:`, `Eval panel:`) |
| F67 | low | doc-drift | `design-oracles/aasc-accept-set/README.md:7` | aasc-accept-set README says AASC is 'NOT yet wired into the harness' — stale since v8.5.0 |
| H6 | low | correctness | `hooks/lib/parse-state-file.sh:307` | export -f parse_ticket_statuses cannot be re-imported by child bash (heredoc inside an `if` condition) |
| H22 | low | doc-drift | `skills/create-ticket/references/autopilot-policy-reference.md:19` | Documented subagent model precedence is inverted: CLAUDE_CODE_SUBAGENT_MODEL does not override frontmatter pins |
| H33 | low | design-debt | `skills/autopilot/SKILL.md:55` | /autopilot `find` probes exit 1 on a missing backlog directory and survive only via the harness's find/grep exit-1 exception |
| H35 | low | harness-conformance | `hooks/pre-skill-contract-guard.sh:83` | pre-skill-contract-guard.sh blocks with the top-level `decision:block` shape, not the PreToolUse `hookSpecificOutput.permissionDecision` contract |
| H46 | low | doc-drift | `skills/impl/workflows/eval-panel.mjs:320` | Workflow-path spawn prompt uses field labels the evaluator contract does not recognise (`Self-documentation verification:`, `Eval panel:`) |
| H50 | low | doc-drift | `README.md:79` | 'ultracode orchestration' overloads the harness term: plugin `uc=on` neither enables nor requires Claude Code ultracode |
| H55 | low | doc-drift | `CONTRIBUTING.md:24` | CONTRIBUTING repository-structure block and dependency list omit workflows/, hooks/lib/, references/, docs/, tools/, design-oracles/ and Node |
| H65 | low | operability | `README.md:186` | Web / desktop / IDE-panel sessions cannot receive keystroke injection; docs and the failure hint do not say so |
| H70 | low | operability | `hooks/pre-level1-guard.sh:11` | pre-level1-guard denies any Bash command that merely mentions the Level-1 filenames (read-only cat/grep/sed included) |
| H71 | low | operability | `README.md:36` | No minimum Claude Code version is stated although the plugin depends on recent harness features |

### 4.2 Confirmed, deferred (follow-up tickets)

| id | severity | category | location | finding |
| --- | --- | --- | --- | --- |
| H13 | high | design-debt | `hooks/hooks.json:35` | Newer handler fields (if, async, statusMessage, timeout) unused where they would remove in-script gating |
| H61 | high | correctness | `skills/plan2doc/SKILL.md:99` | /plan2doc passes a per-spawn `model` that now overrides planner's `model: inherit`, defeating the documented Generator model policy |
| F21 | medium | design-debt | `skills/create-ticket/SKILL.md:171` | Re-running /create-ticket for policy re-propagation duplicates the ticket set instead of propagating |
| F30 | medium | doc-drift | `skills/create-ticket/references/autopilot-policy-reference.md:10` | Model-routing claims contradict each other and the agent frontmatter |
| F80 | medium | doc-drift | `docs/state-schema.md:3` | Two 'single source of truth' schemas for autopilot-state.yaml contradict each other (total_tickets, processing_order, trailing-slash ticket_dir) |
| H14 | medium | design-debt | `hooks/impl-checkpoint-guard.sh:314` | SubagentStop guards and agent_type identity rely on undocumented payload details |
| H15 | medium | doc-drift | `hooks/lib/parse-state-file.sh:11` | hooks/lib header 'Sourced by' lists are stale (removed v6 hook, non-existent planned consumers, wrong writers) |
| F25 | low | doc-drift | `skills/create-ticket/references/mode-dispatch-flows.md:98` | mode-dispatch-flows B-2 reads only `mode:` — contradicts the `chain: precedes mode:` precedence rule and defines no error for an invalid `chain:` value |
| F65 | low | doc-drift | `skills/impl/references/tautological-assertion-rules.md:138` | Hint-exemption scope is stated two contradictory ways; script applies R2/R3 despite 'skips the entire file' |
| H8 | low | operability | `.claude/settings.json:17` | Dev-repo .claude/settings.json double-registers autopilot-continue.sh on Stop alongside the plugin copy |
| H18 | low | security | `agents/ac-evaluator.md:11` | Bash(...) and shell(...) entries in agent tools: are not a tools grammar; evaluator read-only invariant is unenforced |
| H23 | low | operability | `skills/autopilot/SKILL.md:280` | Worktree cleanup tiers ignore the harness's own auto-remove, lock and periodic sweep |
| H24 | low | doc-drift | `skills/test/SKILL.md:50` | maxTurns semantics misdescribed: the harness returns a partial result, the agent does not choose a status |
| H25 | low | design-debt | `agents/ac-evaluator.md:141` | No agent frontmatter sets effort although the harness supports per-agent effort and the plugin has explicit depth tiers |
| H27 | low | design-debt | `agents/ticket-executor.md:22` | Worktree path/branch naming (agent-<id> / worktree-agent-<id>) is pinned to an undocumented platform naming scheme |
| H34 | low | security | `hooks/pre-skill-contract-guard.sh:90` | Skill-payload hooks match only the `simple-workflow:` namespaced name; a bare-name Skill call bypasses the review firewall and the auto-compact trigger, and the test pins the bypass |
| H37 | low | design-debt | `skills/brief/SKILL.md:33` | /brief loads its interview templates through an unbraced `$CLAUDE_PLUGIN_ROOT` shell variable instead of the documented substitution, and silently degrades when it is unset |
| H38 | low | design-debt | `skills/investigate/SKILL.md:15` | `model: sonnet` is declared twice for each fork path (skill frontmatter and agent frontmatter) with no test keeping them aligned |
| H51 | low | doc-drift | `skills/impl/references/ac-evaluator-orchestration.md:85` | ac-evaluator-orchestration.md never mentions the Workflow path and still scopes the 3-lens branch to `exhaustive`; meta.description says the same |
| H56 | low | harness-conformance | `.claude/settings.json:13` | Tracked .claude/settings.json duplicates the plugin's Stop hook — plugin copy runs separately, so autopilot-continue.sh fires twice when dogfooding |
| H66 | low | doc-drift | `skills/create-ticket/references/workflow-patterns.md:15` | workflow-patterns.md still advertises retired size-routing for /impl and implementer |
| H67 | low | test-gap | `tests/test-integration.sh:383` | Level-1 tests use a non-canonical `--allowed-tools=all` flag and omit `--plugin-dir`, keeping an unnecessary 'Unknown skill → SKIP' workaround |
| H69 | low | doc-drift | `skills/brief/references/phase2-dynamic-shrinkage.md:13` | Phase-2 shrinkage prose assumes a 200k Sonnet window |
| H72 | low | design-debt | `hooks/pre-askuserquestion-guard.sh:73` | AskUserQuestion guard probes an undocumented top-level `tool_input.header` before the documented `questions[].header` |
| R1 | low | test-gap | `tests/test-state-parsers.sh` (AC-8c..j), `tests/test-post-ship-state-auto-compact.sh` (AC-3) | Two assertions call `yq` directly instead of going through the three-tier helpers, so a host without mikefarah `yq` cannot run them (the hooks under test pass on the python3 / awk tiers; the GitHub `ubuntu-latest` runner ships `yq`, so CI is unaffected) |

Evidence and the proposed fix for every row live in the audit journal under the session directory; the ids are stable across this document and the CHANGELOG.

## 5. Reported but not independently verified

The adversarial verification pass was interrupted by a usage limit after 105 of 293 findings had been judged (the interrupted slices are re-runnable from the saved verification script). The remaining findings are neither confirmed nor refuted: 0 critical, 10 high, 99 medium, 79 low. The high-severity ones, several of which were fixed anyway because the evidence was self-evident, are:

| id | severity | category | location | finding | status |
| --- | --- | --- | --- | --- | --- |
| F3 | high | harness-conformance | `skills/investigate/SKILL.md:43` | /investigate and /test bodies are written in orchestrator voice although context: fork runs them AS the agent; Agent is pre-granted and Write is not | open |
| F46 | high | correctness | `skills/impl/SKILL.md:142` | Workflow path drops the deterministic `triggered-on=` accept-set list: SKILL passes `accept_set_conformance` but the script reads `accept_set_triggered_on` | fixed in v10.1.0 |
| F63 | high | correctness | `skills/impl/references/independent-oracle-harness.md:111` | Canonical Zeller re-base in the copyable oracle shape is wrong for every date | open |
| F79 | high | doc-drift | `skills/autopilot/references/state-file.md:219` | state-file.md still routes `metric-only` to the executor and claims wave-cursor fields are unread by hooks | open |
| F97 | high | correctness | `skills/ship/SKILL.md:273` | /ship and /audit source hooks/lib/audit-coverage.sh by a repo-relative path that only exists inside the plugin checkout | fixed in v10.1.0 |
| F141 | high | operability | `tests/test-helper.sh:11` | Suite (and hooks) silently require mikefarah yq v4 but detect yq by `command -v` only; a different yq flavour yields 39 spurious failures and fail-open hooks | fixed in v10.1.0 |
| F175 | high | operability | `hooks/session-start.sh:28` | User-scope install runs `git init` + initial commit in every directory a session opens | open |
| F193 | high | correctness | `skills/autopilot/SKILL.md:280` | `git worktree remove --force` makes the documented dirty-worktree safety branch unreachable; uncommitted work in a failed ticket is destroyed | fixed in v10.1.0 |
| F194 | high | design-debt | `hooks/lib/state-authority.sh:150` | HOOK_OWNED_FIELDS `.runtime_metrics` guard cannot fire in the real lost-update scenario (block-form list) | open |
| F205 | high | harness-conformance | `hooks/pre-bash-contract-guard.sh:113` | Five PreToolUse guards emit the legacy top-level `decision:"block"` shape instead of `hookSpecificOutput.permissionDecision` | fixed in v10.1.0 |

## 6. Refuted by the verifiers (22)

Listed so they are not re-reported: F153 (CHANGELOG.md), F49 (skills/impl/workflows/eval-panel.mjs), F177 (skills/autopilot/SKILL.md), H4 (hooks/autopilot-continue.sh), H9 (hooks/pre-level1-guard.sh), H30 (skills/investigate/SKILL.md), H48 (.claude-plugin/plugin.json), F6 (skills/audit/SKILL.md), F176 (hooks/pre-bash-safety.sh), H10 (hooks/session-start.sh), H11 (hooks/pre-compact-save.sh), H12 (hooks/autopilot-continue.sh), H26 (agents/implementer.md), H32 (skills/audit/SKILL.md), H39 (skills/refactor/SKILL.md), H40 (CONTRIBUTING.md), H41 (skills/audit/SKILL.md), H52 (skills/impl/SKILL.md), H53 (.claude-plugin/plugin.json), H57 (skills/impl/workflows/eval-panel.mjs), H64 (agents/ac-evaluator-hi.md), H73 (agents/implementer.md).

## 7. Method

- Sources: the tracked repository (the gitignored `.docs/` notes and any memory files are absent from a fresh clone), the official Claude Code documentation fetched on 2026-09-14, and live probes on Claude Code 2.1.270.
- Readers: 13 subsystem readers + 5 harness-conformance lenses, each returning structured findings; findings were deduplicated by file and title.
- Verification: two independent adversarial lenses per batch (reproduce-from-source; materiality against the documented contracts), a finding surviving only when neither lens refuted it; low-severity batches used the reproduce lens alone.
- Every fix in v10.1.0 is pinned by a test (`tests/`), and the whole suite, the contract tests, ShellCheck and `claude plugin validate --strict` pass on the release commit.

