#!/usr/bin/env bash
# accept-set-verify.sh — PostToolUse(Write|Edit) hook.
#
# Deterministic post-hoc conformance gate over the PERSISTED `## Accept-set
# sweep` section of an `eval-round-{n}.md` report — the Advertised-Accept-Set
# Conformance (AASC) observability line written by the ac-evaluator's
# Persistence-First terminal rewrite (see agents/ac-evaluator.md
# `## Persistence-First Protocol` and the `## Failure-class panel` L-ROBUSTNESS
# lens, plus skills/impl/references/accept-set-conformance-harness.md).
#
# WHY A HOOK (the only recognition-independent lever): the AASC sweep and its
# self-incrimination rule are ALREADY normative MUST in the ac-evaluator lens
# ("on a `triggered-on=` AC, an `## Accept-set sweep` line with `ran=n`, or with
# `ran=y astral=n`, is a NON-CONFORMANT shallow sweep"). Yet because that rule
# is honoured only by the model RECOGNISING it, live dogfoods leaked it
# run-to-run — a triggered boundary stood the sweep down on one re-run of a
# subject it had swept on a prior run. This hook reads the EMITTED line and
# applies the SAME rule deterministically, with zero model recall, closing the
# run-to-run variance that prose alone could not.
#
# WHAT IT CANNOT DO (the bound, R1): it verifies the STRUCTURE of the emitted
# line (a triggered boundary not run; a shallow run that skipped the astral
# complement; a sliced corpus; an authoritative divergence that did not drive
# the verdict to FAIL). It CANNOT verify that a `ran=y astral=y corpus-size=750`
# line is TRUTHFUL — a model could emit those fields without executing the
# sweep. Catching structural self-incrimination, not fabrication, is the ceiling.
#
# Predicates (per `boundary=` line in the section):
#   P1 stand-down  (all axes):  triggered=y ran=n                       -> BLOCK
#   P2 shallow     (A,U axes):  triggered=y ran=y astral=n              -> BLOCK
#   P4 gating      (all axes):  authoritative=y divergences>0 while Status not FAIL/FAIL-CRITICAL -> BLOCK
#   P3 thin-corpus (A,U axes):  triggered=y ran=y corpus-size < FLOOR   -> ADVISORY ONLY (never blocks)
# P3 is ADVISORY, not a gate (dogfood51): corpus-size is a weak proxy for sweep
# depth — a handful of astral probes can be deeper than hundreds of ASCII ones —
# so flooring it would false-trip a legitimately-thin-but-conformant sweep on a
# wide-spec subject (002-r1 A=5, 003-r2 A=105, both astral=y divergences=0, one a
# PASS report). astral (P2) is the real A/U depth gate; P3 only SURFACES the
# run-to-run depth variance as a note. SW_AASC_CORPUS_FLOOR tunes the threshold.
# The `caveat=no-runnable-artifact` escape (a compiled language / no exec
# harness: triggered but the sweep could not be executed) exempts P1/P2 (and the
# P3 advisory) for that line — a legit fail-OPEN degradation. P4 still applies.
# P2/P3 are scoped to the alphabet (A) and unicode-transform (U) axes; the keyed
# (K) and canonical-writer (W) axes legitimately enumerate a small reflection-
# derived corpus (reserved/accessor/private-slot names — a handful of ASCII
# identifiers, never astral), so the astral/corpus checks do not apply to them.
# P1 and P4 are axis-independent. The `## Accept-set sweep` header is matched
# case-insensitively AND at any hash depth (`#`..`######`), so neither a mis-cased
# nor a mis-leveled header can let a whole report silently skip the gate.
#
# Kill switch SW_ACCEPT_SET_CONFORMANCE_MODE:
#   metric-only (DEFAULT) -> observe: log `[ACCEPT-SET-VERIFY] metric-only: would block ...`, ALLOW.
#   on                    -> enforce: emit a PostToolUse `decision: block` with the reason.
#   off                   -> explicit opt-out: silent skip.
#   unknown               -> collapses to metric-only (a typo neither enforces nor silently disables).
#
# Corpus floor SW_AASC_CORPUS_FLOOR (default 256) — the P3 ADVISORY threshold for
# an A/U-axis triggered+run sweep; a thinner corpus is NOTED (never blocked), and
# the threshold is env-tunable per host/subject.
#
# Fail-OPEN iron rule: this hook MUST NEVER break the host Write/Edit. jq
# missing, an unreadable report, a non-eval path, a skeleton (IN_PROGRESS) write,
# the `n/a` fallback, or any internal error is a silent `exit 0`. The exit code
# is ALWAYS 0; the only non-allow influence is the `on`-mode `decision: block`
# JSON, which surfaces the reason to the model (the report write itself already
# completed).

set -euo pipefail

# jq is required to parse the PostToolUse payload. Silent skip if missing —
# Write/Edit must never be blocked by this hook (fail-OPEN).
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || echo '{}')

# Gate 1: path match — only AASC eval-round reports. The single glob
# `*eval-round-*.md` covers eval-round-{n}.md, the -part-{i} / -v{i} partition
# and multi-verifier variants, and the docs/eval-round/{topic}-eval-round-{n}.md
# fallback (case globs are not path-aware, so the leading `*` spans directories).
TOOL_FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
case "$TOOL_FILE_PATH" in
  *eval-round-*.md) ;;
  *) exit 0 ;;
esac

# Gate 2: read the just-written file from disk (NOT the tool payload — the
# terminal rewrite may arrive as a Write of the full body or as Edits, and the
# on-disk state after PostToolUse is the authoritative final content).
[ -f "$TOOL_FILE_PATH" ] || exit 0

# Gate 2a: skeleton false-trip guard. The ac-evaluator does TWO writes — a
# `## Status: IN_PROGRESS` skeleton (no sweep section) FIRST, then a terminal
# rewrite. The first `## Status:` line is authoritative (agents/ac-evaluator.md).
# An IN_PROGRESS file is work-in-flight: pass.
FIRST_STATUS=$(grep -m1 -E '^## Status:' "$TOOL_FILE_PATH" 2>/dev/null | sed -E 's/^## Status:[[:space:]]*//' || true)
case "$FIRST_STATUS" in
  IN_PROGRESS*) exit 0 ;;
esac

# Gate 2b: no `## Accept-set sweep` section -> nothing persisted to verify
# (sweep not in scope, or a pre-v8.5.0 / degraded report). Fail-OPEN. Matched
# case-insensitively so a mis-cased header (`## Accept-set Sweep`) cannot let a
# whole report skip the gate (dogfood51: 001-r2 used a capital-S header).
grep -qiE '^#{1,6}[[:space:]]+accept-set sweep[[:space:]]*$' "$TOOL_FILE_PATH" 2>/dev/null || exit 0

# Gate 3: kill switch. Unknown collapses to metric-only.
MODE_RAW="${SW_ACCEPT_SET_CONFORMANCE_MODE:-metric-only}"
case "$MODE_RAW" in
  on|metric-only|off) MODE="$MODE_RAW" ;;
  *)                  MODE="metric-only" ;;
esac
[ "$MODE" = "off" ] && exit 0

CORPUS_FLOOR="${SW_AASC_CORPUS_FLOOR:-256}"
case "$CORPUS_FLOOR" in
  ''|*[!0-9]*) CORPUS_FLOOR=256 ;;
esac

# Extract the `## Accept-set sweep` section body (heading exclusive, up to the
# next `## ` heading or EOF).
SECTION=$(awk '
  tolower($0) ~ /^#{1,6}[[:space:]]+accept-set sweep[[:space:]]*$/ { f=1; next }
  /^#{1,6}[[:space:]]/ { f=0 }
  f
' "$TOOL_FILE_PATH" 2>/dev/null || true)

# `n/a` fallback (no external-input boundary in scope) -> conformant by contract.
case "$SECTION" in
  *"n/a (no external-input boundary in scope)"*) exit 0 ;;
esac

# Is the terminal verdict a FAIL? FAIL and FAIL-CRITICAL both start FAIL; PASS
# and PASS-WITH-CAVEATS start PASS. Used by P4.
case "$FIRST_STATUS" in
  FAIL*) STATUS_IS_FAIL=1 ;;
  *)     STATUS_IS_FAIL=0 ;;
esac

# field_of <line> <key> -> the token value (empty if absent).
field_of() {
  local v
  v=$(printf '%s\n' "$1" | grep -oE "$2=[^[:space:]]+" | head -1) || true
  printf '%s' "${v#*=}"
}

BLOCKING=""
ADVISORY=""
while IFS= read -r LINE; do
  # Select any sweep line carrying a boundary= token (field_of is order-independent,
  # so a reordered-but-complete line is no longer skipped). The section is already
  # bounded to the `## Accept-set sweep` block by the awk extractor above.
  case "$LINE" in
    *boundary=*) ;;
    *) continue ;;
  esac
  B=$(field_of "$LINE" boundary)
  # Off-grammar boundary label (not A/U/W/K): the A/U astral-depth gate is keyed to
  # A|U, so a relabeled alphabet boundary would silently dodge it. Surface it on
  # stderr (fail-toward-observability; not a block, to avoid false-tripping a genuine
  # W/K-class sweep) so format drift in the only recognition-independent lever is seen.
  case "$B" in
    A|U|W|K) ;;
    "") ;;
    *) printf '[ACCEPT-SET-VERIFY] off-grammar boundary label=%s in %s\n' "$B" "$(basename "$TOOL_FILE_PATH")" >&2 ;;
  esac
  TRIG=$(field_of "$LINE" triggered)
  RAN=$(field_of "$LINE" ran)
  ASTRAL=$(field_of "$LINE" astral)
  CORPUS=$(field_of "$LINE" corpus-size)
  DIV=$(field_of "$LINE" divergences)
  AUTH=$(field_of "$LINE" authoritative)
  CAVEAT=$(field_of "$LINE" caveat)
  # corpus-size may carry a descriptive suffix (dogfood51: `10-non-ascii-decimal`);
  # take the leading integer so an annotation cannot dodge the P3 advisory.
  CORPUS_INT="${CORPUS%%-*}"

  REASON=""
  # The no-runnable-artifact caveat is the documented fail-OPEN escape (a
  # compiled language / no exec harness: the boundary was triggered but the
  # sweep could not be executed). It exempts the execution + depth predicates
  # P1/P2 (and the P3 advisory); the gating-consistency predicate P4 still applies.
  if [ "$CAVEAT" != "no-runnable-artifact" ]; then
    # P1 stand-down (all axes): a triggered boundary that was not run -> BLOCK.
    if [ "$TRIG" = "y" ] && [ "$RAN" = "n" ]; then
      REASON="P1-stand-down"
    elif [ "$TRIG" = "y" ] && [ "$RAN" = "y" ]; then
      # P2 shallow astral (A,U axes): astral complement skipped -> BLOCK (astral
      # is the real A/U depth gate; the planes are the mandated alphabet complement).
      if { [ "$B" = "A" ] || [ "$B" = "U" ]; } && [ "$ASTRAL" = "n" ]; then
        REASON="P2-shallow-astral"
      # P3 thin corpus (A,U axes): corpus below the floor -> ADVISORY ONLY, never
      # blocks (corpus-size is a weak depth proxy; flooring it false-trips a
      # legitimately-thin conformant sweep on a wide-spec subject — dogfood51).
      elif { [ "$B" = "A" ] || [ "$B" = "U" ]; } \
        && printf '%s' "$CORPUS_INT" | grep -qE '^[0-9]+$' \
        && [ "$CORPUS_INT" -lt "$CORPUS_FLOOR" ]; then
        ADVISORY="${ADVISORY}boundary=${B} triggered=${TRIG} ran=${RAN} astral=${ASTRAL} corpus-size=${CORPUS} note=P3-thin-corpus(<$CORPUS_FLOOR)"$'\n'
      fi
    fi
  fi
  # P4 gating-consistency (all axes): an authoritative boundary with divergences
  # must drive the verdict to FAIL -> BLOCK.
  if [ -z "$REASON" ] && [ "$AUTH" = "y" ] \
    && printf '%s' "$DIV" | grep -qE '^[0-9]+$' \
    && [ "$DIV" -gt 0 ] && [ "$STATUS_IS_FAIL" = "0" ]; then
    REASON="P4-gating-inconsistency"
  fi

  [ -n "$REASON" ] || continue
  BLOCKING="${BLOCKING}boundary=${B} triggered=${TRIG} ran=${RAN} astral=${ASTRAL} corpus-size=${CORPUS} reason=${REASON}"$'\n'
done <<EOF
$SECTION
EOF

# Nothing flagged at all -> silent pass.
[ -n "$BLOCKING$ADVISORY" ] || exit 0

BASENAME=$(basename "$TOOL_FILE_PATH")

# Advisory notes (P3 thin-corpus) are emitted in BOTH modes and NEVER block —
# corpus depth is subject-dependent, so this is observability, not a gate.
if [ -n "$ADVISORY" ]; then
  while IFS= read -r V; do
    [ -n "$V" ] || continue
    echo "[ACCEPT-SET-VERIFY] advisory: $BASENAME $V" >&2
  done <<EOF
$ADVISORY
EOF
fi

# No blocking violation -> exit 0 (an advisory-only report is not a block).
[ -n "$BLOCKING" ] || exit 0

if [ "$MODE" = "metric-only" ]; then
  while IFS= read -r V; do
    [ -n "$V" ] || continue
    echo "[ACCEPT-SET-VERIFY] metric-only: would block (file=$BASENAME $V)" >&2
  done <<EOF
$BLOCKING
EOF
  exit 0
fi

# MODE=on: enforce. Surface a consolidated reason to the model via a PostToolUse
# decision:block (the report write already completed; this prompts a re-run /
# re-write of the sweep). The exit code stays 0 — the block is the JSON decision
# field, never a non-zero exit (fail-OPEN invariant preserved).
while IFS= read -r V; do
  [ -n "$V" ] || continue
  echo "[ACCEPT-SET-VERIFY] block (file=$BASENAME $V)" >&2
done <<EOF
$BLOCKING
EOF
REASON_TEXT=$(printf '%s' "$BLOCKING" | tr '\n' ';' | sed 's/;$//')
jq -n --arg r "Accept-set conformance gate (AASC): the persisted '## Accept-set sweep' in $BASENAME records a NON-CONFORMANT sweep — $REASON_TEXT. A triggered boundary must be EXECUTED (ran=y); an alphabet/unicode sweep must include the astral complement (astral=y); an authoritative divergence must drive the verdict to FAIL. Re-run the EXECUTED accept-set sweep per agents/ac-evaluator.md and rewrite the report." \
  '{decision:"block", reason:$r}'
exit 0
