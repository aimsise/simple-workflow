# Verification depth tier (size/risk-aware scaling)

This file is the source of truth for the `constraints.verification_depth`
knob (v8.1.0+). It expands the depth-tier resolution that `/impl` performs
in Phase 1 (after Size detection, Step 3) and consumes in Step 1a (round
cap), Step 15 (evaluator count), and Step 17 (`/audit` handoff). The
SKILL.md body retains the pinned literals (`verification_depth`,
`standard` / `thorough` / `exhaustive`, the `+3` / `+6` bonuses); this file
holds the matrix, the effects ladder, the precedence rules, and the
fallbacks.

The knob is documented as a per-skill consumer field in
[`skills/create-ticket/references/autopilot-policy-reference.md`](../../create-ticket/references/autopilot-policy-reference.md);
its per-tier default (`auto` at every tier) lives in
[`skills/autopilot/references/state-file.md`](../../autopilot/references/state-file.md)
and the emitted YAML template in
[`skills/brief/references/policy-template.md`](../../brief/references/policy-template.md).

## Accepted values

`constraints.verification_depth` ∈ `{auto, standard, thorough, exhaustive, off}`.

- **`auto`** (default; field absent OR policy file absent → `auto`): resolve
  the effective tier from `Size x risk_tolerance` per the matrix below.
- **`standard` / `thorough` / `exhaustive`**: force that effective tier,
  ignoring Size and `risk_tolerance`.
- **`off`**: disable the feature. `max_rounds` uses the base precedence with
  no bonus, Step 15 spawns a single evaluator, and `/audit` receives no
  `depth=` argument (the third-pass keeps its pre-v8.1.0 conditional
  behaviour). This is the exact pre-v8.1.0 contract and is the per-brief
  kill switch.

## Derivation matrix (`auto` only)

Resolve the effective tier from the ticket Size (Phase 1 Step 3; default `M`)
and the policy `risk_tolerance` (default `conservative` when the policy file
is absent or `risk_tolerance` is unreadable — the same fail-safe default used
by `hooks/lib/parse-state-file.sh::get_risk_tolerance`):

| Size \ risk_tolerance | conservative | moderate | aggressive |
|---|---|---|---|
| S | standard | standard | standard |
| M | standard | standard | thorough |
| L | thorough | thorough | exhaustive |
| XL / unknown | thorough | exhaustive | exhaustive |

**Design principle**: the tier rises with change blast-radius (Size) and with
autonomy (`risk_tolerance`). `aggressive` runs `deny` the human-facing
`audit-fail` / `ac-eval` / `ship-review` gates (see the 3-tier matrix in
`skills/autopilot/SKILL.md`), so they compensate for the absent human
oversight with deeper machine verification. `conservative` runs keep those
gates as live `AskUserQuestion` prompts, so the human supplies the extra
assurance and the matrix caps `conservative` at `thorough` even for XL.

## Criticality scalar (the floor's single named trigger, M5 / v8.3.0+)

The floor below has always read a model-judgment over the AC text. M5 promotes that
read into a SINGLE named scalar computed exactly once at `/impl` Step 3a so M5
(evaluator model + red-team budget), M2 (red-team budget), and M3 (integration-review
depth) all read one value instead of re-deriving the judgment:

```
criticality = blast_radius(Size) × irreversibility
```

- **blast_radius(Size)** — the existing Size axis (S/M/L/XL) the derivation matrix
  already uses; larger Size widens the blast radius.
- **irreversibility** — the NEW axis M5 adds (see `## Criticality floor`,
  `### Irreversibility axis` below). An AC whose verified behaviour has an irreversible
  real-world side-effect raises irreversibility regardless of Size.

The resolver collapses to a two-level result `criticality ∈ {routine, critical}`:
`critical` when the existing critical-domain computational-AC condition fires OR the
irreversibility axis fires; `routine` otherwise. `/impl` Step 3a emits
`[CRITICALITY] level={routine|critical} blast_radius={S|M|L|XL}
irreversibility={none|writes|network|money|destructive|external-system}` to stderr so a
dogfood run can audit the derivation without re-deriving it. `criticality=routine` is the
byte-identical-to-pre-v8.3 default: it never raises the depth tier, never bumps the
evaluator model, and leaves the red-team budget at 0.

## Criticality floor (computational / critical ACs)

The matrix above scales depth by blast-radius and autonomy. It does NOT account
for **correctness criticality** — a tiny `S` ticket can still ship a
wrong-but-self-consistent computed value (the WCAG rounded-meet defect class).
The criticality floor adds that axis: when a ticket contains at least one
**computational AC** (PASS/FAIL hinges on a computed numeric/algorithmic value —
see Gate 7 in `skills/create-ticket/references/ac-quality-criteria.md`) in a
**critical domain** — accessibility / security / money / data-integrity /
standard-compliance — the resolved tier is floored at `thorough` regardless of
Size × `risk_tolerance`, so the `/audit` skeptical third-pass is forced even on
an `S` / `conservative` ticket. The critical-domain determination is a
model-judgment read of the AC text (there is no deterministic ticket field);
keyword cues that should trigger it: WCAG / contrast / a11y / focus-order
/ color-space / gamut / OKLab / luminance / chroma conversion (accessibility &
color-science); auth / crypto / token / signature / input-validation
(security); currency / decimal / rounding / money (money); checksum / hash /
dedup / referential-integrity (data-integrity); RFC / ISO / spec-conformance
(standard-compliance); and any **computational AC over a shared-core input
boundary** — a parser / validation / constant (e.g. an epsilon / range / gamut
guard) shared with sibling tools, where an inconsistency in one sibling is the
exact wrong-but-self-consistent defect class the floor targets. The shared-core
trigger is independent of the named domains above: a computational AC that reads
or must hold an invariant across a shared input boundary floors `critical` even
when its surface domain is otherwise routine.

The floor only RAISES the tier (`standard` → `thorough`); it never lowers a tier
the matrix already resolved higher (`exhaustive` stays `exhaustive`). It is
orthogonal to — and does not by itself trigger — the oracle-independence
verification that `ac-evaluator` applies to every computational AC in all modes
(`agents/ac-evaluator.md` `## Oracle Independence (computational ACs)`): the
floor adds DEPTH (more rounds + forced third-pass), while the oracle requirement
adds an INDEPENDENT measurement, and both target the same defect class. An
explicit `rounds=N` argument caps the generator→evaluator loop but does NOT
suppress the floor-forced `/audit` third-pass — the floor adds rigor (one audit
pass), not impl iterations — so that interaction is intentional. The oracle requirement also carries the sibling-guard obligation (Gate 7): an input-validation guard required by a critical-domain computational AC must hold across every sibling tool sharing that input, not just the AC's primary tool.

### Irreversibility axis (M5 / v8.3.0+)

The critical-domain condition above keys off correctness criticality. M5 adds an
orthogonal IRREVERSIBILITY axis: when at least one AC verifies behaviour with an
irreversible real-world side-effect — persistent data WRITES (DB/filesystem/schema
migration), NETWORK mutation (non-idempotent external calls, publishes, deploys), MONEY
movement (charges, transfers, ledger writes), DESTRUCTIVE operations
(delete/truncate/overwrite), or EXTERNAL-SYSTEM calls whose effect cannot be rolled back
— the resolved `criticality` is floored at `critical` even on an `S` ticket — which, exactly
as the critical-domain computational condition does, floors the depth tier at `thorough`
(raise `standard`→`thorough`, never lower a higher tier) AND, per the criticality scalar,
bumps the evaluator model to opus and the red-team budget to full. Like the critical-domain
condition, the irreversibility determination is a model-judgment read of the AC text
(there is no deterministic ticket field); the cue list matches the irreversibility-axis
cue list in `skills/impl/references/evidence-channels.md`. The axis only RAISES
`criticality` to `critical`; it never lowers a value the critical-domain condition
already raised. Its dedicated kill switch is `constraints.irreversibility_floor`
(`auto`/`off`; absent / unknown → `auto` = active); `off` removes ONLY the
irreversibility axis, leaving the critical-domain computational floor and the matrix
depth scaling intact. It is additionally suppressed whenever
`constraints.verification_depth: off` disables the whole depth feature.

**Kill switches**: `constraints.verification_depth: off` disables the whole
depth feature including this floor (pre-v8.1.0 behaviour). `constraints.oracle_verification: off`
(absent / unknown → `auto`) disables the criticality floor AND the mandatory
oracle-independence verification ticket-wide (pre-v8.2.0 behaviour), while
leaving the matrix-derived depth scaling intact. Both default to active.

## Effects ladder

The resolved tier and the criticality floor control these independent knobs — the
`evidence_floor` column added by M1, and the `evaluator model` + `red-team budget`
outputs by M5 (both v8.3.0+); the floor only RAISES them, never lowers. They are folded
into the single resolved struct `{depth_tier, criticality, evidence_floor,
evaluator_model, redteam_budget, domain_set}` that `/impl` Step 3a materialises into
`phases.impl.*`:

| Tier | GE `max_rounds` bonus | `/audit` third-pass | Step 15 evaluators | `evidence_floor` (Gate 8 channels MANDATORY) |
|---|---|---|---|---|
| `standard` | +0 | conditional (existing T-A..T-E) | 1 (single, current behaviour) | EC-STATIC + the AC's natural channel — this is the TIER floor; the RESOLVED floor is `max(tier, AC-shape)`, so a behavioral-AC ticket floors at `+1-independent` even here (see `### AC-shape evidence-independence floor`) |
| `thorough` | +3 | forced via `depth=thorough` (trigger T-F) | 1 | + at least 1 INDEPENDENT channel beyond the natural one (EC-ORACLE / EC-DIFFERENTIAL / EC-PROPERTY / EC-RUNTIME) |
| `exhaustive` | +6 | forced via `depth=exhaustive` (trigger T-F) | 3 (evidence-mode-diverse majority) | >= 2 INDEPENDENT channels (the 3 evidence-mode lenses V1 EC-RUNTIME / V2 EC-DIFFERENTIAL-or-EC-PROPERTY / V3 EC-ORACLE collectively satisfy this) |

1. **GE `max_rounds` bonus** — added to the resolved base
   (`constraints.max_total_rounds` or default 9). See "Round-cap precedence".
2. **`/audit` third-pass** — `/impl` Step 17 passes `depth={tier}` to `/audit`;
   `thorough` / `exhaustive` add trigger **T-F** which forces the existing
   skeptical third-pass (`skills/audit/references/skeptical-pass.md`). This
   reuses existing machinery — it does NOT add a new loop-until-dry pass.
3. **Step 15 evaluator count** — `exhaustive` activates the high-assurance
   multi-verifier majority (3 evidence-mode-diverse `ac-evaluator` spawns + majority
   merge). `standard` / `thorough` keep the single evaluator. See
   [`ac-evaluator-orchestration.md`](ac-evaluator-orchestration.md)
   `## High-assurance multi-verifier branch` for the lenses and merge.

### AC-shape evidence-independence floor (M3 / v8.4.0+)

The `evidence_floor` column above is keyed to the **depth tier** (Size × risk).
M3 adds a SECOND, orthogonal axis keyed to **AC shape** (Size-independent), so the
anti-shared-blind-spot independence the floor buys is no longer gated behind
blast-radius. The resolved floor is the stronger of the two:

```
evidence_floor = max(tier floor, AC-shape floor)
```

ordered `EC-STATIC+natural` < `+1-independent` < `>=2-independent`.

- **AC-shape floor** — derived from the ticket's AC shapes alone, independent of
  `Size × risk_tolerance`:
  - the ticket carries ≥1 **behavioral AC** (Gate 8 — PASS/FAIL hinges on
    observable runtime behaviour) → `+1-independent` (the AC's natural channel PLUS
    one independent channel beyond it; a computational AC satisfies this via its
    EC-ORACLE).
  - **structural-only** ticket (every AC is file-grep / counter / exit-code
    verifiable) → `EC-STATIC+natural` (adds nothing).
- **Monotonicity / no regression on deeper tiers** — the `max()` only ever RAISES
  the floor. A `thorough` / `exhaustive` ticket already floors at `+1-independent` /
  `>=2-independent`, so the AC-shape axis is a no-op there. The ONLY behaviour it
  changes is a `standard`-tier ticket that carries a behavioral AC: its floor rises
  `EC-STATIC+natural → +1-independent`, so the single `standard` evaluator
  establishes that AC through one channel beyond its natural one.
- **Proportionality (the contract this split exists to honour)** — depth and
  evidence-independence are now SEPARATE axes: **Size gates depth** (rounds / `/audit`
  third-pass / the 3-spawn fan-out — all still `exhaustive`-only), **AC shape gates
  the independence floor**. The raised `standard` floor adds NO spawn — the same one
  evaluator just exercises one more channel in-agent — so routine S/M wall-clock and
  spawn count are unchanged; only the evidence bar rises, by one channel.
- **Kill switch / byte-identical revert** — `constraints.independent_evidence: off`
  drops BOTH floors (the `max()` collapses and the evaluator falls back to its
  pre-v8.3.0 path), exactly restoring the routine-S/M behaviour this axis changes.
  Absent / field absent / unknown → `auto` (active). `constraints.verification_depth:
  off` additionally disables the whole depth feature including this axis.

**Strongest-derivation oracle (tier-independent, M3)**: when a computational AC's
contract is **derivable from a published spec / formula**, the expected value SHOULD
be taken from a **first-principles** oracle (the spec formula, hand-implemented, no
library) in preference to a sibling reference library — at EVERY tier, even where a
single oracle suffices (`standard`); a sibling library is the second choice because
it silently inherits that library's conventions. The evaluator records the
**oracle-kind** it used (`first-principles | sibling | hand | none`) in the per-AC
`[ORACLE-AUDIT]` line (M8) so a dogfood run can confirm the strongest AVAILABLE
derivation was chosen, not merely the most convenient. This preference is all-tier;
the depth-gated multi-oracle (H1) requirement (≥2 mutually-validated oracles) below
is unchanged and stays `thorough` / `exhaustive`-only.

### Standard-backed computational evidence floor (Wave A: multi-oracle / seeded-fuzz / algorithm-differential)

At the `thorough` and `exhaustive` floors, the independent channels mandated by
the `evidence_floor` column above are SHARPENED for a **standard-backed
computational AC** (one in a domain with a published spec / a second independent
oracle / a second algorithm — color/WCAG, crypto, dates, units, money rounding,
spec parsers, accessibility ratios):

- **multi-oracle (H1)** — the EC-ORACLE evidence MUST be **two or more
  mutually-validated oracles** with **at least one derived from first
  principles** (the spec formula, no library), trusted only when they agree
  within an explicit tolerance. A single library oracle suffices only at
  `standard`.
- **committed seeded fuzz (H2)** — a **committed, fixed-seed** property-fuzz
  loop (EC-PROPERTY) over the input distribution, tier-scaled, not a hand-picked
  grid.
- **algorithm-vs-algorithm (H3)** — where a second independent ALGORITHM for the
  contract exists, an EC-DIFFERENTIAL cross-check within tolerance (membership is
  necessary-not-sufficient).

These RAISE the bar only for standard-backed computational ACs at
`thorough` / `exhaustive`; they **degrade to the single natural channel + a
Caveat — never a block** where no published spec / second oracle / second
algorithm exists, and the `standard` floor is unchanged. The canonical oracle
shape is [`independent-oracle-harness.md`](independent-oracle-harness.md).

### Evaluator model + red-team budget (M5 / v8.3.0+)

The resolver also fills two struct fields the floor RAISES:

| criticality / tier | evaluator model | red-team budget (M2, v8.5.0+) |
|---|---|---|
| routine AND tier ∈ {standard, thorough} | sonnet (`ac-evaluator`, today's behaviour) | 0 (no red-team phase) |
| critical OR tier == exhaustive | opus (`ac-evaluator-hi`, see below) | full sweep — all 5 attack classes (`skills/impl/references/evidence-channels.md`) at high iteration hardness |

- **evaluator model**: today the evaluator is hardcoded sonnet (`skills/impl/SKILL.md`
  Step 15 "always sonnet"; `agents/ac-evaluator.md` frontmatter `model: sonnet`). M5
  resolves `evaluator_model` to `opus` when `criticality == critical` OR
  `depth_tier == exhaustive`, symmetric with the EXISTING size-aware generator-model
  selection (`constraints.sonnet_size_threshold` escalates the generator to opus for
  L/XL — `skills/create-ticket/references/autopilot-policy-reference.md`). **Platform
  caveat**: the Agent tool's JSONSchema does NOT accept a per-invocation `model:`
  override — the SAME Strategy-B limitation that forces the soft turn budget instead of a
  per-spawn `maxTurns` (`skills/impl/references/ac-evaluator-orchestration.md`
  `## Turn-budget formula`). The orchestrator therefore selects a DEDICATED agent file:
  when `evaluator_model == opus` it spawns `simple-workflow:ac-evaluator-hi`
  (`agents/ac-evaluator-hi.md`, `model: opus`, body byte-identical to `ac-evaluator`
  except its `name:` and `model:` frontmatter lines) instead of
  `simple-workflow:ac-evaluator`; otherwise it spawns `ac-evaluator` unchanged. A v8.3
  dogfood pre-verifies empirically whether a per-spawn `model:` argument is in fact
  rejected; if it is accepted the two-file workaround can later collapse, but the
  byte-identical-body invariant is the supported path today (guarded by CT-EV-MODEL). If
  maintaining the second agent file is judged too costly, M5 degrades to
  red-team-budget-only (evaluator stays sonnet at every tier) — set the floor's evaluator
  bump aside without touching the budget column.
- **red-team budget**: `redteam_budget` (attack-class count × iteration hardness) is
  consumed by the M2 red-team pre-ship phase (v8.5.0). It scales with the SAME
  `criticality` scalar — a tiny irreversible-write ticket gets the full sweep even at
  Size S. In v8.3.0 M2 does not yet exist, so `redteam_budget` is recorded into the
  struct but has no consumer (a pure no-op until v8.5.0).

**Fail-open**: a `routine` ticket at `standard`/`thorough` keeps `evaluator_model =
sonnet` and `redteam_budget = 0`, byte-identical to pre-v8.3 behaviour.
`constraints.verification_depth: off` disables the whole floor including the model bump
and the budget. `constraints.oracle_verification: off` disables the critical-domain axis
of the floor (pre-v8.2.0); `constraints.irreversibility_floor: off` disables only the new
irreversibility axis. Each kill switch defaults active (absent / unknown → `auto`).

## Round-cap precedence (updated)

Written into `phases.impl.max_rounds` in the Phase 2 init block. The depth
bonus is folded in **after** the existing precedence resolves the base:

1. An explicit, valid `rounds=N` argument → `max_rounds = N`, **no depth
   bonus** (the user-specified cap is authoritative and final).
2. Otherwise `base = {ticket-dir}/autopilot-policy.yaml`
   `constraints.max_total_rounds` (when present) else default `9`, and
   `max_rounds = base + bonus`, where `bonus` is `0` / `+3` / `+6` for
   `standard` / `thorough` / `exhaustive`. When `verification_depth: off`,
   `bonus = 0`.

The resulting value never triggers the soft-cap-24 `[ARG-WARN]` (that warning
fires only for an explicit `rounds=N` argument, not for policy/depth-derived
values); the largest reachable derived value is `aggressive` base `12` `+ 6 =
18`, which stays under 24. See
[`round-cap-parser.md`](round-cap-parser.md) for the argument parser itself.

## Composition with the `AC_COUNT >= 30` partition branch

The multi-verifier majority (Step 15, `exhaustive`) and the AC-count
partition branch are mutually exclusive, **partition wins**: when
`AC_COUNT >= 30`, keep the existing two-partition `worst-of-2` evaluation
(`eval-round-{n}-part-1.md` / `-part-2.md`) and do NOT additionally triple
it. This caps the worst-case evaluator spawn count per round at 3 (either
3 lenses for `AC_COUNT < 30`, or 2 partitions for `AC_COUNT >= 30`) rather
than 6. The tier still applies its `max_rounds` bonus and `/audit` third-pass
forcing in the partition path; only the 3-lens fan-out is suppressed.

## Manual / policy-absent flows

For a manual `/impl` on a `.simple-workflow/docs/plans/` plan (no ticket, no
`autopilot-policy.yaml`): Size defaults to `M`, `verification_depth` defaults
to `auto`, and `risk_tolerance` is unreadable → treated as `conservative`.
The matrix resolves `M x conservative = standard`, so a manual `/impl` run is
byte-identical to the pre-v8.1.0 behaviour. Deeper tiers only engage for
ticketed L/XL work or `aggressive` briefs.

## Observability

`/impl` records the resolved tier into `phases.impl.verification_depth` (the
literal effective tier `standard` / `thorough` / `exhaustive`, or `off`) when
it initialises the Phase 2 loop state, and emits a one-line
`[VERIFICATION-DEPTH] tier={tier} source={auto|policy|off} size={S|M|L|XL}
risk={conservative|moderate|aggressive}` to stderr so a dogfood run can audit
the derivation without re-deriving it. The field is advisory metadata; it is
not gated by any hook.
