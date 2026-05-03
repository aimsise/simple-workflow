#!/usr/bin/env bash
# test-hooks-lib.sh — Unit tests for the shared hook helpers under
# hooks/lib/ (PX-01).
#
# Covers:
#   - hooks/lib/forbidden-rationale-patterns.sh: array contents and that
#     each canonical pattern matches a representative offending phrase.
#   - hooks/lib/parse-state-file.sh: is_autopilot_context, parse_phase_status,
#     parse_ticket_statuses, find_state_file.
#
# The fixtures are produced inline under a tempdir so the tests are
# self-contained and do not depend on yq / PyYAML availability — the
# helpers fall through to an awk parser when neither is installed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$REPO_DIR/hooks/lib"

assert_eq() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       expected: $expected"
    echo -e "       actual:   $actual"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_exit_zero() {
  local description="$1"
  local actual_exit="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ "$actual_exit" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description (exit=$actual_exit)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_exit_nonzero() {
  local description="$1"
  local actual_exit="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ "$actual_exit" -ne 0 ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description (exit=0 but expected non-zero)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

echo "=== hooks/lib/ unit tests ==="
echo ""

# ---------------------------------------------------------------------------
# Section 1: forbidden-rationale-patterns.sh
# ---------------------------------------------------------------------------
echo "--- forbidden-rationale-patterns.sh ---"

FRP_PATH="$LIB_DIR/forbidden-rationale-patterns.sh"

# 1.1: file exists and is readable
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -r "$FRP_PATH" ]; then
  echo -e "  ${GREEN}PASS${NC} forbidden-rationale-patterns.sh exists and is readable"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} forbidden-rationale-patterns.sh missing at $FRP_PATH"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# 1.2: array has at least 10 elements
# shellcheck disable=SC1090
source "$FRP_PATH"
assert_eq "FORBIDDEN_RATIONALE_PATTERNS has >= 10 elements" "10" \
  "$([ "${#FORBIDDEN_RATIONALE_PATTERNS[@]}" -ge 10 ] && echo 10 || echo "${#FORBIDDEN_RATIONALE_PATTERNS[@]}")"

# 1.3: each canonical pattern matches a representative offending phrase
declare -A FRP_PROBES=(
  ['context.*budget']='context budget exhausted, falling back'
  ['context.*pressure']='under context pressure'
  ['context.*exhaust(ed|ion)?']='context exhaustion at 95%'
  ['context.*occupancy']='context occupancy at 90%'
  ['context.*window.*press']='context window pressing the cap'
  ['token.*budget']='token budget overflow'
  ['running out.*context']='running out of context, bypassing'
  ['release valve']='used the release valve to skip'
  ['pressure relief']='pressure relief shortcut'
  ['pragmatic shortcut']='took a pragmatic shortcut'
)
for canonical in "${!FRP_PROBES[@]}"; do
  probe="${FRP_PROBES[$canonical]}"
  found_in_array="false"
  for pat in "${FORBIDDEN_RATIONALE_PATTERNS[@]}"; do
    if [ "$pat" = "$canonical" ]; then
      found_in_array="true"
      break
    fi
  done
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ "$found_in_array" != "true" ]; then
    echo -e "  ${RED}FAIL${NC} canonical pattern '$canonical' not present in FORBIDDEN_RATIONALE_PATTERNS"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    continue
  fi
  if echo "$probe" | grep -iE -q "$canonical"; then
    echo -e "  ${GREEN}PASS${NC} pattern '$canonical' matches probe '$probe'"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} pattern '$canonical' did not match probe '$probe'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# 1.4: no escape-hatch env var names appear in the helper.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -iE 'SKIP_|BYPASS_|FORCE_DISABLE' "$FRP_PATH" >/dev/null 2>&1; then
  echo -e "  ${RED}FAIL${NC} forbidden-rationale-patterns.sh contains a banned escape-hatch token"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  echo -e "  ${GREEN}PASS${NC} forbidden-rationale-patterns.sh has no escape-hatch tokens"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

echo ""

# ---------------------------------------------------------------------------
# Section 2: parse-state-file.sh
# ---------------------------------------------------------------------------
echo "--- parse-state-file.sh ---"

PSF_PATH="$LIB_DIR/parse-state-file.sh"

# 2.0: file exists and the four contracted functions are declared
TESTS_TOTAL=$((TESTS_TOTAL + 1))
PSF_FUNCS="$(bash -c "source '$PSF_PATH' && declare -F is_autopilot_context parse_phase_status parse_ticket_statuses find_state_file" 2>/dev/null || true)"
PSF_FUNC_OK="true"
for fn in is_autopilot_context parse_phase_status parse_ticket_statuses find_state_file; do
  if ! echo "$PSF_FUNCS" | grep -qE "(^|[[:space:]])${fn}([[:space:]]|$)"; then
    PSF_FUNC_OK="false"
    break
  fi
done
if [ "$PSF_FUNC_OK" = "true" ]; then
  echo -e "  ${GREEN}PASS${NC} parse-state-file.sh declares all 4 contracted functions"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} parse-state-file.sh missing one of the 4 contracted functions"
  echo -e "       declare -F output: $PSF_FUNCS"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Source the helper for the function-level tests below.
# shellcheck disable=SC1090
source "$PSF_PATH"

# Build a self-contained fixture tree under a tempdir.
PSF_TMP="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$PSF_TMP'" EXIT

mkdir -p \
  "$PSF_TMP/.simple-workflow/backlog/briefs/active/example-slug" \
  "$PSF_TMP/.simple-workflow/backlog/product_backlog/legacy-slug" \
  "$PSF_TMP/.simple-workflow/backlog/briefs/done/done-slug"

# autopilot-state.yaml in briefs/active/<slug>/ — normal autopilot run.
cat >"$PSF_TMP/.simple-workflow/backlog/briefs/active/example-slug/autopilot-state.yaml" <<'YAML'
version: 1
parent_slug: example-slug
execution_mode: split
total_tickets: 3
tickets:
  - logical_id: example-slug-part-1
    status: completed
  - logical_id: example-slug-part-2
    status: in_progress
  - logical_id: example-slug-part-3
    status: pending
YAML

# autopilot-state.yaml in product_backlog/<slug>/ — split-plan-only run.
cat >"$PSF_TMP/.simple-workflow/backlog/product_backlog/legacy-slug/autopilot-state.yaml" <<'YAML'
version: 1
parent_slug: legacy-slug
execution_mode: split
total_tickets: 1
tickets:
  - logical_id: legacy-slug-part-1
    status: failed
YAML

# autopilot-state.yaml in briefs/done/<slug>/ — completed run.
cat >"$PSF_TMP/.simple-workflow/backlog/briefs/done/done-slug/autopilot-state.yaml" <<'YAML'
version: 1
parent_slug: done-slug
execution_mode: split
total_tickets: 1
tickets:
  - logical_id: done-slug-part-1
    status: completed
YAML

# A phase-state.yaml fixture for parse_phase_status.
cat >"$PSF_TMP/phase-state.yaml" <<'YAML'
version: 1
phases:
  scout:
    status: completed
  impl:
    status: in_progress
  ship:
    status: pending
YAML

# A non-autopilot tree (no .simple-workflow/) for the negative case.
NEG_TMP="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$PSF_TMP' '$NEG_TMP'" EXIT

# 2.1: is_autopilot_context — positive (briefs/active branch).
set +e
( cd "$PSF_TMP" && is_autopilot_context )
exit_code=$?
set -e
assert_exit_zero "is_autopilot_context returns 0 inside autopilot tree" "$exit_code"

# 2.2: is_autopilot_context — negative (no .simple-workflow/).
set +e
( cd "$NEG_TMP" && is_autopilot_context )
exit_code=$?
set -e
assert_exit_nonzero "is_autopilot_context returns non-zero outside autopilot tree" "$exit_code"

# 2.3: parse_phase_status — completed.
out="$(parse_phase_status "$PSF_TMP/phase-state.yaml" scout)"
assert_eq "parse_phase_status scout -> completed" "completed" "$out"

# 2.4: parse_phase_status — in_progress.
out="$(parse_phase_status "$PSF_TMP/phase-state.yaml" impl)"
assert_eq "parse_phase_status impl -> in_progress" "in_progress" "$out"

# 2.5: parse_phase_status — pending.
out="$(parse_phase_status "$PSF_TMP/phase-state.yaml" ship)"
assert_eq "parse_phase_status ship -> pending" "pending" "$out"

# 2.6: parse_phase_status — missing phase prints empty.
out="$(parse_phase_status "$PSF_TMP/phase-state.yaml" nonexistent)"
assert_eq "parse_phase_status nonexistent -> empty" "" "$out"

# 2.7: parse_phase_status — missing file exits non-zero.
set +e
parse_phase_status "$PSF_TMP/does-not-exist.yaml" scout >/dev/null 2>&1
exit_code=$?
set -e
assert_exit_nonzero "parse_phase_status returns non-zero on missing file" "$exit_code"

# 2.8: parse_ticket_statuses — three statuses in order.
expected="completed
in_progress
pending"
actual="$(parse_ticket_statuses \
  "$PSF_TMP/.simple-workflow/backlog/briefs/active/example-slug/autopilot-state.yaml")"
assert_eq "parse_ticket_statuses lists 3 statuses in order" "$expected" "$actual"

# 2.9: parse_ticket_statuses — single failed ticket.
actual="$(parse_ticket_statuses \
  "$PSF_TMP/.simple-workflow/backlog/product_backlog/legacy-slug/autopilot-state.yaml")"
assert_eq "parse_ticket_statuses single ticket -> failed" "failed" "$actual"

# 2.10: find_state_file — briefs/active hit.
expected_path="$(cd "$PSF_TMP/.simple-workflow/backlog/briefs/active/example-slug" && pwd -P)/autopilot-state.yaml"
actual_path="$( cd "$PSF_TMP" && find_state_file example-slug )"
assert_eq "find_state_file resolves briefs/active path" "$expected_path" "$actual_path"

# 2.11: find_state_file — product_backlog fallback.
expected_path="$(cd "$PSF_TMP/.simple-workflow/backlog/product_backlog/legacy-slug" && pwd -P)/autopilot-state.yaml"
actual_path="$( cd "$PSF_TMP" && find_state_file legacy-slug )"
assert_eq "find_state_file resolves product_backlog path" "$expected_path" "$actual_path"

# 2.12: find_state_file — briefs/done fallback.
expected_path="$(cd "$PSF_TMP/.simple-workflow/backlog/briefs/done/done-slug" && pwd -P)/autopilot-state.yaml"
actual_path="$( cd "$PSF_TMP" && find_state_file done-slug )"
assert_eq "find_state_file resolves briefs/done path" "$expected_path" "$actual_path"

# 2.13: find_state_file — unknown slug -> non-zero.
set +e
( cd "$PSF_TMP" && find_state_file unknown-slug >/dev/null 2>&1 )
exit_code=$?
set -e
assert_exit_nonzero "find_state_file returns non-zero on unknown slug" "$exit_code"

# 2.14: no escape-hatch tokens in the helper.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -iE 'SKIP_|BYPASS_|FORCE_DISABLE' "$PSF_PATH" >/dev/null 2>&1; then
  echo -e "  ${RED}FAIL${NC} parse-state-file.sh contains a banned escape-hatch token"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  echo -e "  ${GREEN}PASS${NC} parse-state-file.sh has no escape-hatch tokens"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

echo ""
print_summary
