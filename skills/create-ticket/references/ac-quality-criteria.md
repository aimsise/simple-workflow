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

Evaluator MUST list any obvious scope gap by name. Evaluator MUST NOT invent edge cases that are outside the ticket's stated scope.

## Gate 4: Implementability

**Scope**: ticket-wide.

**Definition**: Scope + Implementation Notes MUST name concrete file paths and public contracts (exported function signatures, CLI subcommands, output file schemas). They MUST describe WHAT and WHY, never HOW.

- **BAD**: "Add search functionality" (no file, no contract)
- **GOOD**: "Add `src/search.ts` exporting `searchNotes(query: string): Note[]`; wire a new `search <query>` subcommand in `src/cli.ts`; tests in `tests/search.test.ts`. Why: there is no CLI query entry point today and users copy-paste grep commands."

### Over-specification Check (HOW detection)

Flag Implementation Notes that prescribe internal means rather than the external contract. Examples of HOW that MUST be flagged:

- "Use Node.js `stream.pipeline()` with a `Transform` stream and a 64 KiB chunk size" — prescribes internal machinery.
- "Implement with a red-black tree keyed by slug" — prescribes internal data structure.
- A ten-line code block that is essentially the implementation.

- **BAD (HOW)**: "Use Node.js `stream.pipeline()` with a Transform stream and 64KB chunk size"
- **GOOD (WHAT + WHY)**: "Use streaming to handle large files without loading them entirely into memory; peak RSS MUST stay under 50 MiB for a 1 GiB input"

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

## Evaluator MUST NOT (drift-prevention list)

These rules bind the `ticket-evaluator` specifically and are intended to stop the pedantic-drift failure mode where successive rounds invent new objections.

- **MUST NOT** FAIL an AC on the basis of wording or phrasing preference alone. If the meaning is unambiguous and testable, the AC passes Gates 1 and 2 regardless of whether the evaluator would have phrased it differently.
- **MUST NOT** introduce a new FAIL on content that was revised in direct response to a previous round's feedback, unless the previous feedback itself promoted that new concern. Feedback-guided revisions MUST be treated as settled for the specific point they addressed; raising a different objection on the same text in the next round is drift and is forbidden.
- **MUST NOT** treat a concrete API name that appears as a test-assertion observation point (Gate 4 carve-out above — e.g., `process.stdout.write`, `vi.spyOn(console, 'log')`, `fs.writeFileSync`) as HOW. Such names are part of the PASS/FAIL contract, not prescribed implementation.
- **MUST NOT** invent edge cases outside the ticket's declared scope and then FAIL Gate 3 for their absence.
- **MUST NOT** FAIL Gate 5 when a rationale is present that justifies a single-axis judgement per the tiebreak rule above.

## Planner MUST

- **MUST** draft each AC so it satisfies Gates 1 and 2 on first pass (concrete thresholds, one interpretation).
- **MUST** ensure Scope + Implementation Notes name file paths and public contracts (Gate 4 WHAT).
- **MUST NOT** embed code snippets that prescribe internal algorithms (Gate 4 HOW).
- **MUST** write a one-line rationale when file-count and AC-count axes disagree on size (Gate 5 tiebreak enablement).

## Output Contract (Evaluator)

The evaluator's return block MUST follow the format defined in `agents/ticket-evaluator.md` (Result / Status / Gate Results / Issues / Feedback). This contract file governs the content of the judgement; the evaluator file governs its shape.
