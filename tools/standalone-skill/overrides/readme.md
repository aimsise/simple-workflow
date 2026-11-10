target: README.md
heading: (end of file)
mode: append
---
# create-ticket

A self-contained agent skill that turns a request, a brief, an investigation record or any mix of your own material (documents, spreadsheets, a read-only MCP tool result, an HTTP document) into one or more implementation tickets, each drafted by a planner role, graded by an independent evaluator role against a fixed quality rubric, and delivered to a local directory, a ticket platform reached through an MCP server, or an HTTP API.

This directory is generated; `SKILL.md` and everything under `references/` and `scripts/` are one unit. Do not edit the files by hand, with one exception, `references/ticket-template.md` (see `### Adapting the ticket template`): the `metadata` block in the frontmatter of `SKILL.md` records the upstream version and commit the directory was generated from, and a newer generation replaces the whole directory.

## Install

1. Copy this directory, keeping its name `create-ticket`, into the skill root your agent host reads: `.github/skills/`, `.claude/skills/` or `.agents/skills/` inside the project (project-wide), or the host's personal skill root under your home directory (every project).
2. Nothing else is required: no package, no configuration file, no custom agent definition. Python 3 on the shell is needed only when an `.xlsx` source is passed. Each run keeps its investigation, source dossier, drafts and evaluator reports under `.create-ticket-scratch/run.<id>/` inside the working directory (added to `.gitignore` when that is a git repository) and deletes nothing.
3. Invoke it by name, `/create-ticket`, followed by the input: tokens, or plain prose in any language saying what to read and where to deliver (the skill prints a `Resolved:` line with its reading before it runs). The skill never starts on its own.

## What the host must offer

Any agent host that loads `SKILL.md` skills and provides a file-read, a file-write, a file-edit, text and file-pattern search, a POSIX shell and a subagent tool; an ask-user tool is used when present. The skill names those tools by role, never by a product's tool name, and resolves each role to the host's own tool before it starts (`SKILL.md`, Host notes, Tool roles). Without a subagent tool the skill still runs, inline, and marks every verdict `SELF-EVALUATED` so the loss of evaluator independence is visible; without an ask-user tool it runs non-interactively and records its assumptions in the tickets.

Every shell command goes through the host's own permission prompt; the skill declares no pre-approved tool. Approve only the commands the steps name (`date`, `mktemp`, `mkdir`, `ls`, `mv`, `printf`, `git`, `command`, `curl`, `jq`, `python3` or its fallback `python` for a workbook, and the shell builtins `[`, `echo` and `case` of the variable probes).

## Usage

```text
/create-ticket <ticket description> | brief=<path> | findings=<path>
               [source=<spec> ...]
               [destination=local:<dir> | mcp:<server>[/<tool>] | api:<url>] [parent=<id>]
               [confirm=yes] [depth=<tier>] [constraint_<key>=off]
```

Three input modes, exactly one at a time:

| Mode | Input | What happens |
|---|---|---|
| Bare description | free text after `/create-ticket` | a researcher role investigates the repository, a capped interview fills the gaps (one question per round, up to 3 when independent; at most 30 rounds and 30 questions), then the tickets are drafted and graded |
| `brief=<path>` | a Markdown brief ([references/brief-template.md](references/brief-template.md)) | the brief's Vision, Business Context, Technical Requirements, Scope and Constraints drive the split; `interview_complete: true` in its frontmatter skips the interview |
| `findings=<path>` | an investigation record ([references/findings-schema.md](references/findings-schema.md)) | its `## Required Work Units` become the tickets one-to-one; no investigation is repeated |

A request made only of tokens with at least one `source=` is a bare-description run whose description is derived from the sources.

### Sources (`source=`)

Hand over your material as it is, repeatable, in any mode ([references/sources.md](references/sources.md)):

| Spec | Reads |
|---|---|
| `source=file:<path>` | `.md`, `.markdown`, `.txt`, `.csv`, `.tsv`, `.json`, `.yaml`, `.yml`, or an `.xlsx` workbook read as a workbook (every sheet, or only `?sheet=<name>`; cells addressed by row) |
| `source=dir:<path>` | every supported file directly inside the directory |
| `source=mcp:<server>/<tool>?name=value` | one call of a read-only MCP tool of the session (a wiki page, an issue, a document; illustrative only) |
| `source=api:<url>` | one HTTP `GET`; `source_auth_env=<VAR>` names the variable holding a bearer token, whose value is never printed |

Writing several sources and leaving out the kind:

- **Several sources**: repeat the token (`source=file:a.md source=file:b.xlsx`) or separate the specs with commas in one token (`source=a.md,docs/,https://example.com/spec`). A space does not separate sources: in `source=a.md b.md` only `a.md` is read and `b.md` is taken as part of the description. A file whose name contains a comma is still read whole when that name exists; a comma inside a URL or an MCP query stays part of it.
- **Kind left out**: a value starting with `http://` or `https://` is read as `api:`, an existing directory as `dir:`, any other path as `file:`. `mcp:` is never guessed from a token, because whether a name is an MCP server depends on the session; write `mcp:` or say it in prose. A value whose prefix looks like a kind but is not one (`fiel:a.md`) stops the run instead of being read as a path. When the token was split or a kind was filled in, the `Resolved:` line shows the result.
- **In prose**: "read a.md and the sheet Open items of b.xlsx" needs no kind at all. An item reachable through an MCP server may be named by its title or its link: the skill picks the server and its read tool, passes the link when the tool takes one, and otherwise makes one read-only search call and uses the item only when exactly one result matches; otherwise it asks, or stops in a non-interactive run. A URL in prose is fetched with a plain `GET` unless the statement says to read it through an MCP server.

Everything is normalized into a source dossier before any ticket is drafted. The decomposer role decides whether one source (a backlog sheet, a numbered list; illustrative only) enumerates the work units, in which case they map to tickets one-to-one, or whether every source is context; the Final summary reports that decision as `Partition basis`, and every ticket's Background ends with a `Sources:` line naming the lines it drew on. Caps: 60,000 characters per source (truncation is marked), 150,000 in total, 50 sources. With `brief=` or `findings=` the sources are context only.

### Destinations (`destination=`)

Default `local:.docs/tickets` ([references/destinations.md](references/destinations.md)):

| Spec | Result |
|---|---|
| `local:<dir>` | `<dir>/<parent-slug>/<NNN>-<slug>/ticket.md` per ticket, a `split-plan.md` when there is more than one, numbered by `<dir>/.ticket-counter`; a failed write is quarantined under `<dir>/.rollback/`, never deleted |
| `mcp:<server>[/<tool>]` | one item per ticket through the server's create tool; `mcp_<name>=<value>` fills its other parameters; `parent=<id>` links every item to an existing item (epic, parent task; illustrative only) through the tool's parent-link parameter |
| `api:<url>` | one `POST` per ticket; `auth_env=<VAR>` for the bearer token, `template=<path>` for the request body (`{title}`, `{body}`, and `{parent}` for `parent=<id>`, which on `api:` always needs a `template=`), `id_path=<path>` for the identifier in the response |

A remote destination asks once for confirmation before the first create; `confirm=yes` skips the question and is the only way to deliver remotely in a non-interactive run. Remote creates are not transactional: on a failure part-way the identifiers already created are printed and the run stops.

### Other options

- `depth=standard|thorough|exhaustive`: raises the evidence depth the rubric demands (never lowers it; the default follows each ticket's size).
- `constraint_<key>=off`: turns off one rubric gate for the run (`oracle_verification`, `independent_evidence`, `failure_class_coverage`, `peer_uniformity`).
- Paths, sheet names and identifiers may use any script; a path or sheet name with spaces is written in double quotes (`source="file:My Docs/a.xlsx"`) or stated in prose, while an identifier carries no whitespace. Only `"`, backtick, `$`, backslash and control characters are refused. A token value ends at the next space, so in a language written without word spaces leave a space after it.

### Prose instead of tokens

The tokens are the canonical form; a statement in prose that names material to read or a place to deliver is translated to them first, and the skill prints `Resolved: <tokens>` before it runs. An explicit token wins over prose, prose never sets `confirm=yes`, `depth=` or `constraint_<key>=off`, and a statement that fits two things or none is asked about (or stops the run when nobody can answer).

## What you get

Each ticket carries Background, Scope, Acceptance Criteria, Implementation Notes and a Capabilities table ([references/ticket-template.md](references/ticket-template.md)), plus a `Quality` row with one of three verdicts: `PASS` (the evaluator accepted it, possibly after one revision), `SELF-EVALUATED` (no subagent tool on this host) or `FAIL (user-accepted)` (you chose to proceed after two failed rounds). Nothing is delivered until every ticket of the run has a verdict; every `ERROR:` before delivery leaves the destination untouched. The run ends with a `### Final summary` block listing each ticket, its path or identifier, category, size, acceptance-criteria count and verdict, and, on its `Scratch:` line, the scratch directory where the drafts and evaluator reports of that run were kept.

### Adapting the ticket template

A project may edit `references/ticket-template.md` in its own copy of this directory to shape its tickets; the planner role drafts from that file on every run. The quality gates live in the rubric (`references/ac-quality-criteria.md`, `references/ac-quality-grading.md`), not in the template, so they keep working as long as the parts they and the delivery step read are left intact:

- **Keep**: the `## {id}: [Title]` heading; the field-table rows `Category`, `Size` and `Dependencies` (delivery adds the `Quality` row); the sections `### Background`, `### Scope`, `### Acceptance Criteria`, `### Implementation Notes`, `### Capabilities`, `### Advisory Capabilities`, `#### Capability Gaps`, `#### Capability Skip Rationale`, `#### Failure-Class Coverage (Gate 9)` and `#### Peer-Set Uniformity (Gate 10)`.
- **Do not rename or translate** any of those headings, and do not change the columns of the Scope, Capabilities, Advisory Capabilities, Failure-Class Coverage or Peer-Set Uniformity tables: the evaluator, the delivery step and the Final summary find them by name. Keep the acceptance criteria a numbered list; the Final summary counts it.
- **Free to change**: add sections or field rows (the planner fills them by their heading and guidance; no gate grades them), reword the guidance text inside a section, reorder sections, and drop the `Priority` row (no step reads it, although the drafting rules may still fill it).
- **Updates**: a newer generation replaces this file too, so keep your edit (a copy or a diff) and apply it again after updating.

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

- The skill has been exercised end to end on one agent host (a non-interactive run over a workbook sheet and a Markdown file, default destination, every ticket graded PASS); on other hosts the contracts are verified by construction and by a build-time audit.
- An MCP source tool is judged read-only from its description; a tool that misdescribes itself cannot be detected.
- `dir:` reads one directory level; `.docx` and `.pdf` sources are not supported.
- `parent=` links new items through the create tool's own parent-link parameter (or the `{parent}` template placeholder); a platform that links only through a separate call after the create is not supported, and the parent item itself is never modified.
