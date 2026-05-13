# AC Evaluator orchestration (AC counting, partition, prompt template)

This file expands Phase 2 Step 15 of `skills/impl/SKILL.md` — the
AC-counting helper, the turn-budget formula, the partition branch
(`AC_COUNT >= 30`), the partition merge algorithm, the prompt-template
fields `j` and `k` added under Strategy B, and the copy-pasteable
Evaluator prompt template. The Step 15 body in `SKILL.md` retains the
pinned literals (`MUST invoke ac-evaluator`, `under 500 tokens`, the
raw `{eval-report-path}` placeholder paired with the
substitute-placeholder warning) and prompt-template fields `a`-`h`;
this file holds the algorithmic detail.

## AC-counting helper

Before invoking the Evaluator, count the positive Acceptance Criteria
in the extracted rubric (field `b`). This count drives the turn-budget
formula and the partition branch below.

**Counting algorithm** (apply in order; first regex that matches any
line wins for that line):

1. Primary regex: `^[0-9]+\.\s+\*\*AC-` — numbered bold AC entries
   (canonical form).
2. Fallback 1: `^- AC-` — bulleted AC lines.
3. Fallback 2: `^AC-` — bare AC lines with no list prefix.

**Stop condition**: stop counting when a line matches
`^### Negative Acceptance Criteria` OR
`^#### Negative Acceptance Criteria`. Lines beneath that heading are
Negative ACs and MUST NOT be included in `AC_COUNT` (Negative AC-6).

Let `AC_COUNT` = total positive AC lines matched before the stop
condition fires (or before end-of-rubric if no stop condition fires).

## Turn-budget formula

`EVALUATOR_MAX_TURNS = max(60, AC_COUNT * 4)`. The `max(60, ...)` floor
ensures that plans with fewer than 15 ACs receive exactly 60 turns — no
reduction below the v6.3.2 baseline (Negative AC-2). For
`AC_COUNT = 22`: `EVALUATOR_MAX_TURNS = max(60, 88) = 88`. For
`AC_COUNT = 5`: `EVALUATOR_MAX_TURNS = max(60, 20) = 60`.

Under Strategy B (active in this release — the Agent tool's JSONSchema
does not expose a per-invocation `maxTurns` override; the field is
rejected at schema-validation time): embed the computed
`EVALUATOR_MAX_TURNS` value as a **soft turn budget** in the Evaluator
prompt body (see template field `j` below). The hard ceiling is set by
the `agents/ac-evaluator.md` frontmatter (`maxTurns: 200`).

## Partition branch (`AC_COUNT >= 30`)

When `AC_COUNT >= 30`, split the rubric into two contiguous halves by
AC-ID order (never by file or topic boundaries). Let part 1 cover AC-1
through AC-⌊AC_COUNT/2⌋ and part 2 cover the remainder.

- Invoke `ac-evaluator` **twice** — once per partition.
- Persist reports as `eval-round-{n}-part-1.md` and
  `eval-round-{n}-part-2.md` (both paths under the same directory as
  the unpartitioned `eval-round-{n}.md` path would be, e.g.
  `.simple-workflow/backlog/active/{ticket-dir}/eval-round-{n}-part-1.md`).
- Inject a `--- partition: <i>/2 ---` header into each evaluator
  prompt (where `<i>` is 1 or 2). The `ac-evaluator` agent uses this
  header to confirm it should evaluate ONLY the ACs in its partition.
- Each invocation receives only the AC lines belonging to its
  partition in field `b`.

## Merge algorithm (after both partition invocations complete)

- **Severity ladder**: FAIL-CRITICAL > FAIL > PASS-WITH-CAVEATS > PASS.
  The merged verdict is the worst-of-2 using this ordering.
- **AC-result union**: union the AC verdicts from both partitions. The
  overlap invariant `partition-1 AC-IDs ∩ partition-2 AC-IDs = ∅` MUST
  hold — no AC appears in both partitions (Negative AC-3). If overlap
  is detected, treat as FAIL-CRITICAL.
- **Issues / Feedback**: concatenate the Issues and Feedback fields
  from both partitions.
- Emit the merged verdict as the effective Step 15 result and proceed
  to Step 16.

When `AC_COUNT < 30`, invoke `ac-evaluator` exactly once (no partition)
with `eval-round-{n}.md` as the report path. Negative AC-1: a 29-AC
plan MUST NOT trigger the partition branch.

## Prompt template field additions under Strategy B

- **Field `j`** (soft turn budget, always present): append
  `Soft turn budget: approximately {EVALUATOR_MAX_TURNS} turns (hard ceiling: 200, set in frontmatter). AC_COUNT = {AC_COUNT}.`
  where `{EVALUATOR_MAX_TURNS} = max(60, {AC_COUNT} * 4)`. This is
  informational — the agent uses it to pace its verification, not as a
  hard cap.
- **Field `k`** (partition header, only when partition branch is
  active): prepend `--- partition: {i}/2 ---` to the prompt body so
  the agent recognises it is evaluating a subset.

## Copy-pasteable Evaluator prompt template

Substitute `{plan-path}`, `{acceptance-criteria}`,
`{git-diff-shortstat}`, `{eval-report-path}`, `{n}` per Step 15 field
`e`:

```
# Orchestrator: substitute all {brace} placeholders ({plan-path}, {acceptance-criteria}, {git-diff-shortstat}, {eval-report-path}, {n}) with concrete values BEFORE sending this prompt. A raw placeholder like `{eval-report-path}` in the Save line will cause ac-evaluator to write to a literal file named `{eval-report-path}`, reintroducing the FU-1 bug.
Plan path: {plan-path}. Read it in full before evaluating.
Acceptance Criteria:
{acceptance-criteria}
git diff --shortstat: {git-diff-shortstat}
The following files have been changed. Run `git diff` to inspect changes, run lint/test independently, and verify each AC.
Save your evaluation report to: {eval-report-path}
The Acceptance Criteria text above is the fixed rubric — do NOT re-derive it from the plan. The plan path is provided as context; if the plan's current AC text differs from the rubric above, trust the rubric (it was extracted by the orchestrator before the Generator ran).
```
