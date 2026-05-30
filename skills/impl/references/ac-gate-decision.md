# AC Gate decision (4-way Output envelope check, IN_PROGRESS recovery)

This file expands Phase 2 Step 16 of `skills/impl/SKILL.md` — the
4-way Output envelope check (empty / file + IN_PROGRESS / ERROR- /
non-empty), the single-shot IN_PROGRESS recovery invocation template,
the partition × IN_PROGRESS recovery rules, the FAIL-CRITICAL /
autopilot-policy / FAIL / PASS-WITH-CAVEATS / PASS dispatch, and the
Step 16 `phase-state.yaml` state update block. The Step 16 body in
`SKILL.md` retains the four-way decision NAMES, the literal
`CONTRACT-VIOLATION`, the `PASS_WITH_CONCERNS` and `IN_PROGRESS` pin
tokens, and the state update block; this file holds the full
recovery-prompt and partition detail.

## Output envelope check (precedence over Status parsing) — 4-way decision

### (i) Output empty AND no file at expected path

Print
`[CONTRACT-VIOLATION] ac-evaluator Output was empty and no report was persisted; treating as FAIL-CRITICAL`
and stop. Do NOT re-invoke ac-evaluator to persist.

### (ii) Output empty AND file exists AND first `## Status:` line matches `^## Status: IN_PROGRESS$`

Single-shot recovery branch (exactly 1 recovery attempt per round per
file):

Print
`[IN_PROGRESS] ac-evaluator persisted partial state at <path>; attempting single-shot recovery`.

Invoke `ac-evaluator` exactly once more via the Agent tool using the
resumption prompt template below. This is a single-shot recovery —
do NOT retry more than once, and do NOT use a loop.

```
# RECOVERY INVOCATION — substitute all {brace} placeholders before sending.
# This is NOT the original evaluator call. A partial state file already
# exists at the path below. Read it and resume from unchecked ACs.
IN_PROGRESS file path: {eval-report-path}
Read the IN_PROGRESS file first; resume from the first AC whose
checkbox is `[ ]` (unchecked); preserve already-recorded verdicts
for `[x]` ACs — do not re-verify them.
Acceptance Criteria (fixed rubric — same as original invocation):
{acceptance-criteria}
Save the report to: {eval-report-path}
The Acceptance Criteria text above is the fixed rubric — do NOT
re-derive it from the plan. Merge new verdicts with already-recorded
`[x]` lines; do not overwrite them.
```

After the recovery invocation, re-inspect the Output envelope and the
on-disk file:

- Recovery Output non-empty AND first `## Status:` in file is a
  terminal status (PASS, FAIL, FAIL-CRITICAL, PASS-WITH-CAVEATS)
  → proceed to Status parsing (path iv).
- Recovery Output empty OR first `## Status:` in file is still
  `IN_PROGRESS` → emit
  `[CONTRACT-VIOLATION] ac-evaluator recovery invocation did not produce a terminal verdict; treating as FAIL-CRITICAL`
  and stop. Do NOT invoke a third time.

**Partition × IN_PROGRESS recovery (live behavior)**: when the Step 15
partition branch is active (`AC_COUNT >= 30`), each partition has its
own report file (`eval-round-{n}-part-1.md`,
`eval-round-{n}-part-2.md`). The single-shot IN_PROGRESS recovery
applies independently to each partition file — at most 1 recovery
invocation per partition per round. Worst-case for a 2-partition plan:
4 total invocations (2 partitions × 2 invocations each). The
single-shot cap is per file, not per round globally. Recovery paths
for `eval-round-{n}-part-1.md` and `eval-round-{n}-part-2.md` are
evaluated in sequence; the merged verdict from Step 15 is used only
after both partition files reach terminal status.

**Multi-verifier × IN_PROGRESS recovery (v8.1.0+)**: when the Step 15
high-assurance multi-verifier branch is active
(`verification_depth: exhaustive` and `AC_COUNT < 30`), each of the three
verifier reports (`eval-round-{n}-v1.md`, `-v2.md`, `-v3.md`) is an
independent file. The single-shot IN_PROGRESS recovery applies
independently to each `-v{i}.md` — at most 1 recovery invocation per
verifier file per round (worst case 6 total: 3 verifiers × 2 invocations
each). The per-file rules of branch (ii) above apply unchanged to each
`-v{i}.md`, with ONE difference in the terminal disposition: a `-v{i}.md`
that is still `IN_PROGRESS` after its single recovery attempt (or whose
recovery Output is empty) is **dropped from the `valid` set** as a
per-verifier soft failure — it does NOT stop the whole round the way a
single-evaluator `[CONTRACT-VIOLATION]` does. The quorum rule then
governs: if fewer than 2 verifiers reach a terminal verdict, the merged
result is `FAIL-CRITICAL` (insufficient independent verification). See
[ac-evaluator-orchestration.md](ac-evaluator-orchestration.md)
`## High-assurance multi-verifier branch` for the majority merge and the
`valid < 2` quorum.

### (iii) Output begins with `ERROR-` (e.g. `ERROR-WRITE-FAILED`)

Print
`[CONTRACT-VIOLATION] ac-evaluator returned ERROR-prefixed Output; treating as FAIL-CRITICAL`
and stop.

### (iv) Output non-empty AND not ERROR-prefixed

Proceed to Status parsing below (unchanged path).

## Status dispatch

- **FAIL-CRITICAL** → stop immediately. Report CRITICAL issues. Do NOT
  continue rounds.
- **Autopilot policy check for ac_eval_fail**: If
  `autopilot-policy.yaml` exists, read `gates.ac_eval_fail`:
  `on_critical: stop` is always enforced (FAIL-CRITICAL safety
  invariant); `action: retry` → continue (print
  `[AUTOPILOT-POLICY] gate=ac_eval_fail action=retry round={n}`);
  `action: stop` → stop (print
  `[AUTOPILOT-POLICY] gate=ac_eval_fail action=stop`). Else proceed
  with behavior below.
- **FAIL** → save ac-evaluator's Feedback; continue to next round
  (skip quality review this round).
- **PASS-WITH-CAVEATS** → treat as PASS; record Caveats for Phase 3
  summary ("AC passed with caveats: {caveats}"). Continue to step 17.
- **PASS** → continue to step 17.

## `phase-state.yaml` state update (Step 16)

Update `phase-state.yaml` (touch only `phases.impl.*`):

```
phases.impl.phase_sub: evaluator-complete
phases.impl.last_ac_status: {PASS|FAIL|FAIL-CRITICAL}
phases.impl.next_action: start-audit                    ← PASS / PASS-WITH-CAVEATS
                     or: start-round-{N+1}-generator   ← FAIL
                     or: stop-critical                  ← FAIL-CRITICAL (already stopped)
```
