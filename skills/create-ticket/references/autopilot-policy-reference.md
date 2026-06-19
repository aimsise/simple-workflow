# `autopilot-policy.yaml` — Knob reference

This document catalogs the per-ticket knobs that individual skills read from
`{ticket-dir}/autopilot-policy.yaml`. The full policy schema (gates, retry
limits, etc.) is documented in `.simple-workflow/docs/plans/` — this page lists only the
fields that orchestrator skills consult directly outside the gate machinery.

## Generator model policy

simple-workflow does not size-route the generation-side model. The model each
generation-side agent runs on is fixed in its agent-file frontmatter:

| Agent | `model:` | Rationale |
|---|---|---|
| `agents/implementer.md` | `opus` (always) | High-volume work where the retry economy of the stronger model beats size-routing: at the current price ratio (Opus ≈ 1.67× Sonnet per 1M tokens) a single extra evaluation round on a downgraded generator erases the routing saving, so opus is the cost-rational default. |
| `agents/planner.md` | `inherit` | Small-output, high-leverage step — a planning error loses the whole implement + evaluate round. Inheriting the session model lifts the planning ceiling to whatever model the session runs (raising the bar on newest model families). |
| `agents/decomposer.md` | `inherit` | Same shape — a decomposition error is lost per ticket. Inherits the session model. |

`inherit` resolves to the session model by default. The resolution order is
`CLAUDE_CODE_SUBAGENT_MODEL` env var > a per-invocation override passed by the
caller > the agent frontmatter > the session model. To force the whole
generation + verification fleet onto one model regardless of these per-agent
pins, set `CLAUDE_CODE_SUBAGENT_MODEL` in the environment before launching.

The evaluation-side model allocation (sonnet by default, opus for
`criticality == critical` or the `exhaustive` tier via the byte-identical
`agents/ac-evaluator-hi.md` sibling) is described in
[`../../impl/references/verification-depth.md`](../../impl/references/verification-depth.md)
`## Criticality scalar` / `## Effects ladder` and is unaffected by this policy.

> **Migration note** — the per-ticket `constraints` knob that used to
> size-route the Generator model (documented in this section in earlier
> versions) was **removed**; the Generator now always runs on opus per the
> policy above. If an older `autopilot-policy.yaml` still carries that routing
> field, it is now an unknown key with no consumer and is silently ignored — a
> harmless no-op, so no migration action is required.

## `constraints.verification_depth`

**Consumed by**: `/impl` (round-cap resolution step 1a, multi-verifier
gate step 15, `/audit` depth handoff step 17).

**Accepted values**: `auto`, `standard`, `thorough`, `exhaustive`, `off`.

**Default** (field absent OR policy file absent): `auto`.

**Effect**: scales verification depth by a tier derived from the ticket
Size (S/M/L/XL) and the policy `risk_tolerance`. The full derivation
matrix, the per-tier effects ladder, the `rounds=N` precedence
interaction, the manual-flow fallback, and the composition with the
`AC_COUNT >= 30` partition branch are documented in
[`skills/impl/references/verification-depth.md`](../../impl/references/verification-depth.md).
Summary of the resolved tiers:

| Tier | GE `max_rounds` bonus | `/audit` third-pass | Step 15 evaluators |
|---|---|---|---|
| `standard` | +0 | conditional (existing T-A..T-E) | 1 (single, current behaviour) |
| `thorough` | +3 | forced (trigger T-F) | 1 |
| `exhaustive` | +6 | forced (trigger T-F) | 3 (evidence-mode-diverse majority) |

- `auto` (default): resolve the tier from `Size x risk_tolerance` per the
  matrix in `verification-depth.md`. For the common S/M conservative/moderate
  ticket the tier is `standard`, so `auto` is byte-identical to the
  pre-v8.1.0 behaviour; only L/XL or `aggressive` tickets deepen.
- `standard` / `thorough` / `exhaustive`: force that tier regardless of Size.
- `off`: disable the feature entirely — base `max_total_rounds`, single
  evaluator, no forced third-pass (the exact pre-v8.1.0 contract). Use this as
  the per-brief kill switch when the deeper tiers are not wanted.

The `max_rounds` bonus is **not** applied when an explicit `rounds=N`
argument is supplied to `/impl` (the user-specified cap is authoritative);
see `skills/impl/references/round-cap-parser.md`.

## `constraints.irreversibility_floor`

**Consumed by**: `/impl` (Step 3a criticality resolver — the M5 irreversibility axis of the criticality floor).

**Accepted values**: `auto`, `off`.

**Default** (field absent OR policy file absent OR unknown value): `auto` (fail-safe to active).

**Effect**: when `auto`, the M5 (v8.3.0+) IRREVERSIBILITY axis is active — an AC that verifies an irreversible real-world side-effect (persistent data writes, non-idempotent network mutation, money movement, destructive ops, or external-system calls that cannot be rolled back) floors `criticality` at `critical` even on an `S` ticket, which in turn raises the depth tier to at least `thorough`, bumps the evaluator model to opus (via the `ac-evaluator-hi` agent file), and sets the red-team budget to full (the latter consumed by M2 from v8.5.0). When `off`, ONLY the irreversibility axis is removed — the critical-domain computational floor (`constraints.oracle_verification`) and the matrix depth scaling (`constraints.verification_depth`) are unaffected. The full axis, cue list, evaluator-model column, and red-team-budget column live in [`../../impl/references/verification-depth.md`](../../impl/references/verification-depth.md) `## Criticality scalar` / `## Criticality floor` / `## Effects ladder`. This is the per-brief kill switch for the irreversibility axis alone; use it when a brief's tickets routinely touch irreversible systems but the deeper verification + opus evaluator is unwanted.

## `constraints.oracle_verification`

**Consumed by**: `/impl` (Step 3a criticality floor; `ac-evaluator`
oracle-independence enforcement at Step 15), the `planner` Gate 7 self-audit,
and the `ticket-evaluator` Gate 7 grading.

**Accepted values**: `auto`, `off`.

**Default** (field absent OR policy file absent OR unknown value): `auto`
(fail-safe to active).

**Effect**: when `auto`, two v8.2.0 behaviours are active — (1) **Gate 7 oracle
independence**: every computational AC (PASS/FAIL hinges on a computed
numeric/algorithmic value) must name an oracle independent of the implementation
and be verified on the raw, pre-rounding value with an explicit tolerance
(authoring-time gate in
[`ac-quality-criteria.md`](ac-quality-criteria.md); verifier-side enforcement in
`agents/ac-evaluator.md` `## Oracle Independence (computational ACs)`); and
(2) the **criticality floor** in
[`../../impl/references/verification-depth.md`](../../impl/references/verification-depth.md)
raises the resolved depth tier to at least `thorough` for a computational AC in
a critical domain (accessibility / security / money / data-integrity /
standard-compliance). When `off`, both are disabled ticket-wide: computational ACs are graded `n/a`
for Gate 7 and verified by the project tests + code-inspection path, and the
criticality floor does not fire. NOTE: `off` restores the pre-v8.2.0 RUNTIME
oracle path, NOT byte-identical pre-v8.2.0 behaviour for a freshly written test —
the always-on tautological rule R4 (`tautological-assertion-rules.md`) and the
positive test-authoring rubric carry no kill switch (like R1-R3) and still
reject a newly authored / modified circular test even under `off`.
This is the per-brief kill switch for the oracle-independence feature line; it
is independent of `constraints.verification_depth` (which scales matrix depth).
Use `off` only when the domain genuinely has no oracle and the deeper
verification is unwanted.

## `constraints.independent_evidence`

**Consumed by**: `/impl` (Step 3a `evidence_floor` resolution; `ac-evaluator` Gate 8
enforcement at Step 15), the `planner` Gate 8 self-audit, and the `ticket-evaluator`
Gate 8 grading.

**Accepted values**: `auto`, `off`.

**Default** (field absent OR policy file absent OR unknown value): `auto` (fail-safe to
active).

**Effect**: when `auto`, **Gate 8 independent evidence** (M1, v8.3.0+) is active — every
behavioral AC (PASS/FAIL hinges on observable runtime behaviour) must name at least one
evidence channel independent of the implementation's own internals (EC-ORACLE /
EC-DIFFERENTIAL / EC-PROPERTY / EC-RUNTIME per
[`../../impl/references/evidence-channels.md`](../../impl/references/evidence-channels.md)),
OR be rewritten as a structural AC (EC-STATIC). The resolved `evidence_floor` (effects
ladder in
[`../../impl/references/verification-depth.md`](../../impl/references/verification-depth.md))
sets how many independent channels are MANDATORY as `max(tier floor, AC-shape floor)`
(M3, v8.4.0+): the **tier floor** is `standard` = EC-STATIC + the AC's natural channel,
`thorough` = +1 independent channel, `exhaustive` = >=2; the Size-independent **AC-shape
floor** raises any ticket carrying a behavioral AC to `+1-independent` even at `standard`
(a structural-only ticket stays at EC-STATIC + natural — byte-identical to pre-v8.3.0).
When `off`, Gate 8 is
graded `n/a` ticket-wide and the evidence-floor requirement is dropped (the `ac-evaluator`
falls back to its pre-v8.3.0 path); the always-on Gate 7 oracle check for computational
ACs is governed separately by `constraints.oracle_verification`. This is the per-brief
kill switch for the Gate 8 / independent-evidence feature line; it is independent of
`constraints.oracle_verification` (the EC-ORACLE sub-case) and
`constraints.verification_depth` (which scales tier/depth).

## `constraints.failure_class_coverage`

**Consumed by**: the `planner` Gate 9 self-audit (Pre-emit Self-Audit step 10) and
the `ticket-evaluator` Gate 9 grading. (Authoring-side only — Gate 9 ENUMERATES
which Scope-touched external boundaries need an AC; it has no `/impl` /
`ac-evaluator` consumer, since Gate 7 / Gate 8 GRADE the resulting ACs at
verification time.)

**Accepted values**: `auto`, `off`.

**Default** (field absent OR policy file absent OR unknown value): `auto`
(fail-safe to active).

**Effect**: when `auto`, **Gate 9 failure-class coverage** (v8.4.0+) is active —
for each external boundary the ticket's `### Scope` touches (public / exported
function, CLI subcommand, endpoint, exported API symbol, file-format /
wire-format, or parser; and any `>=2`-peer sibling set), the planner MUST emit the
`#### Failure-Class Coverage (Gate 9)` matrix whose four rows (R1 FULL-DOMAIN
INVARIANT, R2 HOSTILE + BOUNDED TERMINATION + RESOURCE-CAP, R3
DESCRIPTION-MATCHES-BEHAVIOR, R4 DOC/INTERFACE TRUTHFULNESS) each resolve to >=1 AC
OR a one-line `n/a` justification, and the `ticket-evaluator` FAILs a boundary
with a blank (unresolved) row. When `off`, Gate 9 is graded `n/a` ticket-wide and
the matrix is not required (restores the pre-v8.4.0 feature-driven AC derivation
— the byte-for-byte revert). A ticket that touches no external boundary
(internal-helper-only) is `n/a` for Gate 9 regardless of this field
(routine-ticket flood prevention). This is the per-brief kill switch for the
failure-class-coverage feature line; it is independent of
`constraints.oracle_verification` (Gate 7), `constraints.independent_evidence`
(Gate 8), and `constraints.eval_panel` (the failure-class eval panel).

## `constraints.peer_uniformity`

**Consumed by**: the `planner` Gate 10 self-audit (Pre-emit Self-Audit step 11) and
the `ticket-evaluator` Gate 10 grading. (Authoring-side only — Gate 10 ENUMERATES
whether a `>=2`-peer set needs a unified-convention AC; its diff-time grader is the
existing `ac-evaluator` **L-UNIFORMITY** failure-class lens, governed separately by
`constraints.eval_panel`, so Gate 10 itself has no distinct `/impl` consumer.)

**Accepted values**: `auto`, `off`.

**Default** (field absent OR policy file absent OR unknown value): `auto`
(fail-safe to active).

**Effect**: when `auto`, **Gate 10 peer-set uniformity** (v8.4.0+) is active — when
the ticket's `### Scope` creates a `>=2`-peer set (a family of analogous sibling
units in one category — peer tools / endpoints / subcommands / exported functions
sharing an output surface), the planner MUST assert `>=1` **UNIFIED convention** AC
over the set (single error convention / single success-envelope shape / single
vocabulary per concept / single wrapper for repeated boilerplate, mechanically
grep/AST-verifiable across every peer) OR record a one-line `n/a` justification
under the `#### Peer-Set Uniformity (Gate 10)` scaffold, and the `ticket-evaluator`
FAILs a peer set with an unresolved row. When `off`, Gate 10 is graded `n/a`
ticket-wide and no unified AC is required (restores the pre-Gate-10 behaviour where
cross-unit output uniformity was unenforced — the byte-for-byte revert). A ticket
whose Scope creates fewer than 2 peers is `n/a` for Gate 10 regardless of this
field. This is the per-brief kill switch for the peer-uniformity feature line; it
is independent of `constraints.oracle_verification` (Gate 7, incl. its
sibling-INPUT-guard), `constraints.independent_evidence` (Gate 8),
`constraints.failure_class_coverage` (Gate 9), and `constraints.eval_panel` (the
failure-class eval panel whose L-UNIFORMITY lens is the diff-time grader).

## `constraints.eval_panel`

**Consumed by**: `/impl` (Step 3a `EVAL_PANEL` resolution; the `ac-evaluator` /
`ac-evaluator-hi` per-ticket `[EVAL-PANEL]` panel emit at Step 15).

**Accepted values**: `auto`, `on`, `off`.

**Default** (field absent OR policy file absent OR unknown value): `auto`
(fail-safe to active).

**Effect**: when `auto` or `on`, the **failure-class eval panel** (M8, v8.4.0+)
is active — the `ac-evaluator` grades through a fixed failure-class lens set
(L-CORRECTNESS plus >=1 more lens at `standard`, the full five-lens fan-out at
`exhaustive`) instead of a single all-purpose pass, and after every AC is
verdicted it emits one ticket-level `[EVAL-PANEL] lenses={comma-list}
mode={single|exhaustive}` line to stderr recording which lenses ran. `auto`
activates the panel for a ticket touching `>=2` source units OR carrying `>=1`
behavioral AC (a trivial single-unit structural-only ticket stays a single
all-purpose pass); `on` forces it regardless of size / AC shape. The orchestrator
resolves the value at `/impl` Step 3a (emitting `[EVAL-PANEL-MODE] ...`) and
inlines it into the Evaluator spawn prompt as field `m` (the `--- panel: ... ---`
directive), so the evaluator reads the switch from the prompt, not from disk.
When `off`, the panel is disabled, the `--- panel: ---` directive and the
`[EVAL-PANEL]` line are dropped, and the evaluator runs the prior single
all-purpose pass — the byte-for-byte revert to pre-v8.4.0. NOTE: `off` drops ONLY
the panel; the per-AC `[ORACLE-AUDIT]` line is unconditional (governed by no kill
switch) and still emits, as do the always-on Gate 7 oracle check and the R4
tautological-assertion static rule. This is the per-brief kill switch for the
failure-class eval panel; it is independent of `constraints.independent_evidence`,
`constraints.oracle_verification`, `constraints.verification_depth`, and
`constraints.failure_class_coverage` (Gate 9, the authoring-side sibling).

## `constraints.refute_merge`

**Consumed by**: `/impl` (Step 3a `REFUTE_MERGE` resolution; the Step 15
`exhaustive` multi-verifier merge).

**Accepted values**: `auto`, `on`, `off`.

**Default** (field absent OR policy file absent OR unknown value): `auto`
(fail-safe to active).

**Effect**: when `auto` or `on`, the **refute-then-synthesize merge** (v8.4.0+)
is in force for the `exhaustive` 3-spawn multi-verifier branch. A non-critical
`FAIL` raised by any one valid verifier merges `FAIL` UNLESS every other valid
verifier refutes it — i.e. that verifier independently rendered `PASS` /
`PASS-WITH-CAVEATS` on the SAME AC (its own independent-channel evidence did not
surface the failure); silence / not-evaluated / dropped is NOT refutation. A lone
reproducing non-critical FAIL therefore survives instead of being demoted to
`PASS`, closing the prior gap where a real defect one verifier caught was silently
dropped. The orchestrator resolves the value at `/impl` Step 3a and logs
`[AC-EVAL-REFUTE-MERGE] ... survived=N refuted=N` at the merge. When `off`, the
merge reverts byte-for-byte to the prior **majority-merge**: a non-critical FAIL is
merged only with a `>=2`-verifier majority, a lone non-critical FAIL is demoted to
`PASS` (Issues/Feedback retained), and the stderr line reverts to
`[AC-EVAL-MAJORITY]`. NOTE: the switch flips ONLY the non-critical-FAIL
disposition; the CRITICAL-not-voted-away rule, the `valid < 2` Quorum →
FAIL-CRITICAL rule, and the severity ladder are identical in both modes, and the
merge runs ONLY in the `exhaustive` multi-verifier branch (single / partition
modes have no sibling to refute and are unaffected). This is the per-brief kill
switch for the refute-then-synthesize merge; it is independent of
`constraints.eval_panel`, `constraints.independent_evidence`,
`constraints.oracle_verification`, and `constraints.verification_depth`.

## `constraints.accept_set_conformance`

**Consumed by**: `/impl` (Step 15 `accept_set_conformance` resolution — the per-AC
deterministic trigger + the EXECUTED accept-set sweep handoff to `ac-evaluator` /
`ac-evaluator-hi`), the `ac-evaluator` `## Failure-class panel` L-ROBUSTNESS lens
(which EXECUTES the sweep for the `triggered-on=` ACs against an independent
hand-coded spec oracle), and the `hooks/accept-set-verify.sh` PostToolUse gate
(which verifies the persisted `## Accept-set sweep` line post-hoc).

**Accepted values**: `auto`, `off`.

**Default** (field absent OR policy file absent OR unknown value): `auto`
(fail-safe to active).

**Effect**: when `auto`, **Advertised-Accept-Set Conformance** (v8.5.0+) is
active. For any AC whose boundary advertises **strict / canonical / lossless /
limit** (word-existence in the AC, its Implementation Notes, the docstring, or
`--help`) OR shares an input class with a `shared_input_boundary` sibling (a
keyed structure built from untrusted input triggers the K axis even with no
lexical word), the orchestrator marks the AC `triggered-on=` and the evaluator
MUST NOT merely reason about the accept set — it EXECUTES a generative
grammar-complement sweep in `.simple-workflow/scratch/` and diffs the unit's
accept-set against an independent hand-coded spec oracle (the four metamorphic
relations MR-FINITE / MR-ALPHABET / MR-CANONICAL / MR-KEYFAITH; see
[`../../impl/references/accept-set-conformance-harness.md`](../../impl/references/accept-set-conformance-harness.md)).
A divergence is FAILed only under the two-tier oracle-authoritative gate (the
oracle is authoritatively narrower than the unit's accept-set), else recorded as
ADVISORY PASS-WITH-CAVEATS (the EC-SELFDOC fail-open posture). The evaluator
persists one `## Accept-set sweep` line per inspected boundary, and
`hooks/accept-set-verify.sh` deterministically verifies that line — a triggered
boundary not run, an alphabet/unicode (A/U-axis) sweep that skipped the astral
complement, or an authoritative divergence not driven to FAIL is BLOCKED, and a
thin A/U corpus is NOTED (advisory only, never blocked — corpus-size is a weak
depth proxy; see CLAUDE.md `SW_ACCEPT_SET_CONFORMANCE_MODE` / `SW_AASC_CORPUS_FLOOR`),
enforced (`on`) by default from v8.5.0 — set `SW_ACCEPT_SET_CONFORMANCE_MODE=metric-only`
for observe-only or `off` to disable the hook. When the policy field `off`, the EXECUTED sweep and the hook
gate stand down: the evaluator verifies the boundary by the prior read-only
strictness reasoning and records a one-line Caveat — the byte-for-byte revert.
This is the per-brief kill switch for the Advertised-Accept-Set Conformance
feature line; it is independent of `constraints.verification_depth`,
`constraints.oracle_verification`, `constraints.eval_panel`, and
`constraints.independent_evidence`.

## `constraints.selfdoc_verification`

**Consumed by**: the EC-SELFDOC evidence channel in
[`../../impl/references/evidence-channels.md`](../../impl/references/evidence-channels.md)
— the `doc-verifier` agent (spawned by `/audit` Step 2 and `/refactor` Phase 3 Step 6,
in parallel with the other reviewers, when this switch is active and a documentation /
advertised-interface surface is touched), the `ac-evaluator` / `ac-evaluator-hi`
`## Independent Evidence (behavioral ACs)` EC-SELFDOC duty, and the Gate 9 R3
(DESCRIPTION-MATCHES-BEHAVIOR) / R4 (DOC/INTERFACE TRUTHFULNESS) authoring rows in
[`ac-quality-criteria.md`](ac-quality-criteria.md).

**Accepted values**: `auto`, `off`.

**Default** (field absent OR policy file absent OR unknown value): `auto` (fail-safe to
active).

**Effect**: when `auto`, **EC-SELFDOC doc/interface-truthfulness verification** (v8.4.0+)
is active — a behavioral AC's evidence MAY (and for Gate 9 rows R3 / R4 SHOULD) compare
the unit's OWN declared contract (docstring / declared invariant / type annotation /
`--help` line / README or quickstart worked-example / advertised size-or-range boundary)
against observed runtime behaviour, RUN against the real build: each advertised example is
reproduced and diffed (byte-for-byte if deterministic, explicit tolerance otherwise), and
each advertised boundary is probed with a FORBIDDEN value (must be rejected) and an
ALLOWED value (must be accepted). The verifier-side execution happens under the
`.simple-workflow/scratch/` exec carve-out and is **fail-open** — where the build cannot
be exercised or the unit advertises no example / boundary, the verifier records a one-line
Caveat (PASS-WITH-CAVEATS), never a force-FAIL. When `off`, the EC-SELFDOC channel and the
`doc-verifier` agent stand down: the `ac-evaluator` drops the EC-SELFDOC duty (the other
behavioral-AC channels — EC-ORACLE / EC-DIFFERENTIAL / EC-PROPERTY / EC-RUNTIME / EC-STATIC
— are unaffected), `/audit` Step 2 and `/refactor` Phase 3 Step 6 skip the `doc-verifier`
spawn, and Gate 9 rows R3 / R4 are satisfied by their pre-v8.4.0 prose form
without the RUN-the-example / FORBIDDEN+ALLOWED concretization — the byte-for-byte revert.
This is the per-brief kill switch for the EC-SELFDOC / doc-verifier feature line; it is
independent of `constraints.oracle_verification` (Gate 7 / EC-ORACLE),
`constraints.independent_evidence` (Gate 8, the broader behavioral-evidence switch),
`constraints.failure_class_coverage` (Gate 9 authoring enumeration — which still emits the
R3 / R4 ROWS; this switch governs only their EC-SELFDOC concretization + the doc-verifier
run), and `constraints.eval_panel`.
