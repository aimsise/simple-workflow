target: README.md
heading: (end of file)
mode: append
---
# create-ticket

A self-contained agent skill that turns a request, a brief, an investigation record or any mix of your own material (documents, spreadsheets, a read-only MCP tool result, an HTTP document, the output of a command-line client, a page read through a browser-automation tool) into one or more implementation tickets, each drafted by a planner role, graded by an independent evaluator role against a fixed quality rubric, and delivered to a local directory, a ticket platform reached through an MCP server, its command-line client or its create form in the browser, or an HTTP API.

This directory is generated; `SKILL.md` and everything under `references/` and `scripts/` are one unit. Do not edit the files by hand, with one exception, `references/ticket-template.md` (see `### Adapting the ticket template`): the `metadata` block in the frontmatter of `SKILL.md` records the upstream version and commit the directory was generated from, and a newer generation replaces the whole directory.

## Install

1. Copy this directory, keeping its name `create-ticket`, into the skill root your agent host reads: `.github/skills/`, `.claude/skills/` or `.agents/skills/` inside the project (project-wide), or the host's personal skill root under your home directory (every project).
2. Nothing else is required: no package, no configuration file, no custom agent definition. Python 3 on the shell is needed only when an `.xlsx` source is passed; a spreadsheet application or LibreOffice on the host is never required (it only enables the optional sheet render). Each run keeps its investigation, source dossier, drafts and evaluator reports under `.create-ticket-scratch/run.<id>/` inside the working directory (added to `.gitignore` when that is a git repository) and deletes nothing.
3. Invoke it by name, `/create-ticket`, followed by the input: tokens, or plain prose in any language saying what to read and where to deliver (the skill prints a `Resolved:` line with its reading before it runs). The skill never starts on its own.

## What the host must offer

Any agent host that loads `SKILL.md` skills and provides a file-read, a file-write, a file-edit, text and file-pattern search, a POSIX shell and a subagent tool; an ask-user tool is used when present. The skill names those tools by role, never by a product's tool name, and resolves each role to the host's own tool before it starts (`SKILL.md`, Host notes, Tool roles). Without a subagent tool the skill still runs, inline, and marks every verdict `SELF-EVALUATED` so the loss of evaluator independence is visible; without an ask-user tool it runs non-interactively and records its assumptions in the tickets. A browser-automation tool of the session (one that navigates to a URL, reads the page's text, fills a field and clicks; for example an MCP server that drives a browser) is optional: when present, the skill can read a page or fill a create form through the browser session you are already signed in to; without it, those channels are simply not used.

Every shell command goes through the host's own permission prompt; the skill declares no pre-approved tool. Approve only the commands the steps name (`date`, `mktemp`, `mkdir`, `ls`, `mv`, `printf`, `git`, `command`, `curl`, `jq`, `python3` or its fallback `python` for a workbook, and the shell builtins `[`, `echo` and `case` of the variable probes). A `cli:` command, typed by you or derived by the skill from a URL, runs as given and is printed in full first: the permission prompt for it is your gate. The optional sheet render runs as one `python3` command that launches `osascript`, the Windows shell interpreter (powershell.exe) or `soffice`; approving that command approves what it launches.

## Usage

```text
/create-ticket <ticket description> | brief=<path> | findings=<path>
               [source=<spec> ...]
               [destination=local:<dir> | mcp:<server>[/<tool>] | api:<url> | browser:<url> | cli:<command>]
               [parent=<id>]
               [confirm=yes] [depth=<tier>] [render=auto|off|excel|soffice]
               [constraint_<key>=off]
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
| `source=file:<path>` | `.md`, `.markdown`, `.txt`, `.csv`, `.tsv`, `.json`, `.yaml`, `.yml`, or an `.xlsx` workbook read as a workbook (every sheet, or only `?sheet=<name>`; cells addressed by row; line breaks, merged cells, struck-through text and hidden rows and columns marked; notes, shapes and pictures listed under `### Notes`, `### Shapes` and `### Images`; a sheet laid out as a page printed one cell per line; optionally also rendered to PDF, `### Sheet rendering`), a `.pdf` file or a `.png`, `.jpg`, `.jpeg`, `.gif` or `.webp` image (transcribed by the orchestrator through the host's file-read tool, which must be able to show it; no OCR) |
| `source=dir:<path>` | every supported file directly inside the directory, PDFs and images included |
| `source=mcp:<server>/<tool>?name=value` | one call of a read-only MCP tool of the session (a wiki page, an issue, a document; illustrative only) |
| `source=api:<url>` | one HTTP `GET`; `source_auth_env=<VAR>` names the variable holding a token, whose value is never printed (`source_auth_scheme=bearer|basic`, default `bearer`); `source_content_path=<jq path>` takes the content from one field of a JSON response (a missing field, or a body that is not JSON such as a sign-in page, stops the run; a sign-in page returned instead of the content stops the run too) |
| `source="cli:<command>"` | one run of a read-only command of a command-line client on the PATH (the platform's client printing one item; illustrative only), its output the content; `source_content_path=` applies to JSON output; `$VAR` references are expanded by the shell and a token value never appears in the command |
| `source=browser:<url>` | the text of one page, read through the session's browser-automation tool (optional; a page that only your signed-in browser can open); nothing on the page is clicked or submitted |

Writing several sources and leaving out the kind:

- **Several sources**: repeat the token (`source=file:a.md source=file:b.xlsx`) or separate the specs with commas in one token (`source=a.md,docs/,https://example.com/spec`). A space does not separate sources: in `source=a.md b.md` only `a.md` is read and `b.md` is taken as part of the description. A file whose name contains a comma is still read whole when that name exists; a comma inside a URL or an MCP query stays part of it.
- **Kind left out**: a value starting with `http://` or `https://` is read as `api:`, an existing directory as `dir:`, any other path as `file:`. `mcp:`, `cli:` and `browser:` are never guessed from a token, because whether a name is an MCP server depends on the session and a URL alone does not say how to reach it; write the kind or say it in prose. A value whose prefix looks like a kind but is not one (`fiel:a.md`) stops the run instead of being read as a path. When the token was split or a kind was filled in, the `Resolved:` line shows the result.
- **In prose**: "read a.md and the sheet Open items of b.xlsx" needs no kind at all. An item reachable through an MCP server may be named by its title or its link: the skill picks the server and its read tool, passes the link when the tool takes one, and otherwise makes one read-only search call and uses the item only when exactly one result matches; otherwise it asks, or stops in a non-interactive run. A URL in prose (a web page as it appears in the browser's address bar) is reached through the best access channel the skill finds: an MCP server of the session, the platform's command-line client when it is on the PATH and signed in, its HTTP API (`source=api:...` with `source_content_path=...` and a token variable, `source_auth_env=...`, `source_auth_scheme=...`), the browser-automation tool, whose browser may already be signed in, or a plain `GET` of the URL as typed; a statement that names a channel uses that one. The skill may guess the endpoint, the command or the content field: each attempt is printed (`Derived:` before it runs, `Tried:` when it failed, for example because a sign-in page came back instead of the item), and the next channel is tried. The same holds for an output: "create the tickets as children of <item URL>" becomes `destination=api:<create endpoint>` (with a derived body template, `id_path=`, `parent=` and, when needed, `content_type=`, `auth_scheme=`), `destination="cli:<create command>"` or, as the last resort, `destination=browser:<url>`; before the first create a read-only `Probe:` checks the parent item through the same channel, and the confirmation question shows the channel and every derived value. Sign-ins already on the machine are reused: a signed-in command-line client, a signed-in browser, or a token variable, given by name in prose or by token, or a conventional name for that platform checked only for being set (its value is never read or printed, and the name used is always printed). When nothing is signed in, the skill asks you once to sign in or to name a token variable, and a non-interactive run stops with an `ERROR:` that names the tokens to pass.

Everything is normalized into a source dossier before any ticket is drafted. The decomposer role decides whether one source (a backlog sheet, a numbered list; illustrative only) enumerates the work units, in which case they map to tickets one-to-one, or whether every source is context; the Final summary reports that decision as `Partition basis`, and every ticket's Background ends with a `Sources:` line naming the lines it drew on. Caps: 60,000 characters per source (truncation is marked), 150,000 in total, 50 sources. With `brief=` or `findings=` the sources are context only.

### Sheet rendering

A workbook used as a page (callouts pointing at cells, pasted screenshots, merged headings; illustrative only) loses its visual arrangement in text, so `render=` adds an optional PDF render of it, which a role may open when the host's file-read tool can show a PDF:

- `render=auto` (default): a workbook whose text shows shapes, pictures, merged cells or a page layout is rendered by the first renderer the host has: a spreadsheet application driven through its automation interface without a window and without saving (`osascript` on macOS, the Windows shell interpreter (powershell.exe) on Windows), then LibreOffice (`soffice`, headless); a workbook without such structure, or a host with neither renderer, gets no render.
- `render=excel` or `render=soffice`: always render every workbook with that one renderer; `render=off`: never render.

The render is optional and never required: unless `render=off`, the source's dossier text ends with a `Rendered:` line saying where the PDF is and which renderer made it, or why there is none; when a renderer was tried and none produced a PDF, the run continues with a `WARNING:` (a workbook `render=auto` skips for lack of structure, or any workbook under `render=off`, gets no warning). The workbook is never modified (the renderer gets a private copy, opened read-only), and the PDF stays in the run's scratch directory.

### Destinations (`destination=`)

Default `local:.local/tickets` ([references/destinations.md](references/destinations.md)):

| Spec | Result |
|---|---|
| `local:<dir>` | `<dir>/<parent-slug>/<NNN>-<slug>/ticket.md` per ticket, a `split-plan.md` when there is more than one, numbered by `<dir>/.ticket-counter`; a failed write is quarantined under `<dir>/.rollback/`, never deleted |
| `mcp:<server>[/<tool>]` | one item per ticket through the server's create tool; `mcp_<name>=<value>` fills its other parameters; `parent=<id>` links every item to an existing item (epic, parent task; illustrative only) through the tool's parent-link parameter |
| `api:<url>` | one `POST` per ticket; `auth_env=<VAR>` for the token (`auth_scheme=bearer|basic`, default `bearer`), `template=<path>` for the request body (`{title}` and `{body}` as whole string values, and `{parent}` for `parent=<id>`, which may also sit inside a longer string such as a link URL and on `api:` always needs a `template=`), `id_path=<path>` for the identifier in the response, `content_type=<media type>` for a body media type other than `application/json`; the web URL of a platform item named in prose is turned into this form (endpoint, body template, parent link derived, printed on `Resolved:` and `Derived:` lines, confirmed before any create) |
| `cli:<command>` | one run of a create command of the platform's command-line client per ticket, written `destination="cli:<command>"`; `{title_file}`, `{body_file}` or `{request_file}` (the JSON body built from `template=`) and `{parent}` are replaced by double-quoted values; `id_path=` reads the identifier from JSON output, else the first output line is the identifier; `auth_env=` names a variable the command refers to as `$VAR`; a read-only probe of the client runs at preflight |
| `browser:<url>` | the platform's create form, opened from the parent item's page through the browser-automation tool, filled with the title and body and submitted once per ticket, the new item's identifier read from the resulting page; the last resort, used only when no client or API is at hand |

A remote destination asks once for confirmation before the first create; `confirm=yes` skips the question and is the only way to deliver remotely in a non-interactive run. For any destination, `local:` included, `confirm=yes` also answers "proceed" for you when a ticket still fails the quality gates after two rounds: the question is not asked, the remaining issues are printed, and the ticket is delivered as `FAIL (unresolved)`; without the token a non-interactive run stops there instead. Remote creates are not transactional: on a failure part-way the identifiers already created are printed and the run stops.

### Other options

- `depth=standard|thorough|exhaustive`: raises the evidence depth the rubric demands (never lowers it; the default follows each ticket's size).
- `constraint_<key>=off`: turns off one rubric gate for the run (`oracle_verification`, `independent_evidence`, `failure_class_coverage`, `peer_uniformity`).
- Paths, sheet names and identifiers may use any script; a path or sheet name with spaces is written in double quotes (`source="file:My Docs/a.xlsx"`) or stated in prose, while an identifier carries no whitespace. Only `"`, backtick, `$`, backslash and control characters are refused. A token value ends at the next space, so in a language written without word spaces leave a space after it.

### Prose instead of tokens

The tokens are the canonical form; a statement in prose that names material to read or a place to deliver is translated to them first, and the skill prints `Resolved: <tokens>` before it runs. An explicit token wins over prose, prose never sets `confirm=yes`, `depth=` or `constraint_<key>=off`, and a statement that fits two things or none is asked about (or stops the run when nobody can answer). A URL in prose is reached through an MCP server, a command-line client, the HTTP API, the browser or a plain `GET`, with every derived value printed on `Resolved:` and `Derived:` lines first and every failed attempt on a `Tried:` line (**In prose** above).

## What you get

Each ticket carries Background, Scope, Acceptance Criteria, Implementation Notes and a Capabilities table ([references/ticket-template.md](references/ticket-template.md)), plus a `Quality` row with one of four verdicts: `PASS` (the evaluator accepted it, possibly after one revision), `SELF-EVALUATED` (no subagent tool on this host), `FAIL (user-accepted)` (you saw the remaining issues and chose to proceed after two failed rounds) or `FAIL (unresolved)` (`confirm=yes` proceeded in your place, so nobody reviewed the remaining issues before delivery). Nothing is delivered until every ticket of the run has a verdict; every `ERROR:` before delivery leaves the destination untouched. The run ends with a `### Final summary` block listing each ticket, its path or identifier, category, size, acceptance-criteria count and verdict, and, on its `Scratch:` line, the scratch directory where the drafts and evaluator reports of that run were kept.

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
| `scripts/xlsx_render.py` | the optional sheet render of an `.xlsx` source to PDF through a spreadsheet application or LibreOffice on the host (Python 3 standard library only) |

## Limits

- The skill has been exercised end to end on one agent host (a non-interactive run over a workbook sheet and a Markdown file, default destination, every ticket graded PASS); on other hosts the contracts are verified by construction and by a build-time audit.
- An MCP source tool is judged read-only from its description; a tool that misdescribes itself cannot be detected.
- `dir:` reads one directory level; `.docx` sources are not supported; a `.pdf` or image source is transcribed by the orchestrator through the host's file-read tool, which must be able to show it (no OCR).
- The sheet render's real renderer branches (the Windows shell interpreter (powershell.exe) driving the spreadsheet application on Windows, `osascript` on macOS, and LibreOffice) are written by construction and not exercised by the test suite, which drives the render script with stand-in programs only.
- A workbook is read for its cell values and its structure: line breaks, merged ranges, strikethrough, hidden rows and columns, notes and comments, text boxes, callouts and other shapes, and pictures, each saved under the run's `sources/S<n>-media/` directory when the converter can extract it (a picture it cannot extract is still listed, with the reason). The content of a picture is seen only when the host's file-read tool can show an image; otherwise the picture stays a listed gap, and no text is recognized from it. Charts are listed by name only (their data is not read), pivot tables and macros are not read, and no formatting other than strikethrough is kept.
- Browser writes are the last resort: form-driven creates are fragile; the orchestrator prefers a client or an API when either exists, and a page layout it cannot read stops the run before the first create (read probe) or, after a submit, with the identifiers created so far.
- A typed `cli:` command is your own: it runs as given (printed first, through the host's permission prompt), and a derived one is a command the orchestrator knows only reads, or creates one item per ticket.
- `parent=` links new items through the create tool's own parent-link parameter (or the `{parent}` template or command placeholder, or the parent page's own add-child form); a platform that links only through a separate call after the create is not supported, and the parent item itself is never modified.
