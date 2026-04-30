#!/usr/bin/env bash
# Tests for hooks/post-skill-cleanup.sh — PostToolUse hook that physically
# enforces the /autopilot Phase 1 step 0 "Auto-kick cleanup" MUST clause.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_DIR/hooks/post-skill-cleanup.sh"
FIXTURES="$REPO_DIR/tests/fixtures/briefs"

echo "=== post-skill-cleanup.sh Tests ==="
echo ""

# Per-case workspace under a temp dir; the hook expects to operate against
# .simple-workflow/backlog/briefs/active/ relative to the current directory.
setup_workspace() {
  local layout="$1" # "flat" | "nested" | "empty"
  WS=$(mktemp -d)
  mkdir -p "$WS/.simple-workflow/backlog/briefs/active"
  case "$layout" in
    flat)
      cp -R "$FIXTURES/flat-layout/test-slug" \
        "$WS/.simple-workflow/backlog/briefs/active/test-slug"
      ;;
    nested)
      mkdir -p "$WS/.simple-workflow/backlog/briefs/active/parent-slug"
      cp -R "$FIXTURES/nested-layout/parent-slug/child-slug" \
        "$WS/.simple-workflow/backlog/briefs/active/parent-slug/child-slug"
      ;;
    empty)
      : # no fixture content
      ;;
  esac
  echo "$WS"
}

teardown_workspace() {
  local ws="$1"
  if [ -n "$ws" ] && [ -d "$ws" ]; then
    rm -rf "$ws"
  fi
}

# Run the hook with a given JSON payload at a given working directory.
# Populates LAST_EXIT_CODE / LAST_STDOUT / LAST_STDERR via run_hook.
invoke_hook() {
  local input="$1"
  local cwd="$2"
  run_hook "$HOOK" "$input" "$cwd"
}

assert_eq_int() {
  local description="$1"
  local actual="$2"
  local expected="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ "$actual" = "$expected" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description (expected: $expected, got: $actual)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_path_absent() {
  local description="$1"
  local path="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ ! -e "$path" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description (still present: $path)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_path_present() {
  local description="$1"
  local path="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ -e "$path" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description (missing: $path)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_empty() {
  local description="$1"
  local actual="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ -z "$actual" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description (expected empty, got: $actual)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ---------------------------------------------------------------------------
echo "--- AC #1: hook is executable with the expected shebang ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -x "$HOOK" ]; then
  echo -e "  ${GREEN}PASS${NC} hook is executable"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} hook is not executable: $HOOK"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
SHEBANG=$(head -1 "$HOOK")
assert_eq_int "shebang is #!/usr/bin/env bash" "$SHEBANG" "#!/usr/bin/env bash"

# ---------------------------------------------------------------------------
echo ""
echo "--- AC #2: autopilot invocation removes auto-kick ---"
WS=$(setup_workspace flat)
assert_path_present "fixture pre-state: auto-kick.yaml exists" \
  "$WS/.simple-workflow/backlog/briefs/active/test-slug/auto-kick.yaml"
invoke_hook '{"tool_input": {"skill": "simple-workflow:autopilot"}}' "$WS"
assert_eq_int "hook exit 0" "$LAST_EXIT_CODE" "0"
assert_path_absent "auto-kick.yaml removed after autopilot invocation" \
  "$WS/.simple-workflow/backlog/briefs/active/test-slug/auto-kick.yaml"
teardown_workspace "$WS"

# ---------------------------------------------------------------------------
echo ""
echo "--- AC #3: no autokick file present (idempotent no-op) ---"
WS=$(setup_workspace empty)
invoke_hook '{"tool_input": {"skill": "simple-workflow:autopilot"}}' "$WS"
assert_eq_int "no autokick file present: hook exit 0" "$LAST_EXIT_CODE" "0"
assert_empty "no autokick file present: stdout empty" "$LAST_STDOUT"
teardown_workspace "$WS"

# ---------------------------------------------------------------------------
echo ""
echo "--- AC #4: non-autopilot skill keeps autokick ---"
WS=$(setup_workspace flat)
invoke_hook '{"tool_input": {"skill": "simple-workflow:scout"}}' "$WS"
assert_eq_int "non-autopilot skill: hook exit 0" "$LAST_EXIT_CODE" "0"
assert_path_present "non-autopilot skill keeps autokick" \
  "$WS/.simple-workflow/backlog/briefs/active/test-slug/auto-kick.yaml"
teardown_workspace "$WS"

# ---------------------------------------------------------------------------
echo ""
echo "--- AC #5: hooks.json wires the hook to PostToolUse Skill matcher ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if jq -r '.hooks.PostToolUse[].hooks[].command' "$REPO_DIR/hooks/hooks.json" \
  | grep -F 'post-skill-cleanup.sh' > /dev/null; then
  echo -e "  ${GREEN}PASS${NC} hooks.json references post-skill-cleanup.sh under PostToolUse"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} hooks.json missing PostToolUse → post-skill-cleanup.sh wiring"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- AC #6: nested layout autokick removal ---"
WS=$(setup_workspace nested)
NESTED="$WS/.simple-workflow/backlog/briefs/active/parent-slug/child-slug/auto-kick.yaml"
assert_path_present "fixture pre-state: nested auto-kick.yaml exists" "$NESTED"
invoke_hook '{"tool_input": {"skill": "simple-workflow:autopilot"}}' "$WS"
assert_eq_int "nested layout: hook exit 0" "$LAST_EXIT_CODE" "0"
assert_path_absent "nested layout autokick removal" "$NESTED"
teardown_workspace "$WS"

# ---------------------------------------------------------------------------
echo ""
echo "--- NAC #1: other files preserved ---"
WS=$(setup_workspace flat)
SLUG_DIR="$WS/.simple-workflow/backlog/briefs/active/test-slug"
invoke_hook '{"tool_input": {"skill": "simple-workflow:autopilot"}}' "$WS"
assert_path_absent "auto-kick.yaml removed" "$SLUG_DIR/auto-kick.yaml"
assert_path_present "brief.md preserved" "$SLUG_DIR/brief.md"
assert_path_present "autopilot-policy.yaml preserved" "$SLUG_DIR/autopilot-policy.yaml"
assert_path_present "autopilot-state.yaml preserved" "$SLUG_DIR/autopilot-state.yaml"
teardown_workspace "$WS"

# ---------------------------------------------------------------------------
echo ""
echo "--- NAC #2: stdout silence on success ---"
WS=$(setup_workspace flat)
invoke_hook '{"tool_input": {"skill": "simple-workflow:autopilot"}}' "$WS"
assert_eq_int "stdout silence: hook exit 0" "$LAST_EXIT_CODE" "0"
assert_empty "stdout silence on success: stdout empty after removal" "$LAST_STDOUT"
teardown_workspace "$WS"

# ---------------------------------------------------------------------------
echo ""
echo "--- Crash safety: malformed / empty payload ---"
WS=$(setup_workspace flat)
invoke_hook '' "$WS"
assert_eq_int "empty stdin: hook exit 0" "$LAST_EXIT_CODE" "0"
assert_path_present "empty stdin: autokick preserved (no skill match)" \
  "$WS/.simple-workflow/backlog/briefs/active/test-slug/auto-kick.yaml"
teardown_workspace "$WS"

WS=$(setup_workspace flat)
invoke_hook 'not-json' "$WS"
assert_eq_int "malformed stdin: hook exit 0" "$LAST_EXIT_CODE" "0"
assert_path_present "malformed stdin: autokick preserved (no skill match)" \
  "$WS/.simple-workflow/backlog/briefs/active/test-slug/auto-kick.yaml"
teardown_workspace "$WS"

print_summary
