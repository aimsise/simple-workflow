# Round-cap argument parser

This file expands Phase 1 Step 1a of `skills/impl/SKILL.md` — the
`rounds=N` argument parser that resolves the per-invocation maximum round
count. The body of Step 1a in `SKILL.md` retains the pinned literals
(`rounds=N`, `default 9`, `soft cap 24`) and the resolution-precedence
sentence; this file holds the full regex, validation, hard-cap / soft-cap,
strip-rule, precedence, stderr placeholder, and quoted-string-caveat
prose.

## Token boundary

Tokenize `$ARGUMENTS` on whitespace, then test each token against
`^[Rr][Oo][Uu][Nn][Dd][Ss]=([^[:space:]]*)$` (case-insensitive `rounds=`
key; the captured value may be empty so a bare `rounds=` is recognized
as a token and rejected at validation rather than silently dropped).
Match only whole, whitespace-delimited tokens — substrings inside a
quoted plan path (e.g. `.simple-workflow/docs/plans/some-rounds=5-test.md`)
or inside other tokens (`myrounds=15`) are NOT recognized. If multiple
matching tokens appear, the first wins.

## Validate N

The captured value MUST be a non-empty positive decimal integer
(`^[1-9][0-9]*$`) AND MUST have at most 6 digits (`<= 999999`) so the
soft-cap arithmetic stays safely inside bash signed-64-bit range.

- If malformed in form (e.g. `rounds=0`, `rounds=-1`, `rounds=abc`,
  `rounds=1.5`, `rounds==5`, or the bare key `rounds=` with empty
  value): emit a single stderr warning
  `[ARG-WARN] rounds=<raw> is not a positive integer; falling back to policy or default 9`
  and treat the argument as absent (fall through to the policy /
  default precedence below).
- If form-valid but exceeds the 6-digit hard cap (e.g. `rounds=1000000`):
  emit a single stderr warning
  `[ARG-WARN] rounds=<raw> exceeds 999999 (bash arithmetic safety hard cap); falling back to policy or default 9`
  and fall through. This is distinct from the soft cap of 24 below —
  the hard cap rejects, the soft cap warns and proceeds.
- If valid (1..999999 inclusive), set `arg_rounds = N`.

## Soft cap of 24 (warn, do NOT clamp)

If `arg_rounds > 24`, emit a single stderr warning
`[ARG-WARN] rounds=<N> exceeds soft cap 24; proceeding with user-specified value`
and continue with the user-specified value. The cap is advisory only —
the loop will run for the full user-requested count. The boundary
value `rounds=24` does NOT trigger the warning.

## Strip the FIRST recognized `rounds=N` token from `$ARGUMENTS`

Strip the FIRST recognized `rounds=N` token from `$ARGUMENTS` before
plan-path detection — including when validation rejected its value (the
strip is unconditional once the token boundary regex matches; rejection
only affects the cap value, not the additional-instructions tail).
Subsequent matching tokens are intentionally left in place as part of
the additional-instructions tail; the "first wins" rule above already
pinned which token is consumed. Then collapse any resulting double
spaces and trim leading / trailing whitespace so the remaining tokens
(plan path / additional instructions) are unaffected.

**Note**: if the first recognized token is malformed (validation
rejected), validation does NOT retry against subsequent matching
tokens — the cap falls through to policy / default 9, and the user
must fix the typo and re-invoke. This is an intentional simplification
of the parser; "first valid wins" was considered and explicitly
deferred.

## Precedence for the round cap

Resolved in the Phase 2 init block — between Step 12 and Step 13 — and
written into `phases.impl.max_rounds`: `rounds=N` argument (when valid)
> `{ticket-dir}/autopilot-policy.yaml` `constraints.max_total_rounds`
(when present) > **default 9**.

## Stderr placeholder convention

- `<N>` = the parsed positive integer (used in the soft-cap warning,
  where parsing succeeded).
- `<raw>` = the captured right-hand side of the `rounds=` token (i.e.
  the regex's capture group `([^[:space:]]*)`) as it appeared in
  `$ARGUMENTS`, including any sign / decimal point / non-numeric chars
  (used in the malformed and hard-cap warnings, where parsing rejected
  the value).

Examples:
- `rounds=abc` produces `[ARG-WARN] rounds=abc is not a positive integer ...` (capture is `abc`).
- `rounds==5` produces `[ARG-WARN] rounds==5 is not a positive integer ...` (capture is `=5`).
- Bare `rounds=` produces `[ARG-WARN] rounds= is not a positive integer ...` (capture is the empty string).

The two placeholders are NOT interchangeable; downstream log greps that
key off the warning prefix should distinguish them.

## Quoted strings in `$ARGUMENTS`

Quoted strings in `$ARGUMENTS` are NOT part of the parser contract:
shells deliver `$ARGUMENTS` as a flat post-shell-quoting string, so a
quoted plan path like `"path with spaces/plan.md"` becomes
`path with spaces/plan.md` after the shell strips the quotes — there is
no quote-aware tokenization in `/impl`. Users who need spaces in plan
paths should rely on the existing
`.simple-workflow/backlog/active/{ticket-dir}/plan.md` auto-discovery
rather than passing quoted paths. The `rounds=N` parser only sees
whitespace-delimited tokens, so any spaces inside an originally-quoted
argument will split the value mid-token and the regex will not match.
