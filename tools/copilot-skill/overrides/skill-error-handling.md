target: SKILL.md
heading: ## Error Handling
mode: replace
---
## Error Handling

Every `ERROR:` before Delivery is atomic: nothing reaches the destination (the run writes only under `{scratch}`), the `local:` counter is unchanged, and the run stops. A failure during Delivery follows Step DL-4. An error line echoes a `brief=` / `findings=` path exactly as the user typed it (Host notes), and prints an `api:` URL without its query string.

| Trigger | Output |
|---|---|
| Empty arguments | Print Usage line, stop (before any preflight) |
| Both `brief=` and `findings=` | `ERROR: brief= and findings= are mutually exclusive. Pass exactly one.` |
| `brief=` / `findings=` path with other characters | `ERROR: <token>= path contains characters this skill does not accept` |
| Unknown destination kind | `ERROR: unknown destination kind in destination=<spec> (expected local:, mcp: or api:)` |
| `auth_env=` / `template=` / `id_path=` without `api:` | `ERROR: auth_env=, template= and id_path= apply only to an api: destination` |
| `mcp_<name>=` without `mcp:` | `ERROR: mcp_<name>= applies only to an mcp: destination` |
| Unknown `depth=` or `confirm=` value | `ERROR: depth= must be standard, thorough or exhaustive` / `ERROR: confirm= accepts only yes` |
| Unknown `constraint_<key>=` key, or a value other than `off` | `ERROR: unknown constraint key <key>` / `ERROR: constraint_<key>= accepts only off` |
| Destination preflight fails | The `ERROR:` line of the failing check in [references/destinations.md](references/destinations.md) (e.g. `ERROR: destination mcp:<server> exposes no tool that accepts a title and a body`), before Phase 1 |
| A slug is not kebab-case | `ERROR: <field> must be kebab-case (lowercase letters, digits, hyphens)` |
| `local:` counter non-numeric | `ERROR: {dir}/.ticket-counter contains non-numeric value '<content>'. Fix or delete the file and retry.` |
| `findings=<path>` not found by `view` | `ERROR: Findings file not found at <path>` |
| Brief file not found by `view` | `ERROR: Brief file not found at <path>` |
| Findings frontmatter without `title` | `ERROR: findings frontmatter is missing title` |
| `findings_version` missing or != 1 | `ERROR: findings_version missing or unsupported (expected 1)` |
| Findings zero `## Required Work Units` | `ERROR: findings file contains zero Required Work Units` |
| A mandatory role's `task` spawn attempted and failed | Report the error and stop; nothing is delivered (for the decomposer: `ERROR: decomposer agent unavailable`) |
| Researcher `Status: partial` | Not an error: continue, print `WARNING: researcher returned partial findings: <limitations>`, repeat it in the Final summary |
| Researcher `Status: failed` | Report the error and stop; nothing is delivered |
| Decomposer `Status: partial` | Not an error: continue, print `WARNING: decomposer dropped <n> work units beyond the 8-ticket cap: <titles>`, repeat it in the Final summary |
| Decomposer `Status: failed`, or an empty Tickets list | `ERROR: decomposer failed — <Rationale>`, or `ERROR: decomposer returned zero tickets` |
| Cyclic `depends_on` | `ERROR: circular dependency detected among tickets: <cycle members>`; literal `circular` MUST appear |
| Planner `Status: failed` or `Status: partial` | Report the error and stop; nothing is delivered |
| Ticket-evaluator `Status: ERROR` (rubric fail-fast) | Report the error and stop; nothing is delivered |
| FAIL after max 2 rounds (initial + 1 revision) | Present issues via `ask_user`. Proceed → the ticket's verdict is `FAIL (user-accepted)`; decline → stop + print the draft's path under `{scratch}`. A denied, erroring or unavailable `ask_user` → `ERROR: cannot resolve FAIL gates non-interactively; re-run interactively (draft saved under {scratch})`, stop. Do NOT hang. |
| Split partial failure | Any sub-ticket without a verdict → nothing delivered (atomic — Delivery starts only after all N have one) |
| Remote confirmation not given | `ERROR: remote delivery needs an interactive confirmation; re-run with confirm=yes to skip it` — nothing created |
| `local:` path already exists | `ERROR: create-ticket write refused — <path> already exists` — nothing written, counter untouched |
| `local:` split-plan validation fails | `ERROR: split-plan validation failed — <reason>` — quarantined like a write failure (`mv` to `{dir}/.rollback/{parent-slug}-{ts}/`, never delete) |
| `local:` write failure | `ERROR: create-ticket write failed — partial output quarantined at {dir}/.rollback/{parent-slug}-{ts}/ (<reason>)` — counter untouched; re-run with the same inputs is safe |
| `mcp:` / `api:` create failure | The identifiers created so far, then `ERROR: destination <spec> create failed for <logical id> (<reason>)` — nothing deleted or modified, stop |
