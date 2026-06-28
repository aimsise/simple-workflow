#!/usr/bin/env bash
# test-pre-skill-contract-guard.sh -- exercises hooks/pre-skill-contract-guard.sh
# (FIX-2, v9.0.1). The hook denies a review/evaluator subagent invoking a
# pipeline orchestrator Skill (/impl, /audit, /ship, /autopilot, /refactor),
# keyed on the PreToolUse payload's native `.agent_type`. It activates only
# inside an autopilot tree.
#
# Scenarios:
#   CT-FIX2-SKILL-NAMESPACED  review agent + simple-workflow:impl     -> block (on)
#                             review agent + bare `impl`              -> allow
#                             review agent + utility `simple-workflow:brief` -> allow
#   review agent + pipeline skill, metric-only                        -> allow + stderr
#   review agent + pipeline skill, off                                -> allow (silent)
#   empty agent_type (orchestrator) + pipeline skill, on              -> allow
#   non-review agent (implementer) + pipeline skill, on               -> allow

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_PATH="$REPO_DIR/hooks/pre-skill-contract-guard.sh"

echo "=== pre-skill-contract-guard.sh Tests ==="
echo ""

declare -a CLEANUP_DIRS=()
register_cleanup() { CLEANUP_DIRS+=("$1"); }
cleanup_all() {
  for d in "${CLEANUP_DIRS[@]+"${CLEANUP_DIRS[@]}"}"; do
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done
}
trap cleanup_all EXIT

# Build a minimal autopilot tree so is_autopilot_context() returns true.
prepare_autopilot_tree() {
  local tmp="$1" slug="$2"
  mkdir -p "$tmp/.simple-workflow/backlog/briefs/active/$slug"
  cat >"$tmp/.simple-workflow/backlog/briefs/active/$slug/autopilot-state.yaml" <<YAML
version: 1
parent_slug: ${slug}
tickets:
  - logical_id: ${slug}-part-1
    status: in-progress
YAML
}

# Drive the hook. agent_type is merged into the payload ONLY when non-empty
# (an empty string is NOT key-absent; orchestrator-allow depends on ABSENCE).
run_skill_guard() {
  local mode="$1" skill="$2" cwd="$3" at="$4" payload so se
  payload=$(jq -n --arg sk "$skill" --arg cwd "$cwd" --arg at "$at" \
    '{tool_name:"Skill", tool_input:{skill:$sk}, cwd:$cwd, session_id:"test", transcript_path:""}
       + (if $at=="" then {} else {agent_type:$at} end)')
  so=$(mktemp); se=$(mktemp)
  set +e
  printf '%s' "$payload" | env SW_REVIEW_FIREWALL_MODE="$mode" bash "$HOOK_PATH" >"$so" 2>"$se"
  LAST_EXIT_CODE=$?
  set -e
  LAST_STDOUT=$(cat "$so"); LAST_STDERR=$(cat "$se"); rm -f "$so" "$se"
}

assert_block() {
  local desc="$1" tag="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -q -- '"decision":"block"' <<<"$LAST_STDOUT" \
     && grep -q -- "$tag" <<<"$LAST_STDOUT" \
     && [ "$LAST_EXIT_CODE" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} $desc"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $desc"
    echo -e "       exit: $LAST_EXIT_CODE stdout: $LAST_STDOUT stderr: $LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_allow() {
  local desc="$1"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ "$LAST_EXIT_CODE" -eq 0 ] && ! grep -q -- '"decision":"block"' <<<"$LAST_STDOUT"; then
    echo -e "  ${GREEN}PASS${NC} $desc"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $desc"
    echo -e "       exit: $LAST_EXIT_CODE stdout: $LAST_STDOUT stderr: $LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

TMP="$(mktemp -d)"; register_cleanup "$TMP"
SLUG="skillguard-slug"
prepare_autopilot_tree "$TMP" "$SLUG"

echo "--- CT-FIX2-SKILL-NAMESPACED: namespaced pipeline skill blocked, bare/utility allowed ---"
# review agent + namespaced pipeline skill -> block (on).
run_skill_guard on "simple-workflow:impl" "$TMP" "doc-verifier"
assert_block "CT-FIX2-SKILL-NAMESPACED (doc-verifier + simple-workflow:impl, on): blocked" \
  "unauthorized_pipeline_skill_by_review_agent"

# review agent + bare `impl` -> allow (bare never matches the namespaced denylist).
run_skill_guard on "impl" "$TMP" "doc-verifier"
assert_allow "CT-FIX2-SKILL-NAMESPACED (doc-verifier + bare 'impl', on): allowed (bare does not match)"

# review agent + utility skill (not a pipeline orchestrator) -> allow.
run_skill_guard on "simple-workflow:brief" "$TMP" "doc-verifier"
assert_allow "CT-FIX2-SKILL-NAMESPACED (doc-verifier + simple-workflow:brief, on): allowed (utility skill)"

echo ""
echo "--- mode matrix + identity ---"
# namespaced review agent -> still block.
run_skill_guard on "simple-workflow:audit" "$TMP" "simple-workflow:ac-evaluator"
assert_block "(namespaced ac-evaluator + simple-workflow:audit, on): blocked" \
  "unauthorized_pipeline_skill_by_review_agent"

# metric-only -> fail-open + stderr would-deny.
run_skill_guard metric-only "simple-workflow:impl" "$TMP" "code-reviewer"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! grep -q -- '"decision":"block"' <<<"$LAST_STDOUT" \
   && grep -q -- 'metric-only: would deny unauthorized_pipeline_skill_by_review_agent' <<<"$LAST_STDERR"; then
  echo -e "  ${GREEN}PASS${NC} (code-reviewer + simple-workflow:impl, metric-only): fail-open + stderr"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (metric-only): expected allow+stderr. stdout: $LAST_STDOUT stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# off -> disabled, silent allow.
run_skill_guard off "simple-workflow:ship" "$TMP" "ac-evaluator-hi"
assert_allow "(ac-evaluator-hi + simple-workflow:ship, off): disabled, allowed"

# empty agent_type (orchestrator) + pipeline skill, on -> allow (fail-open-on-empty).
run_skill_guard on "simple-workflow:impl" "$TMP" ""
assert_allow "(empty agent_type orchestrator + simple-workflow:impl, on): allowed (fail-open-on-empty)"

# non-review generator (implementer) + pipeline skill, on -> allow.
run_skill_guard on "simple-workflow:impl" "$TMP" "implementer"
assert_allow "(implementer + simple-workflow:impl, on): allowed (role not denylisted)"

# Outside an autopilot tree -> always allow even for a review agent + pipeline skill.
TMP_O="$(mktemp -d)"; register_cleanup "$TMP_O"
run_skill_guard on "simple-workflow:impl" "$TMP_O" "doc-verifier"
assert_allow "(outside autopilot tree, doc-verifier + simple-workflow:impl, on): allowed (no-op)"

echo ""
print_summary
