#!/usr/bin/env bash
# tests/test-detect-policy-gate-stop.sh
#
# Unit tests for hooks/lib/detect-policy-gate-stop.sh — the shared detector
# that the three autopilot Stop hooks use to honour a model-declared
# policy-gate hard-stop (`[AUTOPILOT-POLICY] ... action=stop` in the LAST
# assistant turn). One detection definition, three consumers (AC-6).
#
# Coverage (AC-1):
#   - sourcing produces NO top-level side effects (no stdout/stderr, exit 0)
#   - the function exists and is exported
#   - returns 0 when the marker is in the LAST assistant turn's text block
#   - returns 1 when: marker only in an earlier (non-last) assistant turn;
#     marker only inside a tool_use input; no marker; missing / empty /
#     malformed transcript; no argument
#   - never crashes (clean non-zero return)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test-helper.sh
source "$SCRIPT_DIR/test-helper.sh"

HELPER="$HOOK_DIR/lib/detect-policy-gate-stop.sh"
FIXTURES_DIR="$(cd "$SCRIPT_DIR/fixtures/transcripts" 2>/dev/null && pwd)"

echo "=== detect-policy-gate-stop.sh Tests ==="
echo ""

# ---------------------------------------------------------------------------
# AC-1: sourcing produces NO top-level side effects (no stdout/stderr, exit 0)
# ---------------------------------------------------------------------------
echo "--- source: no side effects ---"
SRC_STDOUT=$(mktemp); SRC_STDERR=$(mktemp)
set +e
bash -c "source '$HELPER'" >"$SRC_STDOUT" 2>"$SRC_STDERR"
SRC_RC=$?
set -e
SRC_OUT=$(cat "$SRC_STDOUT"); SRC_ERR=$(cat "$SRC_STDERR")
rm -f "$SRC_STDOUT" "$SRC_STDERR"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$SRC_RC" -eq 0 ] && [ -z "$SRC_OUT" ] && [ -z "$SRC_ERR" ]; then
  echo -e "  ${GREEN}PASS${NC} sourcing: exit 0, no stdout, no stderr"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} sourcing should be side-effect free"
  echo -e "       rc=$SRC_RC stdout='$SRC_OUT' stderr='$SRC_ERR'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---------------------------------------------------------------------------
# Function exists + is exported
# ---------------------------------------------------------------------------
echo "--- function defined + exported ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if bash -c "source '$HELPER'; declare -F last_turn_declares_policy_gate_stop >/dev/null" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} last_turn_declares_policy_gate_stop is defined"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} last_turn_declares_policy_gate_stop is not defined"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if bash -c "source '$HELPER'; export -p -f last_turn_declares_policy_gate_stop >/dev/null 2>&1 || declare -F last_turn_declares_policy_gate_stop >/dev/null"; then
  # The function is exported via `export -f` in the helper. Verify a child
  # bash that does NOT re-source still sees it (export propagation).
  if bash -c "source '$HELPER'; bash -c 'declare -F last_turn_declares_policy_gate_stop >/dev/null'" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} function is exported to child bash"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} function not exported to child bash"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  echo -e "  ${RED}FAIL${NC} function export check failed"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---------------------------------------------------------------------------
# Helper: assert the detector returns the expected code for a transcript.
# Args: $1=description, $2=transcript_path, $3=expected_rc (0 or 1)
# ---------------------------------------------------------------------------
assert_detect() {
  local desc="$1"; local tp="$2"; local expected="$3"
  local out_stdout out_stderr rc
  out_stdout=$(mktemp); out_stderr=$(mktemp)
  set +e
  bash -c "source '$HELPER'; last_turn_declares_policy_gate_stop '$tp'" >"$out_stdout" 2>"$out_stderr"
  rc=$?
  set -e
  local gotout goterr
  gotout=$(cat "$out_stdout"); goterr=$(cat "$out_stderr")
  rm -f "$out_stdout" "$out_stderr"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  # The function must never write to stdout/stderr itself and must return the
  # expected code.
  if [ "$rc" -eq "$expected" ] && [ -z "$gotout" ] && [ -z "$goterr" ]; then
    echo -e "  ${GREEN}PASS${NC} $desc (rc=$rc, silent)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $desc"
    echo -e "       expected rc=$expected silent; got rc=$rc stdout='$gotout' stderr='$goterr'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ---------------------------------------------------------------------------
# Positive: marker in the LAST assistant turn text block → rc 0
# ---------------------------------------------------------------------------
echo "--- positive: marker in last assistant turn ---"
assert_detect "marker in last assistant turn (shared fixture)" \
  "$FIXTURES_DIR/policy_gate_stop_last_turn.jsonl" 0

# Inline positive variant: gate=ship_review_gate, multi-line text block.
POS_INLINE=$(mktemp)
cat > "$POS_INLINE" <<'EOF'
{"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"text","text":"Stopping per ship review gate.\n[AUTOPILOT-POLICY] gate=ship_review_gate action=stop reason=human_review_required"}]}}
EOF
assert_detect "marker in last turn (inline, ship_review_gate)" "$POS_INLINE" 0
rm -f "$POS_INLINE"

# ---------------------------------------------------------------------------
# Negative: marker only in an EARLIER (non-last) assistant turn → rc 1
# ---------------------------------------------------------------------------
echo "--- negative: marker only in earlier turn ---"
assert_detect "marker only in earlier turn (shared fixture)" \
  "$FIXTURES_DIR/policy_gate_stop_earlier_turn_only.jsonl" 1

# ---------------------------------------------------------------------------
# Negative: marker only inside a tool_use input (not a text block) → rc 1
# ---------------------------------------------------------------------------
echo "--- negative: marker only inside tool_use input ---"
assert_detect "marker only in tool_use input (shared fixture)" \
  "$FIXTURES_DIR/policy_gate_stop_tool_use_only.jsonl" 1

# ---------------------------------------------------------------------------
# Negative: no marker at all → rc 1
# ---------------------------------------------------------------------------
echo "--- negative: no marker ---"
NO_MARKER=$(mktemp)
cat > "$NO_MARKER" <<'EOF'
{"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"text","text":"All steps complete, ending the turn normally."}]}}
EOF
assert_detect "no marker present" "$NO_MARKER" 1
rm -f "$NO_MARKER"

# Negative: an [AUTOPILOT-POLICY] line WITHOUT action=stop (e.g. action=allow)
# must NOT be honoured.
echo "--- negative: [AUTOPILOT-POLICY] but action=allow ---"
ALLOW_MARKER=$(mktemp)
cat > "$ALLOW_MARKER" <<'EOF'
{"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"text","text":"[AUTOPILOT-POLICY] gate=scout action=allow reason=evaluated"}]}}
EOF
assert_detect "action=allow is not a stop" "$ALLOW_MARKER" 1
rm -f "$ALLOW_MARKER"

# ---------------------------------------------------------------------------
# Negative: malformed / empty / missing transcript + missing arg → rc 1, no crash
# ---------------------------------------------------------------------------
echo "--- negative: malformed / empty / missing / no-arg ---"
assert_detect "malformed transcript (shared fixture)" \
  "$FIXTURES_DIR/malformed.jsonl" 1

EMPTY=$(mktemp)
: > "$EMPTY"
assert_detect "empty transcript" "$EMPTY" 1
rm -f "$EMPTY"

assert_detect "missing transcript path" "/nonexistent/path/$$-transcript.jsonl" 1

# No-argument call: must return non-zero and not crash.
NOARG_STDERR=$(mktemp)
set +e
bash -c "source '$HELPER'; last_turn_declares_policy_gate_stop" >/dev/null 2>"$NOARG_STDERR"
NOARG_RC=$?
set -e
NOARG_ERR=$(cat "$NOARG_STDERR"); rm -f "$NOARG_STDERR"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$NOARG_RC" -ne 0 ] && [ -z "$NOARG_ERR" ]; then
  echo -e "  ${GREEN}PASS${NC} no-argument call returns non-zero, no crash (rc=$NOARG_RC)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} no-argument call should return non-zero silently"
  echo -e "       rc=$NOARG_RC stderr='$NOARG_ERR'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---------------------------------------------------------------------------
# DRY (AC-6): the marker regex is defined ONLY in the helper. Assert the
# three Stop hooks do NOT inline the literal `[AUTOPILOT-POLICY]` regex but
# DO source the helper + call the function.
# ---------------------------------------------------------------------------
echo "--- AC-6: DRY — detection only in the helper ---"
for hook in autopilot-continue.sh impl-checkpoint-guard.sh scout-checkpoint-guard.sh; do
  HOOK_PATH="$HOOK_DIR/$hook"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  sources_helper=false
  calls_fn=false
  grep -qF 'detect-policy-gate-stop.sh' "$HOOK_PATH" && sources_helper=true
  grep -qF 'last_turn_declares_policy_gate_stop' "$HOOK_PATH" && calls_fn=true
  # The hook may reference the marker name in a comment, but it must NOT
  # contain the detection REGEX. The helper's regex token is
  # `\[AUTOPILOT-POLICY\]` (escaped-bracket ERE). Assert that escaped form is
  # absent from the hooks (it lives only in the helper).
  inlines_regex=false
  grep -qF '\[AUTOPILOT-POLICY\]' "$HOOK_PATH" && inlines_regex=true
  if [ "$sources_helper" = true ] && [ "$calls_fn" = true ] && [ "$inlines_regex" = false ]; then
    echo -e "  ${GREEN}PASS${NC} $hook sources helper + calls fn, no inlined regex"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $hook DRY violation"
    echo -e "       sources_helper=$sources_helper calls_fn=$calls_fn inlines_regex=$inlines_regex"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# Assert the escaped regex token exists in the helper itself (the single
# source of truth).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF '\[AUTOPILOT-POLICY\]' "$HELPER"; then
  echo -e "  ${GREEN}PASS${NC} detection regex token present in the helper (single source)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} detection regex token missing from the helper"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
print_summary
