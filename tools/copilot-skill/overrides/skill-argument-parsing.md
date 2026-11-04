target: SKILL.md
heading: ## Argument Parsing
mode: replace
---
## Argument Parsing

This host passes no argument variable: the input is the user's request text, that is, the text of the message that invoked this skill (everything after `/create-ticket` when it was typed as a command). Parse it into one mode: `findings=<path>` (scan `findings=`); `brief=<path>` (scan `brief=`); else bare-description free-text.

**Mutual exclusion**: BOTH `brief=` AND `findings=` → print `ERROR: brief= and findings= are mutually exclusive. Pass exactly one.` and stop. Do NOT read either file. Do NOT touch the destination. Do NOT create directories. (Exact wording required: the literal `mutually exclusive`.)

**Input paths**: a `brief=` or `findings=` path may be absolute (it is the user's own file) but MUST match `^[A-Za-z0-9._~/-]+$` (a leading `~` allowed; no whitespace, `$`, backtick, quote or backslash); else print `ERROR: <token>= path contains characters this skill does not accept` and stop. Then check, here and only here (Steps F-1 and B-1 name this check's output), that the file exists with `view`, never with a shell test, before the destination preflight: a missing findings file → `ERROR: Findings file not found at <path>`, a missing brief → `ERROR: Brief file not found at <path>`, and stop. Error lines and the Final summary echo the path exactly as the user typed it (Host notes).

**Option tokens**: scan the same text for these tokens (each runs to the next whitespace) and remove them before the bare-description text is used:

- `destination=<spec>`: where Delivery puts the tickets. Absent → `local:tickets`. The three kinds, `local:<dir>`, `mcp:<server>[/<tool>]` and `api:<url>`, and every check on them are defined in [references/destinations.md](references/destinations.md).
- `auth_env=<VAR>`, `template=<path>`, `id_path=<path>`: options of an `api:` destination only.
- `mcp_<name>=<value>`: the value of a required parameter `<name>` of an `mcp:` destination's create tool (e.g. a project key; illustrative only).
- `confirm=yes`: skips the one confirmation question asked before the first `mcp:` / `api:` create; the only way to deliver to a remote destination in a non-interactive run.
- `depth=<tier>`: `standard`, `thorough` or `exhaustive`. Without it, the evidence depth that the rubric's depth-gated rules read follows each ticket's Size (`thorough` for `L` or `XL`, else `standard`); the token raises that depth, never lowers it (`references/ac-quality-criteria.md`, Terminology, Policy kill switch).
- `constraint_<key>=off` (repeatable): turns off the rubric gate whose **Kill switch** names that key, for every ticket of the run. The keys are `oracle_verification` (Gate 7), `independent_evidence` (Gate 8), `failure_class_coverage` (Gate 9) and `peer_uniformity` (Gate 10); without the token every gate is active. Every planner and ticket-evaluator spawn carries the tokens as one `Constraints:` line (`references/agent-spawn-prompts.md`, Rules for every spawn prompt).

**Empty arguments**: when the request carries no description and no `brief=` / `findings=` token, print `Usage: /create-ticket <ticket description> | brief=<path> | findings=<path> [destination=local:<dir> | mcp:<server>[/<tool>] | api:<url>] [confirm=yes] [depth=<tier>] [constraint_<key>=off]` and stop, before any preflight.

Errors, each printed before anything else runs and followed by stop: an unknown destination kind → `ERROR: unknown destination kind in destination=<spec> (expected local:, mcp: or api:)`; `auth_env=`, `template=` or `id_path=` without an `api:` destination → `ERROR: auth_env=, template= and id_path= apply only to an api: destination`; an `mcp_<name>=` token without an `mcp:` destination → `ERROR: mcp_<name>= applies only to an mcp: destination`; another `depth=` value → `ERROR: depth= must be standard, thorough or exhaustive`; another `confirm=` value → `ERROR: confirm= accepts only yes`; a `constraint_<key>=` token whose key is not one of the four above → `ERROR: unknown constraint key <key>`; a known key with a value other than `off` → `ERROR: constraint_<key>= accepts only off`.

Then run the destination preflight of `references/destinations.md` (read-only: it creates nothing) so an unusable destination fails before any agent runs. Right after a successful preflight, in every mode, create the run scratch directory with `bash` running `mktemp -d` (on Windows, the `powershell` equivalent) and record its path as `{scratch}`. It lives under the system temporary directory, holds every transient file of the run (investigation, drafts, evaluator reports, request and response bodies), and is not removed at the end: this skill uses no delete command. `{scratch}` may be absolute (Host notes); it appears inside spawn prompts and in the Final summary's lines that say where a file was saved, and is never written into a ticket or sent to a destination.
