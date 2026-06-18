#!/usr/bin/env bash
# Behaviour tests for hooks/accept-set-verify.sh — the deterministic
# Advertised-Accept-Set Conformance (AASC) post-hoc gate over the persisted
# `## Accept-set sweep` section of an eval-round-{n}.md report.
#
# Mirrors the proof-by-construction matrix: every conformance predicate
# (P1 stand-down / P2 shallow-astral / P3 sliced-corpus / P4 gating-consistency)
# is exercised against fixture reports, with the no-runnable-artifact escape,
# the A/U-axis floor scoping (K/W small reflection corpora must NOT false-trip),
# the dogfood50 clean shape (NO false positive), the skeleton / n/a / non-eval
# fail-OPEN gates, the kill-switch tri-state, and the jq-absent fail-OPEN path.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

HOOK="$HOOK_DIR/accept-set-verify.sh"
FIXDIR=$(mktemp -d)

echo "=== accept-set-verify.sh Tests ==="
echo ""

mkfix() { printf '%s\n' "$2" > "$FIXDIR/$1"; }

run_fix() { # run_fix <fixture-name>
  local json
  json=$(jq -n --arg fp "$FIXDIR/$1" '{"tool_input":{"file_path":$fp}}')
  run_hook "$HOOK" "$json"
}

pass_local() { echo -e "  ${GREEN}PASS${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1)); }
fail_local() {
  echo -e "  ${RED}FAIL${NC} $1"
  echo -e "       RC=$LAST_EXIT_CODE OUT=[$LAST_STDOUT] ERR=[$LAST_STDERR]"
  TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

expect_block()   { if [ "$LAST_EXIT_CODE" -eq 0 ] && echo "$LAST_STDOUT" | grep -q '"decision": "block"'; then pass_local "$1"; else fail_local "$1"; fi; }
expect_noblock() { if [ "$LAST_EXIT_CODE" -eq 0 ] && ! echo "$LAST_STDOUT" | grep -q '"decision"'; then pass_local "$1"; else fail_local "$1"; fi; }
expect_metric()  { if [ "$LAST_EXIT_CODE" -eq 0 ] && echo "$LAST_STDERR" | grep -qF '[ACCEPT-SET-VERIFY] metric-only: would block'; then pass_local "$1"; else fail_local "$1"; fi; }
expect_silent()  { if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ] && [ -z "$LAST_STDERR" ]; then pass_local "$1"; else fail_local "$1"; fi; }
# P3 thin-corpus is ADVISORY (dogfood51): a stderr note, NEVER a block.
expect_advisory() { if [ "$LAST_EXIT_CODE" -eq 0 ] && echo "$LAST_STDERR" | grep -qF '[ACCEPT-SET-VERIFY] advisory:' && ! echo "$LAST_STDOUT" | grep -q '"decision"'; then pass_local "$1"; else fail_local "$1"; fi; }

# ---- Fixtures -------------------------------------------------------------
mkfix eval-round-F1.md "## Status: FAIL

## Accept-set sweep
boundary=K triggered=y ran=n astral=n corpus-size=0 divergences=0 authoritative=y caveat=none"

mkfix eval-round-F2.md "## Status: PASS

## Accept-set sweep
boundary=A triggered=y ran=y astral=n corpus-size=300 divergences=0 authoritative=n caveat=none"

mkfix eval-round-F3.md "## Status: PASS

## Accept-set sweep
boundary=A triggered=y ran=y astral=n corpus-size=0 divergences=0 authoritative=n caveat=no-runnable-artifact"

mkfix eval-round-F3b.md "## Status: PASS-WITH-CAVEATS

## Accept-set sweep
boundary=A triggered=y ran=n astral=n corpus-size=0 divergences=0 authoritative=n caveat=no-runnable-artifact"

mkfix eval-round-F4.md "## Status: PASS

## Accept-set sweep
boundary=U triggered=y ran=y astral=y corpus-size=12 divergences=0 authoritative=n caveat=none"

mkfix eval-round-F5.md "## Status: PASS

## Accept-set sweep
boundary=A triggered=y ran=y astral=y corpus-size=750 divergences=2 authoritative=y caveat=none"

mkfix eval-round-F6.md "## Status: PASS

## Accept-set sweep
boundary=A triggered=y ran=y astral=y corpus-size=750 divergences=0 authoritative=y caveat=none"

mkfix eval-round-F7.md "## Status: PASS-WITH-CAVEATS

## Accept-set sweep
boundary=W triggered=n ran=n astral=n corpus-size=0 divergences=0 authoritative=n caveat=none
boundary=K triggered=y ran=y astral=n corpus-size=37 divergences=0 authoritative=n caveat=none
boundary=A triggered=y ran=y astral=y corpus-size=512 divergences=3 authoritative=n caveat=none"

mkfix eval-round-F7b.md "## Status: PASS

## Accept-set sweep
n/a (no external-input boundary in scope)"

mkfix eval-round-F9.md "## Status: IN_PROGRESS

- [ ] AC-1: do the thing"

mkfix eval-round-F10.md "## Status: PASS

- [x] AC-1: done"

mkfix some-other-file.md "## Status: PASS

## Accept-set sweep
boundary=A triggered=y ran=n astral=n corpus-size=0 divergences=0 authoritative=y caveat=none"

# dogfood51-derived fixtures.
# Fcap: a mis-cased `## Accept-set Sweep` header (capital S) must still be READ
# (case-insensitive Gate 2b) so a P1 stand-down under it is caught, not skipped.
mkfix eval-round-Fcap.md "## Status: FAIL

## Accept-set Sweep
boundary=K triggered=y ran=n astral=n corpus-size=0 divergences=0 authoritative=y caveat=none"

# Fthin: the dogfood51 002-r1 shape — a thin-but-conformant A sweep on a PASS
# report (A=5, astral=y, divergences=0). P3 is ADVISORY now, so this must NOT
# block (the false-trip the confirmation dogfood surfaced).
mkfix eval-round-Fthin.md "## Status: PASS

## Accept-set sweep
boundary=A triggered=y ran=y astral=y corpus-size=5 divergences=0 authoritative=y caveat=none"

# Fsuffix: a descriptive corpus-size (dogfood51 001-r1: `5-canonical-forms`) — the
# leading integer is parsed so the annotation cannot dodge the P3 advisory.
mkfix eval-round-Fsuffix.md "## Status: PASS

## Accept-set sweep
boundary=A triggered=y ran=y astral=y corpus-size=5-canonical-forms divergences=0 authoritative=n caveat=none"

# ---- MODE=on (enforce) ----------------------------------------------------
echo "--- MODE=on (enforce: decision:block on violation) ---"
export SW_ACCEPT_SET_CONFORMANCE_MODE=on SW_AASC_CORPUS_FLOOR=256
run_fix eval-round-F1.md;  expect_block   "F1 P1 stand-down (triggered=y ran=n) -> block"
run_fix eval-round-F2.md;  expect_block   "F2 P2 shallow-astral (A axis) -> block"
run_fix eval-round-F3.md;  expect_noblock "F3 no-runnable-artifact escape (ran=y) -> no block"
run_fix eval-round-F3b.md; expect_noblock "F3b no-runnable-artifact (ran=n, legit degradation) -> no block"
run_fix eval-round-F4.md;  expect_advisory "F4 thin corpus (U axis, 12<256) -> ADVISORY only, NOT block (P3 demoted, dogfood51)"
export SW_AASC_CORPUS_FLOOR=8
run_fix eval-round-F4.md;  expect_noblock "F4 floor=8 -> no advisory, silent (12>=8, SW_AASC_CORPUS_FLOOR tunable)"
export SW_AASC_CORPUS_FLOOR=256
run_fix eval-round-F5.md;  expect_block   "F5 P4 gating-inconsistency (auth=y div=2 PASS) -> block"
run_fix eval-round-F6.md;  expect_noblock "F6 dogfood50 clean shape -> NO false trip"
run_fix eval-round-F7.md;  expect_noblock "F7 K small-corpus+astral=n & auth=n divergences -> no trip"
run_fix eval-round-F7b.md; expect_noblock "F7b n/a fallback -> no block"
run_fix eval-round-F9.md;  expect_noblock "F9 skeleton IN_PROGRESS (Gate 2a) -> no block"
run_fix eval-round-F10.md; expect_noblock "F10 terminal, no sweep section (Gate 2b) -> no block"
run_fix some-other-file.md; expect_noblock "F8 non-eval path (Gate 1) -> no block"
run_fix eval-round-Fcap.md;    expect_block    "Fcap capital-S header + P1 -> READ case-insensitively + block (dogfood51 fix #2)"
run_fix eval-round-Fthin.md;   expect_advisory "Fthin thin-but-conformant A=5 astral=y PASS report -> advisory, NO block (dogfood51 002-r1 false-trip fix)"
run_fix eval-round-Fsuffix.md; expect_advisory "Fsuffix descriptive corpus-size (5-canonical-forms) -> leading-int parsed -> advisory (dogfood51 fix #3)"

# ---- MODE=metric-only (default; observe only) -----------------------------
echo "--- MODE=metric-only (default: observe, never block) ---"
export SW_ACCEPT_SET_CONFORMANCE_MODE=metric-only SW_AASC_CORPUS_FLOOR=256
run_fix eval-round-F1.md; expect_metric "F1 -> metric-only would-block stderr"
run_fix eval-round-F2.md; expect_metric "F2 -> metric-only would-block stderr"
run_fix eval-round-F5.md; expect_metric "F5 -> metric-only would-block stderr"
run_fix eval-round-F6.md; expect_silent "F6 clean -> silent (no metric line)"
run_fix eval-round-F7.md; expect_silent "F7 -> silent (no false trip)"
run_fix eval-round-Fthin.md; expect_advisory "Fthin metric-only -> advisory note (P3 is advisory in BOTH modes, never would-block)"

# ---- MODE=off (explicit opt-out) ------------------------------------------
echo "--- MODE=off (explicit opt-out: silent) ---"
export SW_ACCEPT_SET_CONFORMANCE_MODE=off SW_AASC_CORPUS_FLOOR=256
run_fix eval-round-F1.md; expect_silent "F1 off -> silent exit 0"
run_fix eval-round-F5.md; expect_silent "F5 off -> silent exit 0"

# ---- MODE=unknown (collapses to metric-only) ------------------------------
echo "--- MODE=typo (unknown collapses to metric-only) ---"
export SW_ACCEPT_SET_CONFORMANCE_MODE=enforce SW_AASC_CORPUS_FLOOR=256
run_fix eval-round-F1.md; expect_metric "F1 unknown-mode -> metric-only (not enforce, not off)"
unset SW_ACCEPT_SET_CONFORMANCE_MODE SW_AASC_CORPUS_FLOOR

# ---- jq-absent (fail-OPEN) ------------------------------------------------
echo "--- jq-absent (fail-OPEN exit 0) ---"
RBIN=$(mktemp -d)
for c in bash cat grep sed awk head tr basename printf; do
  p=$(command -v "$c" 2>/dev/null) && ln -s "$p" "$RBIN/$c" 2>/dev/null
done
jq_json=$(printf '{"tool_input":{"file_path":"%s"}}' "$FIXDIR/eval-round-F1.md")
if printf '%s' "$jq_json" | PATH="$RBIN" SW_ACCEPT_SET_CONFORMANCE_MODE=on bash "$HOOK" >/dev/null 2>&1; then
  jqrc=0
else
  jqrc=$?
fi
LAST_EXIT_CODE="$jqrc"; LAST_STDOUT=""; LAST_STDERR=""
if [ "$jqrc" -eq 0 ]; then pass_local "jq-absent -> fail-OPEN exit 0"; else fail_local "jq-absent -> fail-OPEN exit 0"; fi
rm -rf "$RBIN"

# ---- cleanup + summary ----------------------------------------------------
rm -rf "$FIXDIR"
print_summary
