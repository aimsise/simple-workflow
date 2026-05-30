#!/usr/bin/env bash
# test-ask-guard.sh -- exercises hooks/pre-askuserquestion-guard.sh (P1-3B).
#
# Scenario matrix (AC-1..AC-3, AC-11..AC-13):
#   1. 21 cells = 3 tiers (aggressive / moderate / conservative)
#      x 7 headers (audit-fail / ac-eval / ship-review / ship-ci /
#      eval-dry / tkt-quality / other-unknown).
#      allow cells = 8 (moderate {audit-fail, ac-eval} + conservative
#      {audit-fail, ac-eval, ship-review, ship-ci, eval-dry, tkt-quality}).
#      deny  cells = 13.
#      Each deny cell additionally grep-asserts that the reason text
#      contains all four literals required by AC-11:
#        `risk_tolerance=<tier>`, `header='<header>'`,
#        `policy_gate_stop`, `autopilot-policy.yaml`.
#   2. metric-only mode (AC-2): 2 scenarios -- a deny cell must emit
#      `[ASK-GUARD] metric-only: would deny` on stderr while returning
#      allow on stdout; an allow cell must NOT emit that line.
#   3. unknown-header stderr (AC-3): 1 scenario -- header outside the
#      six known gate IDs emits `[ASK-GUARD] unknown-header=<value>`.
#   4. Kill-switch off (AC-12): all 21 matrix cells must flip to allow
#      when SW_AUTOPILOT_ASK_GUARD=off (verifies the off branch and
#      NAC-4 fail-open behaviour through the unknown_value sub-scenario
#      below).
#   5. Policy-absent fallback (AC-13): when autopilot-policy.yaml is
#      not placed in the state dir, get_risk_tolerance returns
#      "conservative" and the 6 known headers allow / the 1 unknown
#      header denies.
#
# Each scenario builds its own tempdir with the canonical
# .simple-workflow/backlog/briefs/active/<slug>/ skeleton so
# is_autopilot_context / find_any_autopilot_state_file / parse_ticket_statuses
# all fire, then pipes a synthesised harness payload through stdin.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_PATH="$REPO_DIR/hooks/pre-askuserquestion-guard.sh"
FIXTURE_DIR="$REPO_DIR/tests/fixtures/ask-guard"

echo "=== pre-askuserquestion-guard.sh Tests ==="
echo ""

# Each scenario gets its own tempdir for trap-safe cleanup.
declare -a CLEANUP_DIRS=()
register_cleanup() {
  CLEANUP_DIRS+=("$1")
}
cleanup_all() {
  for d in "${CLEANUP_DIRS[@]+"${CLEANUP_DIRS[@]}"}"; do
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done
}
trap cleanup_all EXIT

# write_state_skeleton <tempdir> <slug>
#   Materialises:
#     <tempdir>/.simple-workflow/backlog/briefs/active/<slug>/autopilot-state.yaml
#   with a single non-terminal ticket so the matrix gate fires.
write_state_skeleton() {
  local tmp="$1" slug="$2"
  local dir="$tmp/.simple-workflow/backlog/briefs/active/$slug"
  mkdir -p "$dir"
  cat >"$dir/autopilot-state.yaml" <<YAML
version: 1
parent_slug: ${slug}
execution_mode: split
total_tickets: 1
tickets:
  - logical_id: ${slug}-part-1
    status: pending
manual_bash_fallbacks: []
YAML
  printf '%s' "$dir"
}

# place_policy <state_dir> <tier>
#   Copies the fixture for <tier> alongside autopilot-state.yaml. Pass
#   the empty string for <tier> to skip placement (policy-absent
#   fallback scenarios).
place_policy() {
  local state_dir="$1" tier="$2"
  [ -z "$tier" ] && return 0
  cp "$FIXTURE_DIR/$tier/autopilot-policy.yaml" "$state_dir/autopilot-policy.yaml"
}

# run_ask_guard <cwd> <header>
#   Drives the hook with a synthetic AskUserQuestion harness payload.
#   Sets LAST_EXIT_CODE / LAST_STDOUT / LAST_STDERR via run_hook (which
#   chdir-s to cwd before launching the hook).
run_ask_guard() {
  local cwd="$1" header="$2"
  local payload
  payload=$(jq -n \
    --arg cwd "$cwd" \
    --arg header "$header" \
    '{tool_name:"AskUserQuestion",
      tool_input:{header:$header,questions:[{question:"Continue?",header:$header}]},
      cwd:$cwd,session_id:"test",transcript_path:""}')
  run_hook "$HOOK_PATH" "$payload" "$cwd"
}

# assert_decision_allow <description> <tier> <header>
#   Builds the canonical skeleton + policy fixture and asserts the hook
#   stdout contains `"permissionDecision":"allow"`.
assert_decision_allow() {
  local description="$1" tier="$2" header="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  local tmp
  tmp=$(mktemp -d)
  register_cleanup "$tmp"
  local state_dir
  state_dir=$(write_state_skeleton "$tmp" "example-slug")
  place_policy "$state_dir" "$tier"
  run_ask_guard "$tmp" "$header"
  if printf '%s' "$LAST_STDOUT" | grep -q '"permissionDecision":"allow"'; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       exit:   $LAST_EXIT_CODE"
    echo -e "       stdout: $LAST_STDOUT"
    echo -e "       stderr: $LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# assert_decision_deny <description> <tier> <header>
#   Same setup as assert_decision_allow but asserts deny + AC-11 literals.
assert_decision_deny() {
  local description="$1" tier="$2" header="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  local tmp
  tmp=$(mktemp -d)
  register_cleanup "$tmp"
  local state_dir
  state_dir=$(write_state_skeleton "$tmp" "example-slug")
  place_policy "$state_dir" "$tier"
  run_ask_guard "$tmp" "$header"
  local denied="false" all_literals_present="true"
  if printf '%s' "$LAST_STDOUT" | grep -q '"permissionDecision":"deny"'; then
    denied="true"
  fi
  # AC-11: all four reason literals must be present.
  for lit in \
    "risk_tolerance=${tier}" \
    "header='${header}'" \
    "policy_gate_stop" \
    "autopilot-policy.yaml"; do
    if ! printf '%s' "$LAST_STDOUT" | grep -qF "$lit"; then
      all_literals_present="false"
    fi
  done
  if [ "$denied" = "true" ] && [ "$all_literals_present" = "true" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       exit:   $LAST_EXIT_CODE"
    echo -e "       stdout: $LAST_STDOUT"
    echo -e "       stderr: $LAST_STDERR"
    echo -e "       denied: $denied, all_literals_present: $all_literals_present"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# Expected matrix (3 tiers x 7 headers = 21 cells).
declare -A EXPECTED=(
  [aggressive,audit-fail]=deny
  [aggressive,ac-eval]=deny
  [aggressive,ship-review]=deny
  [aggressive,ship-ci]=deny
  [aggressive,eval-dry]=deny
  [aggressive,tkt-quality]=deny
  [aggressive,other-unknown]=deny
  [moderate,audit-fail]=allow
  [moderate,ac-eval]=allow
  [moderate,ship-review]=deny
  [moderate,ship-ci]=deny
  [moderate,eval-dry]=deny
  [moderate,tkt-quality]=deny
  [moderate,other-unknown]=deny
  [conservative,audit-fail]=allow
  [conservative,ac-eval]=allow
  [conservative,ship-review]=allow
  [conservative,ship-ci]=allow
  [conservative,eval-dry]=allow
  [conservative,tkt-quality]=allow
  [conservative,other-unknown]=deny
)

# ---------------------------------------------------------------------------
# Section 1 (AC-1, AC-11): 21-cell matrix.
# ---------------------------------------------------------------------------
echo "--- Section 1: matrix (21 cells; 8 allow + 13 deny) ---"
for tier in aggressive moderate conservative; do
  for header in audit-fail ac-eval ship-review ship-ci eval-dry tkt-quality other-unknown; do
    expected=${EXPECTED[$tier,$header]}
    if [ "$expected" = "allow" ]; then
      assert_decision_allow \
        "tier=${tier} header=${header} -> allow" \
        "$tier" "$header"
    else
      assert_decision_deny \
        "tier=${tier} header=${header} -> deny (+ AC-11 reason literals)" \
        "$tier" "$header"
    fi
  done
done

# ---------------------------------------------------------------------------
# Section 2 (AC-2): metric-only mode.
# ---------------------------------------------------------------------------
echo ""
echo "--- Section 2: metric-only mode (2 scenarios) ---"

# (m-a) deny cell under metric-only -> stdout allow, stderr `would deny`.
{
  tmp=$(mktemp -d)
  register_cleanup "$tmp"
  state_dir=$(write_state_skeleton "$tmp" "example-slug")
  place_policy "$state_dir" "aggressive"
  payload=$(jq -n \
    --arg cwd "$tmp" --arg header "audit-fail" \
    '{tool_name:"AskUserQuestion",
      tool_input:{header:$header,questions:[{question:"Continue?",header:$header}]},
      cwd:$cwd,session_id:"test",transcript_path:""}')
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  stdout_file=$(mktemp); stderr_file=$(mktemp)
  set +e
  echo "$payload" | (cd "$tmp" && SW_AUTOPILOT_ASK_GUARD=metric-only bash "$HOOK_PATH") \
    >"$stdout_file" 2>"$stderr_file"
  set -e
  LAST_STDOUT=$(cat "$stdout_file"); LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
  if printf '%s' "$LAST_STDOUT" | grep -q '"permissionDecision":"allow"' \
     && printf '%s' "$LAST_STDERR" | grep -qF '[ASK-GUARD] metric-only: would deny tier=aggressive header=audit-fail'; then
    echo -e "  ${GREEN}PASS${NC} (m-a) metric-only deny-cell: stdout=allow + stderr 'would deny' present"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} (m-a) metric-only deny-cell"
    echo -e "       stdout: $LAST_STDOUT"
    echo -e "       stderr: $LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# (m-b) allow cell under metric-only -> stdout allow, stderr NO `would deny`.
{
  tmp=$(mktemp -d)
  register_cleanup "$tmp"
  state_dir=$(write_state_skeleton "$tmp" "example-slug")
  place_policy "$state_dir" "conservative"
  payload=$(jq -n \
    --arg cwd "$tmp" --arg header "audit-fail" \
    '{tool_name:"AskUserQuestion",
      tool_input:{header:$header,questions:[{question:"Continue?",header:$header}]},
      cwd:$cwd,session_id:"test",transcript_path:""}')
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  stdout_file=$(mktemp); stderr_file=$(mktemp)
  set +e
  echo "$payload" | (cd "$tmp" && SW_AUTOPILOT_ASK_GUARD=metric-only bash "$HOOK_PATH") \
    >"$stdout_file" 2>"$stderr_file"
  set -e
  LAST_STDOUT=$(cat "$stdout_file"); LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
  if printf '%s' "$LAST_STDOUT" | grep -q '"permissionDecision":"allow"' \
     && ! printf '%s' "$LAST_STDERR" | grep -qF 'metric-only: would deny'; then
    echo -e "  ${GREEN}PASS${NC} (m-b) metric-only allow-cell: stdout=allow + no 'would deny' log"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} (m-b) metric-only allow-cell"
    echo -e "       stdout: $LAST_STDOUT"
    echo -e "       stderr: $LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ---------------------------------------------------------------------------
# Section 3 (AC-3): unknown-header stderr log.
# ---------------------------------------------------------------------------
echo ""
echo "--- Section 3: unknown-header stderr log (1 scenario) ---"
{
  tmp=$(mktemp -d)
  register_cleanup "$tmp"
  state_dir=$(write_state_skeleton "$tmp" "example-slug")
  place_policy "$state_dir" "conservative"
  run_ask_guard "$tmp" "other-unknown"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if printf '%s' "$LAST_STDERR" | grep -qF '[ASK-GUARD] unknown-header=other-unknown'; then
    echo -e "  ${GREEN}PASS${NC} (u-a) unknown-header stderr contains '[ASK-GUARD] unknown-header=other-unknown'"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} (u-a) unknown-header stderr missing"
    echo -e "       stderr: $LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ---------------------------------------------------------------------------
# Section 4 (AC-12, NAC-4): kill-switch off flips all 21 cells to allow.
# Also covers NAC-4 by setting SW_AUTOPILOT_ASK_GUARD=unknown_value for one
# representative cell -- the case statement's `*)` arm must collapse to allow.
# ---------------------------------------------------------------------------
echo ""
echo "--- Section 4: kill-switch off (21 cells, all allow) ---"
for tier in aggressive moderate conservative; do
  for header in audit-fail ac-eval ship-review ship-ci eval-dry tkt-quality other-unknown; do
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    tmp=$(mktemp -d)
    register_cleanup "$tmp"
    state_dir=$(write_state_skeleton "$tmp" "example-slug")
    place_policy "$state_dir" "$tier"
    payload=$(jq -n \
      --arg cwd "$tmp" --arg header "$header" \
      '{tool_name:"AskUserQuestion",
        tool_input:{header:$header,questions:[{question:"Continue?",header:$header}]},
        cwd:$cwd,session_id:"test",transcript_path:""}')
    stdout_file=$(mktemp); stderr_file=$(mktemp)
    set +e
    echo "$payload" | (cd "$tmp" && SW_AUTOPILOT_ASK_GUARD=off bash "$HOOK_PATH") \
      >"$stdout_file" 2>"$stderr_file"
    set -e
    LAST_STDOUT=$(cat "$stdout_file"); LAST_STDERR=$(cat "$stderr_file")
    rm -f "$stdout_file" "$stderr_file"
    if printf '%s' "$LAST_STDOUT" | grep -q '"permissionDecision":"allow"'; then
      echo -e "  ${GREEN}PASS${NC} off tier=${tier} header=${header} -> allow"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      echo -e "  ${RED}FAIL${NC} off tier=${tier} header=${header} -> expected allow"
      echo -e "       stdout: $LAST_STDOUT"
      echo -e "       stderr: $LAST_STDERR"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  done
done

# NAC-4 fail-open: unknown env value falls into `*)` arm == off.
{
  tmp=$(mktemp -d)
  register_cleanup "$tmp"
  state_dir=$(write_state_skeleton "$tmp" "example-slug")
  place_policy "$state_dir" "aggressive"
  payload=$(jq -n \
    --arg cwd "$tmp" --arg header "audit-fail" \
    '{tool_name:"AskUserQuestion",
      tool_input:{header:$header,questions:[{question:"Continue?",header:$header}]},
      cwd:$cwd,session_id:"test",transcript_path:""}')
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  stdout_file=$(mktemp); stderr_file=$(mktemp)
  set +e
  echo "$payload" | (cd "$tmp" && SW_AUTOPILOT_ASK_GUARD=unknown_value bash "$HOOK_PATH") \
    >"$stdout_file" 2>"$stderr_file"
  set -e
  LAST_STDOUT=$(cat "$stdout_file"); LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
  if printf '%s' "$LAST_STDOUT" | grep -q '"permissionDecision":"allow"'; then
    echo -e "  ${GREEN}PASS${NC} NAC-4 unknown SW_AUTOPILOT_ASK_GUARD value collapses to allow"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} NAC-4 unknown env value did not collapse to allow"
    echo -e "       stdout: $LAST_STDOUT"
    echo -e "       stderr: $LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ---------------------------------------------------------------------------
# Section 5 (AC-13, NAC-5): policy-absent fallback -> conservative.
# When autopilot-policy.yaml is not present, get_risk_tolerance returns
# "conservative" so the 6 known headers allow / 1 unknown denies. Section
# also exercises NAC-5 (unknown risk_tolerance value -> conservative) via
# the inline policy file in the second sub-scenario.
# ---------------------------------------------------------------------------
echo ""
echo "--- Section 5: policy-absent fallback (7 scenarios) ---"
for header in audit-fail ac-eval ship-review ship-ci eval-dry tkt-quality other-unknown; do
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  tmp=$(mktemp -d)
  register_cleanup "$tmp"
  state_dir=$(write_state_skeleton "$tmp" "example-slug")
  # NOTE: deliberately NOT calling place_policy here -- autopilot-policy.yaml
  # must be absent so the get_risk_tolerance file-missing branch fires.
  run_ask_guard "$tmp" "$header"
  if [ "$header" = "other-unknown" ]; then
    expected_decision="deny"
  else
    expected_decision="allow"
  fi
  if printf '%s' "$LAST_STDOUT" | grep -q "\"permissionDecision\":\"$expected_decision\""; then
    echo -e "  ${GREEN}PASS${NC} policy-absent header=${header} -> ${expected_decision} (conservative fallback)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} policy-absent header=${header} expected=${expected_decision}"
    echo -e "       stdout: $LAST_STDOUT"
    echo -e "       stderr: $LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# NAC-5: explicit unknown risk_tolerance value normalises to conservative.
{
  tmp=$(mktemp -d)
  register_cleanup "$tmp"
  state_dir=$(write_state_skeleton "$tmp" "example-slug")
  cat >"$state_dir/autopilot-policy.yaml" <<YAML
version: 1
risk_tolerance: unknown_value
YAML
  # audit-fail should be allowed under conservative (the fallback).
  run_ask_guard "$tmp" "audit-fail"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if printf '%s' "$LAST_STDOUT" | grep -q '"permissionDecision":"allow"'; then
    echo -e "  ${GREEN}PASS${NC} NAC-5 unknown risk_tolerance value -> conservative (audit-fail allowed)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} NAC-5 unknown risk_tolerance value did not fall back to conservative"
    echo -e "       stdout: $LAST_STDOUT"
    echo -e "       stderr: $LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ---------------------------------------------------------------------------
# Section 6 (NAC-1, NAC-2): negative scenarios -- guard must NOT deny.
# ---------------------------------------------------------------------------
echo ""
echo "--- Section 6: NAC-1 / NAC-2 negative scenarios ---"

# NAC-1: outside autopilot context (no .simple-workflow ancestor) -> allow.
{
  tmp=$(mktemp -d)
  register_cleanup "$tmp"
  run_ask_guard "$tmp" "audit-fail"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if printf '%s' "$LAST_STDOUT" | grep -q '"permissionDecision":"allow"'; then
    echo -e "  ${GREEN}PASS${NC} NAC-1 outside autopilot context -> allow (is_autopilot_context=false)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} NAC-1 outside autopilot tree was denied"
    echo -e "       stdout: $LAST_STDOUT"
    echo -e "       stderr: $LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# NAC-2: all tickets terminal -> allow.
{
  tmp=$(mktemp -d)
  register_cleanup "$tmp"
  dir="$tmp/.simple-workflow/backlog/briefs/active/example-slug"
  mkdir -p "$dir"
  cat >"$dir/autopilot-state.yaml" <<YAML
version: 1
parent_slug: example-slug
execution_mode: split
total_tickets: 1
tickets:
  - logical_id: example-slug-part-1
    status: completed
manual_bash_fallbacks: []
YAML
  place_policy "$dir" "aggressive"
  run_ask_guard "$tmp" "ship-review"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if printf '%s' "$LAST_STDOUT" | grep -q '"permissionDecision":"allow"'; then
    echo -e "  ${GREEN}PASS${NC} NAC-2 all tickets terminal -> allow (non_terminal=0)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} NAC-2 all-terminal payload was denied"
    echo -e "       stdout: $LAST_STDOUT"
    echo -e "       stderr: $LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

echo ""
print_summary
