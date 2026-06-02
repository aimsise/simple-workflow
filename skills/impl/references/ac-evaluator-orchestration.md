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

- Invoke `simple-workflow:ac-evaluator` **twice** — once per partition.
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

When `AC_COUNT < 30`, invoke `simple-workflow:ac-evaluator` exactly once (no partition)
with `eval-round-{n}.md` as the report path — **unless** the
high-assurance multi-verifier branch below is active. Negative AC-1: a
29-AC plan MUST NOT trigger the partition branch.

## High-assurance multi-verifier branch (`verification_depth: exhaustive`)

When `/impl` Step 3a resolved `VERIFICATION_DEPTH == exhaustive` **and**
`AC_COUNT < 30` (partition takes precedence over multi-verifier — see
[verification-depth.md](verification-depth.md) "Composition with the
`AC_COUNT >= 30` partition branch"), Step 15 spawns **three independent
`simple-workflow:ac-evaluator` invocations** over the SAME rubric (field `b`) and the SAME
`git diff` instead of one. The three runs are independent — each forms its
own verdict with no visibility into the others (the firewall in
`skills/impl/SKILL.md` line 141 — "Prompt must NOT include Generator's
return value" — applies unchanged, and no verifier sees a sibling's
return).

### Lens directives (field `l`)

Each invocation appends exactly one lens directive so the three runs gather
evidence through DIFFERENT, INDEPENDENT channels (evidence-mode-diverse
verification beats three lenses that read the same `git diff` and run the
same tests — see `## Independent-evidence channels (all evaluator modes)`
below). The three lenses map to the evidence channels defined in
[`evidence-channels.md`](evidence-channels.md): V1 → EC-RUNTIME (real public
boundary), V2 → EC-DIFFERENTIAL or EC-PROPERTY (reference cross-check or
seeded property sweep), V3 → EC-ORACLE + targeted fuzz (independent oracle
on the raw value + a parse-accepted-overflow vector). Substitute `{i}` ∈
{1,2,3} and persist to `eval-round-{n}-v{i}.md`:

- **V1 — runtime / black-box lens (EC-RUNTIME)**: `--- lens: 1/3 runtime/EC-RUNTIME --- Gather evidence through the REAL public / protocol boundary only: drive the actual CLI, the actual MCP Client over a transport, or the exported public API — never internal handlers reached by reflection or imports the real consumer cannot use. A green project suite is necessary but NOT sufficient: confirm the AC's behaviour is observable at the public boundary, and FAIL any AC whose only evidence is a white-box test that bypasses the schema / serialization / transport layer where real consumers fail.`
- **V2 — differential / property lens (EC-DIFFERENTIAL or EC-PROPERTY)**: `--- lens: 2/3 differential-or-property/EC-DIFFERENTIAL,EC-PROPERTY --- Establish evidence INDEPENDENT of the implementation's own output. When a reference implementation of the same contract exists, cross-check the implementation against it (EC-DIFFERENTIAL). Otherwise drive a seeded random sweep over the input space (fixed seed → reproducible) and assert the invariants the output must hold — monotonicity, symmetry, idempotence, round-trip, range/gamut containment (EC-PROPERTY). FAIL an AC whose tests assert only a handful of fixed points the code itself could have produced, with no reference cross-check and no property coverage across the distribution.`
- **V3 — independent-oracle / targeted-fuzz lens (EC-ORACLE + adversarial)**: `--- lens: 3/3 oracle-or-fuzz/EC-ORACLE --- For any computational AC, independently derive at least one expected value from an oracle that does NOT share the implementation's core (a third-party reference library, a published formula applied from first principles, or a cited hand-computed constant) and compare against the implementation's RAW, pre-rounding output with an explicit tolerance — this is the Gate 7 oracle probe, applied with full force. Additionally fuzz at least one parse-accepted-then-overflows vector (a value the parser ACCEPTS that yields a non-finite / out-of-range intermediate, e.g. `oklch(0.5 1e400 30)`) through the tool under a time-bounded watchdog; FAIL if it hangs or returns a non-error success carrying null / NaN fields. A scratch oracle probe under .simple-workflow/scratch/ is permitted.`

The lens header mirrors the `--- partition: <i>/2 ---` convention so the
agent recognises its role; the `ac-evaluator` body documents the three
lenses under `## Verification Lens (high-assurance handoff)`. All other
fields (`a`-`h`, `j`) are identical across the three spawns; field `k`
(partition) is absent here. The soft turn budget (field `j`) is computed
once from the full `AC_COUNT` and passed to all three.

**Evaluator model in the multi-verifier branch (M5, v8.3.0+)**: `exhaustive` tier
resolves `EVALUATOR_MODEL == opus` at Step 3a, so all three lens spawns use the opus
agent file `simple-workflow:ac-evaluator-hi` (the per-spawn `model:` override is rejected
by the Agent JSONSchema — the same Strategy-B limitation as the soft turn budget above;
the model is therefore selected by which agent file is spawned, never by a per-invocation
field). The lens directives, the soft turn budget (field `j`), and the majority merge are
otherwise unchanged; `ac-evaluator-hi.md` is byte-identical to `ac-evaluator.md` except
its `name:` and `model:` lines, so it recognises the `--- lens: <i>/3 ---` header and
applies the assigned lens identically.

### Majority merge (after all three return)

Run the Step 16 four-way output-envelope check (empty / file+IN_PROGRESS /
ERROR- / non-empty) on **each** of the three returns independently —
including the single-shot IN_PROGRESS recovery (at most one recovery
invocation per `-v{i}.md` file per round; see
[ac-gate-decision.md](ac-gate-decision.md)
`## Multi-verifier × IN_PROGRESS recovery`). Drop any verifier whose
**final** envelope is a hard `[CONTRACT-VIOLATION]` (empty + no file,
`Output` begins `ERROR-`, or still `IN_PROGRESS` after its one recovery
attempt — a per-verifier soft failure, not a whole-round stop). Let
`valid` = the surviving verifiers.

- **Quorum**: if `valid < 2`, the merged result is **FAIL-CRITICAL**
  (insufficient independent verification — never silently pass on a single
  surviving verifier). Record which verifiers were dropped and why.
- **Per-AC verdict** over the `valid` set:
  - **CRITICAL is not voted away**: if **any one** valid verifier marks an
    AC `FAIL-CRITICAL` (a [CRITICAL] issue — security, data-loss, auth
    bypass), the merged AC is `FAIL-CRITICAL`. Security findings survive a
    minority.
  - **Non-critical FAIL needs a majority**: an AC is merged `FAIL` when
    **≥2** valid verifiers fail it (non-critically). A lone non-critical
    FAIL against ≥2 PASS is merged `PASS` but its Issues/Feedback are
    retained for the round's feedback trail.
  - Else the AC is `PASS` (or `PASS-WITH-CAVEATS` when ≥2 valid verifiers
    are `PASS-WITH-CAVEATS`; a single caveat is recorded but does not
    downgrade a majority `PASS`).
- **Overall Status**: the worst merged per-AC verdict on the severity
  ladder `FAIL-CRITICAL > FAIL > PASS-WITH-CAVEATS > PASS`.
- **Issues / Feedback**: concatenate across the three reports, tagging each
  line with its source verifier (`[v1]` / `[v2]` / `[v3]`) so the next
  round's Generator sees which lens flagged what.

Emit the merged verdict as the effective Step 15 result and proceed to
Step 16. `[AC-EVAL-MAJORITY] acs={AC_COUNT} valid={valid}/3 merged={Status}`
is logged to stderr for auditability. The three `eval-round-{n}-v{i}.md`
files satisfy the `eval-round-*.md` artifact-presence glob exactly as the
partition `-part-{i}.md` files do; no combined `eval-round-{n}.md` is
written (the orchestrator renders no AC verdict to disk — see
`skills/impl/SKILL.md` line 40).

## Independent-evidence channels (all evaluator modes)

Independent of the verifier count, every `ac-evaluator` invocation — single,
partitioned, or 3-lens — MUST establish that each behavioral AC is proven by
at least one evidence channel independent of the implementation's own
internals, per `agents/ac-evaluator.md` and Gate 8 in
`skills/create-ticket/references/ac-quality-criteria.md`. The five channels
(EC-ORACLE / EC-DIFFERENTIAL / EC-PROPERTY / EC-RUNTIME / EC-STATIC) are
defined in [`evidence-channels.md`](evidence-channels.md). The orchestrator
resolves the `evidence_floor` at `/impl` Step 3a (standard = EC-STATIC + the
AC's natural channel; thorough = +1 independent channel; exhaustive = >=2
independent channels — see
[verification-depth.md](verification-depth.md) effects ladder) and inlines it
into every spawn prompt as the field `Evidence floor: {tier:channels}` so the
evaluator reads the floor from the prompt (like the `## Bound capabilities
(per AC)` handoff), not from disk. The ticket-wide kill switch is
`constraints.independent_evidence: off` (absent / unknown → `auto`, active),
which the orchestrator resolves at Step 3a; when `off`, the evidence-floor
requirement is dropped and the evaluator falls back to its pre-v8.3.0 path
(project tests + code inspection + the always-on Gate 7 oracle check when
`oracle_verification` is active).

### Oracle independence (computational ACs — the EC-ORACLE sub-case)

Gate 7 is the strongest independent-evidence sub-case, scoped to computational
ACs (PASS/FAIL hinges on a computed numeric/algorithmic value).
Independent of the verifier count, every `ac-evaluator` invocation — single,
partitioned, or 3-lens — MUST apply the oracle-independence requirement in
`agents/ac-evaluator.md` `## Oracle Independence (computational ACs)` to any
**computational AC** (one whose PASS/FAIL hinges on a computed
numeric/algorithmic value): derive ≥1 expected value from an oracle that does
not share the implementation's core and compare against the implementation's
RAW (pre-rounding) output with an explicit tolerance — a green project suite is
necessary but not sufficient. A throwaway oracle probe under the gitignored
`.simple-workflow/scratch/` directory is permitted.

Under M1 (v8.3.0+) the three multi-verifier lenses are EVIDENCE-MODE-diverse,
not merely attitude-diverse: V1 exercises the real public boundary
(EC-RUNTIME), V2 cross-checks against a reference impl or a seeded property
sweep (EC-DIFFERENTIAL / EC-PROPERTY), and V3 applies an independent oracle on
the raw value plus a parse-accepted-overflow fuzz vector (EC-ORACLE). Because
the lenses now draw on DIFFERENT, INDEPENDENT evidence channels, they no
longer share the single-source blind spot that the pre-M1 attitude-only
lenses did — a test that re-measures with the code's own rounded value is
caught by V3's oracle and a white-box test that bypasses the transport is
caught by V1's public-boundary requirement. The oracle check remains MANDATORY
for every computational AC in single-verifier (`standard`) mode too — M1 does
NOT gate evidence independence on the `exhaustive` tier; the `evidence_floor`
mandates the AC's natural independent channel even at `standard`, and the
full multi-channel fan-out only at `exhaustive`. The ticket-wide
kill switch is `constraints.oracle_verification: off` (absent / unknown →
`auto`, active); the orchestrator resolves it at `/impl` Step 3a and inlines it
into every `ac-evaluator` spawn prompt as the field `Oracle verification:
{auto|off}`, so the evaluator reads the switch from the prompt (like the
`## Bound capabilities (per AC)` handoff), not from disk.

## Prompt template field additions under Strategy B

- **Field `j`** (soft turn budget, always present): append
  `Soft turn budget: approximately {EVALUATOR_MAX_TURNS} turns (hard ceiling: 200, set in frontmatter). AC_COUNT = {AC_COUNT}.`
  where `{EVALUATOR_MAX_TURNS} = max(60, {AC_COUNT} * 4)`. This is
  informational — the agent uses it to pace its verification, not as a
  hard cap.
- **Field `k`** (partition header, only when partition branch is
  active): prepend `--- partition: {i}/2 ---` to the prompt body so
  the agent recognises it is evaluating a subset.
- **Field `l`** (lens directive, only when the high-assurance
  multi-verifier branch is active — `verification_depth: exhaustive` and
  `AC_COUNT < 30`): prepend the `--- lens: {i}/3 {name} ---` directive for
  verifier `i` (the three verbatim directives are listed under
  `## High-assurance multi-verifier branch` above) so the agent applies
  the assigned EC-RUNTIME / EC-DIFFERENTIAL-or-EC-PROPERTY / EC-ORACLE evidence-mode lens.
  Fields `k` and `l` are mutually exclusive (partition wins).

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
