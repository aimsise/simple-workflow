# Manual Bash Fallback Reference

Detailed contract for the orchestrator-level **Manual Bash Fallback**
discipline. The SKILL.md summarises the rule; this file holds the
verbatim forbidden-rationale list, prohibited destructive operations,
log schema, and the runtime enforcement surfaces.

## Definition

A **Manual Bash Fallback** is an orchestrator-level `Bash` call used to
recover from an anomaly that a subagent could not handle. It is a last
resort. Every legitimate Manual Bash Fallback MUST be logged immediately
in the active `autopilot-state.yaml` `manual_bash_fallbacks[]` list (see
schema below) and replayed verbatim in `autopilot-log.md` on
finalisation.

## Context pressure is NOT an anomaly

Context window / context budget pressure is **NEVER** an anomaly that
justifies a Manual Bash Fallback. Context pressure is a normal
operating condition with two designed responses
(see `## Context-Pressure Response Paths` in the SKILL.md):
auto-compaction via the PreCompact hook, or a
`unexpected_error.action: stop` policy-gate stop. The orchestrator MUST
NOT bypass `/scout` / `/impl` / `/ship` Skill invocations to "save
tokens" or "fit within the context window".

The following verbatim rationale tokens are forbidden in
`manual_bash_fallbacks[].reason` (case-insensitive) — recording any of
them is a contract violation flagged by
`hooks/lib/forbidden-rationale-patterns.sh`:

- `context budget`
- `context window`
- `context pressure`
- `context exhausted`
- `context occupancy`
- `token budget`
- `running out of context`

Any paraphrase that conveys the same meaning (e.g. "to save tokens", "to
fit within the context window") is also rejected.

## MUST NOT patterns

The orchestrator MUST NOT treat the following as Manual Bash Fallback:

- **Subagent response truncation** (timeout / token limit) for the
  Generator, Evaluator, or any other subagent. These MUST trigger the
  configured retry gate (`ac_eval_fail`, `evaluator_dry_run_fail`,
  etc.) and re-spawn the subagent, NOT be covered by an
  orchestrator-run shadow execution.
- **Subagent failure** where the subagent was the intended executor.
  Re-spawn the subagent with the failure context in its prompt.
- **Context pressure rationale** as a reason for orchestrator-level
  Bash that bypasses a Skill invocation. Context pressure is not an
  anomaly: the canonical responses are auto-compaction (PreCompact
  hook) and `unexpected_error.action: stop` (policy-gate stop).

## Destructive-operations prohibition

The orchestrator MUST NOT use destructive operations as error shortcuts.
The following literal commands are prohibited without explicit
justification:

- `rm -rf`
- `rm -f .git/index`
- `git reset --hard`
- `git clean -f`
- `git checkout .`
- `git branch -D` (of an active branch)

If a tool's error output names a non-destructive flag (e.g.
`use -f to force removal`, `use --allow-empty-message`), apply that
flag first. Do not jump to destructive alternatives. Before any
destructive call, write the reasoning into `autopilot-state.yaml`
`manual_bash_fallbacks[]` and prefer an interactive confirmation when
the autopilot is in a resumable state.

## `manual_bash_fallbacks:` log schema

Every Manual Bash Fallback MUST be appended **immediately** to the
active parent dir's `autopilot-state.yaml`:

```yaml
manual_bash_fallbacks:
  - timestamp: "<ISO-8601 UTC>"
    command: "<command verbatim>"
    reason: "<why this fell outside the subagent contract>"
    exit_code: <int>
    destructive: <true|false>
```

Field reference:

- `timestamp` — ISO-8601 UTC, generated via
  `date -u +%Y-%m-%dT%H:%M:%SZ`.
- `command` — the Bash command verbatim.
- `reason` — free-form prose explaining why the fallback was necessary;
  MUST NOT match any forbidden-rationale pattern above.
- `exit_code` — integer exit code of the command.
- `destructive` — `true` if the command was a destructive operation
  (see the prohibition list); `false` otherwise.

On finalisation (when writing `autopilot-log.md`), the
`Manual Bash Fallbacks` section MUST replay this list verbatim.
"No manual bash fallbacks" is valid ONLY when `manual_bash_fallbacks`
is empty or absent. When the state file recorded fallbacks, the log
MUST NOT emit an empty `Manual Bash Fallbacks: none` line — silent
drops are a contract violation.

## Runtime enforcement

The Manual Bash Fallback discipline is enforced at runtime by two
hooks:

- `hooks/pre-bash-contract-guard.sh` — a `PreToolUse:Bash` hook (the
  `pre-bash-contract` guard) that intercepts violation attempts inside
  an autopilot context and emits `decision: block` before the tool
  call fires. It rejects (1) appends to `manual_bash_fallbacks[]`
  whose `reason` matches any pattern in
  `hooks/lib/forbidden-rationale-patterns.sh`
  (`context_budget_fallback`), and (2) direct `git commit` invocations
  when no per-ticket `phases.ship.status: in_progress` is present
  (`unauthorized_ship_inline`, i.e. a `/ship` Skill bypass).
- `hooks/lib/forbidden-rationale-patterns.sh` — the canonical
  forbidden-rationale pattern list referenced by the
  `pre-bash-contract` guard and Phase B post-hoc audit.

The hook has no environment-variable escape hatch — recovery is via
auto-compaction or `unexpected_error.action: stop`, not a bypass flag.

## Forbidden third paths under context pressure

Context window / context budget / context pressure / context exhaustion /
context occupancy are not Manual Bash Fallback rationales — they are
normal operating conditions with two canonical responses defined in the
SKILL.md `## Context-Pressure Response Paths` section
(auto-compaction via PreCompact hook, or `unexpected_error.action: stop`).

The following third paths are all contract violations:

- **NEVER** invoke `AskUserQuestion` as a context-pressure escalation
  path. Stop hooks cannot intercept it, so the SKILL-level prohibition
  is the sole enforcement.
- **NEVER** log context-pressure rationales (`context budget`,
  `context window`, `context pressure`, `context exhausted`,
  `context occupancy`, `token budget`, `running out of context`) as
  `manual_bash_fallbacks[].reason` — the forbidden-rationale list
  above rejects them.
- **NEVER** bypass `/scout`, `/impl`, or `/ship` Skill invocations to
  conserve context. The mandatory chain is the contract surface;
  shrinking it shrinks the contract.

Acceptable third paths: nothing. The canonical two are exhaustive.
