# AC Quality Criteria: Rationale and History

This file is a maintainer reference for `ac-quality-criteria.md` and its grading companion `ac-quality-grading.md` in the same directory. It keeps the motivation paragraphs, dogfood evidence, version-history asides and activation notes that were moved out of the rubric on 2026-11-03 so the rubric (both files inlined into every `ticket-evaluator` spawn, the rules file alone `Read` by the `planner`) carries normative text only.

- **Not normative.** Every MUST / MUST NOT / FAIL condition, `n/a` condition, classifier and kill switch lives in `ac-quality-criteria.md` (the gate rules) or `ac-quality-grading.md` (the ticket-evaluator's grading procedure), which win on any disagreement. Normative clauses that were embedded in the paragraphs below were extracted into the rubric before the narrative moved here.
- **Not injected.** No spawn prompt inlines this file, and no agent reads it when drafting or grading a ticket. The `<canonical_ac_criteria>` block carries exactly two files, `ac-quality-criteria.md` and then `ac-quality-grading.md`; do not add this file to it.
- **Verbatim.** Each entry is the original text, grouped by the gate it came from. Where only part of a paragraph moved, the entry quotes just that part.

## Gate 6: Capability Mapping

### Activation note

**Evaluator note**: Gate 6 activates only after `skills/create-ticket/references/ac-quality-criteria.md` ships this section. Evaluations performed against earlier versions of this file deliberately applied Gates 1-5 only; their PASS verdicts do not imply Gate 6 conformance.

### Subagent / main-thread asymmetry: version tag

Removed aside: "v8.0.0" (the parenthetical read `(v8.0.0 productive agents: ...)`; the rubric keeps the agent list without the version tag).

## Gate 6.5: Probe Completeness

### Motivation

**Motivation**: Gate 6 binds **runtime/visual** ACs to a verification capability. It does NOT speak about **authoring-reference** capabilities — utility skills that an implementer / researcher / test-writer would consult during code authoring (UI/UX design guidance, library API documentation lookup, accessibility heuristics, etc.). Without Gate 6.5, a probe-visible capability that does not fit the Gate 6 runtime/visual classifier is silently dropped by the planner, leaving the implementer with no executable pathway to invoke it (the productive subagents' `## Side-effect ban` forbids speculative invocation of unbound `mcp__*` and unbound utility skills). Gate 6.5 closes that hole by requiring the planner to **classify every probe entry** into one of three buckets — making "the planner forgot about `ui-ux-pro-max`" mechanically detectable rather than a silent omission.

### Self-skip exception: why orchestrator names appear in the probe

These names appear in the `Available user skills:` probe because they live under `~/.claude/skills/` or the plugin's `skills/` tree, but they are never invocable from a subagent (see `agents/<name>.md` External Tool Integration Policy).

### Pointer to the planner restatement

The planner self-audit step for Gate 6.5 lives in `agents/planner.md` (Pre-emit Self-Audit step 7).

(Former pointer, pre-2026-11-03 numbering: step 7 no longer exists; the planner now applies the whole rubric in Pre-emit Self-Audit step 6.)

### Consumer-side consultation discipline: version tag

Original label: "**Consumer-side consultation discipline (v8.0.0+ Recommending semantics)**" (the rubric keeps the label without the version tag).

### Consumer-side consultation discipline: motivation (TW33-TW35)

The motivation: dogfood (TW33-TW35) showed Advisory bindings without consultation discipline collapse into permitting-only — `ui-ux-pro-max` was Advisory-bound in 4/5 TW35 tickets but invoked 0 times, with no skip rationale recorded anywhere; the planner did its part (classification was correct per Gate 6.5), but the consumer side silently skipped without explanation, hiding the design decision from the audit trail. Recommending semantics close that hole.

### Activation note

**Evaluator note**: Gate 6.5 activates only after this section ships. Tickets drafted before Gate 6.5 are pre-Gate-6.5 and are graded `n/a` for Gate 6.5 (PASS verdicts on those tickets do not imply Gate 6.5 conformance).

## Gate 7: Oracle Independence (computational ACs)

### Motivation

**Motivation**: a test whose expected value is re-derived from the implementation's own rounded / formatted output is self-confirming — it passes whenever the code is internally consistent, even when wrong. This is the defect class where a test re-thresholds the same rounded value the code produced (falsely reporting a numeric target as met) past a fully green test suite, because every test re-measured with that rounded value. Gate 7 makes that circularity an authoring-time FAIL.

### Multi-oracle requirement: rationale

Two agreeing channels, one of them first-principles, is what makes the evidence independent of BOTH the implementation AND any single reference library (a lone library oracle silently inherits that library's conventions).

### Adversarial-input requirement: version tag

Removed aside: "broadened in M3, v8.4.0+"

### Adversarial-input requirement: rationale for broadening to behavioral ACs

Removed aside: "because a DoS hang or a contract-violating error path is reachable on bad input regardless of whether the output is a computed number"

### Adversarial-input requirement: what it catches (dogfood)

This is what catches DoS hangs and contract-violating outputs on *bad* input, not merely wrong values on *good* input (the motivating dogfood build also shipped a non-finite-input DoS hang and an out-of-range channel leak, both invisible to fixed valid-only fixtures).

### Parse-accepted-then-overflows vector: rationale

The parser rejects the latter cheaply at the door, so they exercise the wrong path; the real DoS / corrupt-success bugs live in the values the parser ACCEPTS.

### Parse-accepted-then-overflows vector: dogfood evidence

(A real dogfood shipped exactly this: the generated test used parse-rejected `NaN` / `Infinity` keyword tokens, rejected in ~0 ms, while a parse-accepted overflowing magnitude got through and hung an unbounded clamp loop.)

### Shared / sibling-guard requirement: origin

Removed aside: "this is the `## Modifications` sibling-artifact rule (`CLAUDE.md`) enforced at the AC level"

### Shared / sibling-guard requirement: dogfood evidence (single-consumer guard)

(Dogfood evidence: a validation guard added to one consumer but absent from its analogous siblings leaves a live failure reachable through the unguarded siblings.)

### Shared / sibling-guard requirement: dogfood evidence (delegating sibling)

(Dogfood evidence: a delegating sibling that merely round-tripped a value the shared parser had accepted still raised an unguarded error on a valid-but-extreme magnitude — the leak the shared parser's guard did not cover.)

### Kill switch: version aside

Removed aside: "(restores pre-v8.2.0 authoring behaviour)"

### Activation note

**Evaluator note**: Gate 7 activates only after this section ships. Tickets drafted before Gate 7 are pre-Gate-7 and are graded `n/a` for Gate 7 (PASS verdicts on those tickets do not imply Gate 7 conformance).

## Gate 8: Independent Evidence

### Motivation

**Motivation**: Gate 7 closes the oracle-circularity defect class for *computational* ACs only. The broader failure mode is that ALL of a ticket's verification can rest on a single evidence source — the same `git diff` read against the same project test suite — so a behavioral AC passes whenever the code and its own tests are mutually consistent, even when both are wrong. Gate 8 generalizes Gate 7's independence requirement to every behavioral AC: it asks not only "is this AC testable" (Gate 1) but "what evidence channel proves it, and is that channel independent of the implementation's own internals". Gate 7 (oracle independence for computational ACs) is the strongest sub-case of Gate 8 and is UNCHANGED — a computational AC that satisfies Gate 7 automatically satisfies Gate 8 via the `EC-ORACLE` channel.

### Natural-channel sufficiency: AC-shape floor history (original wording)

Under the M3 AC-shape floor (v8.4.0+) `evidence_floor = max(tier floor, AC-shape floor)`: ANY behavioral AC floors at `+1-independent` regardless of Size, so at the `standard` tier a behavioral AC's evaluator must establish one independent channel BEYOND the natural one — the pre-v8.3.0 `standard`-tier natural-channel-sufficient carve-out is REMOVED for behavioral ACs (a structural-only ticket still floors at `EC-STATIC+natural`; `thorough` / `exhaustive` are unchanged). This is a RUNTIME evidence-floor requirement on the evaluator; the AUTHORING-time naming requirement (every behavioral AC names ≥1 independent channel — below) is unchanged, and `constraints.independent_evidence: off` restores the natural-channel-sufficient behaviour.

### Kill switch: version aside

Removed aside: "(restores pre-v8.3.0 authoring behaviour where only Gate 7 governed evidence independence)"

### Activation note

**Evaluator note**: Gate 8 activates only after this section ships. Tickets drafted before Gate 8 are pre-Gate-8 and are graded `n/a` for Gate 8 (PASS verdicts on those tickets do not imply Gate 8 conformance).

## Gate 9: Failure-Class Coverage

### Motivation

**Motivation**: Gates 1-8 GRADE the ACs that were written; none of them GENERATE the ACs that should exist. AC derivation is feature-driven — the planner writes ACs for the behaviour the feature adds, so a whole failure class (a full-domain invariant violated only at an extreme, a DoS hang on hostile input, a docstring that lies about behaviour, an advertised example that no longer builds) is silently uncovered because no AC ever named it. Gate 9 makes AC derivation **coverage-driven**: for each external boundary the Scope touches, it ENUMERATES the four failure-class rows that MUST each yield >=1 AC or carry an explicit `n/a` justification. Gate 9 only ENUMERATES which boundaries need an AC; Gate 7 and Gate 8 GRADE that AC once it exists (Gate 9 does not re-grade evidence independence).

### Boundary key: cross-ticket clause (original wording, consolidated into the Gate 7 sibling-guard)

— and that family is not confined to one ticket: when separate tickets EACH create a unit consuming one common external input class, every such unit is a Scope-touched boundary for Gate 9 even when its own ticket creates a single unit (per-ticket `peer_set: false`), and the cross-ticket `shared_input_boundary` signal the `decomposer` forwards (see Gate 7 sibling-guard) names which tickets belong; a member that DELEGATES the input handling to a shared parser created elsewhere is NOT thereby exempt — its R2 hostile / accept-set row is required, or a justified `n/a` a reviewer can challenge (delegation is NOT an automatic n/a, and 'delegates to the shared parser' is not itself an acceptable n/a reason). This is the same per-boundary failure-class axis Gate 9 already owns, reached across ticket boundaries — Gate 10 (cross-unit output uniformity) remains disjoint and untouched.

### R2: dogfood evidence (strictness-leniency)

(dogfood evidence: a real dogfood shipped a 'strict' parser that silently accepted out-of-alphabet numerals and non-canonical forms its own fixtures never exercised, none caught by its valid-only fixtures, its Gate 9 matrix, or the panel)

### Disjointness: contrast with Gate 3

Where Gate 3 says "name the edge cases somewhere in the prose", Gate 9 says "every external boundary has these four failure-class rows resolved to an AC or an n/a".

### Kill switch: version aside

Removed aside: "(restores the pre-v8.4.0 single-pass authoring behaviour where AC derivation was feature-driven only and no failure-class coverage matrix was required — the byte-for-byte revert)"

### Kill switch: feature-line label and version tag

Removed aside: "This is the per-brief kill switch for the failure-class-coverage feature line;" / "(the failure-class eval panel, v8.4.0+)" (the rubric keeps the independence list and drops the version tag).

### Activation note and model-judgment caveat (original wording)

**Evaluator note**: Gate 9 activates only after this section ships. Tickets drafted before Gate 9 are pre-Gate-9 and are graded `n/a` for Gate 9 (PASS verdicts on those tickets do not imply Gate 9 conformance). NOTE (model-judgment caveat): there is no machine-readable external-boundary field in the ticket schema — "which surfaces are Scope-touched external boundaries" and "is this row's AC sufficient" are model judgment over the ticket's free-text Scope and ACs (the same fragility class as the Gate 7 criticality floor). Gate 9 enforces that the matrix SECTION is present and resolved (every row -> AC or justified `n/a`) per boundary; it does NOT and cannot mechanically verify that the model identified the boundaries correctly or that each row's AC is adequate — that residual judgment is graded by the evaluator, not by a grep.

(Since the 2026-11-03 rules/grading split, the current model-judgment caveat sits under the Gate 9 heading of `ac-quality-grading.md`.)

## Gate 10: Peer-Set Uniformity

### Motivation

**Motivation**: Gates 1-9 cover input, computation, evidence, and per-boundary failure classes, but NONE enforce **cross-unit output uniformity** — failure class D. When a ticket creates `>=2` analogous sibling units (a family of peer tools / endpoints / commands sharing one category), each may independently invent its own error convention, its own success-envelope shape, its own vocabulary for the same concept, or re-hand-roll the same boilerplate wrapper. The only sibling rule before Gate 10 is the Gate 7 **sibling-input-guard**, which keys on the *input* boundary (a validation guard must be shared or replicated across siblings) — it says nothing about the *output* axis. Gate 10 closes that: when the Scope creates a peer set, the ticket MUST assert at least one **UNIFIED convention** AC that holds *across* the set. This is the authoring-side twin of the impl-side **L-UNIFORMITY** failure-class lens (which grades the same property in the diff at verification time — see `agents/ac-evaluator.md` `## Failure-class panel (default lenses)` and `skills/impl/references/ac-evaluator-orchestration.md`); Gate 10 makes the planner *write the AC* so the lens has something to grade and the ticket-evaluator can FAIL its absence.

### Disjointness (original wording)

**Disjointness**: Gate 10 is disjoint from Gate 7's sibling-input-guard (which is the *input*-validation axis — a finiteness / range / gamut guard shared across siblings) and from Gate 9 (which is *per-boundary* failure-class coverage, not *cross-boundary* uniformity). Gate 9 asks "does THIS boundary cover its four failure classes"; Gate 10 asks "do these `>=2` peers agree on ONE output convention". A ticket can need both: each peer carries its own Gate 9 matrix AND the set carries one Gate 10 unified AC.

### Kill switch: version aside

Removed aside: "(restores the pre-Gate-10 authoring behaviour where cross-unit output uniformity was unenforced — the byte-for-byte revert)"

### Kill switch: feature-line label

Removed aside: "This is the per-brief kill switch for the peer-uniformity feature line;"

### Activation note and model-judgment caveat (original wording)

**Evaluator note**: Gate 10 activates only after this section ships. Tickets drafted before Gate 10 are pre-Gate-10 and are graded `n/a` for Gate 10 (PASS verdicts on those tickets do not imply Gate 10 conformance). Same model-judgment caveat as Gate 9: "which Scope units form a `>=2`-peer set" is model judgment over free-text Scope, not a grep — Gate 10 enforces that the unified AC (or a justified `n/a`) is PRESENT for an identified peer set; it does not and cannot mechanically verify the model partitioned the peers correctly.

(Since the 2026-11-03 rules/grading split, the current model-judgment caveat sits under the Gate 10 heading of `ac-quality-grading.md`.)

## Planner MUST

### Gate 8 bullet: version label

Removed aside: "under the M3 AC-shape floor" (now `under the AC-shape floor`).

## Evaluator MUST NOT (drift-prevention list): items folded into their gates

On 2026-11-03 the list was cut to its three cross-gate items. Each other item below was either already stated in its own gate or was folded into that gate as an `Evaluator MUST NOT FAIL when ...` sentence (since the 2026-11-03 rules/grading split, those sentences sit under the same gate heading in `ac-quality-grading.md`). The original items, verbatim:

- **MUST NOT** treat a concrete API name that appears as a test-assertion observation point (Gate 4 carve-out above — e.g., `process.stdout.write`, `vi.spyOn(console, 'log')`, `fs.writeFileSync`) as HOW. Such names are part of the PASS/FAIL contract, not prescribed implementation.
- **MUST NOT** invent edge cases outside the ticket's declared scope and then FAIL Gate 3 for their absence. (Failure-class eval panel carve-out, v8.4.0+: this MUST-NOT binds the *ticket-evaluator* — it does NOT restrict the *impl-side* `ac-evaluator` failure-class panel, whose lenses MAY surface a failure-class coverage gap the planner dropped and report it as advisory `[MEDIUM]` coverage-gap Feedback; that is the grader acting as a coverage-gap finder, not a Gate-3 ticket-quality FAIL. The ticket-evaluator still MUST NOT convert such an impl-side coverage-gap note into a Gate-3 FAIL. See `skills/impl/references/ac-evaluator-orchestration.md` `## Default failure-class panel` and `agents/ac-evaluator.md` `## Failure-class panel (default lenses)`.)
- **MUST NOT** FAIL Gate 5 when a rationale is present that justifies a single-axis judgement per the tiebreak rule above.
- **MUST NOT** FAIL Gate 6.5 solely because the planner chose Advisory over Bound (or vice versa) for an entry whose classification is judgement-debatable — Gate 6.5 enforces **completeness** (every probe entry is classified somewhere), not the **correctness** of the chosen bucket. Bucket choice may be feedback in the Issues / Feedback section but is not a FAIL trigger unless the entry was a runtime/visual capability that Gate 6 required as Bound (in which case Gate 6 FAILs, not Gate 6.5).
- **MUST NOT** FAIL Gate 6.5 when both probes reported `(none)` in the planner's spawn prompt — vacuous satisfaction is PASS.
- **MUST NOT** FAIL Gate 7's **oracle / raw-value** requirement for an AC that is not computational (purely structural — file-grep / counter / exit-code), or when the ticket sets `constraints.oracle_verification: off`, or when the ticket pre-dates Gate 7 — grade the oracle requirement `n/a` for those. Gate 7's oracle FAIL fires only on a computational AC (a computed numeric/algorithmic value) that names neither an independent oracle (with a raw-value tolerance) nor the documented no-oracle fallback. (M3 exception: the **adversarial-input coverage** sub-requirement DOES apply to a *behavioral* AC on external / untrusted input — a behavioral external-input AC with zero adversarial / non-finite / malformed coverage is a Gate 7 FAIL on that sub-requirement alone; the oracle + raw-value requirements remain computational-only.) Naming a library / formula / table that the verifier could apply counts as an oracle even if the evaluator would have chosen a different one — Gate 7 enforces independence, not oracle choice.
- **MUST NOT** FAIL Gate 9 for a ticket that touches **no Scope-touched external boundary** (internal-helper-only / private-function / single-call-site refactor — routine-ticket flood prevention), nor for a boundary that is not part of a `>=2`-peer set when the spec keys the row on peer sets, nor when the ticket sets `constraints.failure_class_coverage: off`, nor when the ticket pre-dates Gate 9 — grade Gate 9 `n/a` for those. Gate 9 FAILs only when a Scope-touched external boundary has a blank failure-class row (R1 / R2 / R3 / R4) that carries neither an AC nor a one-line `n/a` justification. A row resolved to a justified `n/a` is a PASS; the evaluator MUST NOT FAIL Gate 9 merely because it would have written a different AC for a row (Gate 9 enforces **coverage presence per boundary**, not AC adequacy — adequacy is graded by Gates 1-8 once the AC exists).
- **MUST NOT** FAIL Gate 10 for a ticket whose `### Scope` creates fewer than 2 peers in a category (a single new unit, or unrelated units that form no analogous sibling set — there is no peer set over which to assert uniformity), nor when the ticket sets `constraints.peer_uniformity: off`, nor when the ticket pre-dates Gate 10 — grade Gate 10 `n/a` for those. Gate 10 FAILs only a ticket whose Scope creates a `>=2`-peer set that carries neither a unified-convention AC (single error convention / single success-envelope shape / single vocabulary per concept / single wrapper for repeated boilerplate, mechanically grep/AST-verifiable per Gate 1) NOR a one-line `n/a` justification under `#### Peer-Set Uniformity (Gate 10)`. A justified `n/a` is a PASS; the evaluator MUST NOT FAIL Gate 10 merely because it would have chosen a different unified convention (Gate 10 enforces **coverage presence** for the peer set, not which convention was unified). Bucket / convention-choice debate is feedback, not a FAIL trigger.
- **MUST NOT** FAIL Gate 8 for an AC that is purely structural (file-grep / counter / exit-code — its natural evidence is EC-STATIC), or for a behavioral AC whose natural channel IS already independent of the implementation (a black-box CLI / API / MCP-Client assertion is already EC-RUNTIME; a parser round-trip is already EC-PROPERTY), or when the ticket sets `constraints.independent_evidence: off`, or when the ticket pre-dates Gate 8 — grade those `n/a`. Gate 8 FAILs only a behavioral AC whose sole stated evidence is the implementation re-asserting itself (EC-STATIC on a behavioral claim, or re-reading a value the code produced) AND which names no independent channel. Naming an evidence channel that the verifier could exercise counts even if the evaluator would have chosen a different one — Gate 8 enforces independence, not channel choice (inheriting the Gate 7 rule). Bucket / channel-choice debate is feedback, not a FAIL trigger.
