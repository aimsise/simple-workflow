# `[AUTOPILOT-CONTEXT]` self-doc — verbatim branch text

This reference holds the verbatim text emitted by Phase 1 step 0.5 of
`skills/autopilot/SKILL.md`. The orchestrator reads
`SW_AUTO_COMPACT_ON_SHIP_MODE` from the environment and emits EXACTLY
ONE `[AUTOPILOT-CONTEXT]` block to stdout, choosing the branch that
matches the resolved mode.

## Decision logic

1. Read `SW_AUTO_COMPACT_ON_SHIP_MODE` from the environment.
2. Default to `on` when the variable is unset (autopilot context).
   This default matches `hooks/pre-next-scout-auto-compact.sh` L81
   (`MODE="${SW_AUTO_COMPACT_ON_SHIP_MODE:-on}"`).
3. Branch on the resolved value:
   - `on` → Branch A.
   - `metric-only` → Branch B.
   - `off` → Branch C.
   - Any other value (unknown) → Branch C (treated as `off`), matching
     the hook-side fallback.
4. Emit EXACTLY ONE block per pipeline run.

## Idempotency

This step is read-only and idempotent: re-runs after `/compact` re-emit
the same block. No file is written, no state is mutated. Re-emission
on resume is by design — the post-compact session must rediscover the
same context the pre-compact session had.

## Branch A: `SW_AUTO_COMPACT_ON_SHIP_MODE=on` (default in autopilot context)

```text
[AUTOPILOT-CONTEXT] auto-compact-on-ship is enabled (mode=on).
After each `/ship`, `/compact` is auto-injected at the ticket boundary
and the session resumes from `autopilot-state.yaml` via
`hooks/session-start.sh`. You do NOT need to stop preventively for
context-budget concerns; compaction is automatic at every ticket
boundary. Context-pressure response paths are codified in
`## Context-Pressure Response Paths`; the only legitimate stop is a
policy gate with `action: stop`.
```

## Branch B: `SW_AUTO_COMPACT_ON_SHIP_MODE=metric-only`

```text
[AUTOPILOT-CONTEXT] auto-compact-on-ship is in metric-only mode
(mode=metric-only). The hook will LOG the would-be `/compact`
injection but will NOT actually inject. Context-pressure handling
falls back to `hooks/pre-compact-save.sh` (the harness-level
auto-compaction at session-compaction boundaries). You still MUST NOT
issue `AskUserQuestion` for context-budget reasons; context-pressure
response paths are codified in `## Context-Pressure Response Paths`.
```

## Branch C: `SW_AUTO_COMPACT_ON_SHIP_MODE=off`

```text
[AUTOPILOT-CONTEXT] auto-compact-on-ship is disabled (mode=off).
No `/compact` will be injected at ticket boundaries. Context-pressure
handling falls back to `hooks/pre-compact-save.sh` (harness-level
auto-compaction) or `unexpected_error.action: stop` per policy. You
still MUST NOT issue `AskUserQuestion` for context-budget reasons;
context-pressure response paths are codified in
`## Context-Pressure Response Paths`.
```
