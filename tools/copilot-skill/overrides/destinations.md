target: references/destinations.md
heading: (end of file)
mode: append
---
# Destinations

`destination=<spec>` selects where Delivery (`SKILL.md` `## Delivery`) puts the tickets. Producing the tickets (Phases 1-4, the four roles, the rubric) is identical for every destination; only Delivery differs. Absent `destination=` → `local:.docs/tickets`.

| Kind | Spec | What records the run |
|---|---|---|
| Local directory | `local:<dir>` | one `ticket.md` per ticket, `split-plan.md` when N > 1, `{dir}/.ticket-counter` |
| Ticket platform behind an MCP server | `mcp:<server>[/<tool>]` [`mcp_<name>=<value>` ...] | the identifiers the create tool returns |
| HTTP API called directly | `api:<url>` [`auth_env=<VAR>`] [`template=<path>`] [`id_path=<path>`] | the identifiers the create responses carry |

## Rules for every destination

- **Preflight before Phase 1.** Right after Argument Parsing, run the preflight of the destination's kind. It is read-only: it creates, writes and calls nothing that changes state. A failed check prints its `ERROR:` line and stops the run before any agent runs. Delivery re-checks what can change in between (the `local:` counter).
- **Nothing before a verdict.** Delivery starts only after all N tickets have one of the three verdicts `PASS`, `SELF-EVALUATED` (only on a host with no subagent tool at all) or `FAIL (user-accepted)` (the user chose "proceed" at the exhausted-retry question); a destination never receives a draft. A mandatory role's subagent spawn that was attempted and failed fails the run, and nothing is delivered.
- **Topological order.** Every write or create follows the order of Step DL-1, so the identifier of each dependency exists before its dependent is delivered.
- **Destination-assigned identity.** The ticket heading is `## {id}: {Title}`. `local:` assigns `T-{NNN}` before writing; `mcp:` and `api:` submit the body with the heading `## {Title}` and take `{id}` from the create response. The `Dependencies` cell lists the `{id}` of each dependency (`--` when none).
- **Shell-safe names.** `{parent-slug}` and every `{slug_i}` match `^[a-z0-9][a-z0-9-]{0,39}$` before any shell use (a value that does not → `ERROR: <field> must be kebab-case (lowercase letters, digits, hyphens)`), and every path in a shell command is double-quoted.
- **Pattern-checked input.** Every user-controlled string that reaches a shell command (`brief=` / `findings=` paths, `{dir}`, `template=`, `auth_env=`, `id_path=`, the `api:` URL and every slug) is checked against its pattern above or below before any shell use; double quoting alone is not the defence, because a quoted string can still start an option or carry a substitution.
- **Printed URLs.** Every URL this skill prints (the `api:` request URL, a URL a create call returns, the confirmation question, the Final summary and every error line) is printed without its query string (everything from the first `?` on), and a returned item URL is recorded only after the same stripping.
- **No secrets in text.** A token, and the value of the variable `auth_env=` names, never appears in a prompt, ticket, summary, error line, log, file or command line. A shell command refers to it only as `$VAR`; never run such a command with tracing (`set -x`) or verbose output (`curl -v`, `--trace`).
- **Remote creates are not transactional.** On a failure after `k` successful creates (`mcp:` or `api:`), print `Created before the failure:` with the `k` identifiers in creation order (`Created: none` when `k` is 0), then the `ERROR:` line, and stop. Never delete or modify a remote item and never retry on your own: a re-run with the same input creates every ticket again.

## `local:<dir>`

`<dir>` is a relative path inside the repository, resolved against the current working directory (which may be a sub-directory of the repository).

**Preflight**:

1. `<dir>` is non-empty, does not start with `/`, `~` or `-`, is not `.git` and does not start with `.git/`, contains no `..` segment and follows the character rule of SKILL.md Argument Parsing (no double quote, backtick, `$`, backslash or control character; whitespace only inside a double-quoted token or in a value resolved from prose). Else `ERROR: destination local: <dir> must be a relative path inside the repository (no .. segment, quote, backtick, dollar, backslash or control character)`.
2. When `{dir}` exists it must be a directory (else `ERROR: destination local:<dir> is not a directory`); when `{dir}/.ticket-counter` exists, its content, surrounding whitespace removed, must be a non-negative integer (else the counter error below).

Layout (created on demand; `{dir}` itself may not exist yet):

```
{dir}/
  .ticket-counter                    next free ticket number
  .rollback/{parent-slug}-{ts}/      quarantined partial output of a failed write
  {parent-slug}/
    split-plan.md                    N > 1 only
    {NNN}-{slug}/ticket.md           one directory per ticket
```

**Delivery**, in this order:

1. **Counter read and validate.** Read `{dir}/.ticket-counter`; missing → `counter` = `1`. Non-numeric → `ERROR: {dir}/.ticket-counter contains non-numeric value '<content>'. Fix or delete the file and retry.` `N` = the number of tickets.
2. **Allocate.** For the i-th ticket in topological order (`i` = `0..N-1`): `number_i = counter + i`, zero-padded to 3 digits → `{NNN}`, so its `{id}` is `T-{NNN}`; `{slug_i}` = the title in kebab-case (lowercase ASCII, whitespace → `-`, strip every character outside `[a-z0-9-]`, drop leading hyphens, truncate at 40 characters), or `ticket` when that leaves an empty string (e.g. a title with no ASCII letter or digit); `{ticket_dir_i}` = `{dir}/{parent-slug}/{NNN}-{slug_i}/`. Fill each heading (`## T-{NNN}: {Title}`) and each `Dependencies` cell (the `T-{NNN}` of each dependency).
3. **Never overwrite.** If any `{ticket_dir_i}` already exists, or N > 1 and `{dir}/{parent-slug}/split-plan.md` already exists, print `ERROR: create-ticket write refused — <path> already exists` and stop before writing anything (counter untouched).
4. **Keep the quarantine out of commits.** When `git rev-parse --show-toplevel` succeeds and `{dir}` lies inside that repository, run `git check-ignore -q "{dir}/.rollback/x"`. Exit status 1 (not ignored) → append the line `{rel}/.rollback/` to the `.gitignore` at the repository root with the shell tool running `printf '%s\n' "{rel}/.rollback/" >> "<root>/.gitignore"` (double quotes, as for every user-derived value), where `<root>` is the directory `git rev-parse --show-toplevel` printed and `{rel}` is `{dir}` relative to it (append only; the redirect creates the file when it does not exist; never rewrite, reorder or remove existing lines). Outside a repository, skip this step. Whether the tickets and the counter are committed is the user's decision: this skill never adds them to `.gitignore` and never stages or commits anything.
5. **Write.** (1) Note whether `{dir}/{parent-slug}/` exists, then run `mkdir -p "{dir}/{parent-slug}"`; (2) create each `{ticket_dir_i}` with `mkdir -p "{ticket_dir_i}"`; (3) write `{ticket_dir_i}/ticket.md` with the file-write tool; (4) N > 1 only: write `{dir}/{parent-slug}/split-plan.md` from the template in `references/write-path-templates.md` and validate it by the writer-side rules of `references/split-plan-schema.md` (a violation → `ERROR: split-plan validation failed — <reason>`, handled as a write failure).
6. **Counter write.** Only after every file of step 5 is written: write `counter + N` to `{dir}/.ticket-counter`, once (with the file-write tool when the file is absent, otherwise with the file-edit tool replacing its whole content). If this write fails, the tickets stay in place: print `ERROR: create-ticket counter write failed — set {dir}/.ticket-counter to <counter + N> (<reason>)` and stop.

**Write failure → quarantine, never delete.** When step 5 fails: `{ts}` = `date -u +%Y%m%dT%H%M%SZ` (ISO-8601 UTC, colons removed); run `mkdir -p "{dir}/.rollback/{parent-slug}-{ts}"`; then move into that directory, with `mv "<entry>" "{dir}/.rollback/{parent-slug}-{ts}/"`, everything this run created: the whole `{dir}/{parent-slug}` when step 5 created it, otherwise only each `{ticket_dir_i}` and `split-plan.md` this run wrote. Print `ERROR: create-ticket write failed — partial output quarantined at {dir}/.rollback/{parent-slug}-{ts}/ (<reason>)` and stop. The counter is untouched (it is written only in step 6), so a re-run with the same inputs is safe and re-allocates the same `{NNN}` numbers. `.rollback/` starts with a dot, so a listing of the ticket directories under `{dir}` never shows it. No delete command is used: a quarantine stays recoverable and a recursive delete does not.

## `mcp:<server>[/<tool>]`

`<server>` is the name of an MCP server in this session's live tool inventory; `/<tool>` optionally names the create tool exactly. Illustrative only: a work-item tracker's MCP server.

**Preflight**:

1. **Find the server's tools.** The host lists every MCP tool available to this session together with the server it belongs to and its input schema. Collect the tools of `<server>`. None → `ERROR: destination mcp:<server> is not available in this session`.
2. **Select the create tool.** A tool qualifies when its input schema has a string property for the item's title (a short one-line name of the item) and a separate string property for its body (the long-form description); decide by each property's name and schema description, not by the name alone.
   - `/<tool>` given → use that tool verbatim. Not among the server's tools → `ERROR: destination mcp:<server>/<tool>: no such tool on that server`; present but not qualifying → the no-tool error below.
   - Otherwise: no qualifying tool → `ERROR: destination mcp:<server> exposes no tool that accepts a title and a body`. Several → keep those whose name or description says they create a new item (not update, comment on or search existing ones); still several → `ERROR: destination mcp:<server> exposes several tools that accept a title and a body (<names>); pass destination=mcp:<server>/<tool>`.
3. **Fill the other parameters.** Any declared parameter `<name>` other than the title and the body, required or optional (e.g. a project, repository or board key, a label list; illustrative only), takes its value from the request token `mcp_<name>=<value>` when one is given (`ERROR: mcp_<name>= names no parameter of mcp:<server>/<tool> (parameters: <names>)` when the tool declares no such parameter), passed as the parameter's declared JSON type when its schema declares one (integer, number or boolean; otherwise a string); a value that does not convert → `ERROR: mcp_<name>= must be <type>` and stop. A required parameter with no such token (a parameter that step 4 fills from `parent=` counts as given): interactive → ask for all of them in one ask-user call; non-interactive → `ERROR: destination mcp:<server>/<tool> needs <name>; pass mcp_<name>=<value>` and stop. Never guess a value.
4. **Link to a parent item.** With `parent=<id>` (Argument Parsing), find the parameter of the create tool whose declared description says it links the new item to an existing parent, epic or container item (illustrative only: a parent key, an epic link, a container id), decided from the description, never from the name alone, and pass `<id>` there, converted to the parameter's declared type as in step 3. Several such parameters → `ERROR: destination mcp:<server>/<tool> has several parent-link parameters (<names>); pass mcp_<name>=<id> instead`; none → `ERROR: destination mcp:<server>/<tool> has no parameter that links a new item to an existing one (parameters: <names>); pass mcp_<name>=<id> if one of them is it`. An `mcp_<name>=` token that names the chosen parameter with a different value → `ERROR: parent= and mcp_<name>= disagree on the parent item (<id> vs <value>)`; with the same value it is simply redundant. A `parent=` value that does not convert to the parameter's declared type → `ERROR: parent= must be <type> for mcp:<server>/<tool>`. The parent is never modified: the link is set on the new item only.

**Delivery**:

1. **Confirm once.** Before the first create, ask with the ask-user tool: "Create N items in mcp:<server>/<tool>?" A "no", an ask-user error, or no ask-user tool at all (non-interactive) → print `ERROR: remote delivery needs an interactive confirmation; re-run with confirm=yes to skip it` and stop, nothing created. `confirm=yes` in the request text is the only way to skip the question.
2. For each ticket in topological order: title = `{Title}`; body = the ticket with the heading `## {Title}`, its `Dependencies` cell filled with the dependency identifiers, and every logical id (`{parent-slug}-part-N`) of an already-created ticket replaced by that ticket's identifier (a forward reference to a later ticket keeps its logical id).
3. Dependencies: when the tool's schema has a parameter for links or relations to other items that accepts identifiers (e.g. a blocked-by or depends-on field; illustrative only), pass the dependency identifiers there. Otherwise, when the ticket has dependencies, put the line `Depends on: <id>, <id>` right after the body's `## {Title}` heading (the first line after it), followed by a blank line.
4. Call the tool once. `{id}` is the identifier form that the tool's link / relation parameter accepts, when its schema has one (so later dependents can link to it); otherwise the result's primary identifier (its key, number or id). Also record the item's URL, without its query string, when the result carries one.
5. An error result, or a result without an identifier → the remote-failure rule above, with `ERROR: destination mcp:<server>/<tool> create failed for <logical id> (<reason>)`; for an error result the reason is the first line of the tool's error message, at most 200 characters (never the full result), and for a missing identifier it is `no identifier in the result; the item may exist`.

No split-plan file, no counter and no local write other than `{scratch}` and the `.gitignore` append of Argument Parsing. **Limitation**: without `parent=` (or an `mcp_<name>=` for the link parameter) each ticket is a standalone item; linking through a separate link tool after the create, and any change to the parent item itself, are out of scope.

## `api:<url>`

Illustrative only: a work-item tracker's REST create endpoint. `<url>` is the endpoint that creates one item per `POST` with a JSON body. Options (each its own token in the request text):

- `auth_env=<VAR>`: the name of an environment variable holding a bearer token (only the `Bearer` scheme is supported). Only the name is ever written; the value stays in the environment.
- `template=<path>`: a JSON request-body template, a relative path inside the repository. A placeholder is a JSON string whose whole value is `{title}`, `{body}` or `{parent}`, at any depth; `{title}` and `{body}` must appear. `{parent}` is replaced by the `parent=<id>` value (preflight step 7 checks that it is present exactly when `parent=` is given). Default: `{"title": "{title}", "description": "{body}"}`, which has no `{parent}`, so `parent=` on an `api:` destination always needs a `template=`. The Final summary prints `Parent: <id>` when `parent=` was given.
- `id_path=<path>`: where the created item's identifier sits in the response, as a `jq` path that starts with a `.name` step and is made only of `.name` and `[index]` steps (e.g. `.id`, `.data.key`, `.items[0].number`; illustrative only). Default: `.id`.

Wherever this skill prints the URL (error lines, the Final summary `Destination:` line), it prints `<url>` without its query string (everything from the first `?` on is dropped).

**Preflight** (each failure prints its `ERROR:` line and stops):

1. `command -v curl` and `command -v jq` both succeed, and `jq -n 'walk(.)'` succeeds (`jq` 1.6 or later, for `walk` and `--rawfile`) → else `ERROR: destination api: needs curl and jq 1.6 or later on PATH`.
2. `<url>` starts with `https://` (plain `http://` only for a loopback host such as `localhost` or `127.0.0.1`), and contains no whitespace, quote, backtick, `$`, backslash, `[`, `]`, `{` or `}`. Else `ERROR: destination api: unusable URL (<rule>)`.
3. `<url>` carries no credential: no userinfo (an `@` before the first `/` after the scheme) and no query parameter whose name is a credential word or ends in one: lower-case the name and split it into tokens on `_`, `-` and camelCase boundaries; it fails when any token equals `key`, `apikey`, `token`, `secret`, `password`, `passwd`, `pwd`, `sig`, `signature`, `auth`, `authorization`, `bearer`, `credential` or `credentials` (so `api_key`, `access_token` and `sig` fail, while `assignee`, `design`, `author`, `keyword` and `api-version` pass; illustrative only). Else `ERROR: destination api: credentials belong in auth_env=, not in the URL`. Other query parameters are allowed (e.g. an API version parameter; illustrative only). A credential embedded in the URL path cannot be detected, so never put one there.
4. `auth_env=` given: `<VAR>` matches `^[A-Za-z_][A-Za-z0-9_]*$`, and the shell tool running `[ -n "${VAR:-}" ] && echo set || echo unset` (with the variable's name in place of `VAR`) prints `set`; the check prints only `set` or `unset`, never the value. Else `ERROR: destination api: environment variable <VAR> is not set`. Then the shell tool running `case "${VAR:-}" in *\"*|*\\*) echo bad;; *) echo ok;; esac` (the variable's name in place of `VAR`) must print `ok`; it prints only `ok` or `bad`, never the value. The token reaches `curl` inside a double-quoted config value (Delivery step 4), where `"` would end the value and `\` would start an escape, so `bad` → `ERROR: destination api: the token in <VAR> contains a character the curl config cannot carry (" or \)`.
5. `template=` given: `<path>` does not start with `/`, `~` or `-`, is not `.git` and does not start with `.git/`, contains no `..` segment and follows the character rule of SKILL.md Argument Parsing (no double quote, backtick, `$`, backslash or control character; whitespace only inside a double-quoted token or in a value resolved from prose) (else `ERROR: template= <path> must be a relative path inside the repository (no .. segment, quote, backtick, dollar, backslash or control character)`), and `jq -e '[.. | strings | select(. == "{title}")] | length > 0' "<path>"` and the same for `{body}` both succeed (else `ERROR: destination api: template <path> is not JSON with {title} and {body} placeholders`).
6. `id_path=` given: it matches `^\.[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*|\[[0-9]+\])*$`. Else `ERROR: destination api: unusable id_path <path>`.
7. `parent=` given: `template=` must be given (else `ERROR: destination api: parent= needs a template= with a {parent} placeholder`) and `jq -e '[.. | strings | select(. == "{parent}")] | length > 0' "<path>"` must succeed (else `ERROR: destination api: template <path> has no {parent} placeholder for parent=`). `parent=` absent and `template=` given: the same `jq` test must fail (else `ERROR: destination api: template <path> uses {parent} but no parent= was given`).

**Delivery**:

1. **Confirm once.** Before the first create, ask with the ask-user tool: "Create N items in api:<url without query string>?" A "no", an ask-user error, or no ask-user tool at all (non-interactive) → print `ERROR: remote delivery needs an interactive confirmation; re-run with confirm=yes to skip it` and stop, nothing created. `confirm=yes` in the request text is the only way to skip the question.
2. For each ticket `i` in topological order, with the file-write tool, write the title to `{scratch}/title-{i}.txt` and the body to `{scratch}/body-{i}.md`: the ticket with the heading `## {Title}`, its `Dependencies` cell filled with the dependency identifiers, every logical id (`{parent-slug}-part-N`) of an already-created ticket replaced by that ticket's identifier (a forward reference keeps its logical id) and, when it has dependencies, the line `Depends on: <id>, <id>` as the first line after the `## {Title}` heading, followed by a blank line. Without `template=`, write the default template once to `{scratch}/template.json`.
3. Build the request body with `jq`, which does all JSON escaping (never escape by hand); `<template>` is the `template=` path, or `{scratch}/template.json`; `<id>` is the `parent=` value, or the empty string when `parent=` was not given (the flag is always passed; preflight step 7 guarantees the template then holds no `{parent}`):

   ```bash
   jq --rawfile title "{scratch}/title-{i}.txt" --rawfile body "{scratch}/body-{i}.md" --arg parent "<id>" \
     'walk(if . == "{title}" then ($title | rtrimstr("\n")) elif . == "{body}" then $body elif . == "{parent}" then $parent else . end)' \
     "<template>" >"{scratch}/request-{i}.json"
   ```

4. Send it. With `auth_env=`, the header reaches `curl` through a config read from stdin (`-K -`), so the token is in neither the command line nor a file; `$VAR` stands for the variable's name, e.g. `$TRACKER_TOKEN`, never for its value:

   ```bash
   printf 'header = "Authorization: Bearer %s"\n' "$VAR" | curl -sS -g --max-time 120 --connect-timeout 15 -K - \
     -X POST "<url>" \
     -H "Content-Type: application/json" \
     --data-binary @"{scratch}/request-{i}.json" \
     -o "{scratch}/response-{i}.json" -w '%{http_code}'
   ```

   Without `auth_env=`, drop the `printf ... |` prefix and the `-K -` option. `-g` (`--globoff`) keeps `curl` from expanding brackets or braces in the URL.

5. Success is a zero `curl` exit status and an HTTP status of `2xx`. `{id}` = the output of `jq -r '<id_path> // empty' "{scratch}/response-{i}.json"`.
6. A non-zero `curl` exit (a timeout included), a non-`2xx` status or an empty `{id}` → the remote-failure rule above, with `ERROR: destination api:<url without query string> create failed for <logical id> (<reason>)`, where the reason is `timed out after <n> s; the item may exist` for a `curl` timeout, the `curl` exit code for another `curl` failure, the HTTP status, or `no identifier at <id_path>; the item may exist`. Do not print the response body; it stays in `{scratch}/response-{i}.json` for the user to inspect.

No split-plan file, no counter and no local write other than `{scratch}` and the `.gitignore` append of Argument Parsing.
