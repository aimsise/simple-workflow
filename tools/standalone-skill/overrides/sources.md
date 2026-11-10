target: references/sources.md
heading: (end of file)
mode: append
---
# Sources (`source=<spec>`)

A source is any material the user hands to `/create-ticket` besides the request text: a document, a spreadsheet, a directory of such files, the result of a read-only MCP tool, or a document fetched over HTTP. Sources are read during **Intake** (SKILL.md `## Intake`), after the destination preflight and the creation of `{scratch}`, and before Phase 1. Intake normalizes every source to one text file under `{scratch}/sources/`, concatenates them into the **source dossier**, and the rest of the run reads only that dossier: the researcher (as context about the work), the Phase 2 interview (questions the dossier already answers are not asked), the decomposer (which decides whether one source is the **partition basis**, the list of work units the tickets map onto one-to-one, or whether every source is context only) and the planner (excerpts only). The ticket-evaluator never sees it.

`source=` tokens combine with every mode. With `brief=` or `findings=` the dossier is context only and the partition basis stays with the brief-derived or findings-enumerated units; with a bare description, or with no description at all, the decomposer judges the partition basis from the dossier (see `## Partition basis`).

## Rules for every source

- **Read-only.** Intake never writes anywhere but `{scratch}/sources/`, never modifies a source, and never calls a tool or endpoint that creates, updates, deletes, sends or posts anything. A source that cannot be read stops the run before Phase 1 with the `ERROR:` line of its kind; nothing has been delivered and the `local:` counter is unchanged.
- **Order and ids.** Sources are numbered `S1`, `S2`, ... in request order; a `dir:` source expands into one id per file, in sorted file order, at its position. Every later reference to a source uses its id.
- **Pattern-checked input.** A `file:` or `dir:` path may be absolute (it is the user's own file) and may hold any letters of any script, but follows the character rule of SKILL.md Argument Parsing (no double quote, backtick, `$`, backslash or control character; whitespace only inside a double-quoted token or in a value resolved from prose); a `file:` spec may end in a query `?sheet=<name>[&sheet=<name>]`, split off before the check and allowed only on an `.xlsx` file (any other key, or a query on another kind → `ERROR: source=file:<path>: unknown option <key> (only sheet= on an .xlsx file)`), each sheet name following the same rule (the query starts at the last `?` of the spec; a `&` separates two `sheet=` values, so a sheet name that itself contains `&` or `?` cannot be written in token form and is given in prose, which carries it whole); an `mcp:` spec and an `api:` URL follow the patterns of the same kinds in `references/destinations.md`; a `source_auth_env=<VAR>` name matches `^[A-Za-z_][A-Za-z0-9_]*$`. A value that does not match → `ERROR: source=<spec without query> contains characters this skill does not accept` and stop, before anything is read. Every path in a shell command is double-quoted.
- **No secrets in text.** The value of the variable `source_auth_env=` names never appears in a prompt, ticket, summary, error line, log, file or command line; a shell command refers to it only as `$VAR`, and the `api:` fetch passes the header through `curl -K -` exactly as the `api:` destination does. An `api:` origin is recorded and printed without its query string.
- **Normalized file.** Source `S<n>` becomes `{scratch}/sources/S<n>.md`, written with the file-write tool:

```text
Source: S<n>
Kind: file | dir | mcp | api
Origin: <the path (with its ?sheet= query for a workbook), or mcp:<server>/<tool>?<query>, or the URL without its query string>
Fetched: <UTC time of the read>
Chars: <character count of the content below>
Truncated: no | yes

<content>
```

  `Origin:` for a `file:` or `dir:` path is the path as typed when it is relative; an absolute path is written with the home-directory prefix replaced by `~` (an absolute path outside the home directory is written as typed), and that same form is used wherever the origin is repeated (the dossier index, the `{intent}` line, the planner excerpts, the ticket's `Sources:` line, the Final summary), so no home path reaches a prompt, a ticket or a destination. The `Source:` line is line 1; every locator (`## Locators and excerpts`) counts lines of this file. A `.md` / `.markdown` file is copied verbatim. Any other text kind, an MCP result and an HTTP body are placed inside one fenced code block (info string `text`) so their own markup cannot open or close a section of the dossier. The output of the `.xlsx` converter is Markdown already and is copied verbatim.
- **Caps.** A source whose content exceeds **60,000 characters** is cut at the last line boundary before the limit, followed by the line `[truncated: source S<n> exceeds 60000 characters; <k> characters dropped]`, and its header says `Truncated: yes`; the `.xlsx` converter applies its own row, column and character caps and marks each one with a `[truncated: ...]` line, which also sets `Truncated: yes`. When the sum of all normalized files exceeds **150,000 characters**, print `ERROR: sources exceed the intake limit (<total> characters > 150000; largest: S<a> <chars>, S<b> <chars>, S<c> <chars>); narrow the inputs` and stop. Every truncated source is also reported once as `WARNING: source S<n> (<origin>) was truncated at the intake cap` and repeated in the Final summary.
- **Count.** More than 50 sources after `dir:` expansion → `ERROR: more than 50 sources after directory expansion; narrow the inputs` and stop.

## Writing a source

A `source=` token carries one spec or a comma-separated list of specs, and a spec may omit its kind. Both are resolved right after the character rule has passed on the whole value and before any other check; every check, cap and `ERROR:` line of this file then applies to each resolved spec exactly as if it had been typed in its own `source=` token with its kind, and the 50-source cap counts resolved specs. Whether a path exists is tested with the shell tool running `[ -e "<path>" ]` (a directory: `[ -d "<path>" ]`), the path double-quoted, never before the character rule has passed.

1. **List split.** When the whole value, with any kind prefix removed and any `?sheet=` query split off, names an existing file or directory, it is one spec (a file name that contains a comma stays whole). Otherwise split the value at every comma and walk the pieces left to right: a piece that begins with a kind prefix (`file:`, `dir:`, `mcp:`, `api:`), begins with `http://` or `https://`, or, with its `?sheet=` query split off, names an existing file or directory starts a new spec; any other piece is joined back to the spec before it together with its comma, so a comma inside a URL or an MCP query value stays where it was, and a list item that names nothing makes the joined spec fail its own check instead of disappearing. Empty pieces (two commas in a row, a trailing comma) are dropped. Whitespace never separates specs: in `source=a.md b.md` only `a.md` is a source and `b.md` stays in the request text, so several sources are written `source=a.md,b.md`, as repeated tokens, or in prose.
2. **Kind inference.** A spec that begins with a kind prefix keeps it. A spec that begins with `http://` or `https://` is `api:`. A spec whose text before its first `:` is a scheme-like word (a letter followed by letters, digits, `+`, `-` or `.`) that names none of the four kinds → the unknown source kind `ERROR:` of SKILL.md Argument Parsing, so a mistyped kind (`fiel:a.md`) is caught and never read as a path; a path whose first segment contains a `:` is therefore written with `file:`. Any other spec is a path: an existing directory → `dir:`, anything else → `file:` (a missing path then stops with the `file:` not-found `ERROR:`). `mcp:` is never inferred: whether a name is an MCP server depends on the servers connected to the session, so the same text would mean a server in one session and a path in another; an MCP source is written with `mcp:` or stated in prose (`### An MCP item named in prose`).
3. **Echo.** When a token was split or a kind was inferred, the `Resolved:` line of SKILL.md Argument Parsing lists every resolved spec with its kind (`Resolved: source=file:a.md source=dir:docs`), under the same printing rules as a prose resolution.

## `file:<path>`

One file. Its kind is its extension, matched case-insensitively:

| Extension | How it is read |
|---|---|
| `.md`, `.markdown` | file-read tool; copied verbatim |
| `.txt`, `.csv`, `.tsv`, `.json`, `.yaml`, `.yml` | file-read tool; placed inside one fenced block |
| `.xlsx` | the shell tool running the converter shipped with this skill (below); its Markdown output is copied verbatim |

Missing file → `ERROR: source file not found at <path>`. Any other extension, or none → `ERROR: source=file:<path>: unsupported file kind (supported: .md .markdown .txt .csv .tsv .json .yaml .yml .xlsx)`.

**Excel workbooks are read as workbooks**, with nothing converted beforehand. Run, with the shell tool:

```bash
python3 -I "{skill_root}/scripts/xlsx_to_text.py" --max-rows 2000 --max-cols 64 --max-chars 60000 [--sheet="<name>" ...] -- "<path>"
```

In this command line, and only here, a `~`-prefixed path (`{skill_root}`, or the workbook path as typed) is written as `"$HOME/<the part after ~/>"`, the whole value inside one pair of double quotes (`$HOME` expands inside them, a `~` does not); the command line itself is never written into a prompt, a ticket or a file. The `--` keeps a path that starts with `-` from being read as an option, and the `--sheet=` form does the same for a sheet name that starts with `-`. A `~`-prefixed path read with the file-read tool is passed as typed; when the tool reports it missing, retry once with the home directory expanded, and never record the expanded form. The converter uses only the Python 3 standard library (no package to install) and prints one `## Sheet: <name>` section per worksheet as a Markdown table whose first column is the worksheet row number, so a cell keeps its address. Shared and inline strings, numbers, booleans, cell errors and the cached value of a formula are printed; a number whose cell format is a date format is printed as an ISO date; merged ranges are not expanded; hidden sheets are included and marked. `--sheet="<name>"` (one per `?sheet=` value, exact match) restricts the output to those worksheets; without it every worksheet is read. A converter or `curl` message copied into an `ERROR:` line has the home-directory prefix replaced by `~` first (the converter echoes the expanded path it was given). Exit status 2 → `ERROR: source=file:<path> is not a readable .xlsx workbook (<first line of the message>)`, which for an unknown sheet name lists the workbook's sheet names; exit status 3 → `ERROR: source=file:<path> exceeds the workbook safety limits (<first line of the message>)`; any other non-zero status → `ERROR: source=file:<path> could not be converted (<last line of the error output>)`. When `python3` is not on the PATH, try `python` once and use it only if `python --version` reports version 3; otherwise `ERROR: reading an .xlsx source needs Python 3 on the PATH (python3 not found)`. The script is run with `-I` (isolated mode), so nothing in the workbook's directory is imported.

## `dir:<path>`

Every regular file directly inside the directory (subdirectories are not descended, files whose name starts with `.` are skipped), in byte-wise sorted name order, each handled as a `file:` source and numbered in that order. A discovered name is checked against the character rule like a typed path; a name that breaks it is skipped and named in the WARNING below (it never reaches a shell command). A file of an unsupported kind, or with a name outside the character rule, is skipped, and every skipped file is named once in `WARNING: source dir:<path> skipped <k> file(s) (unsupported kind or name): <names>`; a subdirectory is counted in `WARNING: source dir:<path> has <k> subdirectories, which were not read`. Missing directory → `ERROR: source directory not found at <path>`; no supported file → `ERROR: source dir:<path> holds no supported file`.

## `mcp:<server>/<tool>[?<name>=<value>&...]`

`<server>` is the name of an MCP server in this session's live tool inventory and `<tool>` names one of its tools exactly (illustrative only: a wiki page getter, an issue reader, a document fetcher).

1. **Find the tool.** No such server → `ERROR: source mcp:<server> is not available in this session`; no such tool → `ERROR: source mcp:<server>/<tool>: no such tool on that server`.
2. **Read-only check.** The tool's name and declared description MUST read as retrieval (get, read, fetch, list, search, export; illustrative only). A tool whose name or description says it creates, updates, deletes, sends, posts, comments or moves anything → `ERROR: source mcp:<server>/<tool> is not a read-only tool` and stop; the property is what the tool does, decided from its description, never from the name alone.
3. **Arguments.** Each `<name>=<value>` pair of the query becomes the parameter `<name>`, converted to the parameter's declared JSON type when its schema declares one (integer, number or boolean; otherwise a string); a value that does not convert → `ERROR: source mcp: parameter <name> expects <type>`. A required parameter with no pair → `ERROR: source mcp:<server>/<tool> needs <name>=<value> in its query`. A `<value>` follows the character rule of SKILL.md Argument Parsing (letters of any script allowed; no double quote, backtick, `$`, backslash or control character) and contains no `&` (the pair separator) or whitespace; the first `=` of a pair separates name and value, later ones belong to the value.
4. **Call once.** The result's text content (every text block, in order; a JSON result pretty-printed) is the source content. An error result → `ERROR: source mcp:<server>/<tool> failed (<first line of the error, at most 200 characters>)`; an empty result → `ERROR: source mcp:<server>/<tool> returned no content`.

### An MCP item named in prose

A prose statement may name an item reachable through an MCP server of the session by its title or by its web URL rather than by the identifier the server's read tool takes (illustrative only: the wiki page titled "Requirements", an issue given by its link). Prose resolution then:

1. **Picks the server and the read tool**: the server the statement names, or else the one server whose tools read that kind of item, and the one tool on it whose name and description read as retrieval of a single item (the read-only check of step 2 above applies). Two candidates or none → ask, as for any ambiguous prose statement.
2. **Passes a URL as is** when the read tool declares a parameter whose description says it takes the item's URL; no lookup is made.
3. **Looks the item up once** otherwise: one call of a tool of the same server whose name and description read as search or listing (the same read-only check applies), with the title or the URL as its query. Exactly one result whose title equals the stated title (case-insensitive, surrounding whitespace ignored) or whose URL equals the stated URL → its identifier fills the read tool's identifier parameter. Zero such results, two or more, no search or listing tool on the server, or an error result → ask the user, listing at most 5 candidates (title and identifier) when there are any; when the ask-user tool is unavailable, denied or erroring → the Prose resolution `ERROR:` (`cannot resolve the request's input or output statement`) and stop, never a guess.
4. **Echoes** the outcome on the `Resolved:` line as the complete `source=mcp:<server>/<tool>?<parameter>=<identifier>` spec. The lookup is part of the resolution, not a source: its result is not written to `{scratch}/sources/`, never reaches the dossier, and at most one lookup call is made per statement.

A URL stated in prose resolves to `api:` (one plain `GET`) unless the statement says to read it through an MCP server or names one; a page behind a login is usually readable only through its platform's MCP server, so the statement should say so.

## `api:<url>`

An HTTP `GET` of `<url>` (`http` or `https` only, same pattern as the `api:` destination). The optional `source_auth_env=<VAR>` names an environment variable holding a bearer token; only the name is ever written, and `[ -n "${VAR:-}" ] && echo set || echo unset` (run with the variable's name in place of `VAR`) MUST print `set`, else `ERROR: source api: environment variable <VAR> is not set`; then `case "${VAR:-}" in *\"*|*\\*) echo bad;; *) echo ok;; esac` MUST print `ok` (a value holding a double quote or a backslash cannot be written into the `curl` config), else `ERROR: source api: environment variable <VAR> holds characters the fetch cannot carry`. Fetch with the shell tool (`{scratch}/sources/` exists: Intake I-1 creates it):

```bash
printf 'header = "Authorization: Bearer %s"\n' "$VAR" | curl -sS -g --max-time 120 --connect-timeout 15 -K - \
  -o "{scratch}/sources/S<n>.body" -w '%{http_code}' "<url>"
```

Without `source_auth_env=`, drop the `printf ... |` prefix and the `-K -` option. A status outside 200-299, or a transport failure → `ERROR: source api:<url without query string> returned HTTP <status>` (or `could not be fetched (<first line of the curl error>)`) and stop. The body is read back with the file-read tool and becomes the source content (a JSON body pretty-printed with `jq .` when `jq` is available, otherwise verbatim; any other body verbatim, markup included). The response body is never printed.

## The dossier

`{scratch}/sources/dossier.md`, written with the file-write tool once every source is normalized:

```markdown
# Source dossier

| id | kind | origin | chars | truncated |
|---|---|---|---|---|
| S1 | file | docs/backlog.xlsx | 12345 | no |
| S2 | mcp | mcp:<server>/<tool> | 3210 | no |

---

<the normalized file of S1, verbatim>

---

<the normalized file of S2, verbatim>
```

Who receives what:

| Reader | Receives |
|---|---|
| researcher (Phase 1) | the index table inline, and the dossier path to read with the file-read tool; context about the work, never repository evidence |
| Phase 2 interview | the dossier is scanned by the args-aware shrinkage rule: a question the dossier already answers is not asked |
| decomposer | the whole dossier inline, under `## Source dossier` (Form A and Form B of `references/spec-decomposer-input.md`), plus the Form B header `Dossier role: candidate` (bare or derived description) or `Dossier role: context` (brief) |
| planner (Phase 3) | only the excerpts named by its ticket's `source_refs`, under `## Source excerpts` (below) |
| ticket-evaluator | nothing |

## Locators and excerpts

A locator names lines of a normalized file: `S<n>:L<a>-L<b>` (a line range, inclusive), `S<n>:L<a>` (one line) or `S<n>` (the whole source). Line 1 is the `Source:` line of that file. The decomposer emits locators in two places of its `## Result`: `**Partition basis**:` and each ticket's `source_refs:` sub-line.

**Excerpt extraction** (orchestrator, before each planner spawn, initial and retry): for each locator of the ticket's `source_refs`, copy lines 1-6 of the source (its header block) once, then the named lines; when a named line is a row of a Markdown table, also copy once the nearest `## Sheet:` heading above it (a workbook source), that table's header row and separator row, and the table's first data row (in a workbook, worksheet row 1, which usually names the columns). Put the result under `## Source excerpts` in the planner spawn prompt, each excerpt introduced by its locator and origin. Cap: 8,000 characters per ticket, cut at a line boundary with the line `[truncated: source excerpts exceed 8000 characters]`. The whole dossier is never inlined into a planner spawn.

The planner ends the ticket's `### Background` with one line `Sources: <locator> (<origin>[, <where in it>]); ...` naming every excerpt it drew on (for a spreadsheet, the sheet and row numbers of the table rows; for a document, its heading), so an acceptance criterion that restates a requirement of a source can be traced to it. Every requirement drawn from a source is restated in the AC text itself (the value, the behaviour, the limit); an AC never points at a locator, because the ticket-evaluator sees no source. A ticket that used no excerpt writes no `Sources:` line.

## Partition basis

The decomposer decides it; the rule lives in `references/spec-decomposer-input.md` (`## Source dossier`) and `references/agents/decomposer.md` (`## Source dossier handling`). In short: a source, or one part of it (a sheet, a section, a list), is **partition-authoritative** when it enumerates two or more discrete items that each state their own scope and outcome as work still to be done; a list of attributes of one deliverable, a glossary, a status table of finished work or a free-form narrative is context. With `findings=` the partition basis is always the findings units; with `brief=` it is always derived from the brief; otherwise the decomposer reports `**Partition basis**: <locator>` or `derived`, and the Final summary repeats it.

## Final summary

When `source=` was given, the Final summary (`references/write-path-templates.md`) carries one `Sources:` line per source right after the `Destination:` line (after the `Created:` line in the failure block): `Sources: S<n> <kind> <origin> (<chars> chars[, truncated])`, followed by `Partition basis: <locator> | derived | findings | brief`, and repeats every intake `WARNING:` line.
