# Test-authoring guidance (positive rubric)

Binding parties: the `implementer` and `test-writer` agents (they reference this
file when writing tests). This is the POSITIVE counterpart to
[`tautological-assertion-rules.md`](tautological-assertion-rules.md) — that file
says what NOT to write; this one says what a STRONG test looks like, scoped by
AC type. It exists because a green suite proves the code is self-consistent, not
that it is correct: a dogfood build shipped a WCAG contrast solver that accepted
on a 2-decimal ROUNDED ratio and falsely reported a target as met, past 93
passing tests, because every test re-measured with the same rounded value the
code itself produced.

## When each technique applies

A **computational AC** is one whose PASS/FAIL hinges on a COMPUTED numeric or
algorithmic value — a contrast / luminance / color-space ratio, a rounding or
precision threshold, a hash / checksum / collision rate, a financial or unit
conversion, a parser / serializer round-trip, a distance / similarity /
statistical metric, or any "within X of Y" / "≥ / ≤ a numeric target" outcome.
Rules 1-4 below are MANDATORY for computational ACs (Gate 7 in
[`../../create-ticket/references/ac-quality-criteria.md`](../../create-ticket/references/ac-quality-criteria.md))
and recommended elsewhere. A purely structural AC (file exists, symbol exported,
exit code) needs only a direct assertion.

## Rubric

1. **Independent oracle (computational ACs).** Compare the implementation
   against an oracle that does NOT share its core: a third-party reference
   library (e.g. `colorjs.io` cross-checking a culori-based engine), a published
   formula / standard applied from first principles, or a hand-computed truth
   table with a cited source. NEVER take the implementation's own output —
   directly, via an alias, or by re-reading a field the code already rounded —
   as the expected value. That circularity is rejected by tautological rule R4.
   At the `thorough` / `exhaustive` depth tier, for a standard-backed
   computational target use **two or more mutually-validated independent
   oracles** with **at least one first-principles** (the spec formula,
   hand-implemented, no library) and trust a value only when they agree within
   an explicit tolerance — one library oracle silently shares that library's
   conventions. Copy the shape from
   [`independent-oracle-harness.md`](independent-oracle-harness.md). Where no
   second independent oracle exists, the single-oracle path stands (note it).

2. **Raw before rounded, with explicit tolerance.** Assert on the
   implementation's RAW, pre-rounding / pre-formatting value against the oracle
   with an explicit tolerance (`expect(raw).toBeCloseTo(oracle, 6)` or
   `|raw − oracle| ≤ 1e-6`). Do NOT gate acceptance on a display-rounded value
   and do NOT re-threshold a field the code itself rounds (e.g. asserting
   `result.ratio >= target` on a 2-decimal `ratio`) — display rounding hides a
   sub-threshold miss.

3. **Property / invariant tests.** For math / transform / algorithm code, assert
   the laws, not just point values: monotonicity, symmetry, idempotence,
   round-trip (`decode(encode(x)) == x`), gamut / range containment, and
   conservation. A property holds across a distribution; a point test holds at
   one point.
   When a second INDEPENDENT ALGORITHM for the same contract exists (e.g.
   CSS-MINDE vs chroma-clamping gamut mapping, two independent sorts), at the
   `thorough` / `exhaustive` depth tier add an **algorithm-vs-algorithm**
   differential within an explicit tolerance — a membership / containment check
   alone is necessary-not-sufficient, because a wrong result can still be
   in-range. Degrade to property coverage + a note where no second algorithm
   exists.

4. **Adversarial / non-finite / out-of-range inputs by default.** For any
   function taking external or untrusted input, include empty, `NaN`,
   `Infinity`, negative, zero, overflow, malformed, and out-of-gamut /
   out-of-range cases as STANDARD cases, not afterthoughts. These catch DoS
   hangs (e.g. an unbounded binary search on `Infinity`) and contract-violating
   outputs (e.g. impossible channel values) that happy-path fixtures miss.

   **Two classes of bad input — test BOTH, and never skip the second.** (a) *Parse-rejected*
   tokens (`NaN` / `Infinity` as literal keywords, malformed syntax) that the parser / validator
   rejects at the door: these exercise the cheap early-return error path, usually already correct.
   (b) *Parse-accepted-then-overflows* values that pass syntactic parsing but produce a
   non-finite / out-of-range INTERMEDIATE deeper in the algorithm — e.g. `oklch(0.5 1e400 30)`
   (scientific notation that parses to Infinity chroma), extreme-but-finite magnitudes, denormals,
   or values that overflow only after a multiply. Class (b) is where real DoS hangs and
   corrupt-success bugs live (an unbounded binary-search / clamp loop on an Infinity intermediate);
   a suite that tests only class (a) passes green while shipping the class-(b) bug. For every numeric
   input a computational AC accepts, include at least one class-(b) parse-accepted-overflow vector
   and assert the tool returns a bounded error (or a finite, in-contract result) — never hangs and
   never returns a non-error success carrying null / NaN fields.

   **Sibling-guard symmetry.** When the function under test shares an input parser / validation
   boundary with sibling tools (e.g. several MCP tools that each parse the same color string), the
   input-validation guard (finiteness / range / gamut) MUST either live in the SHARED parse /
   validation path so every sibling inherits it, OR be replicated AND adversarially tested in EVERY
   sibling tool that accepts that input class. A guard wired into one tool but absent from its
   analogous siblings is exactly the `CLAUDE.md ## Modifications` sibling-artifact miss — a dogfood
   build added a finite-components guard to the solver but not the analogous `gamut_map` /
   `parse_color` tools, shipping a live DoS hang reachable through the unguarded siblings while the
   guarded solver passed. Write the class-(b) adversarial test against EACH sibling tool, not only
   the one tool the AC names.

5. **Spec-completeness.** Assert every output field and guarantee the spec
   promises — a missing field, an absent `inGamut` flag, a dropped `deltaE`, or
   a "base color preserved" guarantee that no test checks is an untested
   contract. Enumerate the promised outputs and assert each.

6. **Black-box over white-box.** Exercise the public / protocol boundary (the
   real CLI, the real MCP `Client` over a transport, the exported API), not
   internal handlers reached by reflection. White-box calls bypass the schema /
   serialization layer where real consumers hit failures.

7. **Seeded fuzz over fixed points.** When inputs span a space, drive a seeded
   random sweep (fixed seed → deterministic, reproducible) instead of a handful
   of hard-coded fixtures, and cross-check each generated case against the
   oracle / invariant. A dozen fixed inputs is a dozen points; a seeded sweep is
   a distribution.
   At the `thorough` / `exhaustive` depth tier this is a **MUST**, not an
   encouragement: a computational / algorithmic AC MUST ship a **committed,
   fixed-seed** property-fuzz loop (the seed is hard-coded so the run is
   reproducible; a `mulberry32`-style PRNG seeded by a literal is the canonical
   shape — see
   [`independent-oracle-harness.md`](independent-oracle-harness.md)) over the
   input distribution, asserting the invariants / oracle agreement across a
   **tier-scaled minimum** number of cases (rule of thumb: `thorough` >= a few
   hundred per invariant family, `exhaustive` >= ~1000). The loop must be in the
   committed test file, not an ad-hoc external probe. Where the ecosystem has no
   PRNG idiom, or the AC is not computational, this degrades to the existing
   deterministic-grid coverage + a one-line note — never a block.

## No-oracle fallback

When the domain genuinely has no independent oracle (novel business logic),
satisfy the intent of rule 1 with: raw-value assertions against hand-computed
constants (rule 2) AND property / invariant coverage (rule 3) AND adversarial
inputs (rule 4). State in the AC / Implementation Notes that the no-oracle path
applies so the evaluator does not expect an oracle name.

## Enforcement

Rules 1-4 are enforced semantically by the `ac-evaluator`
(`agents/ac-evaluator.md` `## Oracle Independence (computational ACs)`) and at
authoring time by Gate 7 (`../../create-ticket/references/ac-quality-criteria.md`).
The static tautological rule R4 only grep-approximates oracle circularity — it
assumes any non-SUT import is independent, so a transitive-alias re-export of
the implementation can slip past R4 and is caught only by the evaluator's
semantic oracle check. Do not rely on R4 alone; write the test against a
genuinely independent oracle.
