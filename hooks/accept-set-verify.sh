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
#   P1 stand-down  (all axes):  triggered=y ran=n                       -> NON-CONFORMANT
#   P2 shallow     (A,U axes):  triggered=y ran=y astral=n              -> NON-CONFORMANT
#   P3 sliced      (A,U axes):  triggered=y ran=y corpus-size < FLOOR   -> NON-CONFORMANT
#   P4 gating      (all axes):  authoritative=y divergences>0 while Status not FAIL/FAIL-CRITICAL -> NON-CONFORMANT
# The `caveat=no-runnable-artifact` escape (a compiled language / no exec
# harness: triggered but the sweep could not be executed) exempts P1/P2/P3 for
# that line — a legit fail-OPEN degradation, NOT a violation. P4 still applies.
# P2/P3 are scoped to the alphabet (A) and unicode-transform (U) axes, where a
# large astral-inclusive complement corpus is the mandated breadth. The keyed (K)
# and canonical-writer (W) axes legitimately enumerate a small reflection-derived
# corpus (a structure's reserved/accessor/private-slot names are a handful of
# ASCII identifiers, never hundreds, never astral), so flooring them would
# false-trip. P1 and P4 are axis-independent.
#
# Kill switch SW_ACCEPT_SET_CONFORMANCE_MODE:
#   metric-only (DEFAULT) -> observe: log `[ACCEPT-SET-VERIFY] metric-only: would block ...`, ALLOW.
#   on                    -> enforce: emit a PostToolUse `decision: block` with the reason.
#   off                   -> explicit opt-out: silent skip.
#   unknown               -> collapses to metric-only (a typo neither enforces nor silently disables).
#
# Corpus floor SW_AASC_CORPUS_FLOOR (default 256) — the P3 minimum corpus size
# for an A/U-axis triggered+run sweep; env-tunable per host/subject.
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
# (sweep not in scope, or a pre-v8.5.0 / degraded report). Fail-OPEN.
grep -qE '^## Accept-set sweep[[:space:]]*$' "$TOOL_FILE_PATH" 2>/dev/null || exit 0

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
  /^## Accept-set sweep[[:space:]]*$/ { f=1; next }
  /^## / { f=0 }
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
  v=$(printf '%s\n' "$1" | grep -oE "$2=[^ ]+" | head -1) || true
  printf '%s' "${v#*=}"
}

VIOLATIONS=""
while IFS= read -r LINE; do
  case "$LINE" in
    boundary=*) ;;
    *) continue ;;
  esac
  B=$(field_of "$LINE" boundary)
  TRIG=$(field_of "$LINE" triggered)
  RAN=$(field_of "$LINE" ran)
  ASTRAL=$(field_of "$LINE" astral)
  CORPUS=$(field_of "$LINE" corpus-size)
  DIV=$(field_of "$LINE" divergences)
  AUTH=$(field_of "$LINE" authoritative)
  CAVEAT=$(field_of "$LINE" caveat)

  REASON=""
  # The no-runnable-artifact caveat is the documented fail-OPEN escape (a
  # compiled language / no exec harness: the boundary was triggered but the
  # sweep could not be executed). It exempts the execution + depth predicates
  # P1/P2/P3 (ran=n / astral=n / corpus=0 are then justified, not violations);
  # the gating-consistency predicate P4 still applies.
  if [ "$CAVEAT" != "no-runnable-artifact" ]; then
    # P1 stand-down (all axes): a triggered boundary that was not run.
    if [ "$TRIG" = "y" ] && [ "$RAN" = "n" ]; then
      REASON="P1-stand-down"
    elif [ "$TRIG" = "y" ] && [ "$RAN" = "y" ]; then
      # P2 shallow astral (A,U axes): astral complement skipped.
      if { [ "$B" = "A" ] || [ "$B" = "U" ]; } && [ "$ASTRAL" = "n" ]; then
        REASON="P2-shallow-astral"
      # P3 sliced corpus (A,U axes): corpus below the floor.
      elif { [ "$B" = "A" ] || [ "$B" = "U" ]; } \
        && printf '%s' "$CORPUS" | grep -qE '^[0-9]+$' \
        && [ "$CORPUS" -lt "$CORPUS_FLOOR" ]; then
        REASON="P3-sliced-corpus(<$CORPUS_FLOOR)"
      fi
    fi
  fi
  # P4 gating-consistency (all axes): an authoritative boundary with divergences
  # must drive the verdict to FAIL.
  if [ -z "$REASON" ] && [ "$AUTH" = "y" ] \
    && printf '%s' "$DIV" | grep -qE '^[0-9]+$' \
    && [ "$DIV" -gt 0 ] && [ "$STATUS_IS_FAIL" = "0" ]; then
    REASON="P4-gating-inconsistency"
  fi

  [ -n "$REASON" ] || continue
  VIOLATIONS="${VIOLATIONS}boundary=${B} triggered=${TRIG} ran=${RAN} astral=${ASTRAL} corpus-size=${CORPUS} reason=${REASON}"$'\n'
done <<EOF
$SECTION
EOF

[ -n "$VIOLATIONS" ] || exit 0

BASENAME=$(basename "$TOOL_FILE_PATH")

if [ "$MODE" = "metric-only" ]; then
  while IFS= read -r V; do
    [ -n "$V" ] || continue
    echo "[ACCEPT-SET-VERIFY] metric-only: would block (file=$BASENAME $V)" >&2
  done <<EOF
$VIOLATIONS
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
$VIOLATIONS
EOF
REASON_TEXT=$(printf '%s' "$VIOLATIONS" | tr '\n' ';' | sed 's/;$//')
jq -n --arg r "Accept-set conformance gate (AASC): the persisted '## Accept-set sweep' in $BASENAME records a NON-CONFORMANT sweep — $REASON_TEXT. A triggered boundary must be EXECUTED (ran=y); an alphabet/unicode sweep must include the astral complement (astral=y) over a corpus >= the floor; an authoritative divergence must drive the verdict to FAIL. Re-run the EXECUTED accept-set sweep per agents/ac-evaluator.md and rewrite the report." \
  '{decision:"block", reason:$r}'
exit 0
