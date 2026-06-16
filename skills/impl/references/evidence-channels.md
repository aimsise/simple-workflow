---
version: 1
canonical: true
binding_parties: [planner, ticket-evaluator, implementer, test-writer, ac-evaluator, doc-verifier]
---

# Evidence-Channel Taxonomy (canonical)

This file is the ONE shared vocabulary for the abstraction the v8.3.0+ verification
subsystem is built on: **what INDEPENDENT EVIDENCE channel proves this AC, and how
hard do we try to break it.** It replaces three ad-hoc lists (the ac-evaluator lens
descriptions, the red-team attack ideas, the per-domain non-negotiables) with one set
of IDs. Every consumer — the planner (authoring), the ticket-evaluator (Gate 8
grading), the implementer and test-writer (producing evidence), and the ac-evaluator
(verifying it) — cites these IDs **by ID, never by paraphrase**, so the meaning of
`EC-RUNTIME` or `RT-MALFORMED` is fixed in one place and cannot drift across files.

The channel IDs (`EC-*`) are the Gate 8 evidence vocabulary (M1, v8.3.0). The attack
classes (`RT-*`) are reserved for the red-team gate (M2, v8.5.0). The irreversibility
cues are read by the M5 criticality resolver (v8.3.0). A `## Red-team attack classes`
or `## Irreversibility axis cues` section being present before its consumer ships is
intentional: the taxonomy is authored once in Phase 0 so M1/M2/M5 share it.

> **Namespace rule (§5.1 MF1)**: red-team attack classes use the `RT-` prefix, NEVER
> the acceptance-criterion prefix. That prefix is the acceptance-criterion ID namespace
> repo-wide (AC-1, AC-CS-*, AC-AUTOKICK-*, …); an attack token sharing that namespace
> would make an evaluator conflate an acceptance criterion with an attack class in one
> prompt. The M2 auto-AC family likewise avoids a confusable AC-RT-N name (it uses
> `RTF-N`).

## Evidence channels (Gate 8 / M1)

Each channel answers "what makes this evidence independent of the System Under Test
(SUT) — the implementation's own internals". A behavioral AC must be proven by at
least one channel from `{EC-ORACLE, EC-DIFFERENTIAL, EC-PROPERTY, EC-RUNTIME}` (the
four independent channels); `EC-STATIC` is the natural channel for a *structural* AC
but is NOT independent evidence for a *behavioral* AC on its own.

- **EC-ORACLE** — an expected value derived from an oracle that does NOT share the
  implementation's core: a third-party reference library, a published formula applied
  from first principles, or a hand-computed truth table. *Independent because* the
  expected value exists without running the SUT. This is the strongest channel and the
  one Gate 7 (oracle independence for computational ACs) requires. At the
  `thorough` / `exhaustive` evidence_floor a standard-backed computational AC
  must use **two or more mutually-validated** EC-ORACLE channels with **at least
  one first-principles** (spec formula, no library) — they agree within
  tolerance before either is trusted; a single oracle suffices only at
  `standard`, and the requirement degrades to one oracle + a Caveat where no
  second independent oracle exists. See
  [`independent-oracle-harness.md`](independent-oracle-harness.md) for the
  canonical shape.
- **EC-DIFFERENTIAL** — the implementation's output cross-checked against a SEPARATE
  reference implementation of the same contract. *Independent because* a second
  implementation would have to share the exact same bug to agree. Strongest as
  **algorithm-vs-algorithm**: when a second, INDEPENDENT ALGORITHM for the same
  contract exists (two independent algorithms for the same contract), cross-check
  the two within an explicit tolerance — a membership / invariant test alone
  (a containment check, "is sorted") is **necessary-not-sufficient** because a wrong
  result can still satisfy it. At `thorough` / `exhaustive` use the
  second-algorithm differential where one is identifiable; degrade to membership
  / property coverage + a Caveat where no second algorithm exists.
- **EC-PROPERTY** — invariants the output must satisfy across a seeded input
  distribution (monotonicity, symmetry, idempotence, round-trip, range/gamut
  containment), independent of any single expected value. *Independent because* the
  invariant is a law the correct answer obeys, not a value the SUT produced. At
  the `thorough` / `exhaustive` evidence_floor this seeded distribution MUST be a
  **committed, fixed-seed** loop (reproducible PRNG, tier-scaled case count), not
  a hand-picked grid — see
  [`independent-oracle-harness.md`](independent-oracle-harness.md); it degrades
  to deterministic coverage + a Caveat where no PRNG idiom exists.
- **EC-RUNTIME** — black-box observation through the real public / protocol boundary:
  the real CLI, the real MCP `Client` over a transport, the exported public API, a
  rendered DOM — never internal handlers reached by reflection or by imports a real
  consumer cannot use. *Independent because* it exercises the same schema /
  serialization / transport layer where real consumers fail, not a white-box shortcut.
- **EC-STATIC** — file-grep / counter / exit-code / signature inspection. *Necessary
  for structural ACs* (a file exists, a symbol is exported with a given signature, a
  flag is parsed) but NOT an independent channel for a behavioral AC: code can be
  statically well-formed and behaviourally wrong.- **EC-SELFDOC** — the unit's OWN declared contract checked against its observed
  runtime behaviour: a docstring, a declared invariant, a type annotation, a `--help`
  / man-page line, a README / quickstart worked-example, or an advertised schema /
  size / range boundary, RUN against the real build and compared to what the unit
  actually does. EC-SELFDOC is a **specialization layered on EC-RUNTIME** (the
  advertised example / boundary is exercised through the real public / protocol
  boundary); it is NOT a member of the four-channel naming set `{EC-ORACLE,
  EC-DIFFERENTIAL, EC-PROPERTY, EC-RUNTIME}` that the Gate 8 binding rule draws from —
  a behavioral AC still names one of those four (or rewrites to EC-STATIC). *Independent
  because* the expected behaviour is fixed by the unit's own published claim BEFORE the
  run, so a drift between claim and behaviour fails the channel even when every other
  test agrees with the (wrong) code. Two failure modes: (A)
  **description-vs-behavior drift** — the runtime output contradicts the unit's own docstring / declared invariant
  / advertised example (a function documented "returns a sorted copy" that returns the
  input order; a README example whose command no longer reproduces its shown output);
  (E) **advertised-boundary != enforced-boundary** — the value the docs say is the limit
  is not the value the code accepts / rejects at (docs say "accepts up to 100 MiB" but
  100 MiB is rejected, or 200 MiB is accepted). The verifier-side consumer of this
  channel is the [`doc-verifier`](../../../agents/doc-verifier.md) agent (it RUNs the
  advertised example / probes the advertised boundary under the `.simple-workflow/scratch/`
  exec carve-out and diffs), and the `ac-evaluator` / `ac-evaluator-hi`
  `## Independent Evidence (behavioral ACs)` duty. It is the standing evidence channel
  for Gate 9 rows R3 (DESCRIPTION-MATCHES-BEHAVIOR) and R4 (DOC/INTERFACE TRUTHFULNESS)
  in [`../../create-ticket/references/ac-quality-criteria.md`](../../create-ticket/references/ac-quality-criteria.md).
  Where the build cannot be exercised (no runnable build, no example to reproduce, no
  numeric/range boundary advertised), EC-SELFDOC is **fail-open**: the consumer records
  a one-line Caveat (PASS-WITH-CAVEATS), it is never an unconditional FAIL for an example
  or boundary that does not exist. This channel is governed by the
  `constraints.selfdoc_verification` kill switch (default `auto`, fail-safe to active);
  see [`../../create-ticket/references/autopilot-policy-reference.md`](../../create-ticket/references/autopilot-policy-reference.md).

The mapping from these IDs to the producer-side authoring rules lives in
[`test-authoring-guidance.md`](test-authoring-guidance.md) (black-box-over-white-box,
property, oracle, seeded-fuzz rules) — implementer and test-writer already carry that
vocabulary; this file gives the canonical ID for each.

## Red-team attack classes (M2, reserved — consumed by M2, v8.5.0)

Five attack-class IDs the red-team pre-ship gate iterates against the public boundary,
independent of the AC list. Defined here in Phase 0 so M1's V3 oracle/fuzz lens and
M2's later red-team phase share one vocabulary. **`RT-` prefix only** (see the
namespace rule above).

- **RT-FUZZ** — randomized / seeded malformed and boundary inputs across the input
  space, looking for crashes, hangs, or non-error successes.
- **RT-ABUSE** — misuse of the public contract: out-of-order calls, illegal state
  transitions, authorization bypass, contract-violating argument combinations.
- **RT-MALFORMED** — structurally invalid or adversarial payloads (overlong, mixed
  encoding, injection, parse-accepted-then-overflows values: an input the parser
  ACCEPTS that yields a non-finite / out-of-range intermediate after a conversion).
- **RT-EXHAUST** — resource exhaustion: unbounded allocation, pathological recursion,
  timeouts, rate-limit / quota pressure.
- **RT-CONCURRENCY** — races, re-entrancy, shared-state corruption, ordering hazards
  under concurrent access.

## Irreversibility axis cues (M5, reserved — consumed by M5, v8.3.0)

The cue list the M5 criticality resolver reads to decide whether an AC verifies an
IRREVERSIBLE real-world side-effect (which floors `criticality = critical` even at
Size S — see [`verification-depth.md`](verification-depth.md) `### Irreversibility
axis`):

- **writes** — persistent data writes (database, filesystem, schema migration).
- **network** — non-idempotent external mutation (publishes, deploys, non-idempotent
  external calls).
- **money-movement** — charges, transfers, ledger writes.
- **destructive** — delete / truncate / overwrite operations.
- **external-system** — calls to an external system whose effect cannot be rolled back.

## Channel independence rule

A channel counts as independent evidence for an AC only when it can fail *without* the
SUT also failing in the same way — i.e. the evidence does not come from the
implementation re-asserting itself. Re-reading a value the code just produced, or a
test that re-measures with the code's own rounded output, is NOT independent (it is
`EC-STATIC` applied to a behavioral claim) and does not satisfy Gate 8.

**Natural-channel sufficiency**: the channel a competent test *already* provides
counts. A black-box CLI assertion is already `EC-RUNTIME`; a parser round-trip is
already `EC-PROPERTY`; a reference-library cross-check is already `EC-ORACLE` or
`EC-DIFFERENTIAL`. Gate 8 therefore demands NO extra channel beyond the AC's natural
evidence at the `standard` evidence floor — this is what keeps a routine S/M ticket
byte-identical to pre-v8.3.0. Additional independent channels are mandated only by the
resolved `evidence_floor` at the `thorough` (+1 independent channel) and `exhaustive`
(>=2 independent channels) tiers; the floor only RAISES the channel count, never lowers
it. Naming a channel the verifier could exercise counts even if the evaluator would
have chosen a different one — Gate 8 enforces independence, not channel choice.
