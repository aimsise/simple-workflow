target: README.md
heading: (end of file)
mode: append
---
# create-ticket

A self-contained agent skill that turns a request, a brief, an investigation record or any mix of your own material (documents, spreadsheets, a read-only MCP tool result, an HTTP document) into one or more implementation tickets, each drafted by a planner role, graded by an independent evaluator role against a fixed quality rubric, and delivered to a local directory, a ticket platform reached through an MCP server, or an HTTP API.

This directory is generated; `SKILL.md` and everything under `references/` and `scripts/` are one unit. Do not edit the files by hand: the `metadata` block in the frontmatter of `SKILL.md` records the upstream version and commit the directory was generated from, and a newer generation replaces the whole directory.

## Install

1. Copy this directory, keeping its name `create-ticket`, into the skill root your agent host reads: `.github/skills/`, `.claude/skills/` or `.agents/skills/` inside the project (project-wide), or the host's personal skill root under your home directory (every project).
2. Nothing else is required: no package, no configuration file, no custom agent definition. Python 3 on the shell is needed only when an `.xlsx` source is passed.
3. Invoke it by name, `/create-ticket`, followed by the input. The skill never starts on its own.

## What the host must offer

Any agent host that loads `SKILL.md` skills and provides a file-read, a file-write, a file-edit, text and file-pattern search, a POSIX shell and a subagent tool; an ask-user tool is used when present. The skill names those tools by role, never by a product's tool name, and resolves each role to the host's own tool before it starts (`SKILL.md`, Host notes, Tool roles). Without a subagent tool the skill still runs, inline, and marks every verdict `SELF-EVALUATED` so the loss of evaluator independence is visible; without an ask-user tool it runs non-interactively and records its assumptions in the tickets.

Every shell command goes through the host's own permission prompt; the skill declares no pre-approved tool. Approve only the commands the steps name (`date`, `mktemp`, `ls`, `mkdir`, `mv`, `printf`, `git`, `curl`, `jq`, and `python3` for a workbook).

## Usage

```text
/create-ticket <ticket description> | brief=<path> | findings=<path>
               [source=<spec> ...]
               [destination=local:<dir> | mcp:<server>[/<tool>] | api:<url>]
               [confirm=yes] [depth=<tier>] [constraint_<key>=off]
```

Three input modes, exactly one at a time:

| Mode | Input | What happens |
|---|---|---|
| Bare description | free text after `/create-ticket` | a researcher role investigates the repository, a capped interview fills the gaps (at most 3 questions per round, 10 rounds), then the tickets are drafted and graded |
| `brief=<path>` | a Markdown brief ([references/brief-template.md](references/brief-template.md)) | the brief's Vision, Business Context, Technical Requirements, Scope and Constraints drive the split; `interview_complete: true` in its frontmatter skips the interview |
| `findings=<path>` | an investigation record ([references/findings-schema.md](references/findings-schema.md)) | its `## Required Work Units` become the tickets one-to-one; no investigation is repeated |

A request made only of tokens with at least one `source=` is a bare-description run whose description is derived from the sources.

### Sources (`source=`)

Hand over your material as it is, repeatable, in any mode ([references/sources.md](references/sources.md)):

| Spec | Reads |
|---|---|
| `source=file:<path>` | `.md`, `.markdown`, `.txt`, `.csv`, `.tsv`, `.json`, `.yaml`, `.yml`, or an `.xlsx` workbook read as a workbook (every sheet, cells addressed by row) |
| `source=dir:<path>` | every supported file directly inside the directory |
| `source=mcp:<server>/<tool>?name=value` | one call of a read-only MCP tool of the session (a wiki page, an issue, a document; illustrative only) |
| `source=api:<url>` | one HTTP `GET`; `source_auth_env=<VAR>` names the variable holding a bearer token, whose value is never printed |

Everything is normalized into a source dossier before any ticket is drafted. The decomposer role decides whether one source (a backlog sheet, a numbered list; illustrative only) enumerates the work units, in which case they map to tickets one-to-one, or whether every source is context; the Final summary reports that decision as `Partition basis`, and every ticket's Background ends with a `Sources:` line naming the lines it drew on. Caps: 60,000 characters per source (truncation is marked), 150,000 in total, 50 sources. With `brief=` or `findings=` the sources are context only.

### Destinations (`destination=`)

Default `local:tickets` ([references/destinations.md](references/destinations.md)):

| Spec | Result |
|---|---|
| `local:<dir>` | `<dir>/<parent-slug>/<NNN>-<slug>/ticket.md` per ticket, a `split-plan.md` when there is more than one, numbered by `<dir>/.ticket-counter`; a failed write is quarantined under `<dir>/.rollback/`, never deleted |
| `mcp:<server>[/<tool>]` | one item per ticket through the server's create tool; `mcp_<name>=<value>` fills its other required parameters |
| `api:<url>` | one `POST` per ticket; `auth_env=<VAR>` for the bearer token, `template=<path>` for the request body, `id_path=<path>` for the identifier in the response |

A remote destination asks once for confirmation before the first create; `confirm=yes` skips the question and is the only way to deliver remotely in a non-interactive run. Remote creates are not transactional: on a failure part-way the identifiers already created are printed and the run stops.

### Other options

- `depth=standard|thorough|exhaustive`: raises the evidence depth the rubric demands (never lowers it; the default follows each ticket's size).
- `constraint_<key>=off`: turns off one rubric gate for the run (`oracle_verification`, `independent_evidence`, `failure_class_coverage`, `peer_uniformity`).

## What you get

Each ticket carries Background, Scope, Acceptance Criteria, Implementation Notes and a Capabilities table ([references/ticket-template.md](references/ticket-template.md)), plus a `Quality` row with one of three verdicts: `PASS` (the evaluator accepted it, possibly after one revision), `SELF-EVALUATED` (no subagent tool on this host) or `FAIL (user-accepted)` (you chose to proceed after two failed rounds). Nothing is delivered until every ticket of the run has a verdict; every `ERROR:` before delivery leaves the destination untouched. The run ends with a `### Final summary` block listing each ticket, its path or identifier, category, size, acceptance-criteria count and verdict, and the scratch directory where drafts and evaluator reports were kept.

## Files

| Path | Role |
|---|---|
| `SKILL.md` | the orchestration: argument parsing, intake, the four phases, delivery, error handling, host notes |
| `references/agents/*.md` | the prompts of the four roles (researcher, decomposer, planner, ticket-evaluator), each run as a separate subagent |
| `references/ac-quality-criteria.md`, `references/ac-quality-grading.md` | the quality rubric the planner follows and the evaluator grades against |
| `references/sources.md`, `references/destinations.md` | the input and output adapters |
| `references/brief-template.md`, `references/findings-schema.md`, `references/ticket-template.md`, `references/split-plan-schema.md` | the input and output formats |
| `references/agent-spawn-prompts.md`, `references/mode-dispatch-flows.md`, `references/spec-decomposer-input.md`, `references/write-path-templates.md`, `references/interview-templates.md` | the step-by-step contracts the orchestration follows |
| `scripts/xlsx_to_text.py` | the workbook reader for `.xlsx` sources (Python 3 standard library only) |

## Limits

- The skill has not yet been exercised end to end on a live host; the contracts were verified by construction and by a build-time audit.
- An MCP source tool is judged read-only from its description; a tool that misdescribes itself cannot be detected.
- `dir:` reads one directory level; `.docx` and `.pdf` sources are not supported.
- Grouping delivered tickets under a parent item on a remote platform is out of scope; each ticket is created as a standalone item.
