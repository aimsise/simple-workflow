---
version: 1
binding_parties: [planner, ticket-evaluator]
canonical: true
---

# AC Quality Criteria (Canonical Contract)

This document is the **canonical**, **binding** source of truth for judging Acceptance Criteria (AC) quality in `/create-ticket`. Both the `planner` agent (when drafting ACs) and the `ticket-evaluator` agent (when judging them) MUST use this file as their sole rubric. Any rubric text that appears elsewhere in the plugin (`skills/create-ticket/SKILL.md`, `agents/ticket-evaluator.md`, etc.) is a pointer back to this file; this file is the only place where gate definitions, BAD/GOOD examples, and size thresholds live.

If this document and another file disagree, this document wins. The other file MUST be updated to remove the duplication.

## Terminology

- **AC**: one line item in the ticket's `## Acceptance Criteria` section.
- **Ticket-wide**: the judgment is made once for the ticket as a whole, not per AC.
- **Per-AC**: each AC is scored PASS/FAIL independently.
- **HOW**: a prescription of internal implementation detail (algorithm choice, specific library function, internal data structure, code snippet) that forecloses the implementer's design choices.
- **Observation point**: a concrete API surface that a test asserts against. Observation points are WHAT (the externally visible behaviour to assert), not HOW (the means to implement the behaviour).
- **Pre-dated ticket**: a ticket drafted before the section for Gate 6.5, 7, 8, 9 or 10 shipped in this file is graded `n/a` for that gate; a PASS verdict that did not apply a gate (Gate 6 included) implies no conformance to it.

## Gate 1: Testability

**Scope**: per-AC.

**Definition**: each AC MUST be objectively verifiable with a single, unambiguous PASS/FAIL outcome. Replace vague adjectives with concrete thresholds, counts, exit codes, file paths, or substrings to grep.

- **BAD**: "Improve performance" (no threshold, subjective)
- **GOOD**: "Response time under 200ms for the 95th percentile of `/health` requests under 100 RPS"

- **BAD**: "The CLI is user-friendly"
- **GOOD**: "`cli --help` exits 0 and stdout contains the substrings `Usage:` and `--version`"

**Evaluator MUST** mark an AC PASS if a reader can design a test (unit, integration, or grep-based file check) whose outcome is Boolean. Evaluator MUST NOT FAIL an AC merely because the threshold chosen is low or the test would be trivial — testability is about verifiability, not ambition.

## Gate 2: Unambiguity

**Scope**: per-AC.

**Definition**: each AC MUST have exactly one reasonable interpretation. Any term with more than one meaning in context MUST be defined inline or by reference.

- **BAD**: "Support large files" (`large` undefined)
- **GOOD**: "Stream input files over 100 MiB without loading them fully into memory (RSS growth under 50 MiB measured by `/usr/bin/time -v`)"

- **BAD**: "Handle errors gracefully"
- **GOOD**: "On read failure, print `ERROR: cannot read <path>: <errno>` to stderr and exit 1; do not write any output file"

Evaluator MUST mark PASS if two independent readers would converge on the same test. Evaluator MUST NOT FAIL for phrasing preference when the meaning is unambiguous.

## Gate 3: Completeness

**Scope**: ticket-wide.

**Definition**: across the ticket (Scope + Acceptance Criteria + Implementation Notes), the following MUST be covered where relevant:

- Happy-path behaviour
- Named edge cases (empty input, oversized input, missing file, permission denied, concurrent access, etc. — whichever apply to the domain)
- Error handling contract (exit codes, error messages, cleanup guarantees)
- Named external dependencies (libraries, services, files)

- **BAD**: "Support multiple file formats" (which formats? what about unsupported input? symlinks? encoding?)
- **GOOD**: "Accept `.md` and `.txt` (UTF-8 only); reject other extensions with exit 1 and stderr `unsupported format: <ext>`; do not follow symlinks; depends on `gray-matter` ^4.0 for frontmatter parsing"

Evaluator MUST list any obvious scope gap by name. Evaluator MUST NOT invent edge cases that are outside the ticket's stated scope, and MUST NOT FAIL Gate 3 for their absence.

**Impl-side panel carve-out**: the restriction above binds the `ticket-evaluator` only. It does NOT restrict the impl-side `ac-evaluator` failure-class panel, whose lenses MAY surface a failure-class coverage gap the planner dropped and report it as advisory `[MEDIUM]` coverage-gap Feedback; that is the grader acting as a coverage-gap finder, not a Gate 3 ticket-quality FAIL. The ticket-evaluator MUST NOT convert such an impl-side coverage-gap note into a Gate 3 FAIL. See `skills/impl/references/ac-evaluator-orchestration.md` `## Default failure-class panel` and `agents/ac-evaluator.md` `## Failure-class panel (default lenses)`.

## Gate 4: Implementability

**Scope**: ticket-wide.

**Definition**: Scope + Implementation Notes MUST name concrete file paths and public contracts (exported function signatures, CLI subcommands, output file schemas). They MUST describe WHAT and WHY, never HOW.

- **BAD**: "Add search functionality" (no file, no contract)
- **GOOD**: "Add `src/search.ts` exporting `searchNotes(query: string): Note[]`; wire a new `search <query>` subcommand in `src/cli.ts`; tests in `tests/search.test.ts`. Why: there is no CLI query entry point today and users copy-paste grep commands."

### Over-specification Check (HOW detection)

Flag a foreclosing constraint **wherever it appears in the ticket** — `### Scope`, `### Out of Scope`, OR Implementation Notes — that prescribes internal means rather than the external contract (the same means-as-end error is identical regardless of which section carries it). Examples of HOW that MUST be flagged:

- "Use Node.js `stream.pipeline()` with a `Transform` stream and a 64 KiB chunk size" — prescribes internal machinery.
- "Implement with a red-black tree keyed by slug" — prescribes internal data structure.
- A ten-line code block that is essentially the implementation.

- **BAD (HOW)**: "Use Node.js `stream.pipeline()` with a Transform stream and 64KB chunk size"
- **GOOD (WHAT + WHY)**: "Use streaming to handle large files without loading them entirely into memory; peak RSS MUST stay under 50 MiB for a 1 GiB input"

### Representation foreclosure (a HOW sub-class — NOT the external contract)

A constraint that forecloses an internal **representation** (a numeric type, a precision model, a container, a storage encoding) is HOW — **unless that representation IS the external contract**. The discriminating test: does the spec advertise a behavioral END (exactness / losslessness / a round-trip / a bounded range / a canonical form) that the foreclosed representation is REQUIRED to satisfy? If yes, the AC MUST state the END (the advertised property) and leave the representation to the implementer; pinning the MEANS while advertising the END is a Gate 4 FAIL, because the means may silently violate the end.

- **BAD (HOW that hides an exactness violation)**: "Out of Scope: use a fixed-width float; values beyond its mantissa are out of scope" paired with an in-scope claim "round-trips every value losslessly" — the float means cannot satisfy the lossless end at an intermediate value, yet the foreclosure forbids the exact / arbitrary-precision representation that would.
- **GOOD (WHAT + WHY)**: "`parse(format(x)) == x` for every `x` in the supported domain (state the domain bound explicitly); any representation that achieves exact round-trip over that domain is acceptable."

A representation foreclosure is LEGITIMATE scope-bounding (NOT a FAIL) when the representation IS the observable contract — a wire / on-disk format, a declared arithmetic guarantee, an interop ABI — mirroring the observation-point carve-out below. A brief MAY bound the WHAT-domain ("integers beyond N are out of scope"); it MUST NOT bound the MEANS while advertising an END the means cannot meet. A foreclosure kept beside an advertised END on these grounds is recorded as a one-line Caveat naming why the representation IS the external contract (which wire / on-disk format, arithmetic guarantee or interop ABI); otherwise the AC is rewritten to assert the END and the foreclosure dropped.

### Observation-point carve-out (NOT HOW)

Naming an API or method **as a test assertion observation point** is NOT HOW and MUST NOT be flagged by the over-specification check. When a ticket says "assert that X is written to `process.stdout.write`" or "use `vi.spyOn(console, 'log')` in the test to verify the log line", it is specifying the externally observable surface that the test will attach to — this is part of the PASS/FAIL contract, not a prescription of how the production code must be implemented.

Concrete carve-out examples that MUST be treated as PASS (not HOW):

- "Test asserts on `process.stdout.write` receiving a buffer whose UTF-8 decoding contains `OK\n`."
- "Test uses `vi.spyOn(console, 'log')` to capture the log call and asserts the first argument equals `"ready"`."
- "Test asserts `fs.writeFileSync` is called with path `out.json` and a JSON string parseable to `{ ok: true }`."

The production code may reach those observation points via any implementation (direct call, wrapped logger, stream pipe) — the AC does not foreclose that choice. Evaluator MUST NOT FAIL Gate 4 solely because a specific stdlib function name appears inside a test-observation clause.

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

When the two axes point to different sizes (e.g., file count suggests S but AC count suggests M), the evaluator MUST apply this tiebreak:

- If the ticket body contains an explicit **rationale** explaining the mismatch (for example, "only 2 files but 6 ACs because the ACs are independent behavioural guarantees on one CLI entry point"), judging on a **single axis** is sufficient for PASS. The evaluator MUST NOT FAIL Gate 5 when a credible rationale is present and at least one axis matches the declared size.
- If no rationale is present, the evaluator MUST pick the axis that implies the larger size and compare against the declared size; a mismatch of one step (e.g., declared S but both axes imply M) is FAIL.

A minimum-AC-count floor of 2 ACs per ticket applies regardless of size.

## Gate 6: Capability Mapping

**Scope**: ticket-wide.

**Definition**: when a ticket contains one or more **runtime/visual** ACs, each such AC MUST be bound to an upstream-detected capability (utility skill, MCP server, test runner, etc.) that the downstream verifier (`/impl` → `ac-evaluator`) can pick up from the ticket itself, so that live evidence — not static code inspection — drives the PASS/FAIL verdict.

An AC is **runtime/visual** when its PASS/FAIL hinges on at least one of the following observation points (non-exhaustive minimum list):

- Live rendering of the artifact (the AC names a UI surface, page, screenshot, or pixel-level outcome that only materialises when the built code runs).
- Console-error count or any other browser-runtime log invariant.
- Keyboard focus or hover state (the AC names focus order, focus ring visibility, hover style, or any interactive state).
- WCAG contrast or any accessibility ratio measured against a rendered DOM.
- Network I/O (the AC asserts a request/response shape, a status code, or a wire-level payload).
- FS-state-dependent behaviour (the AC asserts a file is written/read/created/deleted, or that the program reacts to a specific on-disk state).

If none of these apply, the AC is **static** (file-grep / counter / exit-code verifiable) and no binding is required; a ticket with no runtime/visual AC is graded `n/a` for Gate 6.

**Binding rule** (per-AC): each runtime/visual AC MUST appear in the `Bound AC(s)` column of at least one row of the ticket's `### Capabilities` section, OR the AC MUST be rewritten as a static AC (e.g. assert a build-artifact byte sequence with `grep` rather than a rendered pixel). A runtime/visual AC with no binding and no static rewrite is a Gate 6 FAIL. When both the `Available user skills:` and `Available MCP servers:` probes report `(none)`, every runtime/visual AC MUST be rewritten as static OR listed under `#### Capability Gaps` — bound capabilities cannot be fabricated.

**Capability shape** (per row): each `### Capabilities` row carries `Name | Type | Purpose | Used by | Bound AC(s)`. `Type` is one of `skill`, `agent`, `MCP server`, `test runner`, or a similarly recognisable label. `Used by` names the consumer phase / agent (e.g. `ac-evaluator`, `/impl`, main-thread orchestrator). `Bound AC(s)` lists the AC identifiers the capability is responsible for; an empty value is allowed only for demonstrative rows that bind no AC.

**Subagent / main-thread asymmetry**: Forked subagents inherit the parent session's MCP tool access when their `tools:` field is omitted (productive agents: `implementer`, `planner`, `researcher`, `test-writer`). Verdict / read-only agents (`ac-evaluator`, `code-reviewer`, `decomposer`, `security-scanner`, `ticket-evaluator`, `tune-analyzer`) carry explicit `tools:` allowlists and do NOT inherit MCP — when binding a runtime / visual AC to one of these agents, the `### Capabilities` row's `Used by` column MUST NOT reference an `mcp__<server>__*` capability for them (a row whose `Name` starts with `mcp__` or whose `Type` is an MCP server); such a row is a Gate 6 FAIL. Where verdict-side verification of an MCP-mediated effect is needed, split the binding (a productive agent invokes the MCP; the verdict agent verifies through a plain Skill or a file-system invariant) or record the gap under `#### Capability Gaps`. Cross-check this when binding.

A `#### Capability Gaps` subsection MAY follow the table to record runtime/visual ACs that could not be bound and the reason. A non-empty Gaps list does NOT automatically PASS Gate 6 — every entry MUST also flow into the AC list as a static rewrite OR be acknowledged by the planner's rationale.

## Gate 6.5: Probe Completeness

**Scope**: ticket-wide. Applies to every ticket drafted by a `planner` invocation whose spawn prompt carried a non-empty `Available user skills:` line and/or `Available MCP servers:` line (as supplied by `/create-ticket`, `/plan2doc`, or `/refactor` in their `## Pre-computed Context` block).

**Definition**: every entry in the orchestrator's `Available user skills:` probe AND every entry in the `Available MCP servers:` probe (each line is a comma-separated list; each trimmed item is one entry) MUST be classified by the planner into exactly one of three buckets in the emitted ticket:

1. **Bound** — the entry appears as a `Name` cell in at least one row of `### Capabilities` whose `Bound AC(s)` column lists one or more AC IDs. The capability is contractually invoked by the named consumer (`Used by` column) during AC verification.

2. **Advisory** — the entry appears as a `Name` cell in at least one row of `### Advisory Capabilities` (a section emitted between `### Capabilities` and `#### Capability Gaps`). The capability is recommended for the named consumer (`Used by` column) to consult during authoring (implementation reference, library docs, design guidance, etc.). Advisory rows carry **no `Bound AC(s)` column** because they do not drive PASS/FAIL verdicts. The Advisory pathway is read by `/impl`, `/scout`, `/investigate`, and `/refactor` and propagated to productive subagents (`implementer`, `researcher`, `test-writer`) under a `## Advisory capabilities (per ticket)` block in the spawn prompt; the productive subagents' `## Side-effect ban` carries an explicit advisory-invocation exception so listed Advisory skills / MCP tools MAY be invoked during authoring without speculative-invocation violation. Fill `Used by` with the productive subagent(s) that would consult the entry: verdict / read-only agents (the Gate 6 asymmetry list) MUST NOT appear in an Advisory row's `Used by`, because they keep explicit `tools:` allowlists and carry no advisory-invocation exception; an MCP entry whose Advisory `Used by` lists a verdict agent is a Gate 6.5 FAIL.

3. **Skipped with rationale** — the entry is named in a bullet of `#### Capability Skip Rationale` (a third subsection following `### Advisory Capabilities` and `#### Capability Gaps`). Each bullet carries one or more capability names and a one-line reason for non-applicability (e.g. "domain mismatch — entry targets mobile UI; this ticket is backend-only"). Entries sharing one reason MAY share one bullet (comma-separated names, one reason): one for the pipeline-orchestrator set (Self-skip exception below), one for the domain-mismatch set naming every entry it skips; a distinct reason gets its own bullet. A grouped bullet classifies every name it lists, so grouping alone is never a Gate 6.5 FAIL; an entry no bullet names in full stays unclassified (a `...`, "etc.", wildcard or "all others" names nothing).

A probe entry that appears in none of the three buckets is a Gate 6.5 FAIL — the planner MUST NOT silently drop a probe-visible capability.

**`(none)` exception**: when both probes report `(none)` in the spawn prompt, Gate 6.5 is vacuously satisfied — there is nothing to classify.

**Self-skip exception**: pipeline orchestrator skills (`scout`, `impl`, `audit`, `ship`, `autopilot`, `brief`, `catchup`, `create-ticket`, `investigate`, `plan2doc`, `refactor`, `test`, `tune`) MAY be classified as Skipped with the fixed rationale `pipeline orchestrator; not subagent-invocable per External Tool Integration Policy`, in one bullet naming each of them that the probe lists. The fixed-rationale path is automatic — the planner does NOT need to interrogate AC-relevance for these names.

**Evaluator MUST** verify each probe entry is classified into one of the three buckets, grading against the **draft-time** probe lines the orchestrator forwards in the evaluator spawn prompt — the same `Available user skills:` / `Available MCP servers:` lines the planner received. The evaluator is hermetic (Read / Write / Grep / Glob, no Bash) and does not re-run the probes. If the spawn prompt carries no probe lines, grade Gate 6.5 as `n/a` with a one-line note. Wording-only objections (e.g. "I would have phrased the skip rationale differently") MUST NOT FAIL Gate 6.5. Gate 6.5 enforces **completeness** (every probe entry is classified somewhere), not the **correctness** of the chosen bucket: the evaluator MUST NOT FAIL Gate 6.5 solely because the planner chose Advisory over Bound (or vice versa) for an entry whose classification is judgement-debatable. Bucket choice may be Feedback but is not a FAIL trigger, unless the entry was a runtime/visual capability that Gate 6 required as Bound (then Gate 6 FAILs, not Gate 6.5).

**Planner MUST** classify every probe entry on first emit and on every retry re-emit. The planner MUST NOT emit a ticket where a probe-visible skill or MCP server is silently absent from all three buckets. When in doubt, the default bucket is Advisory with a `Purpose` cell stating the candidate use case, never silent omission.

**Consumer-side consultation discipline (Recommending semantics)**: Advisory binding is **not merely permitting** — the productive consumer subagents (`implementer`, `researcher`, `test-writer`) MUST, for every Advisory entry whose `Used by` column lists them, either (a) **invoke** the listed Skill / `mcp__*` tool at least once during their work, OR (b) **record a one-line skip rationale** under `### Limitations` (or `Next Steps` when no `### Limitations` heading exists in the consumer's return envelope) explaining why the Advisory entry was not consulted. Silent omission is a contract violation enforced by the agent body's `## Advisory Capabilities ## Consultation discipline` section.

## Gate 7: Oracle Independence (computational ACs)

**Scope**: per-AC, with a ticket-wide kill switch (see below).

**Definition**: an AC is **computational** when its PASS/FAIL hinges on a COMPUTED numeric or algorithmic value — a value the implementation calculates rather than a structural fact. Non-exhaustive cues: a contrast / luminance / color-space ratio, a rounding or precision threshold, a hash / checksum / collision rate, a financial or unit conversion, a parser / serializer round-trip, a distance / similarity / statistical metric, any "within X of Y" or "≥ / ≤ a numeric target" outcome. An AC that is purely structural (file-grep / counter / exit-code verifiable) is **not** computational and is graded `n/a` for Gate 7.

**Independence requirement** (per computational AC): the AC — or its Implementation Notes — MUST name an **oracle independent of the implementation under test**: a third-party reference library that does NOT share the implementation's core, a published formula / standard the verifier can apply from first principles, or a hand-computed truth table with a cited source. The expected value MUST come from that oracle, never from the implementation's own output (directly, via an alias, or by re-thresholding a field the code already rounded).

**Raw-value requirement**: the comparison MUST be made on the implementation's **raw, pre-rounding / pre-formatting** output against the oracle value with an **explicit tolerance** (e.g. `|raw − oracle| ≤ 1e-6`). Asserting on a display-rounded value, or re-thresholding the rounded field the code returns, is a Gate 7 FAIL — display rounding can mask a sub-threshold miss.

**Multi-oracle requirement (depth-gated, standard-backed computational ACs)**: when the resolved `evidence_floor` is `thorough` or `exhaustive` (see [`../../impl/references/verification-depth.md`](../../impl/references/verification-depth.md) effects ladder) AND the AC sits in a domain with a **published spec** (color / WCAG, crypto, dates, units, money rounding, spec parsers, accessibility ratios), the expected value MUST be derived from **two or more oracles independent of the implementation's core, mutually-validated** — they MUST agree within an explicit tolerance BEFORE either is trusted — with **at least one derived from first principles** (the published spec formula, hand-implemented, no library at all). A single independent oracle suffices only at the `standard` floor. The canonical shape of such an oracle module is [`../../impl/references/independent-oracle-harness.md`](../../impl/references/independent-oracle-harness.md). **Degradation (never a block)**: where the domain has no published spec or no second independent oracle, the single-oracle path stands and the AC / Implementation Notes record a one-line Caveat that multi-oracle mutual validation was not available — Gate 7 never force-FAILs an AC for the absence of a second oracle that does not exist. **At drafting** the `evidence_floor` is not yet resolved (it resolves at `/impl`), so a single named independent oracle satisfies the Gate 7 binding rule: the planner names a second, first-principles oracle where one exists (or states that only one exists), a missing second oracle or a missing statement is a Caveat rather than a ticket FAIL, and the two-oracle MUST binds the verifier once the floor resolves.

**No-oracle degradation**: when no independent oracle exists for the domain (novel business logic with no reference), Gate 7 is satisfied by an explicit fallback in the AC / Implementation Notes: (a) raw-value assertions with tolerance against hand-computed constants, AND (b) property / invariant coverage (monotonicity, symmetry, idempotence, round-trip, containment), AND (c) adversarial / non-finite / out-of-range inputs. The planner MUST state which path applies. Gate 7 never force-FAILs a ticket where no oracle is possible, but it DOES FAIL a computational AC that names neither an oracle nor the fallback. See [`../../impl/references/test-authoring-guidance.md`](../../impl/references/test-authoring-guidance.md) for the authoring rubric and `agents/ac-evaluator.md` `## Oracle Independence (computational ACs)` for verifier-side enforcement.

**Binding rule** (per computational AC): each computational AC MUST either (a) name an independent oracle + a raw-value tolerance, OR (b) declare the no-oracle fallback above, OR (c) be rewritten as a static AC. A computational AC with none of these is a Gate 7 FAIL. Naming a library / formula / table the verifier could apply counts as an oracle even if the evaluator would have chosen a different one — Gate 7 enforces independence, not oracle choice.

**Adversarial-input requirement** (every **external-input boundary (computational or behavioral)**): additionally, when an AC's value OR observable behaviour comes from a function that takes external / untrusted input — whether the AC is computational (a computed value) OR behavioral (an observable runtime outcome: a returned value, status code, thrown error, wire payload) — the AC MUST require adversarial / non-finite / out-of-range coverage (`NaN`, `Infinity`, empty, malformed, oversized, out-of-range) — independently of the oracle vs no-oracle path. (The oracle + raw-value + tolerance requirements above stay computational-only; only this hostile-input coverage requirement and the sibling-guard requirement below broaden to behavioral external-input ACs.) A computational OR behavioral AC on an externally-fed function with zero adversarial coverage is a Gate 7 FAIL. The adversarial coverage MUST include at least one **parse-accepted-then-overflows** vector — an input the parser ACCEPTS (satisfies the grammar) that yields a non-finite / out-of-range intermediate deeper in the algorithm (e.g. a syntactically-valid magnitude that overflows after a conversion) — NOT only parse-rejected `NaN` / `Infinity` keyword tokens.

**Shared / sibling-guard requirement** (computational or behavioral external-input ACs sharing an input boundary): when the function behind a computational AC, or behind a behavioral AC on external / untrusted input, shares an input parser / validation boundary with sibling tools (e.g. several tools / endpoints that each parse the same input class), the input-validation guard (finiteness, range) MUST either (a) live in the SHARED boundary so every sibling inherits it, OR (b) be replicated AND adversarially tested in EVERY sibling tool that accepts that input class. A guard wired into one consumer but absent from its analogous siblings is a Gate 7 FAIL. **The sibling set is not confined to one ticket — it spans the whole product across ticket boundaries.** When separate tickets EACH create a unit consuming one common input class (so each ticket creates a single unit and its per-ticket `peer_set` is `false`), those units still form one sibling set that the per-ticket peer signal cannot see; the `decomposer` surfaces it as the cross-ticket `shared_input_boundary` signal forwarded into each sibling's planner and ticket-evaluator spawn (see `agents/decomposer.md`). This is the SAME input-validation-strictness axis Gate 9 R2 already owns, reached across tickets — NOT a new gate and NOT a re-home into Gate 10. **A sibling that DELEGATES to the shared parser is NOT automatically n/a.** A delegating sibling still re-exposes the shared boundary through its own surface (a round-trip / re-serialization / re-validation path that can leak on an input the shared parser accepted), so it MUST carry its own hostile / accept-set row (the Gate 9 R2 strictness-leniency probe, boundary-keyed) OR a one-line JUSTIFIED `n/a` a reviewer can challenge — delegation is NOT an automatic n/a, never a silent skip, and 'delegates to the shared parser' is itself NOT an acceptable n/a reason (the row is owed precisely because delegation re-exposes the boundary; an acceptable n/a names a different reason, e.g. the sibling forwards an opaque handle and never re-serializes the parsed value).

**Algorithm-vs-algorithm differential (depth-gated, EC-DIFFERENTIAL)**: when a computational AC's contract admits a **second, independent ALGORITHM** for the same result (e.g. two independent sorts; two serializers), at the `thorough` / `exhaustive` evidence_floor the verification SHOULD cross-check the implementation against that second algorithm **within an explicit tolerance**, not merely assert the output satisfies a membership / invariant test. A membership check ("result is sorted", "result is in-range") is **necessary-not-sufficient** — a wrong-but-in-range result passes it. Where a second independent algorithm exists, the AC / Implementation Notes SHOULD name it so the verifier can run the differential; where none exists for the contract, the membership / property coverage stands and the AC records a one-line Caveat — this is never a force-FAIL.

**Kill switch**: when `{ticket-dir}/autopilot-policy.yaml` sets `constraints.oracle_verification: off`, Gate 7 is graded `n/a` ticket-wide. Absent field / absent policy / unknown value → `auto` (Gate 7 active — fail-safe). At drafting (`/create-ticket` Phase 3) the per-ticket policy file is normally not yet written (Step W-8 propagates it later), so authoring-time Gate 7 is active unless a policy file already exists in the ticket dir; a brief-level `off` takes effect downstream at `/impl` and `ac-evaluator`.

## Gate 8: Independent Evidence

**Scope**: per-AC (behavioral ACs only), with a ticket-wide kill switch (`constraints.independent_evidence: off`).

**Definition**: an AC is **behavioral** when its PASS/FAIL hinges on observable runtime behaviour — a returned value, an emitted output, a status code, a rendered surface, a wire payload, a thrown error, a side effect. (A purely structural AC — a file exists, a symbol is exported with a given signature, a flag is parsed — is graded `n/a` for Gate 8; its natural evidence is `EC-STATIC` and Gate 8 adds nothing.) The five canonical evidence channels are defined in [`../../impl/references/evidence-channels.md`](../../impl/references/evidence-channels.md):

- **EC-ORACLE** — an expected value derived from an oracle that does not share the implementation's core (third-party reference library, published formula, hand-computed truth table). This is the Gate 7 channel for computational ACs.
- **EC-DIFFERENTIAL** — the implementation's output cross-checked against a separate reference implementation of the same contract.
- **EC-PROPERTY** — invariants the output must satisfy across a seeded input distribution (monotonicity, symmetry, idempotence, round-trip, containment), independent of any single expected value.
- **EC-RUNTIME** — black-box observation through the real public / protocol boundary (the real CLI, the real MCP `Client` over a transport, the exported API, a rendered DOM), never internal handlers reached by reflection.
- **EC-STATIC** — file-grep / counter / exit-code / signature inspection. Necessary for structural ACs but NOT an independent channel for a behavioral AC on its own (the code can be statically well-formed and behaviourally wrong).

**Binding rule** (per behavioral AC): each behavioral AC — or its Implementation Notes — MUST name at least one evidence channel from {EC-ORACLE, EC-DIFFERENTIAL, EC-PROPERTY, EC-RUNTIME} that is independent of the implementation's own internals, OR be rewritten as a structural AC verifiable by EC-STATIC. The named channel is the evidence the AC's test is expected to exercise; a behavioral AC whose only stated evidence is the implementation re-asserting itself (EC-STATIC on a behavioral claim, or a test that re-reads a field the code produced) is a Gate 8 FAIL. Naming a channel the verifier could exercise counts even if the evaluator would have chosen a different one — Gate 8 enforces independence, not channel choice; channel-choice debate is Feedback, not a FAIL trigger. **Natural-channel sufficiency**: the channel a competent test already provides counts — a black-box CLI assertion is already EC-RUNTIME, a parser round-trip is already EC-PROPERTY — so Gate 8 does NOT require an extra channel beyond what the AC's natural evidence already supplies, except where the resolved `evidence_floor` (see [`../../impl/references/verification-depth.md`](../../impl/references/verification-depth.md) effects ladder + `### AC-shape evidence-independence floor`) mandates additional independent channels. That floor is `evidence_floor = max(tier floor, AC-shape floor)`: ANY behavioral AC floors at `+1-independent` regardless of Size, so even at the `standard` tier the verifier must establish one independent channel BEYOND the natural one (a structural-only ticket floors at `EC-STATIC+natural`). This is a RUNTIME evidence-floor requirement on the verifier; the AUTHORING-time requirement is only the binding rule above (every behavioral AC names ≥1 independent channel), and `constraints.independent_evidence: off` restores the natural-channel-sufficient behaviour.

**Relationship to Gate 7**: Gate 7 is the per-computational-AC specialization of Gate 8 with the additional raw-value + explicit-tolerance + adversarial-coverage + sibling-guard obligations. A computational AC is graded under BOTH gates; satisfying Gate 7 satisfies Gate 8. A behavioral-but-not-computational AC (e.g. "on malformed input the CLI exits 2 and prints `ERROR: ...` to stderr") is graded under Gate 8 only and is satisfied by naming EC-RUNTIME.

**Committed fixed-seed fuzz (depth-gated authoring guidance)**: for a computational / algorithmic AC expected at the `thorough` / `exhaustive` evidence_floor, the AC SHOULD name in its Implementation Notes a committed, fixed-seed property-fuzz loop (EC-PROPERTY) over the input distribution; its absence is a Caveat, not a FAIL.

**Kill switch**: when `{ticket-dir}/autopilot-policy.yaml` sets `constraints.independent_evidence: off`, Gate 8 is graded `n/a` ticket-wide (Gate 7 alone then governs evidence independence). Absent field / absent policy / unknown value → `auto` (Gate 8 active — fail-safe). The Gate 7 kill switch `constraints.oracle_verification: off` independently disables the EC-ORACLE sub-case for computational ACs.

## Gate 9: Failure-Class Coverage

**Scope**: ticket-wide, keyed per **Scope-touched external boundary**, with a ticket-wide kill switch (`constraints.failure_class_coverage: off`).

**Boundary key**: a **Scope-touched external boundary** is any externally reachable surface the ticket's `### Scope` adds or changes — a public/exported function, a CLI subcommand, an HTTP/RPC endpoint, an exported API symbol, a file-format or wire-format, or a parser. Gate 9 keys ONLY on these AND on `>=2`-peer sets (a family of analogous sibling tools sharing an input class); the evaluator MUST NOT FAIL a boundary outside a `>=2`-peer set on a row the spec keys on peer sets. That family is not confined to one ticket: when separate tickets EACH create a unit consuming one common external input class, every such unit is a Scope-touched boundary for Gate 9 even when its own ticket creates a single unit (per-ticket `peer_set: false`). The decomposer's cross-ticket `shared_input_boundary` signal (Gate 7 sibling-guard requirement) names which tickets belong, but it is model judgment, not mechanically authoritative, so a missing or false signal does NOT exempt such a unit. Each member, including one that DELEGATES the input handling to a shared parser created elsewhere, owes its own R2 hostile / accept-set row or a justified `n/a` a reviewer can challenge — delegation is NOT an automatic n/a, and 'delegates to the shared parser' is not itself an acceptable n/a reason. Gate 9 does **not** fire on internal helpers, private functions, or single-call-site refactors (routine-ticket flood prevention) — a ticket that touches no external boundary is graded `n/a` for Gate 9 in full.

**Definition**: for EACH Scope-touched external boundary, the ticket MUST carry the **failure-class coverage matrix** under `#### Failure-Class Coverage (Gate 9)` — four rows, each yielding >=1 AC OR a one-line `n/a` justification:

- **R1 FULL-DOMAIN INVARIANT**: a property/invariant AC quantifying over the WHOLE valid input domain, INCLUDING boundaries and extremes — min, max, empty, singleton, max-length, and just-inside-each-boundary. (Not a single happy-path fixture: the invariant must hold across the domain, the extremes included.) **Round-trip losslessness (serialization / persistence / file-format / wire-format boundaries)**: when the boundary serializes, persists, or round-trips a value, the R1 invariant MUST include a `parse(serialize(x)) == x` property (and, where the format IS the persisted state, `load(save(x)) == x`) quantified across the whole value domain, INCLUDING the fidelity-prone extremes: an empty key, an empty value, a value that contains the format's own delimiter / separator / quote / newline, a duplicate key and an accessor / reserved key the host structure treats specially, and non-ASCII / unicode. **Forward-direction writer losslessness**: when a canonical Writer renders a value into a string-form (a `format` / serialize path that advertises lossless / exact / round-trip), the `parse(format(x)) == x` corpus MUST come from an INDEPENDENT generator that samples the **inter-anchor intermediate band** — values strictly between adjacent canonical anchors, INCLUDING just-below-the-next-anchor — not only the exact canonical anchors where rounding is a no-op; an exactly-representable value the writer nonetheless rounds or quantizes (significant-figure / display rounding that corrupts a value the output grammar can represent exactly) is a fidelity-prone extreme the anchors-only grid never reaches. A format that silently drops, truncates, mangles, OR rounds an exactly-representable value at one of these extremes (a list rendering that cannot represent a value containing the format's own delimiter, a serializer that loses an accessor / reserved key, a writer that rounds an exactly-representable value to a lossy canonical string) FAILS R1 even when it is otherwise spec-faithful — a weaker-but-legal format choice is a coverage gap, not an excuse. Where the boundary genuinely cannot round-trip (a one-way digest / hash), R1 is a justified `n/a` naming why.
- **R2 HOSTILE + BOUNDED TERMINATION + RESOURCE-CAP**: malformed / oversized / empty / out-of-domain input yields a **bounded error in bounded time and space** — no hang, no unbounded allocation, no non-error "success" carrying corrupt output. This reuses the Gate 7 overflow-vector + watchdog requirement (a parse-accepted-then-overflows vector through a time-bounded watchdog), boundary-keyed: every external boundary gets its own hostile-input row, not only the one the motivating feature exercised. Where the boundary builds a structure from untrusted input (an object / map keyed by parsed headers, parsed JSON, or form / query / YAML fields), the hostile-input AC MUST also cover hostile KEYS, not only hostile values — prototype-pollution / accessor keys (an accessor / reserved key the host structure treats specially), duplicate / colliding keys, and empty / non-string keys — asserting no silent column-drop, no structure-metadata mutation, and no swallowed key (the structurally-correct fix is a null-prototype / own-properties-only container or a Map-equivalent). Beyond hostile values and keys, the row MUST probe **strictness-leniency** wherever a boundary is advertised **strict / canonical / exact / lowercase-only** OR parses a number through a lenient numeric primitive: feed inputs that satisfy the rules' *letter* yet exceed the *advertised* surface — an out-of-alphabet symbol a permissive matcher accepts (a non-ASCII / Unicode-digit / homoglyph numeral a Unicode-aware matcher or a lenient numeric primitive silently accepts before a unit), a sign / whitespace decoration a lenient primitive strips (a leading sign or surrounding-or-embedded whitespace before the digits), and a structurally-valid-but-non-canonical form the canonical writer would never emit (a leading-zero or an explicit-zero-component form) — and assert the enforced boundary equals the advertised one: each is EITHER rejected with the documented error OR normalized and proven idempotent (`parse(format(parse(x))) == parse(x)` AND `format(parse(x))` is canonical). A parser advertised strict that silently accepts a wider surface than it documents is a **strictness-leniency** gap even when no value is corrupted.
- **R3 DESCRIPTION-MATCHES-BEHAVIOR**: runtime behaviour matches the unit's own description / docstring / declared invariant / type annotation — the code does what its own documentation says it does. Concretely, the row's AC MUST RUN the unit through the real public / protocol boundary and assert the observed behaviour against the unit's OWN declared contract (a docstring that claims "returns a sorted copy" → assert the runtime output is a sorted copy AND a distinct object; a declared range / non-null invariant → assert the runtime value obeys it). This is the **EC-SELFDOC** evidence channel (failure mode A, description-vs-behavior drift — see [`../../impl/references/evidence-channels.md`](../../impl/references/evidence-channels.md)); the verifier-side consumer is the `doc-verifier` agent (and the `ac-evaluator` `## Independent Evidence` duty). A row asserting only that the docstring TEXT exists (a grep) without RUNning the unit against it is EC-STATIC on a behavioral claim and does NOT satisfy R3.
- **R4 DOC/INTERFACE TRUTHFULNESS**: each advertised example reproduces on a real build, and each advertised boundary equals the enforced boundary. Concretely: (a) for each doc / README / `--help` / man-page worked-example the ticket adds or relies on, the row's AC MUST RUN that command against the real build and diff stdout / exit code against the documented output — byte-for-byte when the output is deterministic, an explicit tolerance otherwise (and the AC names which); (b) for each advertised constraint / limit / range, the AC MUST feed a FORBIDDEN value (just past the advertised limit — MUST be rejected with the documented error) AND an ALLOWED value (just inside the advertised limit — MUST be accepted) to the real boundary, so the enforced boundary is proven equal to the advertised one. This is the **EC-SELFDOC** channel (failure mode E, advertised-boundary != enforced-boundary); the verifier-side consumer is the `doc-verifier` agent under the `.simple-workflow/scratch/` exec carve-out. **Fail-open**: where the boundary advertises no example and no numeric / range limit, R4 is a justified `n/a` (not a FAIL); where the build genuinely cannot be exercised, the AC / verifier records a one-line Caveat rather than force-FAILing.

An `n/a` for any row MUST be justified, never implicit — same shape as Gate 6.5's classify-or-justify and Gate 6's `#### Capability Gaps`. Gate 9 FAILs only on a blank row (one carrying neither an AC nor a one-line `n/a` justification) or a boundary with no matrix at all; an `n/a` carrying a one-line reason (e.g. "R4 n/a — this boundary advertises no examples and no numeric limit") is a PASS.

**Enumerate, not re-grade**: Gate 9 only ENUMERATES which boundaries need an AC; Gate 7 and Gate 8 GRADE that AC once it exists (Gate 9 does not re-grade evidence independence). One AC MAY resolve both a Gate 7 sub-requirement and a Gate 9 row (e.g. the R2 row MAY cite the adversarial AC that satisfied Gate 7's external-input requirement); no duplicate AC is owed.

**Disjointness**: Gate 9 is disjoint from Gate 6.5 (capability-probe completeness — classifies probe-visible *capabilities*, not boundaries) and from Gate 3 (prose completeness — advisory, ticket-wide narrative, not per-boundary and not a row matrix).

**Kill switch**: when `{ticket-dir}/autopilot-policy.yaml` sets `constraints.failure_class_coverage: off`, Gate 9 is graded `n/a` ticket-wide. Absent field / absent policy / unknown value -> `auto` (Gate 9 active — fail-safe). It is independent of `constraints.oracle_verification` (Gate 7), `constraints.independent_evidence` (Gate 8), and `constraints.eval_panel` (the failure-class eval panel).

**Model-judgment caveat**: the ticket schema has no machine-readable external-boundary field, so which surfaces are Scope-touched external boundaries, and whether a row's AC is sufficient, are model judgment over the free-text Scope and ACs. Gate 9 enforces that the matrix is present and resolved (every row -> AC or justified `n/a`) per boundary; it does NOT and cannot mechanically verify that the boundaries were identified correctly or that each row's AC is adequate — that residual judgment is graded by the evaluator, not by a grep.

## Gate 10: Peer-Set Uniformity

**Scope**: ticket-wide, keyed on `>=2`-peer sets, with a ticket-wide kill switch (`constraints.peer_uniformity: off`).

**Peer set**: a `>=2`-member family of analogous sibling units the ticket's `### Scope` adds or changes that share one category — several MCP tools that each parse the same input class, several HTTP handlers under one resource, several CLI subcommands of one verb family, several exported functions implementing variants of one operation. Gate 10 keys ONLY on such sets. A ticket whose Scope creates `<2` peers (a single new unit, or unrelated units in different categories) is graded `n/a` for Gate 10 — there is no peer set over which uniformity could be asserted.

**Definition**: when the ticket's `### Scope` creates `>=2` peers in one category, the ticket MUST carry `>=1` **UNIFIED convention** AC (failure class D, cross-unit output uniformity) asserting that the peer set shares, as applicable, ONE of:

- a **single error convention** (every peer surfaces failure through the same error shape / status taxonomy / exception type — not one throwing, one returning `{error}`, one returning `null`);
- a **single success-envelope shape** (every peer returns the same wrapper / field naming / serialization shape for analogous results);
- a **single vocabulary per concept** (the same name for the same thing across peers — not `id` here and `key` there for the identical field);
- a **single wrapper for repeated boilerplate** (one shared helper / decorator / middleware for the cross-cutting concern, not N hand-rolled copies).

The unified AC MUST be **mechanically verifiable** per Gate 1 — a `grep` / AST count over the peer set's source asserting the convention is present in EVERY peer (e.g. "`grep -c 'throwToolError(' src/tools/*.ts` equals the peer count", or "every handler's success path returns `ok(...)`; assert `N` call sites, `0` bare-object returns"). A vague "the tools are consistent" is a Gate 10 FAIL on Gate 1 grounds.

**Binding rule** (ticket-wide): a ticket whose Scope creates a `>=2`-peer set MUST carry `>=1` unified-convention AC over that set OR an explicit one-line `n/a` justification under the `#### Peer-Set Uniformity (Gate 10)` scaffold explaining why no unified convention applies (e.g. "n/a — the two peers share no analogous output surface; one returns a stream, one a scalar"). Gate 10 FAILs only a peer set with neither a unified AC (mechanically verifiable, as above) nor a justified `n/a`. As with Gate 9, Gate 10 enforces **coverage presence** (a unified AC exists, or an `n/a` is justified), NOT AC adequacy — adequacy is graded by Gates 1-2 once the AC exists, and the diff-time L-UNIFORMITY lens grades the actual code.

**Disjointness**: Gate 10 (cross-unit *output* uniformity) is disjoint from Gate 7's sibling-input-guard (the *input*-validation axis — a finiteness / range / gamut guard shared across siblings) and from Gate 9 (*per-boundary* failure-class coverage). A ticket can need both: each peer carries its own Gate 9 matrix AND the set carries one Gate 10 unified AC.

**Decomposer hint**: the `decomposer` agent surfaces `peer_set: true|false` (and, when true, a `shared_conventions:` hint) per ticket in its `## Result` envelope (see `agents/decomposer.md`), forwarded into the planner spawn prompt, giving the planner an upstream signal that a peer set exists. The hint is advisory — the planner re-derives the peer set from the final Scope table; a missing or `false` decomposer hint does NOT exempt the planner from Gate 10 if the emitted Scope in fact creates `>=2` peers.

**Kill switch**: when `{ticket-dir}/autopilot-policy.yaml` sets `constraints.peer_uniformity: off`, Gate 10 is graded `n/a` ticket-wide. Absent field / absent policy / unknown value -> `auto` (Gate 10 active — fail-safe). It is independent of `constraints.oracle_verification` (Gate 7, incl. its sibling-INPUT-guard), `constraints.failure_class_coverage` (Gate 9), `constraints.independent_evidence` (Gate 8), and `constraints.eval_panel` (the failure-class eval panel whose L-UNIFORMITY lens is the diff-time grader).

**Model-judgment caveat**: which Scope units form a `>=2`-peer set is model judgment over free-text Scope, not a grep — Gate 10 enforces that the unified AC (or a justified `n/a`) is PRESENT for an identified peer set; it does not and cannot mechanically verify the model partitioned the peers correctly.

## Evaluator MUST NOT (drift-prevention list)

These rules bind the `ticket-evaluator` specifically and are intended to stop the pedantic-drift failure mode where successive rounds invent new objections. Every gate-specific `MUST NOT FAIL` condition (its `n/a` cases, its kill switch, and carve-outs such as the Gate 3 impl-side panel carve-out and the Gate 4 observation-point carve-out) is stated in that gate and binds equally.

- **MUST NOT** FAIL an AC on the basis of wording or phrasing preference alone. If the meaning is unambiguous and testable, the AC passes Gates 1 and 2 regardless of whether the evaluator would have phrased it differently.
- **MUST NOT** introduce a new FAIL on content that was revised in direct response to a previous round's feedback, unless the previous feedback itself promoted that new concern. Feedback-guided revisions MUST be treated as settled for the specific point they addressed; raising a different objection on the same text in the next round is drift and is forbidden.
- **MUST NOT** FAIL Gate 9 or Gate 10 on adequacy or choice. Both enforce coverage **presence**: each Scope-touched boundary's R1-R4 rows resolve to an AC or a justified `n/a` (Gate 9), and each `>=2`-peer set carries a unified-convention AC or a justified `n/a` (Gate 10). The evaluator MUST NOT FAIL either gate merely because it would have written a different AC for a row or unified a different convention; AC adequacy is graded by Gates 1-8 once the AC exists, and AC / convention-choice debate is Feedback, not a FAIL trigger.

## Planner MUST

- **MUST** draft each AC so it satisfies Gates 1 and 2 on first pass (concrete thresholds, one interpretation).
- **MUST** ensure Scope + Implementation Notes name file paths and public contracts (Gate 4 WHAT).
- **MUST NOT** embed code snippets that prescribe internal algorithms (Gate 4 HOW).
- **MUST** write a one-line rationale when file-count and AC-count axes disagree on size (Gate 5 tiebreak enablement).
- **MUST** emit a `### Capabilities` section between `### Implementation Notes` and `### Claude Code Workflow` whenever Gate 6 applies — that is, whenever at least one AC is runtime/visual per the Gate 6 classifier list. Each row carries `Name | Type | Purpose | Used by | Bound AC(s)`, and every runtime/visual AC MUST appear in at least one row's `Bound AC(s)` column OR be rewritten as a static AC. When no AC is runtime/visual, the section is optional but a one-line note ("All ACs are static; no runtime binding required.") is encouraged for clarity.
- **MUST** classify every probe entry (from `Available user skills:` AND `Available MCP servers:` in the spawn prompt) into one of three buckets — Bound (in `### Capabilities`), Advisory (in `### Advisory Capabilities`), or Skipped (in `#### Capability Skip Rationale`) — per Gate 6.5. Silent omission of a probe-visible capability is FORBIDDEN.
- **MUST**, for every computational AC (per the Gate 7 classifier), either name an oracle independent of the implementation + a raw-value tolerance, OR declare the no-oracle fallback (raw-value + property/invariant + adversarial coverage), OR rewrite the AC as static. Re-thresholding the implementation's own rounded output is a Gate 7 FAIL.
- **MUST**, for an MCP-server ticket, ensure each registered tool declares an `outputSchema` (zod shape) so the SDK validates `structuredContent` server-side and the calling LLM sees a typed return contract; a tool returning only text content with no `outputSchema` is flagged (advisory unless the ticket's AC explicitly requires structured output). This is MCP-protocol hygiene, orthogonal to Gate 7 oracle independence — it is NOT a Gate 7 FAIL trigger.
- **MUST**, for every **Scope-touched external boundary** (public / exported function, CLI subcommand, endpoint, exported API symbol, file-format / wire-format, or parser — and every `>=2`-peer sibling set sharing an input class) per the Gate 9 classifier, emit the **failure-class coverage matrix**: each of the four rows (R1 FULL-DOMAIN INVARIANT, R2 HOSTILE + BOUNDED TERMINATION + RESOURCE-CAP, R3 DESCRIPTION-MATCHES-BEHAVIOR, R4 DOC/INTERFACE TRUTHFULNESS) MUST resolve to >=1 AC OR a one-line `n/a` justification (never an implicit blank). A ticket touching no external boundary (internal-helper-only) is `n/a` for Gate 9 — the matrix is omitted. This MUST is graded `n/a` ticket-wide under `constraints.failure_class_coverage: off`.
- **MUST**, for every **behavioral** AC (per the Gate 8 classifier — PASS/FAIL hinges on observable runtime behaviour, not a structural fact), name at least one independent evidence channel (EC-ORACLE / EC-DIFFERENTIAL / EC-PROPERTY / EC-RUNTIME per `../../impl/references/evidence-channels.md`) in the AC body or its Implementation Notes, OR rewrite the AC as a structural AC (EC-STATIC). The AC's natural channel counts (a black-box CLI assertion is EC-RUNTIME, a parser round-trip is EC-PROPERTY) — no extra channel need be NAMED at authoring time at any tier (the RUNTIME `evidence_floor` governs how many independent channels the evaluator establishes; under the AC-shape floor a behavioral AC floors at `+1-independent` even at `standard` — see Gate 8 above and `../../impl/references/verification-depth.md` `### AC-shape evidence-independence floor` — but that is the evaluator's obligation, not an extra authoring burden). A computational AC satisfies this via Gate 7 (EC-ORACLE). This MUST is graded `n/a` ticket-wide under `constraints.independent_evidence: off`.
- **MUST**, whenever the ticket's `### Scope` creates a `>=2`-peer set (a family of analogous sibling units sharing one category — peer tools / endpoints / subcommands / functions) per the Gate 10 classifier, assert `>=1` **UNIFIED convention** AC over the set — a single error convention / single success-envelope shape / single vocabulary per concept / single wrapper for repeated boilerplate — drafted so it is mechanically grep/AST-verifiable across EVERY peer (e.g. an AC asserting a shared helper is called at all N peer sites with 0 hand-rolled copies), OR record a one-line `n/a` justification under `#### Peer-Set Uniformity (Gate 10)`. A peer set with neither is a Gate 10 FAIL. A ticket whose Scope creates `<2` peers is `n/a` for Gate 10. This MUST is graded `n/a` ticket-wide under `constraints.peer_uniformity: off`.

## Output Contract (Evaluator)

The evaluator's return block MUST follow the format defined in `agents/ticket-evaluator.md` (Result / Status / Gate Results / Issues / Feedback). This contract file governs the content of the judgement; the evaluator file governs its shape.
