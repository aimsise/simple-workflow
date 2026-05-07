#!/usr/bin/env bash
# test-per-phase-metrics.sh -- PX-05: exercises hooks/post-phase-checkpoint.sh
# (PostToolUse:Write hook) which appends `boundary: phase_complete` /
# `phase_failed` / `phase_skipped` entries to the parent autopilot-state.yaml
# whenever a phase-state.yaml `phases.<name>.status` transitions to one of
# the three terminal values.
#
# Scenarios (PX-05 Acceptance Criteria #3 (a)-(g) plus AC #5 simulation):
#   (a) phases.scout.status pending -> completed -> 1 entry phase_complete
#   (b) 3 phases (scout/impl/ship) sequentially completed
#       -> 3 entries phase_complete
#   (c) non-status update (last_round only) -> no entry
#   (d) outside autopilot context -> no entry
#   (e) idempotent completed -> completed run twice -> only 1 entry
#   (f) phases.impl.status pending -> failed -> 1 entry phase_failed
#   (g) phases.ship.status pending -> skipped -> 1 entry phase_skipped
#   (h) AC #5 -- 6 tickets x 3 phases = exactly 18 phase_complete entries
#       (one autopilot-state.yaml hosts 6 ticket dirs; we run scenario (b)
#        equivalent against each in turn). The phase scope mirrors the
#        canonical three-phase schema in
#        skills/create-ticket/references/phase-state-schema.md (scout /
#        impl / ship); the prior five-phase shape was a fixture artefact.
#
# Each scenario builds a self-contained tmp repo via mktemp -d and runs
# the hook with a Claude Code-shaped JSON payload on stdin, mirroring the
# isolation pattern in tests/test-precompact-end-to-end.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_PATH="$REPO_DIR/hooks/post-phase-checkpoint.sh"
FIXTURE_DIR="$REPO_DIR/tests/fixtures/per-phase-metrics-samples"
AUTOPILOT_TEMPLATE="$FIXTURE_DIR/autopilot-state-base.yaml"
PHASE_TEMPLATE="$FIXTURE_DIR/phase-state-pending.yaml"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

TMP_DIRS=()
cleanup() {
  local d
  for d in "${TMP_DIRS[@]+"${TMP_DIRS[@]}"}"; do
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d" || true
  done
  return 0
}
trap cleanup EXIT

# --- helpers ---------------------------------------------------------------

# Build a fresh tmp repo with the canonical .simple-workflow/ layout so the
# hook's is_autopilot_context() returns true.
new_repo() {
  local d
  d=$(mktemp -d "/tmp/sw-pphc-fixture.XXXXXX")
  TMP_DIRS+=("$d")
  mkdir -p "$d/.simple-workflow/backlog/briefs/active"
  mkdir -p "$d/.simple-workflow/backlog/briefs/done"
  mkdir -p "$d/.simple-workflow/backlog/product_backlog"
  printf '%s' "$d"
}

# new_repo without the autopilot anchor so is_autopilot_context() returns
# false (used by scenario (d)).
new_bare_dir() {
  local d
  d=$(mktemp -d "/tmp/sw-pphc-bare.XXXXXX")
  TMP_DIRS+=("$d")
  printf '%s' "$d"
}

# Materialise a phase-state.yaml from the template, substituting ticket_id
# and (optionally) overwriting the named phase's status.
write_phase_state() {
  local out="$1"
  local ticket_id="$2"
  local phase="${3:-}"
  local status="${4:-}"

  mkdir -p "$(dirname "$out")"

  if [ -z "$phase" ] || [ -z "$status" ]; then
    sed "s/^ticket_id: T-001$/ticket_id: $ticket_id/" "$PHASE_TEMPLATE" > "$out"
    return 0
  fi

  # Use python3 + PyYAML when available so the rewrite touches exactly one
  # nested status; degrade to awk otherwise.
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    PHASE_TEMPLATE="$PHASE_TEMPLATE" \
    OUT_PATH="$out" \
    TID="$ticket_id" \
    PH="$phase" \
    ST="$status" \
    python3 - <<'PY'
import os
import yaml
with open(os.environ['PHASE_TEMPLATE'], 'r', encoding='utf-8') as f:
    doc = yaml.safe_load(f)
doc['ticket_id'] = os.environ['TID']
ph = os.environ['PH']
st = os.environ['ST']
phases = doc.setdefault('phases', {})
slot = phases.setdefault(ph, {'status': 'pending', 'started_at': None, 'completed_at': None})
slot['status'] = st
with open(os.environ['OUT_PATH'], 'w', encoding='utf-8') as f:
    yaml.safe_dump(doc, f, default_flow_style=False, sort_keys=False)
PY
  else
    # awk fallback: emit the template but rewrite the requested phase's
    # status line. Since the template is well-known and stable we can rely
    # on indentation-based matching.
    awk -v tid="$ticket_id" -v phase="$phase" -v status="$status" '
      BEGIN { in_phases = 0; in_target = 0 }
      /^ticket_id:[[:space:]]/ { print "ticket_id: " tid; next }
      /^phases:[[:space:]]*$/ { in_phases = 1; print; next }
      in_phases && /^[^[:space:]]/ { in_phases = 0; in_target = 0 }
      in_phases && match($0, /^[[:space:]]+([A-Za-z0-9_-]+):[[:space:]]*$/, m) {
        in_target = (m[1] == phase) ? 1 : 0
        print
        next
      }
      in_phases && in_target && /^[[:space:]]+status:[[:space:]]/ {
        sub(/status:[[:space:]]*.*$/, "status: " status, $0)
        print
        next
      }
      { print }
    ' "$PHASE_TEMPLATE" > "$out"
  fi
}

# Build an autopilot-state.yaml at <repo>/.simple-workflow/backlog/briefs/active/<slug>/
# with the `runtime_metrics: []` initial state.
write_autopilot_state() {
  local out="$1"
  local parent_slug="$2"
  mkdir -p "$(dirname "$out")"
  sed "s/PARENT_SLUG_PLACEHOLDER/$parent_slug/g" "$AUTOPILOT_TEMPLATE" > "$out"
}

# Pipe a Write payload at the hook. $1=repo cwd $2=phase-state.yaml absolute path.
run_hook() {
  local cwd="$1"
  local fp="$2"
  local payload
  payload=$(jq -nc \
    --arg fp "$fp" \
    --arg cwd "$cwd" \
    '{tool_name:"Write", tool_input:{file_path:$fp, content:""}, tool_response:{}, cwd:$cwd, session_id:"per-phase-fixture"}')
  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  set +e
  ( cd "$cwd" && bash "$HOOK_PATH" <<<"$payload" ) >"$stdout_file" 2>"$stderr_file"
  LAST_EXIT_CODE=$?
  set -e
  LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

# Count entries matching boundary in state file's runtime_metrics.
count_boundary_entries() {
  local path="$1"
  local boundary="$2"
  if [ ! -f "$path" ]; then
    echo 0
    return
  fi
  if command -v yq >/dev/null 2>&1; then
    local n
    n=$(yq -r ".runtime_metrics // [] | map(select(.boundary == \"$boundary\")) | length" "$path" 2>/dev/null || echo 0)
    [ -z "$n" ] || [ "$n" = "null" ] && n=0
    echo "$n"
    return
  fi
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    PATH_VAR="$path" BND="$boundary" python3 - <<'PY'
import os
try:
    import yaml
except ImportError:
    print(0); raise SystemExit
try:
    with open(os.environ['PATH_VAR'], 'r') as f:
        doc = yaml.safe_load(f) or {}
    rm = doc.get('runtime_metrics') or []
    n = sum(1 for e in rm if isinstance(e, dict) and e.get('boundary') == os.environ['BND'])
    print(n)
except Exception:
    print(0)
PY
    return
  fi
  # awk fallback
  awk -v bnd="$boundary" '
    /^runtime_metrics:[[:space:]]*$/ { in_rm = 1; next }
    /^[A-Za-z0-9_-]+:[[:space:]]*$/ && in_rm == 1 && !/^runtime_metrics/ { in_rm = 0 }
    in_rm && match($0, /boundary:[[:space:]]*([A-Za-z0-9_]+)/, m) {
      if (m[1] == bnd) c++
    }
    END { print c+0 }
  ' "$path"
}

# Count entries matching (ticket_id, phase, boundary) triple.
count_triple_entries() {
  local path="$1"
  local tid="$2"
  local ph="$3"
  local bnd="$4"
  if [ ! -f "$path" ]; then
    echo 0
    return
  fi
  if command -v yq >/dev/null 2>&1; then
    local n
    n=$(yq -r ".runtime_metrics // [] | map(select(.ticket_id == \"$tid\" and .phase == \"$ph\" and .boundary == \"$bnd\")) | length" "$path" 2>/dev/null || echo 0)
    [ -z "$n" ] || [ "$n" = "null" ] && n=0
    echo "$n"
    return
  fi
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    PATH_VAR="$path" TID="$tid" PH="$ph" BND="$bnd" python3 - <<'PY'
import os
try:
    import yaml
except ImportError:
    print(0); raise SystemExit
try:
    with open(os.environ['PATH_VAR'], 'r') as f:
        doc = yaml.safe_load(f) or {}
    rm = doc.get('runtime_metrics') or []
    tid = os.environ['TID']; ph = os.environ['PH']; bnd = os.environ['BND']
    n = sum(1 for e in rm if isinstance(e, dict)
            and e.get('ticket_id') == tid
            and e.get('phase') == ph
            and e.get('boundary') == bnd)
    print(n)
except Exception:
    print(0)
PY
    return
  fi
  # awk fallback that scans full block.
  awk -v tid="$tid" -v ph="$ph" -v bnd="$bnd" '
    /^runtime_metrics:[[:space:]]*$/ { in_rm = 1; cur_tid = ""; cur_ph = ""; cur_bnd = ""; next }
    /^[A-Za-z0-9_-]+:[[:space:]]*$/ && in_rm == 1 && !/^runtime_metrics/ {
      if (cur_tid == tid && cur_ph == ph && cur_bnd == bnd) c++
      in_rm = 0
    }
    in_rm && /^[[:space:]]*-[[:space:]]/ {
      if (cur_tid == tid && cur_ph == ph && cur_bnd == bnd) c++
      cur_tid = ""; cur_ph = ""; cur_bnd = ""
    }
    in_rm {
      if (match($0, /ticket_id:[[:space:]]*([^[:space:]]+)/, m)) cur_tid = m[1]
      if (match($0, /phase:[[:space:]]*([^[:space:]]+)/, m))     cur_ph  = m[1]
      if (match($0, /boundary:[[:space:]]*([^[:space:]]+)/, m))  cur_bnd = m[1]
    }
    END {
      if (cur_tid == tid && cur_ph == ph && cur_bnd == bnd) c++
      print c+0
    }
  ' "$path"
}

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
    echo -e "       Expected: $expected"
    echo -e "       Actual:   $actual"
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

# --- structural sanity (AC #1 / AC #2) -------------------------------------

echo "=== per-phase observability tests (PX-05) ==="
echo ""
echo "--- Sanity: stop-reason-taxonomy.md and hook source contracts ---"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
TAXONOMY="$REPO_DIR/skills/autopilot/references/stop-reason-taxonomy.md"
TAX_HITS=$(grep -cE 'boundary:[[:space:]]*phase_(complete|failed|skipped)' "$TAXONOMY" 2>/dev/null || echo 0)
if [ "$TAX_HITS" -ge 3 ]; then
  echo -e "  ${GREEN}PASS${NC} taxonomy enumerates the three new boundary literals (hits=$TAX_HITS)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} taxonomy missing one or more of phase_complete/phase_failed/phase_skipped (hits=$TAX_HITS)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'source.*hooks/lib/parse-state-file\.sh|\. .*hooks/lib/parse-state-file\.sh' "$HOOK_PATH" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} hook sources hooks/lib/parse-state-file.sh"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} hook does not source hooks/lib/parse-state-file.sh"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
HELPER_HITS=$(grep -cE 'is_autopilot_context|parse_phase_status|find_state_file' "$HOOK_PATH" 2>/dev/null || echo 0)
if [ "$HELPER_HITS" -ge 3 ]; then
  echo -e "  ${GREEN}PASS${NC} hook references the three required helper functions (hits=$HELPER_HITS)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} hook missing one or more of is_autopilot_context/parse_phase_status/find_state_file (hits=$HELPER_HITS)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! grep -qiE 'last_n|recent_n|window|\btail[[:space:]]+-n([[:space:]]+|=)?[0-9]+' "$HOOK_PATH" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} hook has no recent-N window idioms (AC #6)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} hook contains recent-N window idiom"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! grep -qiE 'SKIP_|BYPASS_|FORCE_' "$HOOK_PATH" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} hook has no env-var bypass (NAC #10)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} hook references env-var bypass"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
PT_ENTRY=$(jq -r '.hooks.PostToolUse | map(select(.matcher == "Write")) | length' "$REPO_DIR/hooks/hooks.json" 2>/dev/null || echo 0)
if [ "$PT_ENTRY" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} hooks.json registers PostToolUse:Write entry"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} hooks.json missing PostToolUse:Write entry"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- (a) pending -> completed for one phase --------------------------------

echo ""
echo "--- (a) phases.scout.status pending -> completed -> 1 entry ---"
REPO=$(new_repo)
SLUG="ppm-a"
TID="T-001"
APS="$REPO/.simple-workflow/backlog/briefs/active/$SLUG/autopilot-state.yaml"
PHS="$REPO/.simple-workflow/backlog/briefs/active/$SLUG/$TID/phase-state.yaml"
write_autopilot_state "$APS" "$SLUG"
write_phase_state "$PHS" "$TID" scout completed
run_hook "$REPO" "$PHS"
assert_exit_zero "(a) hook exits 0"
assert_eq "(a) one phase_complete entry recorded" 1 "$(count_triple_entries "$APS" "$TID" scout phase_complete)"
assert_eq "(a) total phase_complete entries == 1" 1 "$(count_boundary_entries "$APS" phase_complete)"

# --- (b) 3 phases sequentially completed -----------------------------------

echo ""
echo "--- (b) 3 phases (scout/impl/ship) sequentially completed -> 3 entries ---"
REPO=$(new_repo)
SLUG="ppm-b"
TID="T-002"
APS="$REPO/.simple-workflow/backlog/briefs/active/$SLUG/autopilot-state.yaml"
PHS="$REPO/.simple-workflow/backlog/briefs/active/$SLUG/$TID/phase-state.yaml"
write_autopilot_state "$APS" "$SLUG"
write_phase_state "$PHS" "$TID"  # all pending
for ph in scout impl ship; do
  write_phase_state "$PHS" "$TID" "$ph" completed
  run_hook "$REPO" "$PHS"
  assert_exit_zero "(b) hook exits 0 after $ph -> completed"
done
for ph in scout impl ship; do
  assert_eq "(b) one entry for ($TID, $ph, phase_complete)" 1 "$(count_triple_entries "$APS" "$TID" "$ph" phase_complete)"
done
assert_eq "(b) total phase_complete entries == 3" 3 "$(count_boundary_entries "$APS" phase_complete)"

# --- (c) non-status update -> no entry --------------------------------------

echo ""
echo "--- (c) non-status field update (last_round only) -> no entry ---"
REPO=$(new_repo)
SLUG="ppm-c"
TID="T-003"
APS="$REPO/.simple-workflow/backlog/briefs/active/$SLUG/autopilot-state.yaml"
PHS="$REPO/.simple-workflow/backlog/briefs/active/$SLUG/$TID/phase-state.yaml"
write_autopilot_state "$APS" "$SLUG"
write_phase_state "$PHS" "$TID"  # all pending
# Append a `last_round: 1` scalar at top-level. The scout/impl/ship
# statuses remain `pending`, so no entry should be appended.
printf '\nlast_round: 1\n' >> "$PHS"
run_hook "$REPO" "$PHS"
assert_exit_zero "(c) hook exits 0"
assert_eq "(c) zero phase_complete entries" 0 "$(count_boundary_entries "$APS" phase_complete)"
assert_eq "(c) zero phase_failed entries" 0 "$(count_boundary_entries "$APS" phase_failed)"
assert_eq "(c) zero phase_skipped entries" 0 "$(count_boundary_entries "$APS" phase_skipped)"

# --- (d) outside autopilot context -> no entry -----------------------------

echo ""
echo "--- (d) outside autopilot context -> no entry ---"
BARE=$(new_bare_dir)
TID="T-004"
PHS="$BARE/$TID/phase-state.yaml"
write_phase_state "$PHS" "$TID" scout completed
run_hook "$BARE" "$PHS"
assert_exit_zero "(d) hook exits 0 (graceful no-op)"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
LEAKED=$(find "$BARE" -type f -name 'autopilot-state.yaml' 2>/dev/null | wc -l | tr -d '[:space:]')
if [ "$LEAKED" = "0" ]; then
  echo -e "  ${GREEN}PASS${NC} (d) no autopilot-state.yaml created in bare dir"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (d) bare dir gained $LEAKED autopilot-state.yaml file(s)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- (e) idempotent completed -> completed, run twice -> only 1 entry -----

echo ""
echo "--- (e) idempotent completed -> completed (run twice) -> 1 entry ---"
REPO=$(new_repo)
SLUG="ppm-e"
TID="T-005"
APS="$REPO/.simple-workflow/backlog/briefs/active/$SLUG/autopilot-state.yaml"
PHS="$REPO/.simple-workflow/backlog/briefs/active/$SLUG/$TID/phase-state.yaml"
write_autopilot_state "$APS" "$SLUG"
write_phase_state "$PHS" "$TID" scout completed
run_hook "$REPO" "$PHS"
assert_exit_zero "(e) first run exits 0"
# Second run: same payload, same on-disk content. Idempotent triple-check
# should suppress the second append.
run_hook "$REPO" "$PHS"
assert_exit_zero "(e) second run exits 0"
assert_eq "(e) only one phase_complete entry after two runs" 1 "$(count_triple_entries "$APS" "$TID" scout phase_complete)"
assert_eq "(e) total phase_complete entries == 1" 1 "$(count_boundary_entries "$APS" phase_complete)"

# --- (f) phases.impl.status pending -> failed -> 1 entry -------------------

echo ""
echo "--- (f) phases.impl.status pending -> failed -> 1 entry phase_failed ---"
REPO=$(new_repo)
SLUG="ppm-f"
TID="T-006"
APS="$REPO/.simple-workflow/backlog/briefs/active/$SLUG/autopilot-state.yaml"
PHS="$REPO/.simple-workflow/backlog/briefs/active/$SLUG/$TID/phase-state.yaml"
write_autopilot_state "$APS" "$SLUG"
write_phase_state "$PHS" "$TID" impl failed
run_hook "$REPO" "$PHS"
assert_exit_zero "(f) hook exits 0"
assert_eq "(f) one phase_failed entry for impl" 1 "$(count_triple_entries "$APS" "$TID" impl phase_failed)"
assert_eq "(f) total phase_failed entries == 1" 1 "$(count_boundary_entries "$APS" phase_failed)"
assert_eq "(f) zero phase_complete entries" 0 "$(count_boundary_entries "$APS" phase_complete)"

# --- (g) phases.ship.status pending -> skipped -> 1 entry ------------------

echo ""
echo "--- (g) phases.ship.status pending -> skipped -> 1 entry phase_skipped ---"
REPO=$(new_repo)
SLUG="ppm-g"
TID="T-007"
APS="$REPO/.simple-workflow/backlog/briefs/active/$SLUG/autopilot-state.yaml"
PHS="$REPO/.simple-workflow/backlog/briefs/active/$SLUG/$TID/phase-state.yaml"
write_autopilot_state "$APS" "$SLUG"
write_phase_state "$PHS" "$TID" ship skipped
run_hook "$REPO" "$PHS"
assert_exit_zero "(g) hook exits 0"
assert_eq "(g) one phase_skipped entry for ship" 1 "$(count_triple_entries "$APS" "$TID" ship phase_skipped)"
assert_eq "(g) total phase_skipped entries == 1" 1 "$(count_boundary_entries "$APS" phase_skipped)"
assert_eq "(g) zero phase_complete entries" 0 "$(count_boundary_entries "$APS" phase_complete)"

# --- (h) AC #5: 6 tickets x 3 phases = exactly 18 phase_complete entries --

echo ""
echo "--- (h) AC #5: 6 tickets x 3 phases = 18 phase_complete entries ---"
REPO=$(new_repo)
SLUG="ppm-bulk"
APS="$REPO/.simple-workflow/backlog/briefs/active/$SLUG/autopilot-state.yaml"
write_autopilot_state "$APS" "$SLUG"
for i in 1 2 3 4 5 6; do
  TID=$(printf 'T-%03d' "$i")
  PHS="$REPO/.simple-workflow/backlog/briefs/active/$SLUG/$TID/phase-state.yaml"
  write_phase_state "$PHS" "$TID"  # all pending
  for ph in scout impl ship; do
    write_phase_state "$PHS" "$TID" "$ph" completed
    run_hook "$REPO" "$PHS"
  done
done
assert_eq "(h) total phase_complete entries == 18" 18 "$(count_boundary_entries "$APS" phase_complete)"
# Spot-check three triples to prove array-wide identity (not just count).
assert_eq "(h) entry for (T-001, scout, phase_complete) == 1" 1 "$(count_triple_entries "$APS" T-001 scout phase_complete)"
assert_eq "(h) entry for (T-003, impl, phase_complete) == 1" 1 "$(count_triple_entries "$APS" T-003 impl phase_complete)"
assert_eq "(h) entry for (T-006, ship, phase_complete) == 1" 1 "$(count_triple_entries "$APS" T-006 ship phase_complete)"

print_summary
