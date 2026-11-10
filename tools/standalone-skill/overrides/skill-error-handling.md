target: SKILL.md
heading: ## Error Handling
mode: replace
---
## Error Handling

Every `ERROR:` before Delivery is atomic: nothing reaches the destination (before Delivery the run writes only under `{scratch}`, plus the one-line `.gitignore` append of Argument Parsing), the `local:` counter is unchanged, and the run stops. A failure during Delivery follows Step DL-4. An error line echoes a `brief=` / `findings=` path exactly as the user typed it (Host notes), and prints an `api:` URL without its query string.

| Trigger | Output |
|---|---|
| Empty arguments | Print Usage line, stop (before any preflight) |
| Both `brief=` and `findings=` | `ERROR: brief= and findings= are mutually exclusive. Pass exactly one.` |
| Scratch directory cannot be created | `ERROR: create-ticket cannot create the scratch directory .create-ticket-scratch/ in the working directory (<reason>)` |
| `brief=` / `findings=` path with other characters | `ERROR: <token>= path contains characters this skill does not accept` |
| Unknown destination kind | `ERROR: unknown destination kind in destination=<spec without query> (expected local:, mcp: or api:)` (the spec without its query string, at most 80 characters) |
| `auth_env=` / `template=` / `id_path=` without `api:` | `ERROR: auth_env=, template= and id_path= apply only to an api: destination` |
| `mcp_<name>=` without `mcp:` | `ERROR: mcp_<name>= applies only to an mcp: destination` |
| Unknown source kind, or a `source=` value outside its pattern | `ERROR: unknown source kind in source=<spec without query> (expected file:, dir:, mcp: or api:)` / `ERROR: source=<spec without query> contains characters this skill does not accept` |
| `source_auth_env=` without an `api:` source | `ERROR: source_auth_env= applies only to an api: source` |
| `parent=` with a `local:` destination, or outside its pattern | `ERROR: parent= applies only to an mcp: or api: destination` / `ERROR: parent= contains characters this skill does not accept` |
| `parent=` and the destination cannot link items (no or several parent-link parameters; `api:` template without `{parent}`) | The `ERROR:` line of that kind in [references/destinations.md](references/destinations.md), at preflight |
| A prose statement of input or output resolves two ways or to nothing, and no ask-user tool answers | `ERROR: cannot resolve the request's input or output statement: <statement>` |
| `?sheet=` on a non-workbook source, or an unknown option key | `ERROR: source=file:<path>: unknown option <key> (only sheet= on an .xlsx file)` |
| A source cannot be read (missing file or directory, unsupported kind, unreadable `.xlsx`, no Python 3, unavailable or non-read-only MCP tool, missing MCP parameter, HTTP status outside 200-299) | The `ERROR:` line of that kind in [references/sources.md](references/sources.md), before Phase 1; nothing delivered |
| Sources exceed the intake limit, or more than 50 sources | `ERROR: sources exceed the intake limit (<total> characters > 150000; largest: ...); narrow the inputs` / `ERROR: more than 50 sources after directory expansion; narrow the inputs` |
| A source was truncated, or a `dir:` skipped files | Not an error: continue, print the `WARNING:` line of [references/sources.md](references/sources.md), repeat it in the Final summary |
| Unknown `depth=` or `confirm=` value | `ERROR: depth= must be standard, thorough or exhaustive` / `ERROR: confirm= accepts only yes` |
| Unknown `constraint_<key>=` key, or a value other than `off` | `ERROR: unknown constraint key <key>` / `ERROR: constraint_<key>= accepts only off` |
| Destination preflight fails | The `ERROR:` line of the failing check in [references/destinations.md](references/destinations.md) (e.g. `ERROR: destination mcp:<server> exposes no tool that accepts a title and a body`), before Phase 1 |
| A slug is not kebab-case | `ERROR: <field> must be kebab-case (lowercase letters, digits, hyphens)` |
| `local:` counter non-numeric | `ERROR: {dir}/.ticket-counter contains non-numeric value '<content>'. Fix or delete the file and retry.` |
| `findings=<path>` not found by the file-read tool | `ERROR: Findings file not found at <path>` |
| Brief file not found by the file-read tool | `ERROR: Brief file not found at <path>` |
| Brief frontmatter without `slug` | `ERROR: brief frontmatter is missing slug` |
| Findings frontmatter without `title` | `ERROR: findings frontmatter is missing title` |
| `findings_version` missing or != 1 | `ERROR: findings_version missing or unsupported (expected 1)` |
| Findings zero `## Required Work Units` | `ERROR: findings file contains zero Required Work Units` |
| A mandatory role's subagent spawn attempted and failed | Report the error and stop; nothing is delivered (for the decomposer: `ERROR: decomposer agent unavailable`) |
| Researcher `Status: partial` | Not an error: continue, print `WARNING: researcher returned partial findings: <limitations>`, repeat it in the Final summary |
| Researcher `Status: failed` | Report the error and stop; nothing is delivered |
| Decomposer `Status: partial` | Not an error: continue, print `WARNING: decomposer dropped <n> work units beyond the 8-ticket cap: <titles>`, repeat it in the Final summary |
| Decomposer `Status: failed`, or an empty Tickets list | `ERROR: decomposer failed — <Rationale>`, or `ERROR: decomposer returned zero tickets`; a `Status: failed` whose Rationale reports a dependency cycle prints the `circular` line of the next row instead |
| Cyclic `depends_on` (reported by the decomposer, or found by Step F-6 / DL-1) | `ERROR: circular dependency detected among tickets: <cycle members>`; literal `circular` MUST appear |
| Planner `Status: failed` or `Status: partial` | Report the error and stop; nothing is delivered |
| Ticket-evaluator `Status: ERROR` (rubric fail-fast) | Report the error and stop; nothing is delivered |
| FAIL after max 2 rounds (initial + 1 revision) | Present issues with the ask-user tool. Proceed → the ticket's verdict is `FAIL (user-accepted)`; decline → `ERROR: unresolved FAIL gates; the user declined to proceed (draft saved under {scratch})`, stop. A denied, erroring or unavailable ask-user tool → `ERROR: cannot resolve FAIL gates non-interactively; re-run interactively (draft saved under {scratch})`, stop. Do NOT hang. |
| User declines to proceed at the exhausted-retry question | `ERROR: unresolved FAIL gates; the user declined to proceed (draft saved under {scratch})` — nothing delivered |
| Split partial failure | Any sub-ticket without a verdict → nothing delivered (atomic — Delivery starts only after all N have one) |
| Remote confirmation not given | `ERROR: remote delivery needs an interactive confirmation; re-run with confirm=yes to skip it` — nothing created |
| `local:` path already exists | `ERROR: create-ticket write refused — <path> already exists` — nothing written, counter untouched |
| `local:` split-plan validation fails | `ERROR: split-plan validation failed — <reason>` — quarantined like a write failure (`mv` to `{dir}/.rollback/{parent-slug}-{ts}/`, never delete) |
| `local:` write failure | `ERROR: create-ticket write failed — partial output quarantined at {dir}/.rollback/{parent-slug}-{ts}/ (<reason>)` — counter untouched; re-run with the same inputs is safe |
| `local:` counter write fails after the tickets are written | `ERROR: create-ticket counter write failed — set {dir}/.ticket-counter to <counter + N> (<reason>)` — the tickets stay in place; stop |
| `mcp:` / `api:` create failure | The identifiers created so far, then `ERROR: destination <spec> create failed for <logical id> (<reason>)` — nothing deleted or modified, stop |
