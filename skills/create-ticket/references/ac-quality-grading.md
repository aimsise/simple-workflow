---
version: 1
binding_parties: [ticket-evaluator]
canonical: true
companion: ac-quality-criteria.md
---

# AC Quality Grading Procedure (Canonical Contract)

This document is the **canonical**, **binding** source of truth for how the `ticket-evaluator` agent grades Acceptance Criteria (AC) quality in `/create-ticket`: how each gate's verdict is assigned, each gate's Evaluator MUST checks and MUST NOT FAIL conditions, the Feedback-not-FAIL limits, the model-judgment caveats, the drift-prevention list and the Output Contract. It binds the `ticket-evaluator` only; the `planner` does not read it.

Every gate rule (scope, definition, classifiers, binding rules, requirements, exceptions, ticket-side `n/a` conditions, kill switches, BAD/GOOD examples, size thresholds) lives only in the companion rules file `ac-quality-criteria.md` in the same directory, which is inlined before this file in the same canonical block of every `ticket-evaluator` spawn; neither file restates the other. A Caveat-not-FAIL limit that carries a drafting obligation (the ticket records a one-line Caveat instead of failing) stays with its rule text in the rules file. The only `n/a` statements here are verdicts the planner cannot affect: Gate 6.5 graded `n/a` when the evaluator's spawn prompt carries no probe lines, and a Gate 9 row's justified `n/a` graded PASS. Each `## Gate` heading below mirrors the rules file's heading: grade a gate by its rule text there plus the procedure under the same heading here ("Grade per the rule text; no additional procedure." means the rule text alone).

If this document and another file disagree on the grading procedure, this document wins (the rules file wins on a gate rule). The other file MUST be updated to remove the duplication.

## Gate 1: Testability

**Evaluator MUST** mark an AC PASS if a reader can design a test (unit, integration, or grep-based file check) whose outcome is Boolean. Evaluator MUST NOT FAIL an AC merely because the threshold chosen is low or the test would be trivial — testability is about verifiability, not ambition.

## Gate 2: Unambiguity

Evaluator MUST mark PASS if two independent readers would converge on the same test. Evaluator MUST NOT FAIL for phrasing preference when the meaning is unambiguous.

## Gate 3: Completeness

Evaluator MUST list any obvious scope gap by name. Evaluator MUST NOT invent edge cases that are outside the ticket's stated scope, and MUST NOT FAIL Gate 3 for their absence.

**Impl-side panel carve-out**: the restriction above binds the `ticket-evaluator` only. It does NOT restrict the impl-side `ac-evaluator` failure-class panel, whose lenses MAY surface a failure-class coverage gap the planner dropped and report it as advisory `[MEDIUM]` coverage-gap Feedback; that is the grader acting as a coverage-gap finder, not a Gate 3 ticket-quality FAIL. The ticket-evaluator MUST NOT convert such an impl-side coverage-gap note into a Gate 3 FAIL. See `skills/impl/references/ac-evaluator-orchestration.md` `## Default failure-class panel` and `agents/ac-evaluator.md` `## Failure-class panel (default lenses)`.

## Gate 4: Implementability

**Observation-point carve-out**: Evaluator MUST NOT FAIL Gate 4 solely because a specific stdlib function name appears inside a test-observation clause.

## Gate 5: Size Fit

**Tiebreak procedure**: when the two axes disagree, the evaluator MUST apply the rules file's tiebreak. With a rationale present, judging on a single axis is sufficient for PASS, and the evaluator MUST NOT FAIL Gate 5 when a credible rationale is present and at least one axis matches the declared size. With no rationale present, the evaluator MUST pick the axis that implies the larger size and compare against the declared size.

## Gate 6: Capability Mapping

Grade per the rule text; no additional procedure.

## Gate 6.5: Probe Completeness

**Evaluator MUST** verify each probe entry is classified into one of the three buckets, grading against the **draft-time** probe lines the orchestrator forwards in the evaluator spawn prompt — the same `Available user skills:` / `Available MCP servers:` lines the planner received. The evaluator is hermetic (Read / Write / Grep / Glob, no Bash) and does not re-run the probes. If the spawn prompt carries no probe lines, grade Gate 6.5 as `n/a` with a one-line note. Wording-only objections (e.g. "I would have phrased the skip rationale differently") MUST NOT FAIL Gate 6.5. Gate 6.5 enforces **completeness** (every probe entry is classified somewhere), not the **correctness** of the chosen bucket: the evaluator MUST NOT FAIL Gate 6.5 solely because the planner chose Advisory over Bound (or vice versa) for an entry whose classification is judgement-debatable. Bucket choice may be Feedback but is not a FAIL trigger, unless the entry was a runtime/visual capability that Gate 6 required as Bound (then Gate 6 FAILs, not Gate 6.5).

## Gate 7: Oracle Independence (computational ACs)

**Verdict limit**: Naming a library / formula / table the verifier could apply counts as an oracle even if the evaluator would have chosen a different one — Gate 7 enforces independence, not oracle choice.

## Gate 8: Independent Evidence

**Verdict limit**: Naming a channel the verifier could exercise counts even if the evaluator would have chosen a different one — Gate 8 enforces independence, not channel choice; channel-choice debate is Feedback, not a FAIL trigger.

## Gate 9: Failure-Class Coverage

**Verdict limit (boundary key)**: the evaluator MUST NOT FAIL a boundary outside a `>=2`-peer set on a row the spec keys on peer sets.

Gate 9 FAILs only on a blank row (one carrying neither an AC nor a one-line `n/a` justification) or a boundary with no matrix at all; an `n/a` carrying a one-line reason (e.g. "R4 n/a — this boundary advertises no examples and no numeric limit") is a PASS.

**Enumerate, not re-grade**: Gate 9 only ENUMERATES which boundaries need an AC; Gate 7 and Gate 8 GRADE that AC once it exists (Gate 9 does not re-grade evidence independence).

**Model-judgment caveat**: the ticket schema has no machine-readable external-boundary field, so which surfaces are Scope-touched external boundaries, and whether a row's AC is sufficient, are model judgment over the free-text Scope and ACs. Gate 9 enforces that the matrix is present and resolved (every row -> AC or justified `n/a`) per boundary; it does NOT and cannot mechanically verify that the boundaries were identified correctly or that each row's AC is adequate — that residual judgment is graded by the evaluator, not by a grep.

## Gate 10: Peer-Set Uniformity

**Verdict limit**: Gate 10 FAILs only a peer set with neither a unified AC (mechanically verifiable, as the rules file's Gate 10 requires) nor a justified `n/a`. As with Gate 9, Gate 10 enforces **coverage presence** (a unified AC exists, or an `n/a` is justified), NOT AC adequacy — adequacy is graded by Gates 1-2 once the AC exists, and the diff-time L-UNIFORMITY lens grades the actual code.

**Model-judgment caveat**: which Scope units form a `>=2`-peer set is model judgment over free-text Scope, not a grep — Gate 10 enforces that the unified AC (or a justified `n/a`) is PRESENT for an identified peer set; it does not and cannot mechanically verify the model partitioned the peers correctly.

## Evaluator MUST NOT (drift-prevention list)

These rules bind the `ticket-evaluator` specifically and are intended to stop the pedantic-drift failure mode where successive rounds invent new objections. Every gate-specific `MUST NOT FAIL` condition (its `n/a` cases, its kill switch, and carve-outs such as the Gate 3 impl-side panel carve-out and the Gate 4 observation-point carve-out) is stated under that gate, in this file or in the rules file, and binds equally.

- **MUST NOT** FAIL an AC on the basis of wording or phrasing preference alone. If the meaning is unambiguous and testable, the AC passes Gates 1 and 2 regardless of whether the evaluator would have phrased it differently.
- **MUST NOT** introduce a new FAIL on content that was revised in direct response to a previous round's feedback, unless the previous feedback itself promoted that new concern. Feedback-guided revisions MUST be treated as settled for the specific point they addressed; raising a different objection on the same text in the next round is drift and is forbidden.
- **MUST NOT** FAIL Gate 9 or Gate 10 on adequacy or choice. Both enforce coverage **presence**: each Scope-touched boundary's R1-R4 rows resolve to an AC or a justified `n/a` (Gate 9), and each `>=2`-peer set carries a unified-convention AC or a justified `n/a` (Gate 10). The evaluator MUST NOT FAIL either gate merely because it would have written a different AC for a row or unified a different convention; AC adequacy is graded by Gates 1-8 once the AC exists, and AC / convention-choice debate is Feedback, not a FAIL trigger.

## Output Contract (Evaluator)

The evaluator's return block MUST follow the format defined in `agents/ticket-evaluator.md` (Result / Status / Gate Results / Issues / Feedback). This file and the rules file `ac-quality-criteria.md` govern the content of the judgement; the evaluator file governs its shape.
