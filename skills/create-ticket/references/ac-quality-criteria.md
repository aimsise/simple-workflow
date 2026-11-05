---
version: 1
binding_parties: [planner, ticket-evaluator]
canonical: true
companion: ac-quality-grading.md
---

# AC Quality Criteria (Canonical Contract)

This document is the **canonical**, **binding** source of truth for the AC quality rules in `/create-ticket` — every gate's scope, definition, classifiers, binding rules, requirements, exceptions, `n/a` conditions, kill switches, BAD/GOOD examples and size thresholds. The `planner` (drafting ACs) and the `ticket-evaluator` (judging them) MUST use it as their sole source of these rules; rubric text elsewhere in the plugin (`skills/create-ticket/SKILL.md`, `agents/ticket-evaluator.md`, etc.) only points back here or to the grading companion.

The `ticket-evaluator`'s grading procedure (how each verdict is assigned, the drift-prevention list, the Output Contract) lives only in the companion `ac-quality-grading.md` in this directory, inlined after this file into every `ticket-evaluator` spawn and not read by the `planner`; neither file restates the other. If this document and another file disagree on a gate rule, this document wins (the companion wins on the grading procedure), and the other file MUST be updated to remove the duplication.

## Terminology

- **AC**: one line item in the ticket's `## Acceptance Criteria` section.
- **Ticket-wide**: judged once for the ticket as a whole, not per AC.
- **Per-AC**: each AC is scored PASS/FAIL independently.
- **HOW**: a prescription of internal implementation detail (algorithm choice, specific library function, internal data structure, code snippet) that forecloses the implementer's design choices.
- **Observation point**: a concrete API surface a test asserts against — WHAT (the externally visible behaviour to assert), not HOW (the means to implement it).
- **Pre-dated ticket**: a ticket drafted before the section for Gate 6.5, 7, 8, 9 or 10 shipped in this file is graded `n/a` for that gate; a PASS verdict that did not apply a gate (Gate 6 included) implies no conformance to it.
- **Policy kill switch**: a gate's **Kill switch** names a `constraints.<key>` read from `{ticket-dir}/autopilot-policy.yaml`; `<key>: off` grades that gate `n/a` over the scope the paragraph states. Absent field / absent policy / unknown value → `auto` (gate active — fail-safe). At drafting (`/create-ticket` Phase 3) the per-ticket policy file is normally not yet written (Step W-8 propagates it later), so an authoring-time gate is active unless a policy file already exists in the ticket dir.

## Gate 1: Testability

**Scope**: per-AC.

**Definition**: each AC MUST be objectively verifiable with a single, unambiguous PASS/FAIL outcome. Replace vague adjectives with concrete thresholds, counts, exit codes, file paths, or substrings to grep.

- **BAD**: "Improve performance" (no threshold, subjective)
- **GOOD**: "Response time under 200ms for the 95th percentile of `/health` requests under 100 RPS"

- **BAD**: "The CLI is user-friendly"
- **GOOD**: "`cli --help` exits 0 and stdout contains the substrings `Usage:` and `--version`"

## Gate 2: Unambiguity

**Scope**: per-AC.

**Definition**: each AC MUST have exactly one reasonable interpretation. Any term with more than one meaning in context MUST be defined inline or by reference.

- **BAD**: "Support large files" (`large` undefined)
- **GOOD**: "Stream input files over 100 MiB without loading them fully into memory (RSS growth under 50 MiB measured by `/usr/bin/time -v`)"

- **BAD**: "Handle errors gracefully"
- **GOOD**: "On read failure, print `ERROR: cannot read <path>: <errno>` to stderr and exit 1; do not write any output file"

## Gate 3: Completeness

**Scope**: ticket-wide.

**Definition**: across the ticket (Scope + Acceptance Criteria + Implementation Notes), the following MUST be covered where relevant:

- Happy-path behaviour
- Named edge cases (empty input, oversized input, missing file, permission denied, concurrent access, etc. — whichever apply to the domain)
- Error handling contract (exit codes, error messages, cleanup guarantees)
- Named external dependencies (libraries, services, files)

- **BAD**: "Support multiple file formats" (which formats? what about unsupported input? symlinks? encoding?)
- **GOOD**: "Accept `.md` and `.txt` (UTF-8 only); reject other extensions with exit 1 and stderr `unsupported format: <ext>`; do not follow symlinks; depends on `gray-matter` ^4.0 for frontmatter parsing"

## Gate 4: Implementability

**Scope**: ticket-wide.

**Definition**: Scope + Implementation Notes MUST name concrete file paths and public contracts (exported function signatures, CLI subcommands, output file schemas). They MUST describe WHAT and WHY, never HOW.

- **BAD**: "Add search functionality" (no file, no contract)
- **GOOD**: "Add `src/search.ts` exporting `searchNotes(query: string): Note[]`; wire a new `search <query>` subcommand in `src/cli.ts`; tests in `tests/search.test.ts`. Why: there is no CLI query entry point today and users copy-paste grep commands."

### Over-specification Check (HOW detection)

Flag a foreclosing constraint that prescribes internal means rather than the external contract **wherever it appears in the ticket** — `### Scope`, `### Out of Scope`, OR Implementation Notes (the means-as-end error is the same in any section). Examples of HOW that MUST be flagged:

- "Use Node.js `stream.pipeline()` with a `Transform` stream and a 64 KiB chunk size" — prescribes internal machinery.
- "Implement with a red-black tree keyed by slug" — prescribes internal data structure.
- A ten-line code block that is essentially the implementation.

- **BAD (HOW)**: "Use Node.js `stream.pipeline()` with a Transform stream and 64KB chunk size"
- **GOOD (WHAT + WHY)**: "Use streaming to handle large files without loading them entirely into memory; peak RSS MUST stay under 50 MiB for a 1 GiB input"

### Representation foreclosure (a HOW sub-class — NOT the external contract)

A constraint foreclosing an internal **representation** (a numeric type, a precision model, a container, a storage encoding) is HOW — **unless that representation IS the external contract**. The discriminating test: does the spec advertise a behavioral END (exactness / losslessness / a round-trip / a bounded range / a canonical form) the foreclosed representation is REQUIRED to satisfy? If yes, the AC MUST state the END and leave the representation to the implementer; pinning the MEANS while advertising the END is a Gate 4 FAIL, since the means may silently violate the end.

- **BAD (HOW that hides an exactness violation)**: "Out of Scope: use a fixed-width float; values beyond its mantissa are out of scope" paired with an in-scope claim "round-trips every value losslessly" — the float means cannot satisfy the lossless end at an intermediate value, yet the foreclosure forbids the exact / arbitrary-precision representation that would.
- **GOOD (WHAT + WHY)**: "`parse(format(x)) == x` for every `x` in the supported domain (state the domain bound explicitly); any representation that achieves exact round-trip over that domain is acceptable."

A representation foreclosure is LEGITIMATE scope-bounding (NOT a FAIL) when the representation IS the observable contract — a wire / on-disk format, a declared arithmetic guarantee, an interop ABI — mirroring the observation-point carve-out below. A brief MAY bound the WHAT-domain ("integers beyond N are out of scope"); it MUST NOT bound the MEANS while advertising an END the means cannot meet. A foreclosure kept beside an advertised END on these grounds is recorded as a one-line Caveat naming why the representation IS the external contract (which wire / on-disk format, arithmetic guarantee or interop ABI); otherwise the AC is rewritten to assert the END and the foreclosure dropped.

### Observation-point carve-out (NOT HOW)

Naming an API or method **as a test assertion observation point** is NOT HOW and MUST NOT be flagged by the over-specification check (e.g., illustrative only): "assert that X is written to `process.stdout.write`" or "use `vi.spyOn(console, 'log')` in the test to verify the log line" names the externally observable surface the test attaches to — part of the PASS/FAIL contract, not a prescription of how the production code must be implemented.

Concrete carve-out examples that MUST be treated as PASS (not HOW; e.g., illustrative only — the named APIs stand for any language's output, logging or file-write surface):

- "Test asserts on `process.stdout.write` receiving a buffer whose UTF-8 decoding contains `OK\n`."
- "Test uses `vi.spyOn(console, 'log')` to capture the log call and asserts the first argument equals `"ready"`."
- "Test asserts `fs.writeFileSync` is called with path `out.json` and a JSON string parseable to `{ ok: true }`."

The production code may reach those observation points via any implementation (direct call, wrapped logger, stream pipe); the AC does not foreclose that choice.

## Gate 5: Size Fit

**Scope**: ticket-wide.

**Definition**: the declared size (S / M / L / XL) MUST be consistent with the scope of the ticket. Two axes are evaluated; a tiebreak rule applies when they disagree.

### Axis A — File count

| Size | Expected files touched |
|---|---|
| S    | 1-3 files |
| M    | 4-8 files |
| L    | 9+ files |
| XL   | Architecture-level change (module boundaries move, new subsystem introduced) |

### Axis B — AC count

| Size | Expected AC count |
|---|---|
| S    | 2-4 |
| M    | 4-8 |
| L    | 8-15 |
| XL   | 15+ |

### Tiebreak rule (MUST)

When the two axes point to different sizes (e.g., file count suggests S but AC count suggests M), the declared size is judged by this tiebreak:

- If the ticket body contains an explicit **rationale** explaining the mismatch (for example, "only 2 files but 6 ACs because the ACs are independent behavioural guarantees on one CLI entry point"), a **single axis** is sufficient: the declared size is consistent when the rationale is credible and at least one axis matches it.
- If no rationale is present, the declared size MUST match the axis that implies the larger size; a mismatch of one step (e.g., declared S but both axes imply M) is a Gate 5 FAIL.

The planner **MUST** write a one-line rationale when file-count and AC-count axes disagree on size (Gate 5 tiebreak enablement).

A minimum-AC-count floor of 2 ACs per ticket applies regardless of size.

## Gate 6: Capability Mapping

**Scope**: ticket-wide.

**Definition**: each **runtime/visual** AC MUST be bound to an upstream-detected capability (utility skill, MCP server, test runner, etc.) that the downstream verifier (`/impl` → `ac-evaluator`) can pick up from the ticket itself, so live evidence — not static code inspection — drives the PASS/FAIL verdict.

An AC is **runtime/visual** when its PASS/FAIL hinges on at least one of the following observation points (non-exhaustive minimum list of observation-point properties; each named technology is e.g., illustrative only):

- Live rendering of the artifact (the AC names a UI surface, page, screenshot, or pixel-level outcome that only materialises when the built code runs).
- Console-error count or any other browser-runtime log invariant.
- Keyboard focus or hover state (the AC names focus order, focus ring visibility, hover style, or any interactive state).
- WCAG contrast or any accessibility ratio measured against a rendered DOM.
- Network I/O (the AC asserts a request/response shape, a status code, or a wire-level payload).
- FS-state-dependent behaviour (the AC asserts a file is written/read/created/deleted, or that the program reacts to a specific on-disk state).

If none of these apply, the AC is **static** (file-grep / counter / exit-code verifiable) and no binding is required; a ticket with no runtime/visual AC is graded `n/a` for Gate 6.

**Binding rule** (per-AC): each runtime/visual AC MUST appear in the `Bound AC(s)` column of at least one row of the ticket's `### Capabilities` section, OR the AC MUST be rewritten as a static AC (e.g. assert a build-artifact byte sequence with `grep` rather than a rendered pixel); one with neither is a Gate 6 FAIL. When both the `Available user skills:` and `Available MCP servers:` probes report `(none)`, every runtime/visual AC MUST be rewritten as static OR listed under `#### Capability Gaps` — bound capabilities cannot be fabricated.

The planner **MUST** emit a `### Capabilities` section between `### Implementation Notes` and `### Claude Code Workflow` whenever Gate 6 applies — that is, whenever at least one AC is runtime/visual per the Gate 6 classifier list. When no AC is runtime/visual, the section is optional but a one-line note ("All ACs are static; no runtime binding required.") is encouraged for clarity.

**Capability shape** (per row): each `### Capabilities` row carries `Name | Type | Purpose | Used by | Bound AC(s)`. `Type` is one of `skill`, `agent`, `MCP server`, `test runner`, or a similarly recognisable label; `Used by` names the consumer phase / agent (e.g. `ac-evaluator`, `/impl`, main-thread orchestrator); `Bound AC(s)` lists the AC identifiers the capability is responsible for, empty only for demonstrative rows that bind no AC.

**Subagent / main-thread asymmetry**: Forked subagents inherit the parent session's MCP tool access when their `tools:` field is omitted (productive agents: `implementer`, `planner`, `researcher`, `test-writer`). Verdict / read-only agents (`ac-evaluator`, `code-reviewer`, `decomposer`, `security-scanner`, `ticket-evaluator`, `tune-analyzer`) carry explicit `tools:` allowlists and do NOT inherit MCP, so a `### Capabilities` row binding a runtime / visual AC with one of them in `Used by` MUST NOT reference an `mcp__<server>__*` capability (a `Name` starting with `mcp__` or an MCP-server `Type`); such a row is a Gate 6 FAIL. For verdict-side verification of an MCP-mediated effect, split the binding (a productive agent invokes the MCP; the verdict agent verifies through a plain Skill or a file-system invariant) or record the gap under `#### Capability Gaps`; cross-check this when binding.

A `#### Capability Gaps` subsection MAY follow the table, recording each runtime/visual AC that could not be bound and why. A non-empty Gaps list does NOT automatically PASS Gate 6 — every entry MUST also flow into the AC list as a static rewrite OR be acknowledged by the planner's rationale.

## Gate 6.5: Probe Completeness

**Scope**: ticket-wide; applies to every ticket a `planner` drafts from a spawn prompt carrying a non-empty `Available user skills:` and/or `Available MCP servers:` line (as supplied by `/create-ticket`, `/plan2doc`, or `/refactor` in their `## Pre-computed Context` block).

**Definition**: every entry of the orchestrator's `Available user skills:` AND `Available MCP servers:` probes (each line a comma-separated list; each trimmed item one entry) MUST be classified by the planner into exactly one of three buckets in the emitted ticket:

1. **Bound** — the entry appears as a `Name` cell in at least one row of `### Capabilities` whose `Bound AC(s)` column lists one or more AC IDs; the named consumer (`Used by` column) contractually invokes it during AC verification.

2. **Advisory** — the entry appears as a `Name` cell in at least one row of `### Advisory Capabilities` (a section emitted between `### Capabilities` and `#### Capability Gaps`), which the named consumer (`Used by` column) is recommended to consult during authoring (implementation reference, library docs, design guidance, etc.). Advisory rows carry **no `Bound AC(s)` column**: they do not drive PASS/FAIL verdicts. `/impl`, `/scout`, `/investigate`, and `/refactor` read the Advisory pathway and propagate it to productive subagents (`implementer`, `researcher`, `test-writer`) in a `## Advisory capabilities (per ticket)` spawn-prompt block; the productive subagents' `## Side-effect ban` carries an explicit advisory-invocation exception, so listed Advisory skills / MCP tools MAY be invoked during authoring without speculative-invocation violation. Fill `Used by` with the productive subagent(s) that would consult the entry; verdict / read-only agents (the Gate 6 asymmetry list) carry no advisory-invocation exception and MUST NOT appear in an Advisory row's `Used by`; an MCP entry whose Advisory `Used by` lists a verdict agent is a Gate 6.5 FAIL.

3. **Skipped with rationale** — the entry is named in a bullet of `#### Capability Skip Rationale` (a third subsection following `### Advisory Capabilities` and `#### Capability Gaps`). Each bullet carries one or more capability names and a one-line reason for non-applicability (e.g. "domain mismatch — entry targets mobile UI; this ticket is backend-only"). Entries sharing one reason MAY share one bullet (comma-separated names, one reason): one for the pipeline-orchestrator set (Self-skip exception below), one for the domain-mismatch set naming every entry it skips; a distinct reason gets its own bullet. A grouped bullet classifies every name it lists, so grouping alone is never a Gate 6.5 FAIL; an entry no bullet names in full stays unclassified (a `...`, "etc.", wildcard or "all others" names nothing).

A probe entry that appears in none of the three buckets is a Gate 6.5 FAIL — the planner MUST NOT silently drop a probe-visible capability.

**`(none)` exception**: when both probes report `(none)` in the spawn prompt, Gate 6.5 is vacuously satisfied — there is nothing to classify.

**Self-skip exception**: pipeline orchestrator skills (`scout`, `impl`, `audit`, `ship`, `autopilot`, `brief`, `catchup`, `create-ticket`, `investigate`, `plan2doc`, `refactor`, `test`, `tune`) MAY be classified as Skipped with the fixed rationale `pipeline orchestrator; not subagent-invocable per External Tool Integration Policy`, in one bullet naming each of them that the probe lists. This fixed-rationale path is automatic: the planner need not interrogate AC-relevance for these names.

**Planner MUST** classify every probe entry into one of three buckets — Bound (in `### Capabilities`), Advisory (in `### Advisory Capabilities`), or Skipped (in `#### Capability Skip Rationale`) — on first emit and on every retry re-emit. Silent omission of a probe-visible capability is FORBIDDEN. When in doubt, the default bucket is Advisory with a `Purpose` cell stating the candidate use case.

**Consumer-side consultation discipline (Recommending semantics)**: Advisory binding is **not merely permitting** — the productive consumer subagents (`implementer`, `researcher`, `test-writer`) MUST, for every Advisory entry whose `Used by` column lists them, either (a) **invoke** the listed Skill / `mcp__*` tool at least once during their work, OR (b) **record a one-line skip rationale** under `### Limitations` (or `Next Steps` when the consumer's return envelope has no `### Limitations` heading) explaining why the entry was not consulted. Silent omission is a contract violation, enforced by the agent body's `## Advisory Capabilities ## Consultation discipline` section.

## Gate 7: Oracle Independence (computational ACs)

**Scope**: per-AC, with a ticket-wide kill switch (see below).

**Definition**: an AC is **computational** when its PASS/FAIL hinges on a COMPUTED numeric or algorithmic value (one the implementation calculates). Non-exhaustive cues: a contrast / luminance / color-space ratio, a rounding or precision threshold, a hash / checksum / collision rate, a financial or unit conversion, a parser / serializer round-trip, a distance / similarity / statistical metric, any "within X of Y" or "≥ / ≤ a numeric target" outcome. A purely structural AC (file-grep / counter / exit-code verifiable) is **not** computational and is graded `n/a` for Gate 7.

**Independence requirement** (per computational AC): the AC — or its Implementation Notes — MUST name an **oracle independent of the implementation under test** (a third-party reference library that does NOT share the implementation's core, a published formula / standard the verifier can apply from first principles, or a hand-computed truth table with a cited source), and the expected value MUST come from that oracle, never from the implementation's own output (directly, via an alias, or by re-thresholding a field the code already rounded).

**Raw-value requirement**: the comparison MUST use the implementation's **raw, pre-rounding / pre-formatting** output against the oracle value with an **explicit tolerance** (e.g. `|raw − oracle| ≤ 1e-6`). Asserting on a display-rounded value, or re-thresholding the rounded field the code returns, is a Gate 7 FAIL — display rounding can mask a sub-threshold miss.

**Multi-oracle requirement (depth-gated, standard-backed computational ACs)**: at a resolved `evidence_floor` of `thorough` or `exhaustive` (see [`../../impl/references/verification-depth.md`](../../impl/references/verification-depth.md) effects ladder), an AC in a domain with a **published spec** (e.g., illustrative only: color / WCAG, crypto, dates, units, money rounding, spec parsers, accessibility ratios) MUST derive its expected value from **two or more oracles independent of the implementation's core, mutually-validated** — they MUST agree within an explicit tolerance BEFORE either is trusted — with **at least one derived from first principles** (the published spec formula, hand-implemented, no library at all); a single independent oracle suffices only at the `standard` floor. Canonical oracle-module shape: [`../../impl/references/independent-oracle-harness.md`](../../impl/references/independent-oracle-harness.md). **Degradation (never a block)**: with no published spec or no second independent oracle, the single-oracle path stands and the AC / Implementation Notes record a one-line Caveat that multi-oracle mutual validation was not available; Gate 7 never force-FAILs an AC for lacking a second oracle that does not exist. **At drafting** the `evidence_floor` is not yet resolved (it resolves at `/impl`), so a single named independent oracle satisfies the Gate 7 binding rule: the planner names a second, first-principles oracle where one exists (or states that only one exists), a missing second oracle or statement is a Caveat, not a ticket FAIL, and the two-oracle MUST binds the verifier once the floor resolves.

**No-oracle degradation**: when the domain has no independent oracle (novel business logic with no reference), Gate 7 is satisfied by an explicit fallback in the AC / Implementation Notes: (a) raw-value assertions with tolerance against hand-computed constants, AND (b) property / invariant coverage (monotonicity, symmetry, idempotence, round-trip, containment), AND (c) adversarial / non-finite / out-of-range inputs; the planner MUST state which path applies. Gate 7 never force-FAILs a ticket where no oracle is possible, but DOES FAIL a computational AC naming neither an oracle nor the fallback. Authoring rubric: [`../../impl/references/test-authoring-guidance.md`](../../impl/references/test-authoring-guidance.md); verifier-side enforcement: `agents/ac-evaluator.md` `## Oracle Independence (computational ACs)`.

**Binding rule** (per computational AC): each computational AC MUST either (a) name an independent oracle + a raw-value tolerance, OR (b) declare the no-oracle fallback above, OR (c) be rewritten as a static AC. A computational AC with none of these is a Gate 7 FAIL.

**Adversarial-input requirement** (every **external-input boundary (computational or behavioral)**): an AC whose value OR observable behaviour comes from a function taking external / untrusted input — computational (a computed value) OR behavioral (an observable runtime outcome: a returned value, status code, thrown error, wire payload) — MUST require adversarial / non-finite / out-of-range coverage (`NaN`, `Infinity`, empty, malformed, oversized, out-of-range), independently of the oracle vs no-oracle path; such an AC with zero adversarial coverage is a Gate 7 FAIL. Only this requirement and the sibling-guard requirement below extend to behavioral external-input ACs; the oracle + raw-value + tolerance requirements above stay computational-only. The coverage MUST include at least one **parse-accepted-then-overflows** vector — an input the parser ACCEPTS (satisfies the grammar) that yields a non-finite / out-of-range intermediate deeper in the algorithm (e.g. a syntactically-valid magnitude that overflows after a conversion) — NOT only parse-rejected `NaN` / `Infinity` keyword tokens. **Overflow-vector n/a (property-gated, never silent)**: the vector is owed wherever a step after parsing can go non-finite or out-of-range (a numeric conversion, magnitude arithmetic, a size / length / count that grows with the input); where the boundary has no such step, the planner records a one-line Caveat on the AC naming the boundary and stating that no post-parse step can overflow, and Gate 7 does not FAIL the AC for the missing vector; the rest of the adversarial coverage (empty, malformed, oversized, out-of-range) is still owed. Omitting both the vector and the Caveat stays a Gate 7 FAIL.

**Shared / sibling-guard requirement** (computational or behavioral external-input ACs sharing an input boundary): when the function behind a computational AC, or behind a behavioral AC on external / untrusted input, shares an input parser / validation boundary with sibling tools (e.g. several tools / endpoints that each parse the same input class), the input-validation guard (finiteness, range) MUST either (a) live in the SHARED boundary so every sibling inherits it, OR (b) be replicated AND adversarially tested in EVERY sibling tool that accepts that input class; a guard wired into one consumer but absent from its analogous siblings is a Gate 7 FAIL. **The sibling set is not confined to one ticket — it spans the whole product across ticket boundaries**: units that separate tickets EACH create consuming one common input class (each ticket creating a single unit, so its per-ticket `peer_set` is `false`) still form one sibling set the per-ticket peer signal cannot see, which the `decomposer` surfaces as the cross-ticket `shared_input_boundary` signal forwarded into each sibling's planner and ticket-evaluator spawn (see `agents/decomposer.md`). This is the SAME input-validation-strictness axis Gate 9 R2 owns, reached across tickets — NOT a new gate and NOT a re-home into Gate 10. **A sibling that DELEGATES to the shared parser is NOT automatically n/a**: its own surface still re-exposes the shared boundary (a round-trip / re-serialization / re-validation path that can leak on an input the shared parser accepted), so it MUST carry its own hostile / accept-set row (the Gate 9 R2 strictness-leniency probe, boundary-keyed) OR a one-line JUSTIFIED `n/a` a reviewer can challenge — delegation is NOT an automatic n/a, never a silent skip, and 'delegates to the shared parser' is itself NOT an acceptable n/a reason (an acceptable one names a different reason, e.g. the sibling forwards an opaque handle and never re-serializes the parsed value).

**Algorithm-vs-algorithm differential (depth-gated, EC-DIFFERENTIAL)**: when a computational AC's contract admits a **second, independent ALGORITHM** for the same result (e.g. two independent sorts; two serializers), verification at the `thorough` / `exhaustive` evidence_floor SHOULD cross-check the implementation against it **within an explicit tolerance**, beyond a membership / invariant test: a membership check ("result is sorted", "result is in-range") is **necessary-not-sufficient**, as a wrong-but-in-range result passes it. The AC / Implementation Notes SHOULD name such an algorithm where one exists so the verifier can run the differential; where none exists for the contract, the membership / property coverage stands and the AC records a one-line Caveat — never a force-FAIL.

**Kill switch**: `constraints.oracle_verification: off` grades Gate 7 `n/a` ticket-wide (Terminology: Policy kill switch); a brief-level `off` takes effect downstream at `/impl` and `ac-evaluator`.

## Gate 8: Independent Evidence

**Scope**: per-AC (behavioral ACs only), with a ticket-wide kill switch (`constraints.independent_evidence: off`).

**Definition**: an AC is **behavioral** when its PASS/FAIL hinges on observable runtime behaviour — a returned value, an emitted output, a status code, a rendered surface, a wire payload, a thrown error, a side effect. A purely structural AC (a file exists, a symbol is exported with a given signature, a flag is parsed) is graded `n/a` for Gate 8: its natural evidence is `EC-STATIC` and Gate 8 adds nothing. The five canonical evidence channels are defined in [`../../impl/references/evidence-channels.md`](../../impl/references/evidence-channels.md):

- **EC-ORACLE** — an expected value derived from an oracle that does not share the implementation's core (third-party reference library, published formula, hand-computed truth table); the Gate 7 channel for computational ACs.
- **EC-DIFFERENTIAL** — the implementation's output cross-checked against a separate reference implementation of the same contract.
- **EC-PROPERTY** — invariants the output must satisfy across a seeded input distribution (monotonicity, symmetry, idempotence, round-trip, containment), independent of any single expected value.
- **EC-RUNTIME** — black-box observation through the real public / protocol boundary (the real CLI, the real MCP `Client` over a transport, the exported API, a rendered DOM), never internal handlers reached by reflection.
- **EC-STATIC** — file-grep / counter / exit-code / signature inspection: necessary for structural ACs but NOT on its own an independent channel for a behavioral AC (the code can be statically well-formed and behaviourally wrong).

**Binding rule** (per behavioral AC): each behavioral AC — or its Implementation Notes — MUST name at least one evidence channel from {EC-ORACLE, EC-DIFFERENTIAL, EC-PROPERTY, EC-RUNTIME} independent of the implementation's own internals, OR be rewritten as a structural AC verifiable by EC-STATIC. The named channel is the evidence the AC's test is expected to exercise; a behavioral AC whose only stated evidence is the implementation re-asserting itself (EC-STATIC on a behavioral claim, or a test re-reading a field the code produced) is a Gate 8 FAIL. **Natural-channel sufficiency**: the channel a competent test already provides counts (a black-box CLI assertion is already EC-RUNTIME, a parser round-trip already EC-PROPERTY), so authoring needs no channel beyond the AC's natural evidence: the AUTHORING-time requirement is only this binding rule. Additional independent channels are a RUNTIME evidence-floor requirement on the verifier, mandated by the resolved `evidence_floor` (see [`../../impl/references/verification-depth.md`](../../impl/references/verification-depth.md) effects ladder + `### AC-shape evidence-independence floor`), where `evidence_floor = max(tier floor, AC-shape floor)`: ANY behavioral AC floors at `+1-independent` regardless of Size, so even at the `standard` tier the verifier must establish one independent channel BEYOND the natural one (a structural-only ticket floors at `EC-STATIC+natural`). `constraints.independent_evidence: off` restores the natural-channel-sufficient behaviour.

**Relationship to Gate 7**: Gate 7 is the per-computational-AC specialization of Gate 8, adding the raw-value + explicit-tolerance + adversarial-coverage + sibling-guard obligations. A computational AC is graded under BOTH gates, and satisfying Gate 7 satisfies Gate 8. A behavioral-but-not-computational AC (e.g. "on malformed input the CLI exits 2 and prints `ERROR: ...` to stderr") is graded under Gate 8 only, satisfied by naming EC-RUNTIME.

**Committed fixed-seed fuzz (depth-gated authoring guidance)**: a computational / algorithmic AC expected at the `thorough` / `exhaustive` evidence_floor SHOULD name in its Implementation Notes a committed, fixed-seed property-fuzz loop (EC-PROPERTY) over the input distribution; its absence is a Caveat, not a FAIL.

**Kill switch**: `constraints.independent_evidence: off` grades Gate 8 `n/a` ticket-wide (Terminology: Policy kill switch); Gate 7 alone then governs evidence independence. The Gate 7 kill switch `constraints.oracle_verification: off` independently disables the EC-ORACLE sub-case for computational ACs.

## Gate 9: Failure-Class Coverage

**Scope**: ticket-wide, keyed per **Scope-touched external boundary**, with a ticket-wide kill switch (`constraints.failure_class_coverage: off`).

**Boundary key**: a **Scope-touched external boundary** is any externally reachable surface the ticket's `### Scope` adds or changes — a public/exported function, a CLI subcommand, an HTTP/RPC endpoint, an exported API symbol, a file-format or wire-format, or a parser. Gate 9 keys ONLY on these AND on `>=2`-peer sets (a family of analogous sibling tools sharing an input class), a family not confined to one ticket: when separate tickets EACH create a unit consuming one common external input class (the cross-ticket sibling set of the Gate 7 sibling-guard requirement), every such unit is a Scope-touched boundary for Gate 9 even when its own ticket creates a single unit (per-ticket `peer_set: false`). The decomposer's `shared_input_boundary` signal naming which tickets belong is model judgment, not mechanically authoritative, so a missing or false signal does NOT exempt such a unit. Each member, including one that DELEGATES the input handling to a shared parser created elsewhere, owes its own R2 hostile / accept-set row or a justified `n/a` exactly as that Gate 7 requirement states (delegation is NOT an automatic n/a). Gate 9 does **not** fire on internal helpers, private functions, or single-call-site refactors (routine-ticket flood prevention): a ticket touching no external boundary is graded `n/a` for Gate 9 in full and the matrix is omitted.

**Definition**: for EACH Scope-touched external boundary, the ticket MUST carry the **failure-class coverage matrix** under `#### Failure-Class Coverage (Gate 9)` — four rows, each yielding >=1 AC OR a one-line `n/a` justification:

- **R1 FULL-DOMAIN INVARIANT**: a property/invariant AC quantifying over the WHOLE valid input domain, INCLUDING boundaries and extremes — min, max, empty, singleton, max-length, and just-inside-each-boundary — not a single happy-path fixture. **Round-trip losslessness (serialization / persistence / file-format / wire-format boundaries)**: when the boundary serializes, persists, or round-trips a value, the R1 invariant MUST include a `parse(serialize(x)) == x` property (and, where the format IS the persisted state, `load(save(x)) == x`) over the whole value domain, INCLUDING the fidelity-prone extremes: an empty key, an empty value, a value containing the format's own delimiter / separator / quote / newline, a duplicate key and an accessor / reserved key the host structure treats specially, and non-ASCII / unicode. **Forward-direction writer losslessness**: for a canonical Writer rendering a value into a string-form (a `format` / serialize path advertising lossless / exact / round-trip), the `parse(format(x)) == x` corpus MUST come from an INDEPENDENT generator sampling the **inter-anchor intermediate band** — values strictly between adjacent canonical anchors, INCLUDING just-below-the-next-anchor — not only the exact canonical anchors where rounding is a no-op, because an exactly-representable value the writer still rounds or quantizes (significant-figure / display rounding that corrupts a value the output grammar can represent exactly) is a fidelity-prone extreme an anchors-only grid never reaches. A format that silently drops, truncates, mangles, OR rounds an exactly-representable value at one of these extremes (a list rendering that cannot represent a value containing the format's own delimiter, a serializer that loses an accessor / reserved key, a writer that rounds an exactly-representable value to a lossy canonical string) FAILS R1 even when otherwise spec-faithful — a weaker-but-legal format choice is a coverage gap, not an excuse. Where the boundary genuinely cannot round-trip (a one-way digest / hash), R1 is a justified `n/a` naming why.
- **R2 HOSTILE + BOUNDED TERMINATION + RESOURCE-CAP**: malformed / oversized / empty / out-of-domain input yields a **bounded error in bounded time and space** — no hang, no unbounded allocation, no non-error "success" carrying corrupt output. This reuses the Gate 7 overflow-vector + watchdog requirement (a parse-accepted-then-overflows vector through a time-bounded watchdog), boundary-keyed: every external boundary gets its own hostile-input row, not only the one the motivating feature exercised. Where the boundary builds a structure from untrusted input (an object / map keyed by parsed headers, parsed JSON, or form / query / YAML fields), the hostile-input AC MUST also cover hostile KEYS, not only hostile values — prototype-pollution / accessor keys (e.g., illustrative only; the property is: a key that collides with the container's own structural members, an accessor / reserved key the host structure treats specially), duplicate / colliding keys, and empty / non-string keys — asserting no silent column-drop, no structure-metadata mutation, and no swallowed key (the structurally-correct fix is a null-prototype / own-properties-only container or a Map-equivalent). Beyond hostile values and keys, the row MUST probe **strictness-leniency** wherever a boundary is advertised **strict / canonical / exact / lowercase-only** OR parses a number through a lenient numeric primitive: feed inputs that satisfy the rules' *letter* yet exceed the *advertised* surface — an out-of-alphabet symbol a permissive matcher accepts (a non-ASCII / Unicode-digit / homoglyph numeral a Unicode-aware matcher or a lenient numeric primitive silently accepts before a unit), a sign / whitespace decoration a lenient primitive strips (a leading sign or surrounding-or-embedded whitespace before the digits), and a structurally-valid-but-non-canonical form the canonical writer would never emit (a leading-zero or an explicit-zero-component form) — and assert the enforced boundary equals the advertised one: each is EITHER rejected with the documented error OR normalized and proven idempotent (`parse(format(parse(x))) == parse(x)` AND `format(parse(x))` is canonical). A parser advertised strict that silently accepts a wider surface than it documents is a **strictness-leniency** gap even when no value is corrupted.
- **R3 DESCRIPTION-MATCHES-BEHAVIOR**: runtime behaviour matches the unit's own description / docstring / declared invariant / type annotation: the row's AC MUST RUN the unit through the real public / protocol boundary and assert the observed behaviour against the unit's OWN declared contract (a docstring claiming "returns a sorted copy" → assert the runtime output is a sorted copy AND a distinct object; a declared range / non-null invariant → assert the runtime value obeys it). This is the **EC-SELFDOC** evidence channel (failure mode A, description-vs-behavior drift — see [`../../impl/references/evidence-channels.md`](../../impl/references/evidence-channels.md)); the verifier-side consumer is the `doc-verifier` agent (and the `ac-evaluator` `## Independent Evidence` duty). A row asserting only that the docstring TEXT exists (a grep) without RUNning the unit against it is EC-STATIC on a behavioral claim and does NOT satisfy R3.
- **R4 DOC/INTERFACE TRUTHFULNESS**: each advertised example reproduces on a real build, and each advertised boundary equals the enforced boundary: (a) for each doc / README / `--help` / man-page worked-example the ticket adds or relies on, the row's AC MUST RUN that command against the real build and diff stdout / exit code against the documented output — byte-for-byte when the output is deterministic, an explicit tolerance otherwise (the AC names which); (b) for each advertised constraint / limit / range, the AC MUST feed a FORBIDDEN value (just past the advertised limit — MUST be rejected with the documented error) AND an ALLOWED value (just inside it — MUST be accepted) to the real boundary. This is the **EC-SELFDOC** channel (failure mode E, advertised-boundary != enforced-boundary); the verifier-side consumer is the `doc-verifier` agent under the `.simple-workflow/scratch/` exec carve-out. **Fail-open**: where the boundary advertises no example and no numeric / range limit, R4 is a justified `n/a` (not a FAIL); where the build genuinely cannot be exercised, the AC / verifier records a one-line Caveat rather than force-FAILing.

An `n/a` for any row MUST be justified, never implicit — same shape as Gate 6.5's classify-or-justify and Gate 6's `#### Capability Gaps`.

One AC MAY resolve both a Gate 7 sub-requirement and a Gate 9 row (e.g. the R2 row MAY cite the adversarial AC that satisfied Gate 7's external-input requirement); no duplicate AC is owed.

**Disjointness**: Gate 9 is disjoint from Gate 6.5 (capability-probe completeness — classifies probe-visible *capabilities*, not boundaries) and from Gate 3 (prose completeness — advisory, ticket-wide narrative, not per-boundary and not a row matrix).

**Kill switch**: `constraints.failure_class_coverage: off` grades Gate 9 `n/a` ticket-wide (Terminology: Policy kill switch), independently of `constraints.oracle_verification` (Gate 7), `constraints.independent_evidence` (Gate 8), and `constraints.eval_panel` (the failure-class eval panel).

## Gate 10: Peer-Set Uniformity

**Scope**: ticket-wide, keyed on `>=2`-peer sets, with a ticket-wide kill switch (`constraints.peer_uniformity: off`).

**Peer set**: a `>=2`-member family of analogous sibling units the ticket's `### Scope` adds or changes that share one category — several MCP tools that each parse the same input class, several HTTP handlers under one resource, several CLI subcommands of one verb family, several exported functions implementing variants of one operation. Gate 10 keys ONLY on such sets: a ticket whose Scope creates `<2` peers (a single new unit, or unrelated units in different categories) has no peer set to assert uniformity over and is graded `n/a` for Gate 10.

**Definition**: when the ticket's `### Scope` creates `>=2` peers in one category, the ticket MUST carry `>=1` **UNIFIED convention** AC (failure class D, cross-unit output uniformity) asserting that the peer set shares, as applicable, ONE of:

- a **single error convention** (every peer surfaces failure through the same error shape / status taxonomy / exception type — not one throwing, one returning `{error}`, one returning `null`);
- a **single success-envelope shape** (every peer returns the same wrapper / field naming / serialization shape for analogous results);
- a **single vocabulary per concept** (the same name for the same thing across peers — not `id` here and `key` there for the identical field);
- a **single wrapper for repeated boilerplate** (one shared helper / decorator / middleware for the cross-cutting concern, not N hand-rolled copies).

The unified AC MUST be **mechanically verifiable** per Gate 1: a `grep` / AST count over the peer set's source asserting the convention is present in EVERY peer (e.g. "`grep -c 'throwToolError(' src/tools/*.ts` equals the peer count", "every handler's success path returns `ok(...)`; assert `N` call sites, `0` bare-object returns", or an AC asserting a shared helper is called at all N peer sites with 0 hand-rolled copies). A vague "the tools are consistent" is a Gate 10 FAIL on Gate 1 grounds.

**Binding rule** (ticket-wide): a ticket whose Scope creates a `>=2`-peer set MUST carry `>=1` unified-convention AC over that set OR an explicit one-line `n/a` justification under the `#### Peer-Set Uniformity (Gate 10)` scaffold explaining why no unified convention applies (e.g. "n/a — the two peers share no analogous output surface; one returns a stream, one a scalar"). A peer set with neither is a Gate 10 FAIL.

**Disjointness**: Gate 10 (cross-unit *output* uniformity) is disjoint from Gate 7's sibling-input-guard (the *input*-validation axis — a finiteness / range / gamut guard shared across siblings) and from Gate 9 (*per-boundary* failure-class coverage). A ticket can need both: each peer carries its own Gate 9 matrix AND the set carries one Gate 10 unified AC.

**Decomposer hint**: the `decomposer` agent surfaces `peer_set: true|false` (and, when true, a `shared_conventions:` hint) per ticket in its `## Result` envelope (see `agents/decomposer.md`), forwarded into the planner spawn prompt as an upstream signal that a peer set exists. The hint is advisory: the planner re-derives the peer set from the final Scope table, and a missing or `false` decomposer hint does NOT exempt the planner from Gate 10 if the emitted Scope in fact creates `>=2` peers.

**Kill switch**: `constraints.peer_uniformity: off` grades Gate 10 `n/a` ticket-wide (Terminology: Policy kill switch), independently of `constraints.oracle_verification` (Gate 7, incl. its sibling-INPUT-guard), `constraints.failure_class_coverage` (Gate 9), `constraints.independent_evidence` (Gate 8), and `constraints.eval_panel` (the failure-class eval panel whose L-UNIFORMITY lens is the diff-time grader).

## Planner MUST

The planner MUST apply every gate's rules above to each draft it emits, the first included; each obligation is stated in its gate.

- **MUST**, whenever the ticket's Scope registers a tool / endpoint that an external caller invokes and that advertises a structured return (a typed object the caller consumes, not plain text), ensure the registration declares that return schema so the host validates the structured payload and the caller sees a typed return contract (e.g. an MCP server tool's `outputSchema`, illustrative only); a tool returning only unstructured text with no declared return schema is flagged (advisory unless the ticket's AC explicitly requires structured output). This is interface hygiene, orthogonal to Gate 7 oracle independence — it is NOT a Gate 7 FAIL trigger.
