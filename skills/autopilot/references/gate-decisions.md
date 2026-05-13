# Gate-Decision Reference

Detailed canonical format for `[AUTOPILOT-POLICY]` gate-decision lines
emitted on stdout and `## Decisions Made` table rows written into
`autopilot-log.md`, plus the Unreached gate enumeration discipline. The
SKILL.md cites this file rather than redefining the regexes inline.

The autopilot canonical gate set is `scout`, `plan`, `build`, `verify`,
`retro` (the five pipeline gates). Policy gates emitted by `/scout`,
`/impl`, `/ship` (e.g. `ac_eval_fail`, `ship_review_gate`,
`ticket_quality_fail`, `unexpected_error`) are also rendered using the
same canonical line and table-row shapes — the regexes below admit any
`[a-z][a-z0-9_-]*` gate name.

## `gate-decision-line` (stdout, one line per decision)

Emitted as autopilot decides each gate:

```
[AUTOPILOT-POLICY] gate=<name> action=<allow|deny|skip> reason=<evaluated|not_reached|condition_unmet|dependency_skipped>
```

The line MUST match the following ERE exactly. No trailing whitespace,
no extra fields:

```
^\[AUTOPILOT-POLICY\] gate=[a-z][a-z0-9_-]* action=(allow|deny|skip) reason=(evaluated|not_reached|condition_unmet|dependency_skipped)$
```

The line is also written verbatim into `autopilot-log.md` (non-fenced
lines only — illustrative `[AUTOPILOT-POLICY]` lines inside
triple-backtick fences or HTML comments are documentation, not contract
events, and are ignored by readers).

## `decisions-table-row` (autopilot-log.md, one row per gate)

Emitted under the `## Decisions Made` heading:

```
| <gate> | <action> | <reason> | <free-form notes> |
```

Each row MUST match the following ERE exactly:

```
^\| [a-z][a-z0-9_-]* \| (allow|deny|skip) \| (evaluated|not_reached|condition_unmet|dependency_skipped) \| .+ \|$
```

The fourth column is free-form notes (e.g., `human_override`,
`kb_override`, `eval_status=PASS`, the cited policy path) and MUST be
non-empty.

## Reason semantics

The only four canonical values, with their when-to-emit conditions:

| reason | When to emit |
|---|---|
| `evaluated` | The gate's conditions were considered and the decision (`allow` / `deny` / `skip`) follows from that evaluation. This is the default outcome for any gate that runs. |
| `not_reached` | The run terminated (stop, fatal failure, exhausted iteration budget, etc.) before this gate was considered. The gate was never evaluated against its policy. |
| `condition_unmet` | The gate's preconditions were not satisfied (e.g., `retro` requires the upstream `build` to have emitted `action=allow`). The action will always be `skip`. |
| `dependency_skipped` | An upstream gate emitted `action=deny` and this gate is skipped as a cascade. The action will always be `skip`. |

`reason=evaluated` is paired with any of the three actions (`allow` /
`deny` / `skip`). The other three reasons (`not_reached`,
`condition_unmet`, `dependency_skipped`) are paired with `action=skip`
only — they describe a non-evaluation, not a deny.

## Unreached gate enumeration discipline

The five canonical gates are `scout`, `plan`, `build`, `verify`,
`retro`. When the run terminates **before considering** one or more
canonical gates (e.g., a fatal failure during `build` short-circuits
`verify` and `retro`, or `scout` exits with `ERROR:` so
`plan`/`build`/`verify`/`retro` are never considered),
`autopilot-log.md` MUST contain an `## Unreached Gates` section
enumerating each unreached gate on its own line:

```
## Unreached Gates

- plan: not_reached
- build: not_reached
- verify: not_reached
- retro: not_reached
```

Each enumerated line MUST match the ERE:

```
^- (scout|plan|build|verify|retro): not_reached$
```

The number of enumerated lines equals the count of canonical gates that
have **zero** corresponding `decisions-table-row` in the
`## Decisions Made` table. When every canonical gate has a row in
`## Decisions Made`, the literal heading `## Unreached Gates` MUST NOT
appear anywhere in the log body — its presence-without-need is a
contract violation flagged by `tests/test-skill-contracts.sh`.

### Edge case: empty decisions table

If `## Decisions Made` contains zero rows (e.g., the run aborted in
pre-flight before any gate was decided), the `## Unreached Gates`
section enumerates **all five** canonical gates — `scout`, `plan`,
`build`, `verify`, `retro` — each on a separate line followed by
`: not_reached`.

### Relationship to runtime gate-decision lines

An unreached gate has no `[AUTOPILOT-POLICY]` line on stdout (it was
never decided). The `## Unreached Gates` section is the only mechanism
that records its non-evaluation. Tooling (`/tune`, `tune-analyzer`)
reads both the `## Decisions Made` table and the `## Unreached Gates`
enumeration to compute consecutive-`not_reached` counts per gate
across runs.
