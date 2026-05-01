#!/usr/bin/env bash
# test-precompact-end-to-end.sh — PX-06: end-to-end fixture that forces the
# PreCompact hook (`hooks/pre-compact-save.sh`) to fire and verifies it
# appends a `boundary: session_compaction` entry to a dummy
# `autopilot-state.yaml`.
#
# Why this fixture exists: report-b D-9 from test_simple_workflow14 observed
# zero `pre_compact_summary` events in the JSONL. The most plausible reading
# is that the 1M context window never crossed the auto-compaction threshold,
# but that explanation is observational only — it does not prove the hook
# would have written `runtime_metrics:` if it had fired. discussion treats
# auto-compaction as normal operation, so the PreCompact wiring needs an
# explicit end-to-end check.
#
# Approach: launching real Claude Code is not viable in CI, so this fixture
# invokes `hooks/pre-compact-save.sh` directly, piping a PreCompact-shaped
# JSON payload on stdin and asserting on the resulting state file. The JSON
# keys (`session_id`, `cache_creation_input_tokens`, `cache_read_input_tokens`,
# `input_tokens`) match `_pc_runtime_metrics_payload_field` in the hook
# (NAC #6 — no synthetic shortcut shape).
#
# Scenarios exercised (matching PX-06 AC #3 and AC #4 (c)/(d)):
#   (a) state file in briefs/active/ only → boundary: session_compaction added
#   (b) state file in briefs/done/, all steps completed → boundary added
#       (PX-03 hook discovery extension)
#   (c) state file in briefs/done/ with a pending step → no append
#       (NAC #7 protection against premature partial_completion)
#   (d) no state file in any of the three lookup roots → exit 0 graceful, no
#       runtime_metrics: write
#
# Isolation contract: every scenario builds its repo skeleton inside
# `mktemp -d`. The fixture never reads or writes the host project's
# `.simple-workflow/` (NAC #1). Cleanup is wired through `trap … EXIT` so
# the tmp dirs disappear even on failure (NAC #4).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_PRECOMPACT="$REPO_DIR/hooks/pre-compact-save.sh"

# Color output (mirrors tests/test-helper.sh palette without sourcing it —
# the helper repurposes globals like TEST_REPO that we intentionally avoid
# colliding with so each scenario gets its own mktemp -d).
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Track every tmp dir we create so the EXIT trap can remove them all.
TMP_DIRS=()

cleanup() {
  local d
  # The `+x` expansion preserves the unset/empty distinction so we never
  # iterate over a synthetic empty element; `|| true` keeps a false test
  # condition from short-circuiting the trap and leaking a non-zero exit.
  for d in "${TMP_DIRS[@]+"${TMP_DIRS[@]}"}"; do
    if [ -n "$d" ] && [ -d "$d" ]; then
      rm -rf "$d" || true
    fi
  done
  return 0
}
trap cleanup EXIT

# --- helpers ----------------------------------------------------------------

# Create an isolated repo skeleton under mktemp -d. The three lookup roots
# the PreCompact hook scans (briefs/active/, product_backlog/, briefs/done/)
# are pre-created so a scenario can drop a state file into any of them.
new_repo() {
  local d
  d=$(mktemp -d "/tmp/sw-precompact-fixture.XXXXXX")
  TMP_DIRS+=("$d")
  mkdir -p "$d/.simple-workflow/backlog/briefs/active"
  mkdir -p "$d/.simple-workflow/backlog/briefs/done"
  mkdir -p "$d/.simple-workflow/backlog/product_backlog"
  mkdir -p "$d/.simple-workflow/docs/compact-state"
  printf '%s' "$d"
}

write_completed_state() {
  # $1 = path. Writes a state file whose every step is `completed`.
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'YAML'
version: 1
parent_slug: precompact-fixture-completed
started: 2026-04-29T00:00:00Z
execution_mode: split
total_tickets: 1
ticket_mapping:
  precompact-fixture-completed-part-1: 001-done
tickets:
  - logical_id: precompact-fixture-completed-part-1
    ticket_dir: .simple-workflow/backlog/active/precompact-fixture-completed/001-done
    status: completed
    steps: {scout: completed, impl: completed, ship: completed}
    invocation_method: {scout: skill, impl: skill, ship: skill}
manual_bash_fallbacks: []
runtime_metrics: []
YAML
}

write_pending_state() {
  # $1 = path. Writes a state file with at least one pending step. The hook's
  # `briefs/done/` filter rejects this because it greps for
  # (create-ticket|scout|impl|ship): (in_progress|pending).
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'YAML'
version: 1
parent_slug: precompact-fixture-pending
started: 2026-04-29T00:00:00Z
execution_mode: split
total_tickets: 1
ticket_mapping:
  precompact-fixture-pending-part-1: 001-pending
tickets:
  - logical_id: precompact-fixture-pending-part-1
    ticket_dir: .simple-workflow/backlog/active/precompact-fixture-pending/001-pending
    status: in_progress
    steps: {scout: completed, impl: pending, ship: pending}
    invocation_method: {scout: skill, impl: unknown, ship: unknown}
manual_bash_fallbacks: []
runtime_metrics: []
YAML
}

# Invoke the PreCompact hook with a Claude Code-shaped JSON payload (NAC #6).
# `cd` into the tmp repo because the hook runs `find` against the relative
# paths `.simple-workflow/backlog/{briefs/active,product_backlog,briefs/done}`.
run_precompact_hook() {
  local repo="$1"
  local payload="${2:-{\"session_id\":\"precompact-fixture\",\"cache_creation_input_tokens\":111,\"cache_read_input_tokens\":222,\"input_tokens\":333}}"
  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  set +e
  ( cd "$repo" && bash "$HOOK_PRECOMPACT" <<<"$payload" ) >"$stdout_file" 2>"$stderr_file"
  LAST_EXIT_CODE=$?
  set -e
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

# Assert the state file contains at least one entry with
# `boundary: session_compaction`. Prefers `yq` per AC #2; falls back to a
# grep-based check when yq is missing (CLAUDE.md treats yq as optional —
# the hook degrades to python3 / pure-shell, and so does the verifier).
assert_session_compaction_present() {
  local description="$1"
  local path="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ ! -f "$path" ]; then
    echo -e "  ${RED}FAIL${NC} $description (state file missing: $path)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return
  fi
  local hit=0
  if command -v yq >/dev/null 2>&1; then
    local out
    out=$(yq '.runtime_metrics[] | select(.boundary == "session_compaction")' "$path" 2>/dev/null || true)
    [ -n "$out" ] && hit=1
  else
    if grep -qE '^[[:space:]]*-?[[:space:]]*boundary:[[:space:]]*session_compaction[[:space:]]*$' "$path"; then
      hit=1
    fi
  fi
  if [ "$hit" -eq 1 ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       File: $path"
    echo -e "       --- contents ---"
    sed 's/^/       /' "$path" 1>&2 || true
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_session_compaction_absent() {
  local description="$1"
  local path="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ ! -f "$path" ]; then
    # Missing file vacuously satisfies "absent". Used by scenario (d).
    echo -e "  ${GREEN}PASS${NC} $description (state file does not exist)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return
  fi
  local hit=0
  if command -v yq >/dev/null 2>&1; then
    local out
    out=$(yq '.runtime_metrics[] | select(.boundary == "session_compaction")' "$path" 2>/dev/null || true)
    [ -n "$out" ] && hit=1
  else
    if grep -qE '^[[:space:]]*-?[[:space:]]*boundary:[[:space:]]*session_compaction[[:space:]]*$' "$path"; then
      hit=1
    fi
  fi
  if [ "$hit" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       File: $path"
    echo -e "       --- contents ---"
    sed 's/^/       /' "$path" 1>&2 || true
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_exit_zero() {
  local description="$1"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ "$LAST_EXIT_CODE" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description (exit=$LAST_EXIT_CODE)"
    echo -e "       stderr: $LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_file_unchanged() {
  local description="$1"
  local path="$2"
  local pre_hash="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ ! -f "$path" ]; then
    echo -e "  ${GREEN}PASS${NC} $description (file does not exist; trivially unchanged)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return
  fi
  local post_hash
  post_hash=$(shasum "$path" | awk '{print $1}')
  if [ "$pre_hash" = "$post_hash" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description (sha1 changed: $pre_hash → $post_hash)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

print_summary() {
  echo ""
  echo "==============================="
  echo -e "Total: $TESTS_TOTAL | ${GREEN}Passed: $TESTS_PASSED${NC} | ${RED}Failed: $TESTS_FAILED${NC}"
  echo "==============================="
  if [ "$TESTS_FAILED" -gt 0 ]; then
    return 1
  fi
  return 0
}

# --- scenarios --------------------------------------------------------------

echo "=== PreCompact end-to-end fixture (PX-06) ==="
echo ""
if ! command -v yq >/dev/null 2>&1; then
  echo "  (note: yq not on PATH — verification falls back to grep, mirroring the"
  echo "   yq → python3 → pure-shell graceful-degrade chain in the hook itself.)"
  echo ""
fi

# (a) briefs/active/ only — append expected
echo "--- (a) briefs/active/ only — boundary: session_compaction appended ---"
REPO_A=$(new_repo)
ACTIVE_PATH="$REPO_A/.simple-workflow/backlog/briefs/active/precompact-a/autopilot-state.yaml"
write_completed_state "$ACTIVE_PATH"
run_precompact_hook "$REPO_A"
assert_exit_zero "(a) PreCompact hook exits 0"
assert_session_compaction_present \
  "(a) runtime_metrics contains boundary: session_compaction" \
  "$ACTIVE_PATH"

echo ""

# (b) briefs/done/ only, all steps completed — append expected (PX-03 fallback)
echo "--- (b) briefs/done/ all-completed — PX-03 hook discovery extension ---"
REPO_B=$(new_repo)
DONE_PATH_B="$REPO_B/.simple-workflow/backlog/briefs/done/precompact-b/autopilot-state.yaml"
write_completed_state "$DONE_PATH_B"
run_precompact_hook "$REPO_B"
assert_exit_zero "(b) PreCompact hook exits 0"
assert_session_compaction_present \
  "(b) runtime_metrics contains boundary: session_compaction" \
  "$DONE_PATH_B"

echo ""

# (c) Negative: briefs/done/ with pending step — no append (NAC #7)
echo "--- (c) briefs/done/ with pending step — no append (NAC #7 guard) ---"
REPO_C=$(new_repo)
DONE_PATH_C="$REPO_C/.simple-workflow/backlog/briefs/done/precompact-c/autopilot-state.yaml"
write_pending_state "$DONE_PATH_C"
PRE_HASH_C=$(shasum "$DONE_PATH_C" | awk '{print $1}')
run_precompact_hook "$REPO_C"
assert_exit_zero "(c) PreCompact hook exits 0 (graceful skip)"
assert_session_compaction_absent \
  "(c) runtime_metrics is NOT updated when steps are still pending" \
  "$DONE_PATH_C"
assert_file_unchanged \
  "(c) state file content is byte-identical (sha1 stable)" \
  "$DONE_PATH_C" "$PRE_HASH_C"

echo ""

# (d) Negative: no state file anywhere — graceful exit 0
echo "--- (d) no state file in any lookup root — graceful no-op ---"
REPO_D=$(new_repo)
# Intentionally do NOT write any autopilot-state.yaml. The three lookup
# directories exist but are empty.
run_precompact_hook "$REPO_D"
assert_exit_zero "(d) PreCompact hook exits 0 with no state file present"
# The hook still writes a compact-state-*.md snapshot; that artefact is fine.
# What MUST NOT happen is a runtime_metrics: append. We assert by listing
# every yaml under the three roots and confirming none contain the boundary.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
LEAKED=$(find "$REPO_D/.simple-workflow/backlog" -type f -name 'autopilot-state.yaml' 2>/dev/null | wc -l | tr -d '[:space:]')
if [ "$LEAKED" = "0" ]; then
  echo -e "  ${GREEN}PASS${NC} (d) no autopilot-state.yaml was created by the hook"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (d) the hook should not invent a state file (found $LEAKED)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
print_summary
