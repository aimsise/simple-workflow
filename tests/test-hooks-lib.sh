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

# ---------------------------------------------------------------------------
# Section 2c: find_done_autopilot_state_file (v8.0.1, AC-5)
# ---------------------------------------------------------------------------
# Counterpart to find_any_autopilot_state_file that scans briefs/done/ and
# applies an optional mtime TTL bound. Six cases mirror the AC-5(a)..(f)
# enumeration in the ticket.

echo "--- find_done_autopilot_state_file (v8.0.1) ---"

# 2c.0: function is exported and callable.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if bash -c "source '$PSF_PATH' && declare -F find_done_autopilot_state_file" >/dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC} find_done_autopilot_state_file is defined and sourceable"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} find_done_autopilot_state_file missing or not sourceable"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

DONE_TMP=$(mktemp -d)
mkdir -p "$DONE_TMP/.simple-workflow/backlog/briefs"

# 2c.a: no briefs/done/ directory at all -> exit 1, empty stdout.
set +e
out="$( cd "$DONE_TMP" && find_done_autopilot_state_file 2>/dev/null )"
exit_code=$?
set -e
assert_exit_nonzero "(a) no briefs/done/ directory -> exit non-zero" "$exit_code"
assert_eq "(a) no briefs/done/ -> empty stdout" "" "$out"

# 2c.b: empty briefs/done/ -> exit 1.
mkdir -p "$DONE_TMP/.simple-workflow/backlog/briefs/done"
set +e
out="$( cd "$DONE_TMP" && find_done_autopilot_state_file 2>/dev/null )"
exit_code=$?
set -e
assert_exit_nonzero "(b) empty briefs/done/ -> exit non-zero" "$exit_code"
assert_eq "(b) empty briefs/done/ -> empty stdout" "" "$out"

# 2c.c: single fresh briefs/done/<slug>/autopilot-state.yaml -> prints its
# absolute path, exit 0. Mtime is "now" so any TTL >= 1 should accept it.
mkdir -p "$DONE_TMP/.simple-workflow/backlog/briefs/done/colorforge"
cat > "$DONE_TMP/.simple-workflow/backlog/briefs/done/colorforge/autopilot-state.yaml" <<'YAML'
version: 1
slug: colorforge
tickets:
  - logical_id: t1
    status: completed
    steps:
      ship: completed
YAML
expected_path="$( cd "$DONE_TMP/.simple-workflow/backlog/briefs/done/colorforge" && pwd -P )/autopilot-state.yaml"
set +e
actual_path="$( cd "$DONE_TMP" && find_done_autopilot_state_file 2>/dev/null )"
exit_code=$?
set -e
assert_exit_zero "(c) single fresh done state -> exit 0" "$exit_code"
assert_eq "(c) single fresh done state -> prints absolute path" "$expected_path" "$actual_path"

# 2c.d: two done state files, different mtimes -> the newer one wins.
mkdir -p "$DONE_TMP/.simple-workflow/backlog/briefs/done/older-brief"
cat > "$DONE_TMP/.simple-workflow/backlog/briefs/done/older-brief/autopilot-state.yaml" <<'YAML'
version: 1
slug: older-brief
tickets:
  - logical_id: t1
    status: completed
YAML
# Touch the older one with an older mtime explicitly so the comparison is
# deterministic on filesystems with low timestamp resolution.
touch -t 202401010000 "$DONE_TMP/.simple-workflow/backlog/briefs/done/older-brief/autopilot-state.yaml"
# Re-touch colorforge to "now" to ensure it wins.
touch "$DONE_TMP/.simple-workflow/backlog/briefs/done/colorforge/autopilot-state.yaml"
set +e
actual_path="$( cd "$DONE_TMP" && find_done_autopilot_state_file 2>/dev/null )"
exit_code=$?
set -e
assert_exit_zero "(d) two done states -> exit 0" "$exit_code"
assert_eq "(d) two done states -> newest (colorforge) wins" "$expected_path" "$actual_path"

# 2c.e: TTL bound rejects a stale match. Aging the file by touch -t to
# year-2020, then passing TTL=60 seconds.
touch -t 202001010000 "$DONE_TMP/.simple-workflow/backlog/briefs/done/colorforge/autopilot-state.yaml"
touch -t 202001010000 "$DONE_TMP/.simple-workflow/backlog/briefs/done/older-brief/autopilot-state.yaml"
set +e
out="$( cd "$DONE_TMP" && find_done_autopilot_state_file 60 2>/dev/null )"
exit_code=$?
set -e
assert_exit_nonzero "(e) all matches older than TTL -> exit non-zero" "$exit_code"
assert_eq "(e) stale match -> empty stdout" "" "$out"

# 2c.e-bis: TTL=0 disables the bound, the same stale match becomes acceptable.
set +e
actual_path="$( cd "$DONE_TMP" && find_done_autopilot_state_file 0 2>/dev/null )"
exit_code=$?
set -e
assert_exit_zero "(e-bis) TTL=0 disables bound -> exit 0 on stale match" "$exit_code"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$actual_path" ] && [ -f "$actual_path" ]; then
  echo -e "  ${GREEN}PASS${NC} (e-bis) TTL=0 returns a valid existing path"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (e-bis) TTL=0 returned '$actual_path' which is not a regular file"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# 2c.f: non-numeric TTL coerces to 0 (unbounded), so the stale match wins
# rather than being rejected. This pairs the helper's defensive coercion
# with the gate-side caller policy (which prints a warning AND substitutes
# the default 86400 — the helper itself collapses non-numeric to 0).
set +e
actual_path="$( cd "$DONE_TMP" && find_done_autopilot_state_file "garbage" 2>/dev/null )"
exit_code=$?
set -e
assert_exit_zero "(f) non-numeric TTL coerces to 0 -> exit 0 on stale match" "$exit_code"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$actual_path" ] && [ -f "$actual_path" ]; then
  echo -e "  ${GREEN}PASS${NC} (f) non-numeric TTL returns a valid existing path"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (f) non-numeric TTL returned '$actual_path' which is not a regular file"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

rm -rf "$DONE_TMP"

# ---------------------------------------------------------------------------
# --- _psf_repo_root strict anchor (T-01) ---
#
# Field evidence (`test_simple_workflow29`, session
# 8f7dff21-c491-4fc2-ada0-20f2bb814fd4): after a successful auto-compact
# at a ticket boundary, the post-compact SessionStart(source=compact)
# resume injection silently no-op'd because `is_autopilot_context`
# returned false. Root cause: prior hooks ran from a cwd of
# `.simple-workflow/kb/` (a tune-skill artifact) and wrote via relative
# paths like `.simple-workflow/docs/session-log/`, leaving behind a nested
# `.simple-workflow/kb/.simple-workflow/` directory. The pre-fix
# `_psf_repo_root` accepted ANY directory with a `.simple-workflow/` child
# as the repo root, so it returned `.simple-workflow/kb/` itself — making
# `find_any_autopilot_state_file` look in
# `.simple-workflow/kb/.simple-workflow/backlog/briefs/active`, which does
# not exist.
#
# The T-01 fix tightens the anchor: a candidate must contain BOTH
# `.simple-workflow/` AND `.simple-workflow/backlog/` to qualify. The
# tests below pin the new behaviour so a future regression cannot revert
# the loose anchor without failing CI.
# ---------------------------------------------------------------------------
echo ""
echo "--- _psf_repo_root strict anchor (T-01) ---"

# Build the T-01 fixture tree. Use a private tempdir so the existing
# PSF_TMP trap does not have to be extended.
T01_TMP="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$PSF_TMP' '$NEG_TMP' '$T01_TMP'" EXIT

# Real autopilot root with a live state file.
mkdir -p "$T01_TMP/repo/.simple-workflow/backlog/briefs/active/foo"
touch "$T01_TMP/repo/.simple-workflow/backlog/briefs/active/foo/autopilot-state.yaml"

# Empty nested subdir used by AC-2 (positive walk-up).
mkdir -p "$T01_TMP/repo/some/nested/dir"

# Decoy nested `.simple-workflow/` from the field incident — has NO
# `backlog/` subdirectory but does have `docs/session-log/` (mirrors the
# tune-skill artifact path).
mkdir -p "$T01_TMP/repo/.simple-workflow/kb/.simple-workflow/docs/session-log"
touch "$T01_TMP/repo/.simple-workflow/kb/.simple-workflow/docs/session-log/x.md"

# AC-6 fixture: a stray `.simple-workflow/` without `backlog/`, with an
# empty `child/` subdir so we can invoke `_psf_repo_root` from a
# descendant — that way the start-dir fallback path `$1` is not equal to
# `$T01_TMP/scratch` (the directory under test).
mkdir -p "$T01_TMP/scratch/.simple-workflow"
mkdir -p "$T01_TMP/scratch/child"

# AC-2: positive — normal root preserved. Walk up from an empty nested
# dir and stop at the canonical root.
# Wrap in set +e / set -e: even on success the function returns 0, but
# the same idiom is used below for AC-6 (which intentionally returns
# non-zero) so keep the guards uniform across the section.
set +e
out="$( _psf_repo_root "$T01_TMP/repo/some/nested/dir" )"
set -e
assert_eq "T-01 AC-2: _psf_repo_root walks up to canonical root" "$T01_TMP/repo" "$out"

# AC-3: negative — nested `.simple-workflow/` without `backlog/` is
# skipped; the walk continues up to the real autopilot root.
set +e
out="$( _psf_repo_root "$T01_TMP/repo/.simple-workflow/kb" )"
set -e
assert_eq "T-01 AC-3: _psf_repo_root skips nested decoy .simple-workflow/" "$T01_TMP/repo" "$out"

# AC-4: is_autopilot_context regression under nested cwd. The strict
# anchor must let the function walk past the decoy to the real root,
# where the find -mindepth/-maxdepth probe succeeds.
set +e
( cd "$T01_TMP/repo/.simple-workflow/kb" && is_autopilot_context )
exit_code=$?
set -e
assert_exit_zero "T-01 AC-4: is_autopilot_context returns 0 under nested decoy cwd" "$exit_code"

# AC-5: find_any_autopilot_state_file regression under nested cwd. The
# returned path must resolve to the real autopilot-state.yaml.
set +e
t01_ac5_out="$( cd "$T01_TMP/repo/.simple-workflow/kb" && find_any_autopilot_state_file )"
t01_ac5_exit=$?
set -e
assert_exit_zero "T-01 AC-5: find_any_autopilot_state_file exits 0 under nested decoy cwd" "$t01_ac5_exit"
t01_ac5_resolved="$(realpath -e "$t01_ac5_out" 2>/dev/null || true)"
t01_ac5_expected="$(realpath -e "$T01_TMP/repo/.simple-workflow/backlog/briefs/active/foo/autopilot-state.yaml" 2>/dev/null || true)"
assert_eq "T-01 AC-5: find_any_autopilot_state_file resolves to real autopilot-state.yaml" \
  "$t01_ac5_expected" "$t01_ac5_resolved"

# AC-6: no false-positive on empty `.simple-workflow/`. Start from
# `$T01_TMP/scratch/child` (an empty subdir). The function must NOT
# return `$T01_TMP/scratch` because `$T01_TMP/scratch/.simple-workflow/`
# has no `backlog/`. The fallback prints `$1` (the start dir) which is
# `$T01_TMP/scratch/child`, NOT `$T01_TMP/scratch`. Wrap in set +e /
# set -e because the function returns 1 on the fallback path (no anchor
# found anywhere on the walk) and would otherwise abort the script.
set +e
out="$( _psf_repo_root "$T01_TMP/scratch/child" )"
set -e
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$out" != "$T01_TMP/scratch" ]; then
  echo -e "  ${GREEN}PASS${NC} T-01 AC-6: _psf_repo_root does not promote empty .simple-workflow/"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} T-01 AC-6: _psf_repo_root falsely returned \$T01_TMP/scratch ($out)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# ---------------------------------------------------------------------------
# Section 2-bis: tier-3 BSD awk regression for parse_phase_status /
# parse_ticket_statuses. These functions previously used the gawk-only
# 3-arg `match($0, regex, m)` form in their awk fallback, which silently
# failed under macOS's stock /usr/bin/awk. The regression test forces
# tier-3 by mocking _psf_have to disable yq + python3 tiers, then pins
# `awk` resolution to /usr/bin/awk via PATH so any future re-introduction
# of gawk-only syntax fails CI on macOS hosts.
# ---------------------------------------------------------------------------
echo ""
echo "--- tier-3 BSD awk regression (parse_phase_status / parse_ticket_statuses) ---"

# Save and override _psf_have so the yq and python3 tiers report unavailable
# even when the host has them installed.
_psf_have_saved="$(declare -f _psf_have)"
_psf_have() {
  case "$1" in
    yq|python3) return 1 ;;
    *) command -v "$1" >/dev/null 2>&1 ;;
  esac
}

# Save PATH and restrict to /usr/bin:/bin so `awk` resolves to BSD awk on
# macOS (and to whichever awk is at /usr/bin on Linux — both lack gawk's
# 3-arg match()).
PATH_SAVED="$PATH"
PATH="/usr/bin:/bin"

# 2-bis.1: parse_phase_status — completed (BSD awk).
out="$(parse_phase_status "$PSF_TMP/phase-state.yaml" scout)"
assert_eq "tier-3 BSD awk: parse_phase_status scout -> completed" "completed" "$out"

# 2-bis.2: parse_phase_status — in_progress (BSD awk).
out="$(parse_phase_status "$PSF_TMP/phase-state.yaml" impl)"
assert_eq "tier-3 BSD awk: parse_phase_status impl -> in_progress" "in_progress" "$out"

# 2-bis.3: parse_phase_status — pending (BSD awk).
out="$(parse_phase_status "$PSF_TMP/phase-state.yaml" ship)"
assert_eq "tier-3 BSD awk: parse_phase_status ship -> pending" "pending" "$out"

# 2-bis.4: parse_phase_status — missing phase (BSD awk).
out="$(parse_phase_status "$PSF_TMP/phase-state.yaml" nonexistent)"
assert_eq "tier-3 BSD awk: parse_phase_status nonexistent -> empty" "" "$out"

# 2-bis.5: parse_ticket_statuses — three statuses in order (BSD awk).
expected="completed
in_progress
pending"
actual="$(parse_ticket_statuses \
  "$PSF_TMP/.simple-workflow/backlog/briefs/active/example-slug/autopilot-state.yaml")"
assert_eq "tier-3 BSD awk: parse_ticket_statuses lists 3 statuses in order" "$expected" "$actual"

# 2-bis.6: parse_ticket_statuses — single failed ticket (BSD awk).
actual="$(parse_ticket_statuses \
  "$PSF_TMP/.simple-workflow/backlog/product_backlog/legacy-slug/autopilot-state.yaml")"
assert_eq "tier-3 BSD awk: parse_ticket_statuses single ticket -> failed" "failed" "$actual"

# 2-bis.7: parse_impl_next_action via tier-3 — gawk-free since v6.4.1.
# A phase-state.yaml with phases.impl.next_action exercises the same awk
# tier and would catch any future re-introduction of gawk-only syntax.
cat >"$PSF_TMP/phase-state-with-next-action.yaml" <<'YAML'
version: 1
phases:
  scout:
    status: completed
  impl:
    status: in_progress
    next_action: read-and-resume-impl-step-18
  ship:
    status: pending
YAML
out="$(parse_impl_next_action "$PSF_TMP/phase-state-with-next-action.yaml")"
assert_eq "tier-3 BSD awk: parse_impl_next_action -> read-and-resume-impl-step-18" \
  "read-and-resume-impl-step-18" "$out"

# Restore PATH and _psf_have so subsequent sections see the host environment.
PATH="$PATH_SAVED"
unset -f _psf_have
eval "$_psf_have_saved"
unset _psf_have_saved PATH_SAVED

echo ""

# ---------------------------------------------------------------------------
# Section 3: jsonl-tail-audit.sh
# ---------------------------------------------------------------------------
echo "--- jsonl-tail-audit.sh ---"

JTA_PATH="$LIB_DIR/jsonl-tail-audit.sh"
JTA_FIXTURES="$REPO_DIR/tests/fixtures/jsonl-tail-audit"
JTA_F1="$JTA_FIXTURES/fixture-1-empty.jsonl"
JTA_F2="$JTA_FIXTURES/fixture-2-3-skill-uses.jsonl"
JTA_F3="$JTA_FIXTURES/fixture-3-overflow.jsonl"
JTA_F4="$JTA_FIXTURES/fixture-4-mixed-tools.jsonl"

# Capture function names in current shell BEFORE sourcing the lib (for Negative AC-1).
jta_before_source_funcs="$(declare -F | awk '{print $3}' | sort -u)"

# AC-1: file exists and shebang is correct
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if test -f "$JTA_PATH"; then
  echo -e "  ${GREEN}PASS${NC} jsonl-tail-audit.sh exists"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} jsonl-tail-audit.sh not found at $JTA_PATH"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

shebang_count="$(grep -E '^#!/usr/bin/env bash$' "$JTA_PATH" | wc -l | tr -d ' ')"
assert_eq "AC-1: jsonl-tail-audit.sh has exactly one shebang line" "1" "$shebang_count"

# AC-2: four public functions are declared after sourcing
# shellcheck disable=SC1090
source "$JTA_PATH"
jta_declare_out="$(bash -c "source '$JTA_PATH' && declare -F jsonl_tail_skill_uses jsonl_tail_agent_uses jsonl_tail_tool_use_count jsonl_tail_most_recent_skill" 2>/dev/null)"
set +e
bash -c "source '$JTA_PATH' && declare -F jsonl_tail_skill_uses jsonl_tail_agent_uses jsonl_tail_tool_use_count jsonl_tail_most_recent_skill" >/dev/null 2>&1
jta_ac2_exit=$?
set -e
assert_exit_zero "AC-2: sourcing and declare -F four functions exits 0" "$jta_ac2_exit"
jta_declare_lines="$(printf '%s\n' "$jta_declare_out" | count_matches '.')"
assert_eq "AC-2: declare -F emits exactly 4 lines" "4" "$jta_declare_lines"

# AC-3: jsonl_tail_skill_uses on empty fixture produces zero lines, exits 0
set +e
jta_ac3_out="$(jsonl_tail_skill_uses "$JTA_F1")"
jta_ac3_exit=$?
set -e
assert_exit_zero "AC-3: jsonl_tail_skill_uses on empty fixture exits 0" "$jta_ac3_exit"
jta_ac3_lines="$(printf '%s' "$jta_ac3_out" | grep -c . || true)"
assert_eq "AC-3: jsonl_tail_skill_uses on empty fixture produces 0 lines" "0" "$jta_ac3_lines"

# AC-4: jsonl_tail_skill_uses on 3-skill fixture returns skills in order
set +e
jta_ac4_out="$(jsonl_tail_skill_uses "$JTA_F2")"
jta_ac4_exit=$?
set -e
assert_exit_zero "AC-4: jsonl_tail_skill_uses on 3-skill fixture exits 0" "$jta_ac4_exit"
jta_ac4_expected="simple-workflow:scout
simple-workflow:impl
simple-workflow:ship"
assert_eq "AC-4: jsonl_tail_skill_uses produces scout/impl/ship in order" "$jta_ac4_expected" "$jta_ac4_out"

# AC-5: overflow fixture — tail-500 sees zero Skill records; bash -x trace has tail -n 500
set +e
jta_ac5_out="$(jsonl_tail_skill_uses "$JTA_F3")"
jta_ac5_exit=$?
set -e
assert_exit_zero "AC-5: jsonl_tail_skill_uses on overflow fixture exits 0" "$jta_ac5_exit"
jta_ac5_lines="$(printf '%s' "$jta_ac5_out" | grep -c . || true)"
assert_eq "AC-5: overflow fixture returns 0 Skill lines in tail-500 window" "0" "$jta_ac5_lines"

JTA_TRACE_TMP="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -rf '$PSF_TMP' '$NEG_TMP' '$JTA_TRACE_TMP'" EXIT
bash -x -c "source '$JTA_PATH'; jsonl_tail_skill_uses '$JTA_F3'" >/dev/null 2>"$JTA_TRACE_TMP" || true

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -q 'tail -n 500' "$JTA_TRACE_TMP"; then
  echo -e "  ${GREEN}PASS${NC} AC-5: bash -x trace contains 'tail -n 500'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC-5: bash -x trace does NOT contain 'tail -n 500'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'tail -n [6-9][0-9]{2,}|tail -n [0-9]{4,}' "$JTA_TRACE_TMP"; then
  echo -e "  ${RED}FAIL${NC} AC-5: bash -x trace contains tail with limit >= 600"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  echo -e "  ${GREEN}PASS${NC} AC-5: bash -x trace has no tail limit >= 600"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'cat [^|]*\.jsonl|cat \*\.jsonl' "$JTA_TRACE_TMP"; then
  echo -e "  ${RED}FAIL${NC} AC-5: bash -x trace contains cat *.jsonl"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  echo -e "  ${GREEN}PASS${NC} AC-5: bash -x trace has no cat *.jsonl"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# AC-6: jsonl_tail_tool_use_count on mixed fixture
set +e
jta_ac6_skill="$(jsonl_tail_tool_use_count "$JTA_F4" "Skill")"
jta_ac6_skill_exit=$?
jta_ac6_agent="$(jsonl_tail_tool_use_count "$JTA_F4" "Agent")"
jta_ac6_agent_exit=$?
jta_ac6_bash="$(jsonl_tail_tool_use_count "$JTA_F4" "Bash")"
jta_ac6_bash_exit=$?
set -e
assert_exit_zero "AC-6: jsonl_tail_tool_use_count Skill exits 0" "$jta_ac6_skill_exit"
assert_exit_zero "AC-6: jsonl_tail_tool_use_count Agent exits 0" "$jta_ac6_agent_exit"
assert_exit_zero "AC-6: jsonl_tail_tool_use_count Bash exits 0" "$jta_ac6_bash_exit"
assert_eq "AC-6: Skill count is 5" "5" "$jta_ac6_skill"
assert_eq "AC-6: Agent count is 3" "3" "$jta_ac6_agent"
assert_eq "AC-6: Bash count is 12" "12" "$jta_ac6_bash"

# AC-7: jsonl_tail_most_recent_skill
set +e
jta_ac7_ship="$(jsonl_tail_most_recent_skill "$JTA_F2")"
jta_ac7_ship_exit=$?
jta_ac7_empty="$(jsonl_tail_most_recent_skill "$JTA_F1")"
jta_ac7_empty_exit=$?
set -e
assert_exit_zero "AC-7: jsonl_tail_most_recent_skill on 3-skill fixture exits 0" "$jta_ac7_ship_exit"
assert_exit_zero "AC-7: jsonl_tail_most_recent_skill on empty fixture exits 0" "$jta_ac7_empty_exit"
assert_eq "AC-7: most recent skill on 3-skill fixture is simple-workflow:ship" "simple-workflow:ship" "$jta_ac7_ship"
assert_eq "AC-7: most recent skill on empty fixture is empty" "" "$jta_ac7_empty"

# Negative AC-1: exactly 5 new public functions after sourcing — the four
# declared in v6.2.1 (jsonl_tail_skill_uses, jsonl_tail_agent_uses,
# jsonl_tail_tool_use_count, jsonl_tail_most_recent_skill) plus
# transcript_contains_skill_invocation added in v6.4.0 for
# impl-checkpoint-guard.sh's 5-AND condition (e).
# Use jta_before_source_funcs (captured before sourcing the lib above) and compare
# against what the current shell declares now (after sourcing the lib).
jta_after_source_funcs="$(declare -F | awk '{print $3}' | sort -u)"
jta_new_public_funcs="$(comm -13 <(printf '%s\n' "$jta_before_source_funcs") <(printf '%s\n' "$jta_after_source_funcs") | grep -vE '^_' || true)"
jta_new_public_count="$(printf '%s\n' "$jta_new_public_funcs" | grep -c '[^[:space:]]' || true)"
assert_eq "Negative-AC-1: exactly 5 new public functions (no _ prefix)" "5" "$jta_new_public_count"

# Negative AC-2: no tail -n with variable expansion in lib
# grep returns 1 on no match (the success path here), which would trip
# `set -euo pipefail`. Wrap each pipeline in `set +e ... set -e` so the
# zero-match case stays a PASS rather than aborting the script.
set +e
neg_ac2_count="$(grep -nE 'tail[[:space:]]+[^|]*-n[[:space:]]+\$' "$JTA_PATH" | wc -l | tr -d ' ')"
neg_ac3_count="$(grep -nE '\bcat[[:space:]]+[^|]*\.jsonl|\bawk[[:space:]]+.*\.jsonl|\bsed[[:space:]]+.*\.jsonl|tail[[:space:]]+[^-|]*\.jsonl[[:space:]]*$' "$JTA_PATH" | wc -l | tr -d ' ')"
neg_ac4_count="$(grep -rnE 'skills/|agents/' "$JTA_PATH" | wc -l | tr -d ' ')"
set -e
assert_eq "Negative-AC-2: no tail -n variable expansion in lib" "0" "$neg_ac2_count"

# Negative AC-3: no unbounded JSONL read paths in lib
assert_eq "Negative-AC-3: no unbounded JSONL read paths in lib" "0" "$neg_ac3_count"

# Negative AC-4: no skills/ or agents/ path references in lib
assert_eq "Negative-AC-4: no skills/ or agents/ path references in lib" "0" "$neg_ac4_count"

# ---------------------------------------------------------------------------
# Cross-session staleness window (5000-line tail) for
# transcript_contains_skill_invocation. The window is wider than the
# 500-line literal used by the other helpers because the /impl Skill
# invocation that triggered an /audit handoff can be hundreds-to-thousands
# of records back in long autopilot runs. Generate large transcripts
# inline via awk (~10 ms total) instead of checking 2 MB of fixtures
# into the repo. `yes | head` is avoided here because SIGPIPE under
# `set -o pipefail` would abort the test script.
# ---------------------------------------------------------------------------
JTA_NOISE='{"type":"assistant","uuid":"noise","message":{"role":"assistant","content":[{"type":"text","text":"noise"}]}}'
JTA_SKILL_IMPL='{"type":"assistant","uuid":"impl-skill","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu-impl","name":"Skill","input":{"skill":"simple-workflow:impl","args":""}}]}}'

JTA_F5_TMP="$(mktemp)"
JTA_F6_TMP="$(mktemp)"
JTA_TRACE_X="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -rf '$PSF_TMP' '$NEG_TMP' '$JTA_TRACE_TMP' '$JTA_F5_TMP' '$JTA_F6_TMP' '$JTA_TRACE_X'" EXIT

# Within-window fixture: 4900-line transcript with Skill(impl) at line 4500.
# Entire file fits inside the 5000-line tail window — detection MUST succeed.
awk -v n=4499 -v line="$JTA_NOISE" 'BEGIN { for (i=0; i<n; i++) print line }' > "$JTA_F5_TMP"
printf '%s\n' "$JTA_SKILL_IMPL" >> "$JTA_F5_TMP"
awk -v n=400 -v line="$JTA_NOISE" 'BEGIN { for (i=0; i<n; i++) print line }' >> "$JTA_F5_TMP"

# Overflow fixture: 6000-line transcript with Skill(impl) at line 100.
# tail -n 5000 covers lines 1001-6000, so the Skill record at line 100 is
# OUTSIDE the window — detection MUST fail (returns 1).
awk -v n=99 -v line="$JTA_NOISE" 'BEGIN { for (i=0; i<n; i++) print line }' > "$JTA_F6_TMP"
printf '%s\n' "$JTA_SKILL_IMPL" >> "$JTA_F6_TMP"
awk -v n=5900 -v line="$JTA_NOISE" 'BEGIN { for (i=0; i<n; i++) print line }' >> "$JTA_F6_TMP"

# AC-CS-1: within-window detection succeeds.
set +e
transcript_contains_skill_invocation "simple-workflow:impl" "$JTA_F5_TMP"
jta_cs1_exit=$?
set -e
assert_exit_zero "AC-CS-1: transcript_contains_skill_invocation finds Skill(impl) in 4900-line transcript (within 5000 window)" "$jta_cs1_exit"

# AC-CS-2: overflow detection fails (skill at line 100 is outside the
# last-5000 window of a 6000-line transcript).
set +e
transcript_contains_skill_invocation "simple-workflow:impl" "$JTA_F6_TMP"
jta_cs2_exit=$?
set -e
assert_exit_nonzero "AC-CS-2: transcript_contains_skill_invocation does NOT find Skill(impl) at line 100 of 6000-line transcript (outside 5000 window)" "$jta_cs2_exit"

# AC-CS-3: bash -x trace shows tail -n 5000 (the new cross-session window),
# distinct from the 500-line literal used by _jta_iter_tool_uses callers.
bash -xc "source '$JTA_PATH' && transcript_contains_skill_invocation 'simple-workflow:impl' '$JTA_F5_TMP'" 2>"$JTA_TRACE_X" >/dev/null
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'tail -n[[:space:]]+5000' "$JTA_TRACE_X"; then
  echo -e "  ${GREEN}PASS${NC} AC-CS-3: bash -x trace contains 'tail -n 5000'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC-CS-3: bash -x trace does NOT contain 'tail -n 5000'"
  echo -e "         (expected the new _JTA_CROSS_SESSION_TAIL constant in transcript_contains_skill_invocation)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AC-CS-4 (v6.4.3 / F-3'): tier-2 (python3 + json) regression. The previous
# heredoc form `python3 - "$arg" <<'PY' ... PY` overrode python3's stdin
# with the heredoc body, so `for line in sys.stdin` iterated the python
# source itself and the tier always returned 1. v6.4.3 routes the source
# through `python3 -c "$src"` so stdin stays the `tail | ...` pipe.
#
# To exercise tier-2 deterministically we need to disable tier-1 (jq) for
# the call. We do that by spawning a subshell with a stripped PATH that
# contains python3 + tail + cat (everything tier-2 needs) but lacks jq.
# A symlinked bin dir is the smallest hermetic approach: each link points
# to the absolute resolution of the host binary, and PATH points only at
# that dir for the duration of the subshell.
#
# IMPORTANT: do NOT symlink `grep` into `JTA_TIER2_BIN`. Today's
# `transcript_contains_skill_invocation` tier-2 ends with `return 0` /
# `return 1` so tier-3 never runs once tier-2 is reached, and adding
# grep would not silently change THIS test's outcome. The omission is
# a forward-looking hermetic seal: if a future refactor relaxes tier-2
# into a fall-through-on-failure shape (e.g. for graceful degradation),
# a stray grep here would let tier-3 mask a tier-2 regression. Keeping
# the bin dir minimal pins what tier this test actually exercises.
JTA_TIER2_BIN="$(mktemp -d)"
JTA_TIER2_TRANSCRIPT="$(mktemp)"
JTA_TIER2_TRANSCRIPT_NEG="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -rf '$PSF_TMP' '$NEG_TMP' '$JTA_TRACE_TMP' '$JTA_F5_TMP' '$JTA_F6_TMP' '$JTA_TRACE_X' '$JTA_TIER2_BIN' '$JTA_TIER2_TRANSCRIPT' '$JTA_TIER2_TRANSCRIPT_NEG'" EXIT

# Wire the tier-2-only PATH (python3 + tail + cat exist; jq does not).
for _bin in python3 tail cat; do
  if _resolved="$(command -v "$_bin")" && [ -n "$_resolved" ]; then
    ln -sf "$_resolved" "$JTA_TIER2_BIN/$_bin"
  fi
done
unset _bin _resolved

# Positive transcript: contains a Skill(simple-workflow:impl) tool_use record.
printf '%s\n' '{"type":"assistant","uuid":"impl-skill","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu-impl","name":"Skill","input":{"skill":"simple-workflow:impl","args":""}}]}}' \
  > "$JTA_TIER2_TRANSCRIPT"
# Negative transcript: noise only, no Skill records.
printf '%s\n' '{"type":"assistant","uuid":"noise","message":{"role":"assistant","content":[{"type":"text","text":"noise"}]}}' \
  > "$JTA_TIER2_TRANSCRIPT_NEG"

set +e
# NOTE: invoke bash via its absolute path. The PATH override below points
# only at the symlink dir (no jq), so a bare `bash` would not be found by
# the parent shell's command lookup if the parent is zsh / not bash.
JTA_BASH_BIN="$(command -v bash)"
PATH="$JTA_TIER2_BIN" "$JTA_BASH_BIN" -c "source '$JTA_PATH' && transcript_contains_skill_invocation 'simple-workflow:impl' '$JTA_TIER2_TRANSCRIPT'" >/dev/null 2>&1
jta_cs4_pos_exit=$?
PATH="$JTA_TIER2_BIN" "$JTA_BASH_BIN" -c "source '$JTA_PATH' && transcript_contains_skill_invocation 'simple-workflow:impl' '$JTA_TIER2_TRANSCRIPT_NEG'" >/dev/null 2>&1
jta_cs4_neg_exit=$?
set -e
assert_exit_zero "AC-CS-4 (F-3'): tier-2 finds Skill(impl) when jq absent (positive transcript)" "$jta_cs4_pos_exit"
assert_exit_nonzero "AC-CS-4 (F-3'): tier-2 returns 1 when jq absent and no Skill record (negative transcript)" "$jta_cs4_neg_exit"

echo ""

# ---------------------------------------------------------------------------
# Section 3-bis (v6.4.3 / F-1'): tier-3 BSD awk regression for
# post-phase-checkpoint.sh::_pphc_entry_already_present. The function
# previously used the gawk-only 3-arg `match($0, regex, m)` form in its
# pure-shell idempotency probe. Under BSD awk + no PyYAML + no yq the
# probe always returned "not present" and `runtime_metrics:` rows were
# duplicated on every reentry. v6.4.3 replaces the 3-arg form with POSIX
# `sub()` strip-by-prefix; this micro-test exercises the function
# directly under BSD awk so any future re-introduction of gawk-only
# syntax fails CI.
#
# Test shape: write a state file with one canonical runtime_metrics
# entry, force tier-3 by stripping yq + python3 + jq from PATH, and
# assert (a) probing the present triple returns 0 and (b) probing an
# absent triple returns non-zero.
# ---------------------------------------------------------------------------
echo "--- tier-3 BSD awk regression (post-phase-checkpoint::_pphc_entry_already_present) ---"

PPHC_TIER3_TMP="$(mktemp -d)"
PPHC_TIER3_BIN="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$PSF_TMP' '$NEG_TMP' '$JTA_TRACE_TMP' '$JTA_F5_TMP' '$JTA_F6_TMP' '$JTA_TRACE_X' '$JTA_TIER2_BIN' '$JTA_TIER2_TRANSCRIPT' '$JTA_TIER2_TRANSCRIPT_NEG' '$PPHC_TIER3_TMP' '$PPHC_TIER3_BIN'" EXIT

# Build a tier-3-only PATH: awk + grep + tail + cat + dirname + basename
# present, but yq + python3 + jq absent so the function falls through to
# the awk fallback unconditionally. /usr/bin/awk on macOS is BSD awk.
for _bin in awk grep tail cat dirname basename printf sed mktemp date uname tr; do
  if _resolved="$(command -v "$_bin")" && [ -n "$_resolved" ]; then
    ln -sf "$_resolved" "$PPHC_TIER3_BIN/$_bin"
  fi
done
unset _bin _resolved

# Canonical runtime_metrics entry — three keys per element with the same
# 4-space indent the writer emits.
cat > "$PPHC_TIER3_TMP/state.yaml" <<'YAML'
runtime_metrics:
  - boundary: phase_complete
    stop_reason: null
    ticket_id: T-001
    phase: scout
    timestamp: 2026-05-10T00:00:00Z
    cache_creation_input_tokens: null
    cache_read_input_tokens: null
    input_tokens: null
    consecutive_stop_blocks: null
YAML

# Source the hook script's helper; we only want the function definition
# without firing the top-level main flow. Wrap in a subshell that exits
# before the main flow runs by sourcing into a fresh shell process and
# calling the function directly via bash -c.
PPHC_HOOK="$REPO_DIR/hooks/post-phase-checkpoint.sh"

# Spawn the call under the tier-3 PATH so awk resolves to /usr/bin/awk
# (BSD on macOS) and yq / python3 / jq are NOT visible. We inline the
# function definition extracted from the hook to avoid running the hook's
# top-level main flow (which reads stdin via `cat` and would block).
# NOTE: invoke bash via its absolute path because the restricted PATH
# below does not contain bash itself (parent zsh would otherwise fail to
# resolve the command name).
PPHC_BASH_BIN="$(command -v bash)"
set +e
PATH="$PPHC_TIER3_BIN" "$PPHC_BASH_BIN" -c '
  set -uo pipefail
  _pphc_have() { command -v "$1" >/dev/null 2>&1; }
  # Source just the function definition from the hook by sed-extracting
  # it. This is fragile across hook revisions but documented as the
  # intended shape: the function spans from `_pphc_entry_already_present()`
  # through the matching close brace at column 1.
  fn_src=$(sed -n "/^_pphc_entry_already_present()/,/^}$/p" "'"$PPHC_HOOK"'")
  eval "$fn_src"
  _pphc_entry_already_present "'"$PPHC_TIER3_TMP/state.yaml"'" T-001 scout phase_complete
' >/dev/null 2>&1
pphc_present_exit=$?
PATH="$PPHC_TIER3_BIN" "$PPHC_BASH_BIN" -c '
  set -uo pipefail
  _pphc_have() { command -v "$1" >/dev/null 2>&1; }
  fn_src=$(sed -n "/^_pphc_entry_already_present()/,/^}$/p" "'"$PPHC_HOOK"'")
  eval "$fn_src"
  _pphc_entry_already_present "'"$PPHC_TIER3_TMP/state.yaml"'" T-002 impl phase_failed
' >/dev/null 2>&1
pphc_absent_exit=$?
set -e

assert_exit_zero "tier-3 BSD awk: _pphc_entry_already_present detects present triple" "$pphc_present_exit"
assert_exit_nonzero "tier-3 BSD awk: _pphc_entry_already_present returns non-zero for absent triple" "$pphc_absent_exit"

echo ""

# ---------------------------------------------------------------------------
# Section 4: state-authority.sh
# ---------------------------------------------------------------------------
echo "--- state-authority.sh ---"

SA_PATH="$LIB_DIR/state-authority.sh"

# AC-1: file exists with bash shebang exactly once
[ -f "$SA_PATH" ] && sa_ac1_file_exit=0 || sa_ac1_file_exit=1
assert_exit_zero "AC-1: state-authority.sh file exists" "$sa_ac1_file_exit"
set +e
sa_ac1_shebang_count="$(grep -cE '^#!/usr/bin/env bash$' "$SA_PATH")"
set -e
assert_eq "AC-1: shebang line present exactly once" "1" "$sa_ac1_shebang_count"

# AC-2: three public functions + HOOK_OWNED_FIELDS associative array
sa_ac2_funcs_out="$(bash -c "source '$SA_PATH' && declare -F resolve_active_state_file is_hook_owned_field state_field_change_blocked")"
sa_ac2_func_count="$(printf '%s\n' "$sa_ac2_funcs_out" | wc -l | tr -d ' ')"
assert_eq "AC-2: declare -F emits exactly three lines" "3" "$sa_ac2_func_count"
sa_ac2_arr_head="$(bash -c "source '$SA_PATH' && declare -p HOOK_OWNED_FIELDS" | cut -c1-29)"
assert_eq "AC-2: HOOK_OWNED_FIELDS declared as associative array" \
  "declare -A HOOK_OWNED_FIELDS=" "$sa_ac2_arr_head"

# AC-3: resolve_active_state_file in briefs/active
SA_T3="$(mktemp -d)"
mkdir -p "$SA_T3/.simple-workflow/backlog/briefs/active/test-slug"
touch "$SA_T3/.simple-workflow/backlog/briefs/active/test-slug/autopilot-state.yaml"
sa_t3_canon="$(cd "$SA_T3" && pwd -P)"
sa_ac3_out="$(bash -c "source '$SA_PATH' && resolve_active_state_file '$SA_T3'")"
assert_eq "AC-3: emits briefs/active state path" \
  "$sa_t3_canon/.simple-workflow/backlog/briefs/active/test-slug/autopilot-state.yaml" \
  "$sa_ac3_out"

# AC-4: done-completed adoption (inline YAML flow mapping)
SA_T4="$(mktemp -d)"
mkdir -p "$SA_T4/.simple-workflow/backlog/briefs/done/test-slug"
printf 'phases:\n  scout: {status: completed}\n  impl: {status: completed}\n  ship: {status: completed}\n' \
  > "$SA_T4/.simple-workflow/backlog/briefs/done/test-slug/autopilot-state.yaml"
sa_t4_canon="$(cd "$SA_T4" && pwd -P)"
sa_ac4_out="$(bash -c "source '$SA_PATH' && resolve_active_state_file '$SA_T4'")"
assert_eq "AC-4: emits done-completed state path (inline YAML)" \
  "$sa_t4_canon/.simple-workflow/backlog/briefs/done/test-slug/autopilot-state.yaml" \
  "$sa_ac4_out"

# AC-5: done-incomplete rejection
SA_T5="$(mktemp -d)"
mkdir -p "$SA_T5/.simple-workflow/backlog/briefs/done/test-slug"
printf 'phases:\n  scout: {status: completed}\n  impl: {status: completed}\n  ship: {status: in-progress}\n' \
  > "$SA_T5/.simple-workflow/backlog/briefs/done/test-slug/autopilot-state.yaml"
sa_ac5_out="$(bash -c "source '$SA_PATH' && resolve_active_state_file '$SA_T5'")"
assert_eq "AC-5: rejects done-incomplete (empty stdout)" "" "$sa_ac5_out"

# AC-6: HOOK_OWNED_FIELDS empty by default
sa_ac6_count="$(bash -c "source '$SA_PATH' && echo \${#HOOK_OWNED_FIELDS[@]}")"
assert_eq "AC-6: registry empty by default" "0" "$sa_ac6_count"

# AC-7: is_hook_owned_field returns 1 on unknown
set +e
bash -c "source '$SA_PATH' && is_hook_owned_field .anything" >/dev/null 2>&1
sa_ac7_exit=$?
set -e
assert_exit_nonzero "AC-7: unknown key exits 1" "$sa_ac7_exit"

# AC-8: is_hook_owned_field exact match (3 sub-cases)
# Uses a neutral test key (.test_owned_key) to avoid Negative-AC-3 coupling.
set +e
bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.test_owned_key']=x; is_hook_owned_field .test_owned_key" >/dev/null 2>&1
sa_ac8_match_exit=$?
bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.test_owned_key']=x; is_hook_owned_field .test_owned" >/dev/null 2>&1
sa_ac8_short_exit=$?
bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.test_owned_key']=x; is_hook_owned_field .test_owned_key.extra" >/dev/null 2>&1
sa_ac8_extra_exit=$?
set -e
assert_exit_zero "AC-8: exact match exits 0" "$sa_ac8_match_exit"
assert_exit_nonzero "AC-8: shorter prefix exits 1" "$sa_ac8_short_exit"
assert_exit_nonzero "AC-8: extra suffix exits 1" "$sa_ac8_extra_exit"

# AC-9: is_hook_owned_field glob single segment (4 sub-cases)
set +e
bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.phases.*.completed_at']=x; is_hook_owned_field .phases.scout.completed_at" >/dev/null 2>&1
sa_ac9_scout_exit=$?
bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.phases.*.completed_at']=x; is_hook_owned_field .phases.impl.completed_at" >/dev/null 2>&1
sa_ac9_impl_exit=$?
bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.phases.*.completed_at']=x; is_hook_owned_field .phases.completed_at" >/dev/null 2>&1
sa_ac9_missing_exit=$?
bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.phases.*.completed_at']=x; is_hook_owned_field .phases.scout.sub.completed_at" >/dev/null 2>&1
sa_ac9_dotted_exit=$?
set -e
assert_exit_zero "AC-9: glob matches scout segment" "$sa_ac9_scout_exit"
assert_exit_zero "AC-9: glob matches impl segment" "$sa_ac9_impl_exit"
assert_exit_nonzero "AC-9: glob requires segment present" "$sa_ac9_missing_exit"
assert_exit_nonzero "AC-9: glob excludes dotted segments" "$sa_ac9_dotted_exit"

# AC-10: state_field_change_blocked false on empty registry (3+ pairs)
set +e
bash -c "source '$SA_PATH'; state_field_change_blocked /tmp/x 'foo: 1' 'foo: 2'" >/dev/null 2>&1
sa_ac10_a_exit=$?
bash -c "source '$SA_PATH'; state_field_change_blocked /tmp/x '' 'foo: 1'" >/dev/null 2>&1
sa_ac10_b_exit=$?
bash -c "source '$SA_PATH'; state_field_change_blocked /tmp/x 'a: 1' 'a: 1'" >/dev/null 2>&1
sa_ac10_c_exit=$?
set -e
assert_exit_nonzero "AC-10: empty registry allows pair A" "$sa_ac10_a_exit"
assert_exit_nonzero "AC-10: empty registry allows pair B" "$sa_ac10_b_exit"
assert_exit_nonzero "AC-10: empty registry allows pair C" "$sa_ac10_c_exit"

# AC-11: state_field_change_blocked true on registered exact key change
# Uses a neutral test key (.test_owned_key) to avoid Negative-AC-3 coupling.
set +e
bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.test_owned_key']=x; state_field_change_blocked /tmp/x 'test_owned_key: true' 'test_owned_key: false'" >/dev/null 2>&1
sa_ac11_exit=$?
set -e
assert_exit_zero "AC-11: registered exact key change blocked" "$sa_ac11_exit"

# AC-12: state_field_change_blocked true on registered glob key change
set +e
bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.phases.*.completed_at']=x; state_field_change_blocked /tmp/x \$'phases:\n  scout:\n    completed_at: 2026-05-03T04:46:00Z' \$'phases:\n  scout:\n    completed_at: 2026-05-03T04:00:00Z'" >/dev/null 2>&1
sa_ac12_exit=$?
set -e
assert_exit_zero "AC-12: registered glob key change blocked" "$sa_ac12_exit"

# AC-13: state_field_change_blocked false on initial-set
# Uses a neutral test key (.test_owned_key) to avoid Negative-AC-3 coupling.
set +e
bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.test_owned_key']=x; state_field_change_blocked /tmp/x 'other: foo' 'test_owned_key: true'" >/dev/null 2>&1
sa_ac13_exit=$?
set -e
assert_exit_nonzero "AC-13: initial set is allowed" "$sa_ac13_exit"

# Negative AC-1: exactly 3 new public functions + HOOK_OWNED_FIELDS public var
sa_neg_ac1_before_funcs="$(declare -F | awk '{print $3}' | sort -u)"
# shellcheck disable=SC1090
source "$SA_PATH"
sa_neg_ac1_after_funcs="$(declare -F | awk '{print $3}' | sort -u)"
sa_neg_ac1_new_funcs="$(comm -13 <(printf '%s\n' "$sa_neg_ac1_before_funcs") <(printf '%s\n' "$sa_neg_ac1_after_funcs") | grep -vE '^_' || true)"
sa_neg_ac1_new_func_count="$(printf '%s\n' "$sa_neg_ac1_new_funcs" | grep -c '[^[:space:]]' || true)"
assert_eq "Negative-AC-1: exactly 3 new public functions (no _ prefix)" "3" "$sa_neg_ac1_new_func_count"

# Negative AC-2: no per-key insertions in the lib
set +e
sa_neg_ac2_count="$(grep -cnE '^HOOK_OWNED_FIELDS\[' "$SA_PATH")"
set -e
assert_eq "Negative-AC-2: no registry pre-population" "0" "$sa_neg_ac2_count"

# Negative AC-3: no scheduler-coupling identifiers in the lib file.
# Pattern assembled from hex parts to prevent this script itself from matching.
_p1="$(printf 'Cron\x43reate')"
_p2="$(printf 'cron\x5fhandoff')"
_p3="$(printf 'cron\x2dcreate')"
_p4="$(printf 'cron\x2dhandoff')"
_p5="$(printf '/.cron\x2dhandoff-pending')"
_SA_NEG3_PAT="${_p1}|${_p2}|${_p3}|${_p4}|${_p5}"
set +e
sa_neg_ac3_lib_count="$(grep -cnE "$_SA_NEG3_PAT" "$SA_PATH")"
set -e
assert_eq "Negative-AC-3: no scheduler-coupling identifiers in lib" "0" "$sa_neg_ac3_lib_count"
unset _SA_NEG3_PAT _p1 _p2 _p3 _p4 _p5

# Negative AC-5: no skills/ or agents/ path references in the lib
set +e
sa_neg_ac5_count="$(grep -cE 'skills/|agents/' "$SA_PATH")"
set -e
assert_eq "Negative-AC-5: no skills/ or agents/ path references in lib" "0" "$sa_neg_ac5_count"

# ---------------------------------------------------------------------------
# Section 4b: state-authority.sh hardening (v6.3.1)
# ---------------------------------------------------------------------------
echo ""
echo "--- state-authority.sh hardening (v6.3.1) ---"

# AC-A1 (F-H1, ERE escape): with a registry key whose leaf contains a
# non-glob POSIX-ERE meta (`+`), state_field_change_blocked must NOT match
# unrelated lines whose key happens to satisfy the un-escaped regex
# `value+:` (i.e. "valu" + one-or-more "e"). Five distinct unrelated
# old/new pairs all expected to return exit 1 (allow).
# `+` is intentionally ERE-meta-only — F-M1 rejects glob meta `[]?{}` so
# we exercise F-H1 with an input the registry validator does NOT reject.
SA_F_H1_PAIRS=(
  "valu: stable|valu: changed"
  "valuee: foo|valuee: bar"
  "value: 1|value: 2"
  "valueee: stable|valueee: changed"
  "xyz_value: a|xyz_value: b"
)
for pair in "${SA_F_H1_PAIRS[@]}"; do
  old="${pair%%|*}"
  new="${pair##*|}"
  set +e
  bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.prefix.value+']=x; state_field_change_blocked /tmp/x '$old' '$new'" >/dev/null 2>&1
  sa_h1_exit=$?
  set -e
  assert_exit_nonzero "AC-A1 (F-H1): unrelated payload [$old] -> [$new] not falsely matched" \
    "$sa_h1_exit"
done

# Sanity contrast: a payload that DOES contain the literal escaped leaf
# `value+:` triggers the change-block, demonstrating the escape preserves
# the legitimate detection path.
set +e
bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.prefix.value+']=x; state_field_change_blocked /tmp/x 'value+: a' 'value+: b'" >/dev/null 2>&1
sa_h1_literal_exit=$?
set -e
assert_exit_zero "AC-A1 (F-H1): literal leaf 'value+:' still detected" "$sa_h1_literal_exit"

# AC-A2 (F-M1, registry rejection): keys containing glob meta other than
# `*` (e.g. `[`, `]`) are rejected at the first call to
# is_hook_owned_field with a stderr diagnostic and exit code 2.
set +e
sa_m1_stderr="$(bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.[abc].field']=x; is_hook_owned_field .a.field" 2>&1 >/dev/null)"
sa_m1_exit=$?
set -e
assert_eq "AC-A2 (F-M1): is_hook_owned_field exits 2 on bad registry key" "2" "$sa_m1_exit"
case "$sa_m1_stderr" in
  *'state-authority: registry key "'*'" contains glob meta'*) sa_m1_msg_ok=1 ;;
  *)                                                          sa_m1_msg_ok=0 ;;
esac
assert_eq "AC-A2 (F-M1): rejection diagnostic on stderr" "1" "$sa_m1_msg_ok"

# state_field_change_blocked also rejects (defense-in-depth).
set +e
bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.[abc].field']=x; state_field_change_blocked /tmp/x 'a: 1' 'a: 2'" >/dev/null 2>&1
sa_m1_sfcb_exit=$?
set -e
assert_eq "AC-A2 (F-M1): state_field_change_blocked also exits 2" "2" "$sa_m1_sfcb_exit"

# AC-B1 (F-M2): REPO_HOOKS_DIR removed from both safety hooks.
set +e
sa_m2_count="$(grep -cE 'REPO_HOOKS_DIR' "$REPO_DIR/hooks/pre-edit-safety.sh" "$REPO_DIR/hooks/pre-write-safety.sh" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')"
set -e
assert_eq "AC-B1 (F-M2): REPO_HOOKS_DIR absent from safety hooks" "0" "$sa_m2_count"
# Both hooks now source state-authority.sh from $SCRIPT_DIR/lib.
set +e
sa_m2_source_count="$(grep -cE 'source "\$SCRIPT_DIR/lib/state-authority.sh"' "$REPO_DIR/hooks/pre-edit-safety.sh" "$REPO_DIR/hooks/pre-write-safety.sh" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')"
set -e
assert_eq "AC-B1 (F-M2): both hooks source from \$SCRIPT_DIR/lib" "2" "$sa_m2_source_count"

# AC-B2 (F-DUP): the helper _sa_extract_leaf_value exists, and there is no
# inline `old_val=...grep -E...` on a single line in the public function.
sa_dup_helper_decl="$(bash -c "source '$SA_PATH' && declare -F _sa_extract_leaf_value" 2>/dev/null)"
case "$sa_dup_helper_decl" in
  *_sa_extract_leaf_value) sa_dup_helper_ok=1 ;;
  *)                       sa_dup_helper_ok=0 ;;
esac
assert_eq "AC-B2 (F-DUP): _sa_extract_leaf_value declared after sourcing" "1" "$sa_dup_helper_ok"
set +e
sa_dup_inline_count="$(grep -cE '^[[:space:]]*(old_val|new_val)=.*\| grep -E' "$SA_PATH")"
set -e
assert_eq "AC-B2 (F-DUP): no inline grep -E in old_val/new_val assignments" "0" "$sa_dup_inline_count"

# AC-B3 (F-RR): both libs document the divergence with an explicit F-RR
# header comment naming `.git` fallback and `pwd -P` canonicalisation as
# intentional in state-authority.sh.
sa_rr_state_count="$(grep -cE 'F-RR' "$SA_PATH" || true)"
sa_rr_psf_count="$(grep -cE 'F-RR' "$REPO_DIR/hooks/lib/parse-state-file.sh" || true)"
assert_exit_zero "AC-B3 (F-RR): state-authority.sh has F-RR divergence comment" \
  "$([ "$sa_rr_state_count" -ge 1 ] && echo 0 || echo 1)"
assert_exit_zero "AC-B3 (F-RR): parse-state-file.sh has F-RR divergence comment" \
  "$([ "$sa_rr_psf_count" -ge 1 ] && echo 0 || echo 1)"

# AC-C1 (F-BLANK): blank-out of an owned field (old_val present, new_val
# empty) is now a block, not an allow.
set +e
bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.test_field']=x; state_field_change_blocked /tmp/x 'test_field: completed' 'test_field: '" >/dev/null 2>&1
sa_blank_blockout_exit=$?
set -e
assert_exit_zero "AC-C1 (F-BLANK): blank-out of owned field is blocked" \
  "$sa_blank_blockout_exit"
# Initial-set with present-only-in-new (key absent in old) still allowed.
set +e
bash -c "source '$SA_PATH'; HOOK_OWNED_FIELDS['.test_field']=x; state_field_change_blocked /tmp/x 'other: x' 'test_field: completed'" >/dev/null 2>&1
sa_blank_initset_exit=$?
set -e
assert_exit_nonzero "AC-C1 (F-BLANK): initial-set still allowed (regression guard)" \
  "$sa_blank_initset_exit"

# AC-C2 (F-EXTGLOB): the parent shell's `extglob` state is preserved.
# Test from extglob-OFF parent: after sourcing + calling
# is_hook_owned_field, `shopt -p extglob` reports `shopt -u extglob`.
sa_extglob_after_off="$(bash -c "shopt -u extglob; source '$SA_PATH'; HOOK_OWNED_FIELDS['.test_x']=x; is_hook_owned_field .y >/dev/null 2>&1 || true; shopt -p extglob" 2>/dev/null || true)"
assert_eq "AC-C2 (F-EXTGLOB): extglob OFF preserved across is_hook_owned_field" \
  "shopt -u extglob" "$sa_extglob_after_off"
sa_extglob_after_on="$(bash -c "shopt -s extglob; source '$SA_PATH'; HOOK_OWNED_FIELDS['.test_x']=x; is_hook_owned_field .y >/dev/null 2>&1 || true; shopt -p extglob" 2>/dev/null || true)"
assert_eq "AC-C2 (F-EXTGLOB): extglob ON preserved across is_hook_owned_field" \
  "shopt -s extglob" "$sa_extglob_after_on"

# AC-D1 (F-QYAML, double-quoted): briefs/done/<slug>/autopilot-state.yaml
# with every phase status as `"completed"` -> resolve_active_state_file
# returns the absolute path.
SA_TQDQ="$(mktemp -d)"
mkdir -p "$SA_TQDQ/.simple-workflow/backlog/briefs/done/qyaml-dq"
printf 'phases:\n  scout: {status: "completed"}\n  impl: {status: "completed"}\n  ship: {status: "completed"}\n' \
  > "$SA_TQDQ/.simple-workflow/backlog/briefs/done/qyaml-dq/autopilot-state.yaml"
sa_qdq_canon="$(cd "$SA_TQDQ" && pwd -P)"
sa_qdq_out="$(bash -c "source '$SA_PATH' && resolve_active_state_file '$SA_TQDQ'")"
assert_eq "AC-D1 (F-QYAML, double-quoted): done-completed adopted" \
  "$sa_qdq_canon/.simple-workflow/backlog/briefs/done/qyaml-dq/autopilot-state.yaml" \
  "$sa_qdq_out"

# AC-D2 (F-COMMENT): block-form with `status: completed  # done` ->
# resolve_active_state_file returns the absolute path.
SA_TCMT="$(mktemp -d)"
mkdir -p "$SA_TCMT/.simple-workflow/backlog/briefs/done/comment-test"
printf 'phases:\n  scout:\n    status: completed  # done\n  impl:\n    status: completed\n  ship:\n    status: completed\n' \
  > "$SA_TCMT/.simple-workflow/backlog/briefs/done/comment-test/autopilot-state.yaml"
sa_cmt_canon="$(cd "$SA_TCMT" && pwd -P)"
sa_cmt_out="$(bash -c "source '$SA_PATH' && resolve_active_state_file '$SA_TCMT'")"
assert_eq "AC-D2 (F-COMMENT): block-form with trailing comment adopted" \
  "$sa_cmt_canon/.simple-workflow/backlog/briefs/done/comment-test/autopilot-state.yaml" \
  "$sa_cmt_out"

# AC-D3 (F-QYAML, single-quoted): briefs/done with single-quoted
# 'completed' -> resolve_active_state_file returns the absolute path.
SA_TQSQ="$(mktemp -d)"
mkdir -p "$SA_TQSQ/.simple-workflow/backlog/briefs/done/qyaml-sq"
printf "phases:\n  scout: {status: 'completed'}\n  impl: {status: 'completed'}\n  ship: {status: 'completed'}\n" \
  > "$SA_TQSQ/.simple-workflow/backlog/briefs/done/qyaml-sq/autopilot-state.yaml"
sa_qsq_canon="$(cd "$SA_TQSQ" && pwd -P)"
sa_qsq_out="$(bash -c "source '$SA_PATH' && resolve_active_state_file '$SA_TQSQ'")"
assert_eq "AC-D3 (F-QYAML, single-quoted): done-completed adopted" \
  "$sa_qsq_canon/.simple-workflow/backlog/briefs/done/qyaml-sq/autopilot-state.yaml" \
  "$sa_qsq_out"

echo ""

# ---------------------------------------------------------------------------
# Section 5: runtime-metrics.sh
# ---------------------------------------------------------------------------
echo "--- runtime-metrics.sh ---"

RM_PATH="$LIB_DIR/runtime-metrics.sh"

# AC-1: file exists with correct shebang
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if test -f "$RM_PATH"; then
  echo -e "  ${GREEN}PASS${NC} runtime-metrics.sh exists"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} runtime-metrics.sh missing at $RM_PATH"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
RM_SHEBANG_COUNT=$(grep -cE '^#!/usr/bin/env bash$' "$RM_PATH" || true)
if [ "${RM_SHEBANG_COUNT:-0}" -eq 1 ]; then
  echo -e "  ${GREEN}PASS${NC} runtime-metrics.sh has exactly one #!/usr/bin/env bash shebang"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} runtime-metrics.sh shebang count: $RM_SHEBANG_COUNT (expected 1)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AC-2: public function exported
TESTS_TOTAL=$((TESTS_TOTAL + 1))
RM_FUNC_OUT="$(bash -c "source '$RM_PATH' && declare -F append_runtime_metrics_entry" 2>/dev/null || true)"
if echo "$RM_FUNC_OUT" | grep -q 'append_runtime_metrics_entry'; then
  echo -e "  ${GREEN}PASS${NC} runtime-metrics.sh exports append_runtime_metrics_entry"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} append_runtime_metrics_entry not declared after sourcing runtime-metrics.sh"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
RM_FUNC_LINE_COUNT="$(echo "$RM_FUNC_OUT" | grep -c 'append_runtime_metrics_entry' || true)"
if [ "${RM_FUNC_LINE_COUNT:-0}" -eq 1 ]; then
  echo -e "  ${GREEN}PASS${NC} declare -F emits exactly one line for append_runtime_metrics_entry"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} declare -F emits $RM_FUNC_LINE_COUNT lines (expected 1)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AC-3: yq-tier path (skip if yq unavailable)
if command -v yq >/dev/null 2>&1; then
  RM_YQ_TMP="$(mktemp)"
  printf '%s\n' 'runtime_metrics: []' > "$RM_YQ_TMP"
  # No EXIT trap here: it would clobber the trap chain set up by earlier
  # test sections (parse-state-file, jsonl-tail-audit). The block performs
  # explicit `rm -f "$RM_YQ_TMP"` at the end of normal flow; in the unlikely
  # event of a mid-block abort the temp file is the only leak.

  RM_YQ_EXIT=0
  # shellcheck source=hooks/lib/runtime-metrics.sh
  (source "$RM_PATH" && append_runtime_metrics_entry "$RM_YQ_TMP" "session_end" "normal_completion" "2026-05-06T12:00:00Z" "100" "200" "300" "0") || RM_YQ_EXIT=$?
  assert_exit_zero "AC-3: append_runtime_metrics_entry (yq tier) exits 0" "$RM_YQ_EXIT"

  assert_eq "AC-3: stop_reason = normal_completion (yq)" \
    "normal_completion" "$(yq '.runtime_metrics[0].stop_reason' "$RM_YQ_TMP")"
  assert_eq "AC-3: cache_creation_input_tokens = 100 (yq)" \
    "100" "$(yq '.runtime_metrics[0].cache_creation_input_tokens' "$RM_YQ_TMP")"
  assert_eq "AC-3: cache_read_input_tokens = 200 (yq)" \
    "200" "$(yq '.runtime_metrics[0].cache_read_input_tokens' "$RM_YQ_TMP")"
  assert_eq "AC-3: input_tokens = 300 (yq)" \
    "300" "$(yq '.runtime_metrics[0].input_tokens' "$RM_YQ_TMP")"
  assert_eq "AC-3: consecutive_stop_blocks = 0 (yq)" \
    "0" "$(yq '.runtime_metrics[0].consecutive_stop_blocks' "$RM_YQ_TMP")"

  rm -f "$RM_YQ_TMP"
else
  echo "  (skip) AC-3: yq not on PATH — yq-tier test skipped"
fi

# AC-4: pure-shell fallback (PATH restricted to a dir with no yq or python3)
# Build a fake-bin dir that has bash + essential POSIX utilities but NOT yq/python3.
RM_PS_TMP="$(mktemp)"
printf '%s\n' 'runtime_metrics: []' > "$RM_PS_TMP"
RM_FAKE_BIN="$(mktemp -d)"
# No EXIT trap here: would clobber the earlier trap chain (parse-state-file,
# jsonl-tail-audit). Explicit `rm -f` / `rm -rf` runs at the end of normal flow.

# Symlink only the tools the lib needs (bash, grep, sed, tail, uname, cat, date, printf is builtin)
for _tool in bash grep sed tail uname cat date; do
  _tool_path="$(command -v "$_tool" 2>/dev/null || true)"
  [ -n "$_tool_path" ] && ln -sf "$_tool_path" "$RM_FAKE_BIN/$_tool" || true
done
unset _tool _tool_path

RM_PS_EXIT=0
PATH="$RM_FAKE_BIN" bash -c "source '$RM_PATH' && append_runtime_metrics_entry '$RM_PS_TMP' 'session_end' 'normal_completion' '2026-05-06T12:00:00Z' '100' '200' '300' '0'" || RM_PS_EXIT=$?
assert_exit_zero "AC-4: append_runtime_metrics_entry (pure-shell tier) exits 0" "$RM_PS_EXIT"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'stop_reason: normal_completion' "$RM_PS_TMP"; then
  echo -e "  ${GREEN}PASS${NC} AC-4: stop_reason: normal_completion present in file (pure-shell)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC-4: stop_reason: normal_completion not found in file (pure-shell)"
  echo "       file contents: $(cat "$RM_PS_TMP")"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'boundary: session_end' "$RM_PS_TMP"; then
  echo -e "  ${GREEN}PASS${NC} AC-4: boundary: session_end present in file (pure-shell)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC-4: boundary: session_end not found in file (pure-shell)"
  echo "       file contents: $(cat "$RM_PS_TMP")"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

rm -f "$RM_PS_TMP"
rm -rf "$RM_FAKE_BIN"

# AC-5: shipped_count (optional 9th arg) — emitted only when provided, placed
# AFTER consecutive_stop_blocks; the historical 8-arg form stays byte-identical
# and a literal "null" arg9 is treated as "omit".
if command -v yq >/dev/null 2>&1; then
  RM_SC_TMP="$(mktemp)"; printf '%s\n' 'runtime_metrics: []' > "$RM_SC_TMP"
  # shellcheck source=hooks/lib/runtime-metrics.sh
  ( source "$RM_PATH" && append_runtime_metrics_entry "$RM_SC_TMP" "auto_compact_inject" "safety_net" "2026-05-06T12:00:00Z" "null" "null" "null" "null" "4" ) || true
  assert_eq "AC-5: arg9 emits shipped_count = 4 (yq)" \
    "4" "$(yq '.runtime_metrics[0].shipped_count' "$RM_SC_TMP")"
  assert_eq "AC-5: arg8 null -> consecutive_stop_blocks null (yq)" \
    "null" "$(yq '.runtime_metrics[0].consecutive_stop_blocks' "$RM_SC_TMP")"
  RM_SC8_TMP="$(mktemp)"; printf '%s\n' 'runtime_metrics: []' > "$RM_SC8_TMP"
  # shellcheck source=hooks/lib/runtime-metrics.sh
  ( source "$RM_PATH" && append_runtime_metrics_entry "$RM_SC8_TMP" "session_end" "normal_completion" "2026-05-06T12:00:00Z" "1" "2" "3" "0" ) || true
  assert_eq "AC-5: 8-arg form omits shipped_count (yq)" \
    "null" "$(yq '.runtime_metrics[0].shipped_count' "$RM_SC8_TMP")"
  RM_SCN_TMP="$(mktemp)"; printf '%s\n' 'runtime_metrics: []' > "$RM_SCN_TMP"
  # shellcheck source=hooks/lib/runtime-metrics.sh
  ( source "$RM_PATH" && append_runtime_metrics_entry "$RM_SCN_TMP" "auto_compact_inject" "safety_net" "2026-05-06T12:00:00Z" "null" "null" "null" "null" "null" ) || true
  assert_eq "AC-5: literal 'null' arg9 omits shipped_count (yq)" \
    "null" "$(yq '.runtime_metrics[0].shipped_count' "$RM_SCN_TMP")"
  rm -f "$RM_SC_TMP" "$RM_SC8_TMP" "$RM_SCN_TMP"
else
  echo "  (skip) AC-5: yq not on PATH — yq-tier shipped_count test skipped"
fi

# AC-5 (pure-shell tier): shipped_count emitted only when arg9 provided.
RM_SCPS_TMP="$(mktemp)"; printf '%s\n' 'runtime_metrics: []' > "$RM_SCPS_TMP"
RM_SCPS_BIN="$(mktemp -d)"
for _tool in bash grep sed tail uname cat date; do
  _tp="$(command -v "$_tool" 2>/dev/null || true)"; [ -n "$_tp" ] && ln -sf "$_tp" "$RM_SCPS_BIN/$_tool" || true
done; unset _tool _tp
PATH="$RM_SCPS_BIN" bash -c "source '$RM_PATH' && append_runtime_metrics_entry '$RM_SCPS_TMP' 'auto_compact_inject' 'safety_net' '2026-05-06T12:00:00Z' 'null' 'null' 'null' 'null' '7'" || true
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'shipped_count: 7' "$RM_SCPS_TMP"; then
  echo -e "  ${GREEN}PASS${NC} AC-5: arg9 emits 'shipped_count: 7' (pure-shell)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC-5: 'shipped_count: 7' not found (pure-shell)"
  echo "       file contents: $(cat "$RM_SCPS_TMP")"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
RM_SCPS8_TMP="$(mktemp)"; printf '%s\n' 'runtime_metrics: []' > "$RM_SCPS8_TMP"
PATH="$RM_SCPS_BIN" bash -c "source '$RM_PATH' && append_runtime_metrics_entry '$RM_SCPS8_TMP' 'session_end' 'normal_completion' '2026-05-06T12:00:00Z' '1' '2' '3' '0'" || true
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'shipped_count' "$RM_SCPS8_TMP"; then
  echo -e "  ${RED}FAIL${NC} AC-5: shipped_count leaked into 8-arg pure-shell entry"
  echo "       file contents: $(cat "$RM_SCPS8_TMP")"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  echo -e "  ${GREEN}PASS${NC} AC-5: 8-arg pure-shell entry omits shipped_count (byte-compat)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi
rm -f "$RM_SCPS_TMP" "$RM_SCPS8_TMP"; rm -rf "$RM_SCPS_BIN"

# Negative AC-3: no new public API beyond append_runtime_metrics_entry
TESTS_TOTAL=$((TESTS_TOTAL + 1))
RM_BEFORE_FUNCS="$(declare -F | awk '{print $3}' | sort)"
# shellcheck disable=SC1090
source "$RM_PATH"
RM_AFTER_FUNCS="$(declare -F | awk '{print $3}' | sort)"
RM_NEW_PUBLIC="$(comm -13 <(echo "$RM_BEFORE_FUNCS") <(echo "$RM_AFTER_FUNCS") | grep -v '^_' || true)"
if [ "$RM_NEW_PUBLIC" = "append_runtime_metrics_entry" ]; then
  echo -e "  ${GREEN}PASS${NC} Negative AC-3: only append_runtime_metrics_entry added as public function"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Negative AC-3: unexpected public functions: '$RM_NEW_PUBLIC'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Negative AC-4: lib does not reference skills/ or agents/ paths
TESTS_TOTAL=$((TESTS_TOTAL + 1))
RM_PATH_LEAK="$(grep -rnE 'skills/|agents/' "$RM_PATH" || true)"
if [ -z "$RM_PATH_LEAK" ]; then
  echo -e "  ${GREEN}PASS${NC} Negative AC-4: runtime-metrics.sh has no skills/ or agents/ references"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Negative AC-4: found skills/agents references in runtime-metrics.sh"
  echo "       $RM_PATH_LEAK"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
print_summary
