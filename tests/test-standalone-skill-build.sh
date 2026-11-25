#!/usr/bin/env bash
# Contract test for tools/build-standalone-skill.sh: the generated, standalone,
# host-neutral skill `create-ticket/`.
#
# The generated tree is never committed, so this suite builds it into a temp
# directory and re-checks it independently of the build's own exit audit:
#   - the build succeeds, refuses a non-empty target, and honours --force
#   - the tree holds exactly SKILL.md + the shipped references (including
#     the override-only references/destinations.md)
#   - the SKILL.md frontmatter follows the Agent Skills contract and names
#     the source version and the source commit
#   - every relative link and backticked references/ path resolves
#   - zero denylist hits (the decoupling and undefined-jargon entries
#     included, each also re-run here with a literal pattern) and zero
#     backticked Claude Code tool names
#   - the AC rubric keeps its Gate headings, Terminology and word count
#   - SKILL.md carries the host notes, the Delivery section, the destination
#     argument and the degraded branch; destinations.md defines all five kinds
#   - the constraint_<key>=off kill-switch tokens are parsed, resolved in the
#     rubric Terminology and forwarded; the planner gets the ticket template
#     by path; the new ERROR: literals are present
#   - the .xlsx converter, run on a fixture workbook built here, prints
#     values, structure (line breaks, merges, strikethrough, hidden rows and
#     columns), notes, shapes and images, honours --layout, --extract-media
#     and every cap, and marks a missing part instead of failing; the
#     character cap also bounds the text generated (traced peak memory on
#     workbooks built here whose cells, notes, comments or pictures share one
#     long string), a worksheet that starts at the cap is not parsed, a part
#     that many relationships or worksheet entries point at is printed once
#     per reference without being parsed once per reference, a long value
#     that many cells hold is not escaped once per cell, the full output of
#     the fixture workbook equals the text pinned here, and at every
#     --max-chars the output is that text, whole or cut at the documented
#     place
#   - the optional sheet renderer, driven by stand-in renderer programs
#     written here (a PDF writer per renderer shape, a failing one, a hanging
#     one, one that writes no PDF), walks its chain, honours --timeout without
#     leaving a process behind, writes nothing outside --out and reports one
#     Rendered: line; render=, PDF and image sources are documented
#   - a platform item URL named in prose is documented as reached through
#     an access channel (mcp:, cli:, api:, browser:, plain GET) chosen by a
#     printed best guess (Derived:/Tried:/Probe: lines, the sign-in rule, the
#     new cli: and browser: kinds and their ERROR: literals in the raising
#     section, the Error Handling table and the reference file), the Usage
#     line stays consistent with the argument-hint, and the Delivery jq
#     filter and the source_content_path= extraction run on fixtures
#   - --name: a tree built as zq-x7 holds no other spelling of create-ticket
#     (with the exit audit's variant check, that shows no occurrence in a
#     form that check covers was missed) and, mapped back, equals the default build byte for byte (the
#     rename changed nothing else; so does create-ticket-v2); --name
#     create-ticket is the default build; names that resemble plugin words or
#     folders (hooks, brief, test-plan, best-effort, home) build; invalid,
#     reserved, YAML-typed and foreign-tool names exit 2 before anything is
#     written, also against an absent --out; --force replaces <out>/<name>
#     only, and only when it holds a generated skill (a non-generated
#     directory, a file and a dangling link are refused); a failed build
#     leaves the previous skill byte for byte and a missing source file
#     leaves nothing; a relative --out lands under the working directory
#     with an exported CDPATH; every create-ticket of the default tree sits in
#     a known name context; the role prompts and the description do not
#     depend on the name being unusual; the name audit catches a foreign tool
#     name the probe misses, a rename that misses occurrences and a
#     description the name makes too long
#   - the exit audit's variant check reports the other forms of the name it
#     covers, planted in a copied source (another case, underscore, camel
#     case, glued, wrapped, an upstream skills/create-ticket path), and a file
#     named after it, for the default name and for --name, and publishes
#     nothing; a form that differs by markup, an entity or a non-ASCII
#     character is out of its reach
#   - publish: a dotfile-only or unreadable <out>/<name> is refused, a
#     near-miss marker line is not the marker, a publish that fails after a
#     partial copy leaves only the previous skill, and a previous tree that
#     cannot be removed completely is still replaced, with a WARNING
#   - a --src outside git stamps source-commit "unknown"
#   - two mutations (a plugin variable, a plugin backlog path, each injected
#     into a copied source) FAIL the build, proving the audit is the exit gate
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=./test-helper.sh
source "$SCRIPT_DIR/test-helper.sh"
export LC_ALL=C

BUILD="$REPO_DIR/tools/build-standalone-skill.sh"
MANIFEST_DIR="$REPO_DIR/tools/standalone-skill"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/test-standalone-skill.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
# The generator builds in a staging directory under TMPDIR and keeps it after
# a failed audit; every build of this suite stages inside TMP_ROOT instead.
export TMPDIR="$TMP_ROOT/tmp"
mkdir -p "$TMPDIR"
OUT="$TMP_ROOT/out"
SKILL_DIR="$OUT/create-ticket"

pass() {
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "  ${GREEN}PASS${NC} $1"
}

fail() {
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "  ${RED}FAIL${NC} $1"
  [ -z "${2:-}" ] || printf '%s\n' "$2" | head -n 20 | sed 's/^/       /'
}

# check NAME DETAIL — PASS when DETAIL is empty, FAIL listing DETAIL otherwise.
check() {
  if [ -z "$2" ]; then pass "$1"; else fail "$1" "$2"; fi
}

manifest_lines() {
  grep -vE '^[[:space:]]*(#|$)' "$1" || true
}

echo "=== Standalone host-neutral create-ticket skill build ==="
echo ""

# --- build ------------------------------------------------------------------
BUILD_LOG="$TMP_ROOT/build.log"
if bash "$BUILD" --out "$OUT" >"$BUILD_LOG" 2>&1; then
  pass "build exits 0 into a temp dir"
else
  fail "build exits 0 into a temp dir" "$(cat "$BUILD_LOG")"
  print_summary
  exit 1
fi

set +e
bash "$BUILD" --out "$OUT" >"$TMP_ROOT/refuse.log" 2>&1
REFUSE_RC=$?
bash "$BUILD" --out "$OUT" --force >"$TMP_ROOT/force.log" 2>&1
FORCE_RC=$?
set -e
if [ "$REFUSE_RC" -ne 0 ] && grep -q -- '--force' "$TMP_ROOT/refuse.log"; then
  pass "--out on a non-empty target without --force exits non-zero"
else
  fail "--out on a non-empty target without --force exits non-zero" "rc=$REFUSE_RC $(cat "$TMP_ROOT/refuse.log")"
fi
check "--force rebuilds a non-empty target" "$([ "$FORCE_RC" -eq 0 ] || cat "$TMP_ROOT/force.log")"
check "the build reports 23 files and a clean exit audit" \
  "$(grep -qF '(23 files, ' "$BUILD_LOG" || echo 'file count is not 23')$(grep -qF 'exit audit clean' "$BUILD_LOG" || echo ' audit not clean')"

# --- tree shape ---------------------------------------------------------------
EXPECTED="README.md
SKILL.md
references/ac-quality-criteria.md
references/ac-quality-grading.md
references/agent-spawn-prompts.md
references/agents/decomposer.md
references/agents/planner.md
references/agents/researcher.md
references/agents/ticket-evaluator.md
references/brief-template.md
references/destinations.md
references/findings-schema.md
references/interview-templates.md
references/mode-dispatch-flows.md
references/shell-powershell.md
references/sources.md
references/spec-decomposer-input.md
references/split-plan-schema.md
references/ticket-template.md
references/write-path-templates.md
scripts/ticket_body.py
scripts/xlsx_render.py
scripts/xlsx_to_text.py"
ACTUAL="$(cd "$SKILL_DIR" && find . -type f | sed 's#^\./##' | sort)"
check "tree holds exactly README.md + SKILL.md + the 18 shipped references + the xlsx converter, the sheet renderer and the ticket body script (23 files)" \
  "$(diff <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$ACTUAL") || true)"

NOT_SHIPPED=""
for name in ac-quality-criteria-history autopilot-foldin autopilot-policy-reference \
            phase-state-migration phase-state-schema sw-checkpoint-template workflow-patterns; do
  if [ -n "$(find "$SKILL_DIR" -name "$name.md")" ]; then NOT_SHIPPED="$NOT_SHIPPED $name.md"; fi
done
check "nothing from the do-not-ship list is generated" "$NOT_SHIPPED"

# --- frontmatter -----------------------------------------------------------------
FM="$(awk 'NR == 1 && $0 == "---" {fm = 1; next} fm && $0 == "---" {exit} fm {print}' "$SKILL_DIR/SKILL.md")"
FM_NAME="$(printf '%s\n' "$FM" | sed -n 's/^name:[[:space:]]*//p')"
check "frontmatter name equals the directory name (create-ticket)" \
  "$([ "$FM_NAME" = "$(basename "$SKILL_DIR")" ] || echo "name='$FM_NAME'")"
DESC="$(printf '%s\n' "$FM" | awk '/^description:/ {d = 1; next} d && /^[a-z-]+:/ {d = 0} d {sub(/^ +/, ""); s = s (s == "" ? "" : " ") $0} END {print s}')"
check "description is non-empty and at most 1024 chars" \
  "$({ [ -n "$DESC" ] && [ "${#DESC}" -le 1024 ]; } || echo "length=${#DESC}")"
check "description allows invocation by name only (no phrase trigger, no by-name contradiction)" \
  "$(grep -q 'Invoke only when the user names this skill' <<<"$DESC" || echo 'name-only rule missing')$(printf '%s\n' "$DESC" | grep -E -o 'Triggers on|Only invoke when called by name|\(2\) user' || true)"
check "frontmatter carries no allowed-tools key" "$(printf '%s\n' "$FM" | grep '^allowed-tools:' || true)"
check "frontmatter metadata names the source version" \
  "$(grep -qE '^  source-version: "[0-9]+\.[0-9]+\.[0-9]+"$' <<<"$FM" || echo missing)"
COMMIT_VAL="$(printf '%s\n' "$FM" | sed -n 's/^  source-commit: //p')"
# The pattern sits in a variable: bash 3.2 misreads a double quote inside
# single quotes inside "$( ... )".
COMMIT_RE='^"([0-9a-f]{7,40}|unknown)"$'
check "frontmatter metadata names the source commit (short sha or unknown)" \
  "$(grep -qE -- "$COMMIT_RE" <<<"$COMMIT_VAL" || echo "source-commit='$COMMIT_VAL'")"
check "frontmatter metadata.source is neutral (no plugin name, no generator path)" \
  "$(grep -qx '  source: generated skill; do not edit by hand' <<<"$FM" || echo "$(printf '%s\n' "$FM" | grep '^  source:')")"

# --- --name: any valid skill name, with nothing left of the canonical one ----
# The manifests carry the canonical name create-ticket; --name renames the
# audited tree. No other spelling of create-ticket left in the renamed tree,
# together with the exit audit's variant check on the canonical text, shows
# that no occurrence in a form that check covers was missed. The default tree above, built from the same
# source, is the reference for the rest: a renamed tree mapped back to
# create-ticket must equal it byte for byte, which shows the rename changed
# nothing else (a missed occurrence would map back to itself, so the round
# trip cannot show that none was missed).
# frontmatter_of FILE / description_of — the frontmatter block and its
# joined description, as above.
frontmatter_of() { awk 'NR == 1 && $0 == "---" {fm = 1; next} fm && $0 == "---" {exit} fm {print}' "$1"; }
description_of() { awk '/^description:/ {d = 1; next} d && /^[a-z-]+:/ {d = 0} d {sub(/^ +/, ""); s = s (s == "" ? "" : " ") $0} END {print s}'; }
# map_name DIR FROM TO — replace FROM by TO in every file of DIR.
map_name() {
  while IFS= read -r f; do
    sed "s/$2/$3/g" "$1/$f" >"$1/$f.map"
    mv "$1/$f.map" "$1/$f"
  done < <(cd "$1" && find . -type f | sed 's#^\./##')
}
# build_name OUT NAME — run the build with --name; sets NB_RC and NB_LOG.
build_name() {
  NB_LOG="$TMP_ROOT/name-build-$(printf '%s' "$2" | tr -c 'a-z0-9-' '_').log"
  set +e
  bash "$BUILD" --out "$1" --name "$2" >"$NB_LOG" 2>&1
  NB_RC=$?
  set -e
}
# entries_of DIR — the names directly under DIR, sorted, space-separated.
entries_of() { find "$1" -mindepth 1 -maxdepth 1 | sed 's#.*/##' | sort | tr '\n' ' '; }
CANON_COUNT="$(grep -roF 'create-ticket' "$SKILL_DIR" | wc -l | tr -d ' ')"

NAME_OUT="$TMP_ROOT/name-out"
NAME_DIR="$NAME_OUT/zq-x7"
build_name "$NAME_OUT" zq-x7
NAME_LOG="$NB_LOG"
check "--name zq-x7: exit 0, the tree is <out>/zq-x7, no <out>/create-ticket is created, the same file list as the default build" \
  "$([ "$NB_RC" -eq 0 ] || echo "rc=$NB_RC $(head -n 5 "$NAME_LOG")")$([ -d "$NAME_DIR" ] || echo ' no <out>/zq-x7')$([ ! -e "$NAME_OUT/create-ticket" ] || echo ' <out>/create-ticket was created')$([ "$(entries_of "$NAME_OUT")" = "zq-x7 " ] || echo " <out> holds: $(entries_of "$NAME_OUT")")$([ ! -d "$NAME_DIR" ] || diff <(printf '%s\n' "$ACTUAL") <(cd "$NAME_DIR" && find . -type f | sed 's#^\./##' | sort) || true)"
check "--name zq-x7: the build reports the 23 files and a clean name audit that renamed every create-ticket of the default tree ($CANON_COUNT)" \
  "$(grep -qF '(23 files, ' "$NAME_LOG" || echo 'file count is not 23')$(grep -qF "; exit audit clean; name audit clean ($CANON_COUNT occurrences of create-ticket renamed to zq-x7)" "$NAME_LOG" || echo " log: $(tail -n 1 "$NAME_LOG")")"
check "--name zq-x7: no create-ticket, create_ticket or createTicket, in any case, is left in the renamed tree" \
  "$(grep -rniE 'create[-_]?ticket' "$NAME_DIR" | cut -c1-160 || true)"
check "zq-x7 does not occur in the default tree (so the round trip below is exact)" \
  "$(grep -rnF 'zq-x7' "$SKILL_DIR" | cut -c1-160 || true)"
RT_DIR="$TMP_ROOT/roundtrip/create-ticket"
if [ -d "$NAME_DIR" ]; then
  mkdir -p "$TMP_ROOT/roundtrip"
  cp -R "$NAME_DIR" "$RT_DIR"
  map_name "$RT_DIR" zq-x7 create-ticket
fi
check "round trip: the zq-x7 tree with every zq-x7 mapped back to create-ticket equals the default build byte for byte" \
  "$([ -d "$RT_DIR" ] || echo 'no renamed tree')$([ ! -d "$RT_DIR" ] || { diff -r "$SKILL_DIR" "$RT_DIR" 2>&1 || true; } | head -n 20)"

build_name "$TMP_ROOT/name-canon" create-ticket
check "--name create-ticket builds the default tree byte for byte, with the default log line" \
  "$([ "$NB_RC" -eq 0 ] || echo "rc=$NB_RC $(head -n 5 "$NB_LOG")")$(grep -q 'name audit' "$NB_LOG" && echo ' a name audit ran')$([ ! -d "$TMP_ROOT/name-canon/create-ticket" ] || { diff -r "$SKILL_DIR" "$TMP_ROOT/name-canon/create-ticket" 2>&1 || true; } | head -n 20)"

# A name that contains the canonical one.
V2_DIR="$TMP_ROOT/name-v2/create-ticket-v2"
build_name "$TMP_ROOT/name-v2" create-ticket-v2
if [ -d "$V2_DIR" ]; then
  mkdir -p "$TMP_ROOT/roundtrip-v2"
  cp -R "$V2_DIR" "$TMP_ROOT/roundtrip-v2/create-ticket"
  map_name "$TMP_ROOT/roundtrip-v2/create-ticket" create-ticket-v2 create-ticket
fi
check "--name create-ticket-v2 (holds the canonical name) builds, keeps create-ticket only inside create-ticket-v2 and maps back to the default build" \
  "$([ "$NB_RC" -eq 0 ] || echo "rc=$NB_RC $(head -n 5 "$NB_LOG")")$([ -d "$V2_DIR" ] || echo ' no tree')$([ ! -d "$V2_DIR" ] || grep -rnF 'create-ticket' "$V2_DIR" | sed 's/create-ticket-v2//g' | grep -F 'create-ticket' | cut -c1-160 || true)$([ ! -d "$V2_DIR" ] || { diff -r "$SKILL_DIR" "$TMP_ROOT/roundtrip-v2/create-ticket" 2>&1 || true; } | head -n 20)"

# A name the canonical text already holds as a word: the occurrence count of
# the name audit is relative to the text, so it still builds.
build_name "$TMP_ROOT/name-word" ticket
check "--name ticket (a word the text already holds) builds with a clean name audit and leaves no create-ticket" \
  "$([ "$NB_RC" -eq 0 ] || echo "rc=$NB_RC $(head -n 5 "$NB_LOG")")$(grep -qF "name audit clean ($CANON_COUNT occurrences" "$NB_LOG" || echo ' no clean name audit')$([ ! -d "$TMP_ROOT/name-word/ticket" ] || grep -rnF 'create-ticket' "$TMP_ROOT/name-word/ticket" | cut -c1-160 || true)"

# The longest valid name: 64 characters; one more is refused.
N64="$(printf 'abcdefghi-%.0s' 1 2 3 4 5 6)abcd"
build_name "$TMP_ROOT/name-64" "$N64"
DESC64=""
[ ! -f "$TMP_ROOT/name-64/$N64/SKILL.md" ] || DESC64="$(frontmatter_of "$TMP_ROOT/name-64/$N64/SKILL.md" | description_of)"
check "a 64-character name builds and its description stays within 1024 characters" \
  "$([ "${#N64}" -eq 64 ] || echo "the fixture name has ${#N64} characters")$([ "$NB_RC" -eq 0 ] || echo " rc=$NB_RC $(head -n 5 "$NB_LOG")")$({ [ -n "$DESC64" ] && [ "${#DESC64}" -le 1024 ]; } || echo " description length ${#DESC64}")$(grep -qF "\`/$N64\`" <<<"$DESC64" || echo ' the name is not in the description')"
mkdir -p "$TMP_ROOT/name-65"
build_name "$TMP_ROOT/name-65" "${N64}e"
check "a 65-character name exits 2 and creates nothing" \
  "$([ "$NB_RC" -eq 2 ] || echo "rc=$NB_RC")$([ -z "$(entries_of "$TMP_ROOT/name-65")" ] || echo ' something was created')$(grep -qF '1 to 64' "$NB_LOG" || echo ' the message does not state the rule')"

# Invalid names: exit 2 before any filesystem action.
INV_OUT="$TMP_ROOT/name-invalid"
mkdir -p "$INV_OUT"
printf 'keep\n' >"$INV_OUT/keep.txt"
INVALID_DETAIL=""
for bad in '' 'Foo' 'a_b' '-a' 'a-' 'a--b' '../x' 'a/b' 'a b' 'a&b' 'a\b' 'a.b'; do
  build_name "$INV_OUT" "$bad"
  [ "$NB_RC" -eq 2 ] || INVALID_DETAIL="$INVALID_DETAIL '$bad':rc=$NB_RC"
  grep -qF 'lowercase ASCII letters, digits and hyphens' "$NB_LOG" || INVALID_DETAIL="$INVALID_DETAIL '$bad':no-rule-in-message"
  [ "$(entries_of "$INV_OUT")" = "keep.txt " ] || INVALID_DETAIL="$INVALID_DETAIL '$bad':created:$(entries_of "$INV_OUT")"
done
[ "$(cat "$INV_OUT/keep.txt")" = "keep" ] || INVALID_DETAIL="$INVALID_DETAIL sentinel-changed"
[ ! -e "$TMP_ROOT/x" ] || INVALID_DETAIL="$INVALID_DETAIL ../x-created-a-sibling"
set +e
bash "$BUILD" --out "$INV_OUT" --name >"$TMP_ROOT/name-novalue.log" 2>&1
NOVALUE_RC=$?
bash "$BUILD" --out "$TMP_ROOT/name-invalid-absent" --name Foo >/dev/null 2>&1
ABSENT_RC=$?
set -e
[ "$NOVALUE_RC" -eq 2 ] || INVALID_DETAIL="$INVALID_DETAIL --name-without-value:rc=$NOVALUE_RC"
[ "$ABSENT_RC" -eq 2 ] || INVALID_DETAIL="$INVALID_DETAIL absent-out:rc=$ABSENT_RC"
[ ! -e "$TMP_ROOT/name-invalid-absent" ] || INVALID_DETAIL="$INVALID_DETAIL absent-out-was-created"
check "invalid names (empty, uppercase, underscore, hyphen first, last or doubled, path parts, space, ampersand, backslash, dot) and --name without a value exit 2 and create nothing" \
  "$INVALID_DETAIL"

# refused_before_write NAME — run the build with NAME against an --out that
# does not exist; print nothing when it exits 2 without creating that
# directory, a detail otherwise.
refused_before_write() {
  local absent rc
  absent="$TMP_ROOT/name-absent-$(printf '%s' "$1" | tr -c 'a-z0-9-' '_')"
  set +e
  bash "$BUILD" --out "$absent" --name "$1" >/dev/null 2>&1
  rc=$?
  set -e
  [ "$rc" -eq 2 ] || printf ' absent-out:%s:rc=%s' "$1" "$rc"
  [ ! -e "$absent" ] || printf ' absent-out:%s:created' "$1"
}

YAML_DETAIL=""
for bad in 123 true false yes no on off null y n 0x1f 0o17 0b101 1e3 1e-3 2024-01-01 2024-1-1; do
  build_name "$INV_OUT" "$bad"
  [ "$NB_RC" -eq 2 ] || YAML_DETAIL="$YAML_DETAIL $bad:rc=$NB_RC"
  grep -qF 'a YAML reader takes it for a number, a boolean, null or a date' "$NB_LOG" || YAML_DETAIL="$YAML_DETAIL $bad:no-yaml-message"
done
[ "$(entries_of "$INV_OUT")" = "keep.txt " ] || YAML_DETAIL="$YAML_DETAIL created:$(entries_of "$INV_OUT")"
YAML_DETAIL="$YAML_DETAIL$(refused_before_write 2024-1-1)"
check "spec-valid names a YAML reader takes for a number, boolean, null or date (the frontmatter name would not be a string) exit 2 and create nothing, not even an absent --out" "$YAML_DETAIL"

RESERVED_DETAIL=""
for bad in planner researcher decomposer ticket-evaluator evaluator orchestrator; do
  build_name "$INV_OUT" "$bad"
  [ "$NB_RC" -eq 2 ] || RESERVED_DETAIL="$RESERVED_DETAIL $bad:rc=$NB_RC"
  grep -qF "reserved --name '$bad'" "$NB_LOG" || RESERVED_DETAIL="$RESERVED_DETAIL $bad:no-reserved-message"
done
[ "$(entries_of "$INV_OUT")" = "keep.txt " ] || RESERVED_DETAIL="$RESERVED_DETAIL created:$(entries_of "$INV_OUT")"
RESERVED_DETAIL="$RESERVED_DETAIL$(refused_before_write orchestrator)"
check "the names the skill's text uses for its roles (planner, researcher, decomposer, ticket-evaluator, evaluator, orchestrator) are reserved: exit 2, nothing created, not even an absent --out" "$RESERVED_DETAIL"
# A spec-valid name that the exit audit's foreign-tool-name rule rejects.
DENY_NAME="$(manifest_lines "$MANIFEST_DIR/tool-vocabulary.txt" | awk '$1 == "deny" {print $2}' | grep -xE '[a-z0-9]+(-[a-z0-9]+)*' | head -n 1 || true)"
if [ -z "$DENY_NAME" ]; then
  echo "  SKIP a spec-valid foreign tool name is refused (no deny row of tool-vocabulary.txt is a valid skill name)"
else
  build_name "$INV_OUT" "$DENY_NAME"
  DENY_DETAIL="$(refused_before_write "$DENY_NAME")"
  check "a spec-valid name from a deny row of tool-vocabulary.txt ($DENY_NAME) exits 2 naming the foreign tool name rule, and creates nothing, not even an absent --out" \
    "$([ "$NB_RC" -eq 2 ] || echo "rc=$NB_RC")$(grep -qF 'foreign tool name rule' "$NB_LOG" || echo " message: $(head -n 2 "$NB_LOG")")$([ "$(entries_of "$INV_OUT")" = "keep.txt " ] || echo ' something was created')$DENY_DETAIL"
fi
# The name is not a leak: a name that resembles a word of the source plugin
# or a folder (one a denylist row would match in one of its contexts, such as
# .claude/skills/hooks/) builds, and the name audit does not run the
# denylist on it.
RESEMBLE_DETAIL=""
for ok in hooks brief test-plan best-effort home; do
  build_name "$TMP_ROOT/name-resemble" "$ok"
  [ "$NB_RC" -eq 0 ] || { RESEMBLE_DETAIL="$RESEMBLE_DETAIL $ok:rc=$NB_RC:$(head -n 3 "$NB_LOG")"; continue; }
  grep -qF "; exit audit clean; name audit clean ($CANON_COUNT occurrences of create-ticket renamed to $ok)" "$NB_LOG" || RESEMBLE_DETAIL="$RESEMBLE_DETAIL $ok:no-clean-name-audit"
  [ -f "$TMP_ROOT/name-resemble/$ok/SKILL.md" ] || RESEMBLE_DETAIL="$RESEMBLE_DETAIL $ok:no-tree"
done
RESEMBLE_DETAIL="$RESEMBLE_DETAIL$(grep -rniE 'create[-_]?ticket' "$TMP_ROOT/name-resemble/hooks" | cut -c1-160 || true)"
check "names that resemble a word of the source plugin or a folder (hooks, brief, test-plan, best-effort, home) build with exit 0 and a clean name audit, and the hooks tree holds no create-ticket" \
  "$RESEMBLE_DETAIL"

# --force replaces <out>/<name> only.
FORCE_OUT="$TMP_ROOT/name-force"
mkdir -p "$FORCE_OUT/unrelated"
printf 'keep\n' >"$FORCE_OUT/unrelated/keep.txt"
cp -R "$SKILL_DIR" "$FORCE_OUT/create-ticket"
FORCE_DETAIL=""
if [ -d "$NAME_DIR" ]; then
  cp -R "$NAME_DIR" "$FORCE_OUT/zq-x7"
  printf 'stale\n' >"$FORCE_OUT/zq-x7/stale.txt"
  set +e
  bash "$BUILD" --out "$FORCE_OUT" --name zq-x7 >"$TMP_ROOT/name-force-refuse.log" 2>&1
  NF_REFUSE_RC=$?
  set -e
  [ "$NF_REFUSE_RC" -eq 2 ] || FORCE_DETAIL="$FORCE_DETAIL without-force:rc=$NF_REFUSE_RC"
  grep -q -- '--force' "$TMP_ROOT/name-force-refuse.log" || FORCE_DETAIL="$FORCE_DETAIL without-force:no-hint"
  [ -f "$FORCE_OUT/zq-x7/stale.txt" ] || FORCE_DETAIL="$FORCE_DETAIL the-refused-build-touched-the-target"
  set +e
  bash "$BUILD" --out "$FORCE_OUT" --name zq-x7 --force >"$TMP_ROOT/name-force.log" 2>&1
  NF_RC=$?
  set -e
  [ "$NF_RC" -eq 0 ] || FORCE_DETAIL="$FORCE_DETAIL with-force:rc=$NF_RC $(head -n 3 "$TMP_ROOT/name-force.log")"
  [ ! -e "$FORCE_OUT/zq-x7/stale.txt" ] || FORCE_DETAIL="$FORCE_DETAIL stale-file-kept"
  FORCE_DETAIL="$FORCE_DETAIL$({ diff -r "$NAME_DIR" "$FORCE_OUT/zq-x7" 2>&1 || true; } | head -n 5)"
  FORCE_DETAIL="$FORCE_DETAIL$({ diff -r "$SKILL_DIR" "$FORCE_OUT/create-ticket" 2>&1 || true; } | head -n 5)"
  [ "$(cat "$FORCE_OUT/unrelated/keep.txt")" = "keep" ] || FORCE_DETAIL="$FORCE_DETAIL unrelated-touched"
  [ "$(entries_of "$FORCE_OUT")" = "create-ticket unrelated zq-x7 " ] || FORCE_DETAIL="$FORCE_DETAIL out-holds:$(entries_of "$FORCE_OUT")"
else
  FORCE_DETAIL="no renamed tree to start from"
fi
check "--force --name zq-x7 replaces <out>/zq-x7 only (a create-ticket sibling and an unrelated directory untouched); without --force a non-empty <out>/zq-x7 is refused with exit 2" \
  "$FORCE_DETAIL"

# --force replaces only a skill this generator wrote: a directory without a
# SKILL.md, or with one that lacks the generated marker line, is refused with
# exit 2 and left byte for byte.
GUARD_OUT="$TMP_ROOT/name-force-guard"
mkdir -p "$GUARD_OUT/docs/sub" "$GUARD_OUT/handmade"
printf 'keep\n' >"$GUARD_OUT/docs/readme.txt"
printf 'nested\n' >"$GUARD_OUT/docs/sub/n.txt"
printf -- '---\nname: handmade\ndescription: written by hand\n---\n\n# handmade\n' >"$GUARD_OUT/handmade/SKILL.md"
cp -R "$GUARD_OUT" "$TMP_ROOT/name-force-guard-before"
# The generator prints the path resolved by cd and pwd (no doubled slash, as
# a TMPDIR that ends in a slash gives TMP_ROOT).
GUARD_REAL="$(CDPATH='' cd -- "$GUARD_OUT" && pwd)"
GUARD_DETAIL=""
for n in docs handmade; do
  set +e
  bash "$BUILD" --out "$GUARD_OUT" --name "$n" --force >"$TMP_ROOT/name-force-guard-$n.log" 2>&1
  rc=$?
  set -e
  [ "$rc" -eq 2 ] || GUARD_DETAIL="$GUARD_DETAIL $n:rc=$rc"
  grep -qF "refusing to replace $GUARD_REAL/$n: it is not a skill this generator wrote" "$TMP_ROOT/name-force-guard-$n.log" ||
    GUARD_DETAIL="$GUARD_DETAIL $n:message:$(head -n 1 "$TMP_ROOT/name-force-guard-$n.log")"
done
GUARD_DETAIL="$GUARD_DETAIL$(diff -r "$TMP_ROOT/name-force-guard-before" "$GUARD_OUT" 2>&1 | head -n 5 || true)"
check "--force on a non-empty directory that is not a generated skill (no SKILL.md; a SKILL.md without the generated marker line) exits 2 and leaves every file byte for byte" \
  "$GUARD_DETAIL"

# A file or a dangling link at <out>/<name> is refused with or without --force
# and left as it was.
NOTDIR_OUT="$TMP_ROOT/name-notdir"
mkdir -p "$NOTDIR_OUT"
printf 'a file\n' >"$NOTDIR_OUT/plain"
ln -s "$NOTDIR_OUT/nowhere" "$NOTDIR_OUT/dangling"
NOTDIR_REAL="$(CDPATH='' cd -- "$NOTDIR_OUT" && pwd)"
NOTDIR_DETAIL=""
for n in plain dangling; do
  for force in "" --force; do
    set +e
    bash "$BUILD" --out "$NOTDIR_OUT" --name "$n" ${force:+"$force"} >"$TMP_ROOT/name-notdir.log" 2>&1
    rc=$?
    set -e
    [ "$rc" -eq 2 ] || NOTDIR_DETAIL="$NOTDIR_DETAIL $n${force:+ $force}:rc=$rc"
    grep -qF "refusing to overwrite $NOTDIR_REAL/$n: it exists and is not a directory" "$TMP_ROOT/name-notdir.log" ||
      NOTDIR_DETAIL="$NOTDIR_DETAIL $n${force:+ $force}:message:$(head -n 1 "$TMP_ROOT/name-notdir.log")"
  done
done
{ [ -f "$NOTDIR_OUT/plain" ] && [ ! -L "$NOTDIR_OUT/plain" ] && [ "$(cat "$NOTDIR_OUT/plain")" = 'a file' ]; } || NOTDIR_DETAIL="$NOTDIR_DETAIL plain-changed"
{ [ -L "$NOTDIR_OUT/dangling" ] && [ "$(readlink "$NOTDIR_OUT/dangling")" = "$NOTDIR_OUT/nowhere" ] && [ ! -e "$NOTDIR_OUT/nowhere" ]; } || NOTDIR_DETAIL="$NOTDIR_DETAIL dangling-changed"
[ "$(entries_of "$NOTDIR_OUT")" = "dangling plain " ] || NOTDIR_DETAIL="$NOTDIR_DETAIL out-holds:$(entries_of "$NOTDIR_OUT")"
check "a regular file and a dangling link at <out>/<name> exit 2 (it exists and is not a directory), with and without --force, and are left as they were" \
  "$NOTDIR_DETAIL"

# The audited tree is moved next to <out>/<name> before the old tree is
# removed, so an <out> that cannot be written leaves the previous skill byte
# for byte (exit 2). Root writes anywhere, so the check is skipped for root.
if [ "$(id -u)" -eq 0 ]; then
  echo "  SKIP an --out that cannot be written leaves the previous skill (running as root)"
else
  RO_OUT="$TMP_ROOT/name-readonly"
  mkdir -p "$RO_OUT"
  cp -R "$SKILL_DIR" "$RO_OUT/create-ticket"
  chmod 555 "$RO_OUT"
  set +e
  bash "$BUILD" --out "$RO_OUT" --force >"$TMP_ROOT/name-readonly.log" 2>&1
  RO_RC=$?
  set -e
  RO_DETAIL="$([ "$RO_RC" -eq 2 ] || echo "rc=$RO_RC")$(grep -qF 'create-ticket is unchanged' "$TMP_ROOT/name-readonly.log" || echo " log: $(tail -n 1 "$TMP_ROOT/name-readonly.log")")$([ "$(entries_of "$RO_OUT")" = "create-ticket " ] || echo " <out> holds: $(entries_of "$RO_OUT")")$(diff -r "$SKILL_DIR" "$RO_OUT/create-ticket" 2>&1 | head -n 5 || true)"
  chmod 755 "$RO_OUT"
  check "--force into an --out that cannot be written exits 2 and leaves the previous skill byte for byte, with nothing else in <out>" \
    "$RO_DETAIL"
fi

# A directory holding only a dotfile is not empty: refused without --force.
DOT_OUT="$TMP_ROOT/name-dotonly"
mkdir -p "$DOT_OUT/dotonly"
printf 'KEY=1\n' >"$DOT_OUT/dotonly/.env"
cp -R "$DOT_OUT" "$TMP_ROOT/name-dotonly-before"
set +e
bash "$BUILD" --out "$DOT_OUT" --name dotonly >"$TMP_ROOT/name-dotonly.log" 2>&1
DOT_RC=$?
set -e
check "a directory holding only a dotfile is refused without --force (exit 2) and left byte for byte" \
  "$([ "$DOT_RC" -eq 2 ] || echo "rc=$DOT_RC")$(grep -qF '(pass --force)' "$TMP_ROOT/name-dotonly.log" || echo " log: $(head -n 1 "$TMP_ROOT/name-dotonly.log")")$(diff -r "$TMP_ROOT/name-dotonly-before" "$DOT_OUT" 2>&1 | head -n 5 || true)"

# The marker counts only as the exact line inside the leading frontmatter
# block: another indentation, text after it, the line quoted in a sentence or
# in a fenced block of the text are not the marker. (CR LF line ends are
# tolerated: see the check after this one.)
NM_OUT="$TMP_ROOT/name-nearmiss"
mkdir -p "$NM_OUT/indent0" "$NM_OUT/indent4" "$NM_OUT/sentence" "$NM_OUT/suffix" "$NM_OUT/quoted"
printf -- '---\nname: indent0\nsource: generated skill; do not edit by hand\n---\n' >"$NM_OUT/indent0/SKILL.md"
printf -- '---\nname: indent4\nmetadata:\n    source: generated skill; do not edit by hand\n---\n' >"$NM_OUT/indent4/SKILL.md"
printf -- '# sentence\n\nA built tree holds the line "  source: generated skill; do not edit by hand" in its frontmatter.\n' >"$NM_OUT/sentence/SKILL.md"
printf -- '---\nname: suffix\nmetadata:\n  source: generated skill; do not edit by hand (edited since)\n---\n' >"$NM_OUT/suffix/SKILL.md"
printf -- '---\nname: quoted\ndescription: by hand\n---\n\n# Quoted\n\n```yaml\nmetadata:\n  source: generated skill; do not edit by hand\n```\n' >"$NM_OUT/quoted/SKILL.md"
for n in indent0 indent4 sentence suffix quoted; do printf 'mine\n' >"$NM_OUT/$n/mine.txt"; done
cp -R "$NM_OUT" "$TMP_ROOT/name-nearmiss-before"
NM_REAL="$(CDPATH='' cd -- "$NM_OUT" && pwd)"
NM_DETAIL=""
for n in indent0 indent4 sentence suffix quoted; do
  set +e
  bash "$BUILD" --out "$NM_OUT" --name "$n" --force >"$TMP_ROOT/name-nearmiss-$n.log" 2>&1
  rc=$?
  set -e
  [ "$rc" -eq 2 ] || NM_DETAIL="$NM_DETAIL $n:rc=$rc"
  grep -qF "refusing to replace $NM_REAL/$n: it is not a skill this generator wrote" "$TMP_ROOT/name-nearmiss-$n.log" || NM_DETAIL="$NM_DETAIL $n:not-refused"
done
NM_DETAIL="$NM_DETAIL$(diff -r "$TMP_ROOT/name-nearmiss-before" "$NM_OUT" 2>&1 | head -n 5 || true)"
check "--force on a SKILL.md with a near-miss marker (other indentation, text after it, quoted in a sentence or in a fenced block of the text) exits 2 and leaves every file byte for byte" \
  "$NM_DETAIL"

# A generated tree checked out with CR LF line ends is still a generated
# tree: --force replaces it.
CRLF_OUT="$TMP_ROOT/name-crlf"
mkdir -p "$CRLF_OUT"
cp -R "$SKILL_DIR" "$CRLF_OUT/create-ticket"
awk '{ printf "%s\r\n", $0 }' "$SKILL_DIR/SKILL.md" >"$CRLF_OUT/create-ticket/SKILL.md"
set +e
bash "$BUILD" --out "$CRLF_OUT" --force >"$TMP_ROOT/name-crlf.log" 2>&1
CRLF_RC=$?
set -e
check "--force replaces a generated tree whose SKILL.md has CR LF line ends (exit 0, the tree equals the default build)" \
  "$([ "$CRLF_RC" -eq 0 ] || echo "rc=$CRLF_RC $(tail -n 1 "$TMP_ROOT/name-crlf.log")")$(diff -r "$SKILL_DIR" "$CRLF_OUT/create-ticket" 2>&1 | head -n 5 || true)"

# A publish whose first move fails after it created the directory leaves only
# the previous tree in <out>: a mv stand-in first on PATH fails for the
# incoming directory and runs the real mv otherwise.
STUB_BIN="$TMP_ROOT/name-stub-bin"
mkdir -p "$STUB_BIN"
REAL_MV="$(command -v mv)"
cat >"$STUB_BIN/mv" <<STUBEOF
#!/bin/sh
for last; do :; done
case "\$last" in
  */.*.incoming.*) mkdir -p "\$last/references"; echo partial >"\$last/SKILL.md"; echo "mv: stand-in: no space left" >&2; exit 1 ;;
esac
exec "$REAL_MV" "\$@"
STUBEOF
chmod +x "$STUB_BIN/mv"
PF_OUT="$TMP_ROOT/name-partial"
mkdir -p "$PF_OUT" "$TMP_ROOT/name-partial-tmp"
cp -R "$SKILL_DIR" "$PF_OUT/create-ticket"
printf 'old\n' >"$PF_OUT/create-ticket/old.txt"
cp -R "$PF_OUT/create-ticket" "$TMP_ROOT/name-partial-before"
set +e
PATH="$STUB_BIN:$PATH" TMPDIR="$TMP_ROOT/name-partial-tmp" bash "$BUILD" --out "$PF_OUT" --force >"$TMP_ROOT/name-partial.log" 2>&1
PF_RC=$?
set -e
check "a publish that fails after a partial copy exits 2 and leaves only the previous skill, byte for byte, in <out> and no staging directory" \
  "$([ "$PF_RC" -eq 2 ] || echo "rc=$PF_RC")$(grep -qF 'create-ticket is unchanged' "$TMP_ROOT/name-partial.log" || echo " log: $(tail -n 1 "$TMP_ROOT/name-partial.log")")$([ "$(entries_of "$PF_OUT")" = "create-ticket " ] || echo " <out> holds: $(entries_of "$PF_OUT")")$(diff -r "$TMP_ROOT/name-partial-before" "$PF_OUT/create-ticket" 2>&1 | head -n 5 || true)$([ -z "$(entries_of "$TMP_ROOT/name-partial-tmp")" ] || echo " left behind: $(entries_of "$TMP_ROOT/name-partial-tmp")")"

# A directory that cannot be listed is refused, not taken for empty; and a
# previous generated tree that cannot be removed completely is still replaced
# (it is moved aside first), with a WARNING naming what is left. Root reads
# and removes anything, so both are skipped for root.
if [ "$(id -u)" -eq 0 ]; then
  echo "  SKIP an unreadable <out>/<name> is refused and an undeletable previous tree is still replaced (running as root)"
else
  UR_OUT="$TMP_ROOT/name-unreadable"
  mkdir -p "$UR_OUT/mode0"
  printf 'mine\n' >"$UR_OUT/mode0/mine.txt"
  chmod 000 "$UR_OUT/mode0"
  UR_DETAIL=""
  for force in "" --force; do
    set +e
    bash "$BUILD" --out "$UR_OUT" --name mode0 ${force:+"$force"} >"$TMP_ROOT/name-unreadable.log" 2>&1
    rc=$?
    set -e
    [ "$rc" -eq 2 ] || UR_DETAIL="$UR_DETAIL mode0${force:+ $force}:rc=$rc"
    grep -qF 'mode0: it cannot be read' "$TMP_ROOT/name-unreadable.log" || UR_DETAIL="$UR_DETAIL mode0${force:+ $force}:message:$(tail -n 1 "$TMP_ROOT/name-unreadable.log")"
  done
  chmod 755 "$UR_OUT/mode0"
  [ "$(cat "$UR_OUT/mode0/mine.txt")" = "mine" ] || UR_DETAIL="$UR_DETAIL content-changed"
  [ "$(entries_of "$UR_OUT")" = "mode0 " ] || UR_DETAIL="$UR_DETAIL out-holds:$(entries_of "$UR_OUT")"
  check "a non-empty <out>/<name> that cannot be listed exits 2 (it cannot be read), with and without --force, and is left as it was" \
    "$UR_DETAIL"

  LK_OUT="$TMP_ROOT/name-locked-old"
  mkdir -p "$LK_OUT"
  cp -R "$SKILL_DIR" "$LK_OUT/create-ticket"
  printf 'old\n' >"$LK_OUT/create-ticket/references/old.txt"
  chmod 555 "$LK_OUT/create-ticket/references"
  set +e
  bash "$BUILD" --out "$LK_OUT" --force >"$TMP_ROOT/name-locked-old.log" 2>&1
  LK_RC=$?
  set -e
  LK_LEFT="$(sed -n 's/.*what is left of it is at \(.*\)$/\1/p' "$TMP_ROOT/name-locked-old.log" | head -n 1)"
  LK_DETAIL="$([ "$LK_RC" -eq 0 ] || echo "rc=$LK_RC $(tail -n 2 "$TMP_ROOT/name-locked-old.log")")$(grep -qF 'WARNING: the previous tree could not be removed completely' "$TMP_ROOT/name-locked-old.log" || echo ' no WARNING')$(diff -r "$SKILL_DIR" "$LK_OUT/create-ticket" 2>&1 | head -n 5 || true)"
  { [ -n "$LK_LEFT" ] && [ -f "$LK_LEFT/references/old.txt" ]; } || LK_DETAIL="$LK_DETAIL left-path-missing:$LK_LEFT"
  [ -z "$LK_LEFT" ] || { chmod -R u+w "$LK_LEFT" 2>/dev/null || true; }
  check "--force over a generated tree that cannot be removed completely still publishes the new tree (exit 0) and names what is left of the old one in a WARNING" \
    "$LK_DETAIL"
fi

# A failed build leaves the previous skill byte for byte: a copy of the
# generator whose own manifest copy has one more denylist row, one the
# canonical text trips, fails the exit audit of a --force rebuild. The failed
# tree is kept in the staging directory, outside <out>.
FAILED_TOOLS="$TMP_ROOT/gen-extra-deny/tools"
mkdir -p "$FAILED_TOOLS"
cp "$BUILD" "$FAILED_TOOLS/build-standalone-skill.sh"
cp -R "$MANIFEST_DIR" "$FAILED_TOOLS/standalone-skill"
printf 'Do not auto-invoke\n' >>"$FAILED_TOOLS/standalone-skill/denylist.txt"
FAILED_DETAIL=""
if [ -f "$FORCE_OUT/zq-x7/SKILL.md" ]; then
  cp -R "$FORCE_OUT/zq-x7" "$TMP_ROOT/name-force-before-failed"
  set +e
  bash "$FAILED_TOOLS/build-standalone-skill.sh" --src "$REPO_DIR" --out "$FORCE_OUT" --name zq-x7 --force >"$TMP_ROOT/name-force-failed.log" 2>&1
  rc=$?
  set -e
  [ "$rc" -eq 1 ] || FAILED_DETAIL="$FAILED_DETAIL rc=$rc"
  grep -qF 'exit audit FAILED' "$TMP_ROOT/name-force-failed.log" || FAILED_DETAIL="$FAILED_DETAIL no-exit-audit-failure:$(head -n 2 "$TMP_ROOT/name-force-failed.log")"
  grep -qF 'denylist [Do not auto-invoke] SKILL.md:' "$TMP_ROOT/name-force-failed.log" || FAILED_DETAIL="$FAILED_DETAIL the-extra-row-did-not-fire"
  FAILED_DETAIL="$FAILED_DETAIL$(diff -r "$TMP_ROOT/name-force-before-failed" "$FORCE_OUT/zq-x7" 2>&1 | head -n 5 || true)"
  LEFT_AT="$(sed -n 's/.* output left at \(.*\) for inspection.*/\1/p' "$TMP_ROOT/name-force-failed.log" | head -n 1)"
  [ -n "$LEFT_AT" ] || FAILED_DETAIL="$FAILED_DETAIL no-output-left-at-path"
  [ -z "$LEFT_AT" ] || [ -f "$LEFT_AT/SKILL.md" ] || FAILED_DETAIL="$FAILED_DETAIL left-at-path-missing:$LEFT_AT"
  FORCE_REAL="$(CDPATH='' cd -- "$FORCE_OUT" && pwd)"
  case "$LEFT_AT" in "$FORCE_REAL"/*|"$FORCE_OUT"/*) FAILED_DETAIL="$FAILED_DETAIL left-at-path-under-out:$LEFT_AT" ;; esac
  [ "$(entries_of "$FORCE_OUT")" = "create-ticket unrelated zq-x7 " ] || FAILED_DETAIL="$FAILED_DETAIL out-holds:$(entries_of "$FORCE_OUT")"
else
  FAILED_DETAIL="no previously generated <out>/zq-x7 to start from"
fi
check "a failed --force rebuild (exit audit) exits 1, leaves the previous <out>/zq-x7 byte for byte and keeps the failed tree at the printed path outside <out>" \
  "$FAILED_DETAIL"

# A build that stops with exit 2 (a source file missing) leaves nothing
# behind: no <out>/<name>, no staging directory.
MISS_SRC="$TMP_ROOT/src-missing"
mkdir -p "$MISS_SRC/skills/brief"
cp -R "$REPO_DIR/skills/create-ticket" "$MISS_SRC/skills/create-ticket"
cp -R "$REPO_DIR/skills/brief/references" "$MISS_SRC/skills/brief/references"
cp -R "$REPO_DIR/agents" "$MISS_SRC/agents"
cp -R "$REPO_DIR/.claude-plugin" "$MISS_SRC/.claude-plugin"
rm -f "$MISS_SRC/agents/planner.md"
mkdir -p "$TMP_ROOT/tmp-missing"
set +e
TMPDIR="$TMP_ROOT/tmp-missing" bash "$BUILD" --src "$MISS_SRC" --out "$TMP_ROOT/name-missing-out" >"$TMP_ROOT/name-missing.log" 2>&1
MISS_RC=$?
set -e
check "a build that stops on a missing source file exits 2 and leaves no <out>/create-ticket and no staging directory" \
  "$([ "$MISS_RC" -eq 2 ] || echo "rc=$MISS_RC")$(grep -qF 'source file missing: agents/planner.md' "$TMP_ROOT/name-missing.log" || echo " message: $(head -n 1 "$TMP_ROOT/name-missing.log")")$([ ! -e "$TMP_ROOT/name-missing-out/create-ticket" ] || echo ' <out>/create-ticket was created')$([ -z "$(entries_of "$TMP_ROOT/tmp-missing")" ] || echo " left behind: $(entries_of "$TMP_ROOT/tmp-missing")")"

# With an exported CDPATH that holds a directory of the same name as a
# relative --out, the tree lands under the working directory's --out.
CDP_DIR="$TMP_ROOT/cdpath"
CDP_WD="$TMP_ROOT/cdpath-wd"
mkdir -p "$CDP_DIR/rel-out" "$CDP_WD"
set +e
(cd "$CDP_WD" && CDPATH="$CDP_DIR" bash "$BUILD" --out rel-out >"$TMP_ROOT/cdpath.log" 2>&1)
CDP_RC=$?
set -e
check "a relative --out with an exported CDPATH lands under the working directory, and nothing is written under the CDPATH directory" \
  "$([ "$CDP_RC" -eq 0 ] || echo "rc=$CDP_RC $(head -n 3 "$TMP_ROOT/cdpath.log")")$([ -f "$CDP_WD/rel-out/create-ticket/SKILL.md" ] || echo ' no tree under the working directory')$([ -z "$(entries_of "$CDP_DIR/rel-out")" ] || echo " written under CDPATH: $(entries_of "$CDP_DIR/rel-out")")"

# What the skill does is stated without the name: in the description, under
# the top heading of SKILL.md and in the README; the README's Install says the
# name is not changed by hand.
WHAT_DETAIL=""
for d in "$SKILL_DIR" "$NAME_DIR"; do
  n="$(basename "$d")"
  [ -f "$d/SKILL.md" ] || { WHAT_DETAIL="$WHAT_DETAIL $n:no-SKILL.md"; continue; }
  fm="$(frontmatter_of "$d/SKILL.md")"
  grep -qx "name: $n" <<<"$fm" || WHAT_DETAIL="$WHAT_DETAIL $n:name-line"
  desc="$(printf '%s\n' "$fm" | description_of)"
  case "$desc" in "Do not auto-invoke. "*) ;; *) WHAT_DETAIL="$WHAT_DETAIL $n:description-does-not-start-with-Do-not-auto-invoke" ;; esac
  second="$(printf '%s\n' "$desc" | sed -E 's/^Do not auto-invoke\. ([^.]*\.).*/\1/')"
  case "$second" in *"$n"*) WHAT_DETAIL="$WHAT_DETAIL $n:the-purpose-sentence-uses-the-name" ;; esac
  for w in 'drafts implementation tickets' 'quality rubric' 'delivers them'; do
    case "$second" in *"$w"*) ;; *) WHAT_DETAIL="$WHAT_DETAIL $n:description-purpose:'$w'" ;; esac
  done
  grep -qF 'A request about tickets that does not name this skill is never a trigger.' <<<"$desc" || WHAT_DETAIL="$WHAT_DETAIL $n:closing-sentence"
  case "$desc" in *'A request about tickets that does not name this skill is never a trigger.') ;; *) WHAT_DETAIL="$WHAT_DETAIL $n:description-does-not-end-with-the-closing-sentence" ;; esac
  # The wording does not depend on the name being unusual: a name that is
  # also a word (tickets) or a command (grep) still reads as the skill.
  grep -qF 'The name used as an ordinary word does not name the skill. A request about tickets that does not name this skill is never a trigger.' <<<"$desc" || WHAT_DETAIL="$WHAT_DETAIL $n:description-ordinary-word-sentence"
  for role in planner researcher decomposer; do
    grep -qF "You MUST NOT run the \`$n\` skill (the skill that spawned you)" "$d/references/agents/$role.md" || WHAT_DETAIL="$WHAT_DETAIL $n:$role-never-run-the-skill"
  done
  top="$(awk -v H="# /$n" 'f && NF {print; exit} $0 == H {f = 1}' "$d/SKILL.md")"
  case "$top" in *"$n"*|'') WHAT_DETAIL="$WHAT_DETAIL $n:SKILL.md-top-sentence:'$top'" ;; esac
  case "$top" in *'implementation tickets'*'quality rubric'*) ;; *) WHAT_DETAIL="$WHAT_DETAIL $n:SKILL.md-top-sentence-purpose" ;; esac
  rtop="$(awk -v H="# $n" 'f && NF {print; exit} $0 == H {f = 1}' "$d/README.md")"
  case "$rtop" in *"$n"*|'') WHAT_DETAIL="$WHAT_DETAIL $n:README-first-paragraph" ;; esac
  case "$rtop" in *'implementation tickets'*) ;; *) WHAT_DETAIL="$WHAT_DETAIL $n:README-first-paragraph-purpose" ;; esac
  grep -qF "keeping its name \`$n\`" "$d/README.md" || WHAT_DETAIL="$WHAT_DETAIL $n:README-install-name"
  # shellcheck disable=SC2016  # literal backticks
  grep -qF 'The directory name must stay equal to the `name` in the frontmatter of `SKILL.md`, and neither may be changed by hand' "$d/README.md" || WHAT_DETAIL="$WHAT_DETAIL $n:README-install-rename-rule"
done
check "default and renamed trees: name: line, a description that starts with Do not auto-invoke., says without the name that the skill drafts, grades and delivers implementation tickets and ends with the name-as-a-word and closing sentences, the same under the SKILL.md top heading and in the README's first paragraph, the README's do-not-rename rule, and the planner, researcher and decomposer told not to run the <name> skill (the skill that spawned you)" \
  "$WHAT_DETAIL"

# Every occurrence of create-ticket in the default tree sits in a known name
# context, so a new context (one the rename might not read well in) has to be
# classified here first. Each context is "<before>|<after>" around the name
# (EREs without inner groups in <before>); occurrences are removed context by
# context and whatever is left is reported with its file and line.
# shellcheck disable=SC2016  # literal backticks and anchors
NAME_CONTEXTS='^name: |$
^# /?|$
\.[a-z]+/skills/|/
\.local/|-scratch
ERROR: | (cannot create|write refused|write failed|counter write failed|counter changed|delivery refused)
`|`
[Tt]he | (skill|orchestrator)
[`( ]/|[` ]|$
^/|[` ]|$'
NAME_SED=()
SEP="$(printf '\001')"
while IFS= read -r ctx; do
  NAME_SED+=(-e "s${SEP}(${ctx%%|*})create-ticket(${ctx#*|})${SEP}\\1@NAME@\\2${SEP}g")
done <<<"$NAME_CONTEXTS"
unclassified_in() { sed -E "${NAME_SED[@]}" "$1" | grep -nF 'create-ticket' | cut -c1-160 || true; }
UNCLASSIFIED=""
while IFS= read -r f; do
  h="$(unclassified_in "$SKILL_DIR/$f")"
  [ -z "$h" ] || UNCLASSIFIED="$UNCLASSIFIED
$(printf '%s\n' "$h" | sed "s#^#$f:#")"
done < <(printf '%s\n' "$ACTUAL")
check "every create-ticket in the default tree sits in a known name context (slash invocation, skill-root path, -scratch directory, ERROR: prefix, backticked name, frontmatter name:, top headings, the ... skill/orchestrator prose)" \
  "${UNCLASSIFIED#$'\n'}"
# shellcheck disable=SC2016  # literal backticks
printf 'one `create-ticket` and one create-ticket here\n' >"$TMP_ROOT/name-context-fixture.md"
# shellcheck disable=SC2016  # literal backticks
check "the context check reports an occurrence outside the known contexts" \
  "$([ "$(unclassified_in "$TMP_ROOT/name-context-fixture.md")" = '1:one `@NAME@` and one create-ticket here' ] || echo "got: $(unclassified_in "$TMP_ROOT/name-context-fixture.md")")"

# The name audit is the backstop for a context the probe does not hold, it
# catches a rename that missed occurrences, and it names a description the
# name made too long: proven on copies of the generator (with the probe
# switched off, with the g flag of the rename dropped, then with a padded
# description).
NB_TOOLS="$TMP_ROOT/name-backstop/tools"
mkdir -p "$NB_TOOLS"
cp -R "$MANIFEST_DIR" "$NB_TOOLS/standalone-skill"
# shellcheck disable=SC2016  # the literal variable name is the pattern
sed 's/^  if \[ -n "\$PROBE_FAIL" \]; then$/  if false; then/' "$BUILD" >"$NB_TOOLS/build-standalone-skill.sh"
if [ -z "$DENY_NAME" ]; then
  echo "  SKIP name audit backstop for a foreign tool name (no deny row of tool-vocabulary.txt is a valid skill name)"
elif [ "$(grep -c '^  if false; then$' "$NB_TOOLS/build-standalone-skill.sh" || true)" = 1 ]; then
  set +e
  bash "$NB_TOOLS/build-standalone-skill.sh" --src "$REPO_DIR" --out "$TMP_ROOT/name-backstop/out" --name "$DENY_NAME" >"$TMP_ROOT/name-backstop.log" 2>&1
  NBS_RC=$?
  set -e
  check "name audit backstop: with the probe switched off, --name $DENY_NAME fails the build (exit 1) with a foreign tool name finding attributed to the name, and publishes nothing" \
    "$([ "$NBS_RC" -eq 1 ] || echo "rc=$NBS_RC")$(grep -qF 'name audit FAILED' "$TMP_ROOT/name-backstop.log" || echo ' no name audit failure')$(grep -q "^  name audit (caused by --name $DENY_NAME): foreign tool name " "$TMP_ROOT/name-backstop.log" || echo " log: $(head -n 3 "$TMP_ROOT/name-backstop.log")")$([ -z "$(entries_of "$TMP_ROOT/name-backstop/out")" ] || echo " published: $(entries_of "$TMP_ROOT/name-backstop/out")")"
else
  fail "name audit backstop: the probe could not be switched off in the copy of the generator"
fi
# A rename that misses occurrences (the g flag dropped, so only the first
# create-ticket of each line is renamed) fails the occurrence count and the
# left-over check.
NG_TOOLS="$TMP_ROOT/name-backstop-g/tools"
mkdir -p "$NG_TOOLS"
cp -R "$MANIFEST_DIR" "$NG_TOOLS/standalone-skill"
# The lines sit in variables: bash 3.2 misreads a double quote inside single
# quotes inside "$( ... )".
# shellcheck disable=SC2016  # the literal variable names are the text
RENAME_G='  sed "s/$CANON_NAME/$NAME/g" "$p" >"$p.tmp"'
# shellcheck disable=SC2016  # the literal variable names are the text
RENAME_1='  sed "s/$CANON_NAME/$NAME/" "$p" >"$p.tmp"'
# shellcheck disable=SC2016  # the literal variable names are the pattern
sed 's|^  sed "s/\$CANON_NAME/\$NAME/g" "\$p" >"\$p.tmp"$|  sed "s/$CANON_NAME/$NAME/" "$p" >"$p.tmp"|' "$BUILD" >"$NG_TOOLS/build-standalone-skill.sh"
if [ "$(grep -cxF -- "$RENAME_G" "$BUILD" || true)" = 1 ] &&
   [ "$(grep -cxF -- "$RENAME_1" "$NG_TOOLS/build-standalone-skill.sh" || true)" = 1 ] &&
   [ "$(grep -cxF -- "$RENAME_G" "$NG_TOOLS/build-standalone-skill.sh" || true)" = 0 ]; then
  set +e
  bash "$NG_TOOLS/build-standalone-skill.sh" --src "$REPO_DIR" --out "$TMP_ROOT/name-backstop-g/out" --name zq-x7 >"$TMP_ROOT/name-backstop-g.log" 2>&1
  NBG_RC=$?
  set -e
  check "name audit backstop: a rename without the g flag (one create-ticket per line) fails the build (exit 1) on the occurrence count and on the create-ticket left, and publishes nothing" \
    "$([ "$NBG_RC" -eq 1 ] || echo "rc=$NBG_RC")$(grep -qF 'occurrence(s) of the name after the rename, expected' "$TMP_ROOT/name-backstop-g.log" || echo ' no occurrence-count finding')$(grep -qF 'occurrence(s) of create-ticket left after the rename' "$TMP_ROOT/name-backstop-g.log" || echo ' no left-over finding')$([ -z "$(entries_of "$TMP_ROOT/name-backstop-g/out")" ] || echo " published: $(entries_of "$TMP_ROOT/name-backstop-g/out")")"
  NBG_LEFT="$(sed -n 's/.* output left at \(.*\) for inspection.*/\1/p' "$TMP_ROOT/name-backstop-g.log" | head -n 1)"
  check "a failed name audit keeps the failed tree at the path it prints" \
    "$([ -n "$NBG_LEFT" ] || echo 'no output-left-at path')$([ -z "$NBG_LEFT" ] || [ -f "$NBG_LEFT/SKILL.md" ] || echo " no SKILL.md at $NBG_LEFT")"
else
  fail "name audit backstop: the g flag of the rename could not be dropped in the copy of the generator"
fi
# A generated file named after the skill fails the exit audit's variant check
# (the rename does not rename files): a copy of the generator whose own
# manifest copy maps one more destination, named Create_Ticket-notes.md.
NF_TOOLS="$TMP_ROOT/variant-file/tools"
mkdir -p "$NF_TOOLS"
cp "$BUILD" "$NF_TOOLS/build-standalone-skill.sh"
cp -R "$MANIFEST_DIR" "$NF_TOOLS/standalone-skill"
printf 'references/Create_Ticket-notes.md\tskills/create-ticket/references/ticket-template.md\n' >>"$NF_TOOLS/standalone-skill/files.tsv"
set +e
bash "$NF_TOOLS/build-standalone-skill.sh" --src "$REPO_DIR" --out "$TMP_ROOT/variant-file/out" >"$TMP_ROOT/variant-file.log" 2>&1
NF_RC=$?
set -e
check "exit audit variant check: a generated file named after the skill (references/Create_Ticket-notes.md) fails the build (exit 1) and publishes nothing" \
  "$([ "$NF_RC" -eq 1 ] || echo "rc=$NF_RC")$(grep -qF 'exit audit FAILED' "$TMP_ROOT/variant-file.log" || echo ' no exit audit failure')$(grep -qxF '  name in a file name (the rename does not rename files): references/Create_Ticket-notes.md' "$TMP_ROOT/variant-file.log" || echo " log: $(head -n 3 "$TMP_ROOT/variant-file.log")")$([ -z "$(entries_of "$TMP_ROOT/variant-file/out")" ] || echo " published: $(entries_of "$TMP_ROOT/variant-file/out")")"
# Pad the canonical description to 20 characters under the limit: the
# 64-character name (51 more than create-ticket) then overflows it.
PAD=$((1024 - 20 - ${#DESC}))
FM_OVR="$NB_TOOLS/standalone-skill/overrides/skill-frontmatter.md"
awk -v P="$(printf '%*s' $((PAD - 1)) '' | tr ' ' 'x')" '{print} /^  Do not auto-invoke\. / && !done {print "  " P; done = 1}' "$FM_OVR" >"$FM_OVR.pad"
mv "$FM_OVR.pad" "$FM_OVR"
if [ "$PAD" -gt 1 ] && grep -qE '^  x+$' "$FM_OVR"; then
  set +e
  bash "$NB_TOOLS/build-standalone-skill.sh" --src "$REPO_DIR" --out "$TMP_ROOT/name-backstop/long" --name "$N64" >"$TMP_ROOT/name-backstop-long.log" 2>&1
  NBL_RC=$?
  set -e
  check "name audit: a description pushed over 1024 characters by a 64-character name fails the build (exit 1) saying the name is too long for the description" \
    "$([ "$NBL_RC" -eq 1 ] || echo "rc=$NBL_RC")$(grep -qF 'the name is too long for the description' "$TMP_ROOT/name-backstop-long.log" || echo " log: $(head -n 3 "$TMP_ROOT/name-backstop-long.log")")"
else
  fail "name audit: the description of the copy could not be padded (pad $PAD)"
fi

# --- links and references/ paths ---------------------------------------------
BROKEN=""
# shellcheck disable=SC2016  # literal backticks, no expansion intended
REF_PATH_RE='`references/[A-Za-z0-9_./-]+`'
while IFS= read -r f; do
  fdir="$(dirname "$f")"
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    link="${m#*](}"; link="${link%)}"; link="${link%%#*}"
    case "$link" in ''|http://*|https://*|mailto:*) continue ;; esac
    [ -f "$SKILL_DIR/$fdir/$link" ] || BROKEN="$BROKEN
$f -> $link"
  done < <(grep -oE '\]\([^)[:space:]]+\)' "$SKILL_DIR/$f" || true)
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    p="${m#\`}"; p="${p%\`}"
    [ -e "$SKILL_DIR/$p" ] || BROKEN="$BROKEN
$f -> $p"
  done < <(grep -oE "$REF_PATH_RE" "$SKILL_DIR/$f" || true)
done < <(printf '%s\n' "$ACTUAL" | grep '\.md$')
check "every relative link and backticked references/ path resolves" "${BROKEN#$'\n'}"

# --- denylist, re-run independently --------------------------------------------
HITS=""
while IFS= read -r pat; do
  h="$(cd "$SKILL_DIR" && grep -rnE -- "$pat" . || true)"
  [ -z "$h" ] || HITS="$HITS
[$pat] $(head -n 3 <<<"$h" | cut -c1-160)"
done < <(manifest_lines "$MANIFEST_DIR/denylist.txt")
check "every denylist pattern has zero hits" "${HITS#$'\n'}"

# The decoupling entries must stay in the denylist (so the build fails when an
# upstream edit reintroduces them) and, re-run here with literal patterns
# independent of the manifest, must have zero hits in the generated tree.
DECOUPLE_ERES='simple-workflow
\.simple-workflow
product_backlog
\{ticket-dir\}
investigation_sha256'
MISSING_DENY=""
while IFS= read -r pat; do
  manifest_lines "$MANIFEST_DIR/denylist.txt" | grep -qxF -- "$pat" || MISSING_DENY="$MISSING_DENY '$pat'"
done <<<"$DECOUPLE_ERES"
check "denylist.txt carries every decoupling entry" "$MISSING_DENY"
DECOUPLE_HITS=""
while IFS= read -r pat; do
  h="$(cd "$SKILL_DIR" && grep -rnE -- "$pat" . || true)"
  [ -z "$h" ] || DECOUPLE_HITS="$DECOUPLE_HITS
[$pat] $(head -n 3 <<<"$h" | cut -c1-160)"
done <<<"$DECOUPLE_ERES"
check "no plugin name, backlog layout, ticket-dir or reuse key in the tree" "${DECOUPLE_HITS#$'\n'}"

# Plugin-internal jargon the generated tree does not define: each entry must
# stay in the denylist and, re-run here with literal patterns, have zero hits.
JARGON_ERES='eval_panel
L-UNIFORMITY
[Ii]mpl-side
\+1-independent
EC-STATIC\+natural
failure (mode|class) [A-Z]\b
downstream AC evaluator
downstream implementation step
downstream verifier\b
ac-evaluator
main-thread
load-bearing
(^|[^-A-Za-z0-9_])plan\.md
Mandatory Skill Invocations
upstream brief
build-standalone-skill
Stopped:
(^|[^/A-Za-z0-9_.-])tools/
Limitations` of your output file
([a-z,] |\()Read\b'
MISSING_DENY=""
while IFS= read -r pat; do
  manifest_lines "$MANIFEST_DIR/denylist.txt" | grep -qxF -- "$pat" || MISSING_DENY="$MISSING_DENY '$pat'"
done <<<"$JARGON_ERES"
check "denylist.txt carries every undefined-jargon entry" "$MISSING_DENY"
JARGON_HITS=""
while IFS= read -r pat; do
  h="$(cd "$SKILL_DIR" && grep -rnE -- "$pat" . || true)"
  [ -z "$h" ] || JARGON_HITS="$JARGON_HITS
[$pat] $(head -n 3 <<<"$h" | cut -c1-160)"
done <<<"$JARGON_ERES"
check "no undefined plugin jargon (eval panel, floor shorthands, role names, Read tool, generator paths)" "${JARGON_HITS#$'\n'}"
# The mid-sentence Read pattern must catch the tool-name form it targets
# and spare a sentence-initial verb.
check "the mid-sentence Read pattern catches the tool name, not a sentence-initial verb" \
  "$(printf 'attempt to Read, open\n(Read both files\n' | { grep -cE '([a-z,] |\()Read\b' || true; } | grep -qx 2 || echo 'misses a tool-name form')$(printf 'Read the brief.\n1. Read the ticket.\n' | grep -E '([a-z,] |\()Read\b' || true)"

DENY_TOOLS="$(manifest_lines "$MANIFEST_DIR/tool-vocabulary.txt" | awk '$1 == "deny" {printf "%s%s", sep, $2; sep = "|"}')"
check "no backticked host tool name (Claude Code or GitHub Copilot) remains" \
  "$(cd "$SKILL_DIR" && grep -rnE -- "\`($DENY_TOOLS)(\\([^\`]*\\))?\`" . | cut -c1-160 || true)"
# shellcheck disable=SC2016  # literal backticks
check "no tool named \`skill\`" "$(cd "$SKILL_DIR" && grep -rn '`skill` tool' . || true)"
check "no /Users/ path anywhere in the tree" "$(grep -rn '/Users/' "$SKILL_DIR" | cut -c1-160 || true)"

# --- rubric parity (zero-loss) -------------------------------------------------
SRC_RUBRIC="$REPO_DIR/skills/create-ticket/references/ac-quality-criteria.md"
GEN_RUBRIC="$SKILL_DIR/references/ac-quality-criteria.md"
SRC_GATES="$(grep -E '^#{2,3} Gate ' "$SRC_RUBRIC")"
GEN_GATES="$(grep -E '^#{2,3} Gate ' "$GEN_RUBRIC" || true)"
check "rubric Gate heading set is identical to the source ($(printf '%s\n' "$SRC_GATES" | wc -l | tr -d ' ') gates)" \
  "$(diff <(printf '%s\n' "$SRC_GATES") <(printf '%s\n' "$GEN_GATES") || true)"
terms() { awk '/^## Terminology/ {t = 1; next} t && /^## / {t = 0} t && /^- \*\*/ {n++} END {print n + 0}' "$1"; }
check "rubric Terminology entry count matches the source" \
  "$([ "$(terms "$SRC_RUBRIC")" = "$(terms "$GEN_RUBRIC")" ] || echo "$(terms "$SRC_RUBRIC") vs $(terms "$GEN_RUBRIC")")"
SRC_WC="$(wc -w <"$SRC_RUBRIC" | tr -d ' ')"
GEN_WC="$(wc -w <"$GEN_RUBRIC" | tr -d ' ')"
DELTA=$((GEN_WC - SRC_WC)); [ "$DELTA" -ge 0 ] || DELTA=$((-DELTA))
check "rubric word count within 5% of the source ($GEN_WC vs $SRC_WC)" \
  "$([ $((DELTA * 100)) -le $((SRC_WC * 5)) ] || echo "delta=$DELTA")"

# --- SKILL.md content ------------------------------------------------------------
SKILL_MD="$SKILL_DIR/SKILL.md"
MISSING=""
# shellcheck disable=SC2016  # literal backticks
for needle in '## Host notes' '## Delivery' 'SELF-EVALUATED' '**Tool roles**' 'the subagent tool' 'the ask-user tool' 'the file-read tool'; do
  grep -qF -- "$needle" "$SKILL_MD" || MISSING="$MISSING '$needle'"
done
check "SKILL.md carries Host notes, Delivery, SELF-EVALUATED and the tool-role phrases" "$MISSING"

# Host neutrality: no host name, no host-bound parameter or phrasing anywhere,
# each entry kept in the denylist and re-run here with literal patterns.
HOST_ERES='Copilot
GitHub\.com
cloud agent
agent_type
on (this|a|the) surface\b
surface offers no'
MISSING_DENY=""
while IFS= read -r pat; do
  manifest_lines "$MANIFEST_DIR/denylist.txt" | grep -qxF -- "$pat" || MISSING_DENY="$MISSING_DENY '$pat'"
done <<<"$HOST_ERES"
check "denylist.txt carries every host-neutrality entry" "$MISSING_DENY"
HOST_HITS=""
while IFS= read -r pat; do
  h="$(cd "$SKILL_DIR" && grep -rnE -- "$pat" . || true)"
  [ -z "$h" ] || HOST_HITS="$HOST_HITS
[$pat] $(head -n 3 <<<"$h" | cut -c1-160)"
done <<<"$HOST_ERES"
check "no host name or host-bound phrasing in the tree" "${HOST_HITS#$'\n'}"
COMPAT="$(printf '%s\n' "$FM" | sed -n 's/^compatibility:[[:space:]]*//p')"
check "frontmatter compatibility names capabilities, not a host" \
  "$([ -n "$COMPAT" ] || echo 'compatibility missing')$(printf '%s\n' "$COMPAT" | grep -oE 'Copilot|Claude|Cursor|Codex|Gemini|VS Code' || true)"
check "the tool-vocabulary denylist covers both the Claude Code and the GitHub Copilot names" \
  "$(for n in Read Write Edit Bash Grep Glob Agent AskUserQuestion view create edit bash task ask_user web_fetch glob powershell; do manifest_lines "$MANIFEST_DIR/tool-vocabulary.txt" | grep -qx "deny $n" || printf ' %s' "$n"; done)"

DEST_MD="$SKILL_DIR/references/destinations.md"
MISSING=""
for f in "$SKILL_MD" "$DEST_MD"; do
  # shellcheck disable=SC2016  # literal backticks
  for needle in 'destination=' '`local:' '`mcp:' '`api:' '`browser:' '`cli:'; do
    grep -qF -- "$needle" "$f" || MISSING="$MISSING ${f#"$SKILL_DIR"/}:'$needle'"
  done
done
check "SKILL.md and destinations.md name destination= and the local:/mcp:/api:/browser:/cli: kinds" "$MISSING"
HOST_NOTES="$(awk '/^## Host notes$/ {h = 1; next} h && /^## / {h = 0} h' "$SKILL_MD")"
check "Host notes cover the auth_env secret and non-transactional remote creates" \
  "$(grep -q 'auth_env' <<<"$HOST_NOTES" || echo 'no auth_env')$(grep -q 'not transactional' <<<"$HOST_NOTES" || echo ' no non-transactional note')"
check "the run scratch directory comes from mktemp -d" \
  "$(grep -qF 'mktemp -d' "$SKILL_MD" || echo 'mktemp -d missing from SKILL.md')"
# shellcheck disable=SC2016  # literal backticks
check "the run scratch directory lives under .local/ inside the working directory and is gitignored" \
  "$(grep -qF 'mktemp -d .local/create-ticket-scratch/run.XXXXXX' "$SKILL_MD" || echo 'relative mktemp template missing')$(grep -qF '`mkdir -p .local/create-ticket-scratch`' "$SKILL_MD" || echo ' mkdir command missing')$(grep -qF 'ERROR: create-ticket cannot create the scratch directory .local/create-ticket-scratch/ in the working directory (<reason>)' "$SKILL_MD" || echo ' scratch ERROR line missing')$(grep -rqF 'it may be absolute' "$SKILL_DIR/references/agents" && echo ' agent bodies keep the absolute-scratch exception' || true)$(grep -qF 'mkdir -p .local/create-ticket-scratch &&' "$SKILL_MD" && echo ' scratch creation is a joined command' || true)$(grep -qF '>> "<root>/.gitignore"' "$SKILL_MD" || echo ' gitignore append does not target the repository root file')$(grep -qF 'git check-ignore -q .create-ticket-scratch' "$SKILL_MD" && echo ' stale check-ignore scratch step' || true)$(grep -rqE 'system temporary directory \(|may be absolute \(Host|TMPDIR' "$SKILL_DIR" && echo ' stale system-temp wording' || true)"
# The old scratch literal must be gone per occurrence, not per line (one
# Argument Parsing line holds several occurrences).
check "no .create-ticket-scratch literal outside the .local/ form remains in the generated tree" \
  "$(grep -rn 'create-ticket-scratch' "$SKILL_DIR" | sed 's#\.local/create-ticket-scratch##g' | grep 'create-ticket-scratch' | cut -c1-160 || true)"
MISSING=""
for f in SKILL.md README.md references/destinations.md references/agent-spawn-prompts.md references/mode-dispatch-flows.md references/agents/researcher.md references/agents/planner.md references/agents/decomposer.md references/agents/ticket-evaluator.md; do
  grep -qF '.local/create-ticket-scratch' "$SKILL_DIR/$f" || MISSING="$MISSING $f"
done
check "the .local/create-ticket-scratch path is named in SKILL.md, the README, the references and every agent body" "$MISSING"
check "the researcher and planner are banned from running the product and from delete commands" \
  "$(for a in researcher planner; do grep -qF 'execution is not inspection' "$SKILL_DIR/references/agents/$a.md" || echo "no execution ban in $a.md"; grep -qF 'never run a delete command' "$SKILL_DIR/references/agents/$a.md" || echo "no delete ban in $a.md"; done)"
check "Phase 4 spawns every ticket's evaluator in one message" \
  "$(grep -qF 'spawn the initial evaluator of every ticket in one message' "$SKILL_MD" || echo 'concurrent evaluator rule missing')"
check "README names the scratch directory and no longer claims the skill was never run" \
  "$(grep -qF '.local/create-ticket-scratch/run.<id>/' "$SKILL_DIR/README.md" || echo 'scratch dir missing from README')$(grep -qF 'not yet been exercised' "$SKILL_DIR/README.md" && echo ' stale never-run claim' || true)"
check "no ticket is ever delivered as NOT EVALUATED" \
  "$(grep -rn 'NOT EVALUATED' "$SKILL_DIR" | cut -c1-160 || true)"
check "no MCP configuration file is read (mcp.json)" \
  "$(grep -rn 'mcp\.json' "$SKILL_DIR" | cut -c1-160 || true)"
MISSING=""
# shellcheck disable=SC2016  # literal braces and backticks
for needle in 'depth=' 'mcp_<name>=' '{skill_root}'; do
  grep -qF -- "$needle" "$SKILL_MD" || MISSING="$MISSING SKILL.md:'$needle'"
done
# shellcheck disable=SC2016  # literal regex and option text
for needle in 'mcp_<name>=' '--max-time' '-K -' '^[a-z0-9][a-z0-9-]{0,39}$'; do
  grep -qF -- "$needle" "$DEST_MD" || MISSING="$MISSING destinations.md:'$needle'"
done
check "depth=, mcp_<name>=, {skill_root}, curl --max-time / -K - and the slug pattern are present" "$MISSING"
MISSING=""
for f in "$SKILL_MD" "$DEST_MD"; do
  grep -qF -- 'confirm=yes' "$f" || MISSING="$MISSING ${f#"$SKILL_DIR"/}:'confirm=yes'"
done
grep -qE -- '--globoff|curl [^`]*-g ' "$DEST_MD" || MISSING="$MISSING destinations.md:'curl -g/--globoff'"
# shellcheck disable=SC2016  # literal braces
grep -rqF -- 'eval-{logical-id}' "$SKILL_DIR" || MISSING="$MISSING tree:'eval-{logical-id}'"
check "confirm=yes, curl --globoff and the evaluator report path are present" "$MISSING"

# --- Intake (source=) -------------------------------------------------------------
SOURCES_MD="$SKILL_DIR/references/sources.md"
XLSX_PY="$SKILL_DIR/scripts/xlsx_to_text.py"
MISSING=""
# shellcheck disable=SC2016  # literal backticks and braces
for needle in '## Intake' 'source=<spec>' 'source_auth_env=' '{intent}' '## Source dossier' 'source_refs' 'Partition basis'; do
  grep -qF -- "$needle" "$SKILL_MD" || MISSING="$MISSING SKILL.md:'$needle'"
done
for needle in '## `file:<path>`' '## `dir:<path>`' '## `mcp:<server>/<tool>' '## `api:<url>`' 'xlsx_to_text.py' '{python} -I' 'S<n>:L<a>-L<b>' '60,000' '150,000' 'source_auth_env' '## Source excerpts' 'Sources:' '## Partition basis'; do
  grep -qF -- "$needle" "$SOURCES_MD" || MISSING="$MISSING sources.md:'$needle'"
done
for needle in '## Source dossier handling' 'source_refs' '**Partition basis**' '## Source dossier' 'Dossier role: candidate' 'Dossier role: context'; do
  grep -qF -- "$needle" "$SKILL_DIR/references/agents/decomposer.md" || MISSING="$MISSING decomposer.md:'$needle'"
done
grep -qF -- '## `## Source dossier`' "$SKILL_DIR/references/spec-decomposer-input.md" || MISSING="$MISSING spec-decomposer-input.md:'## Source dossier'"
for needle in '## Source excerpts' 'Sources:' 'source dossier' 'dossier.md'; do
  grep -qF -- "$needle" "$SKILL_DIR/references/agent-spawn-prompts.md" || MISSING="$MISSING agent-spawn-prompts.md:'$needle'"
done
grep -qF -- 'Partition basis:' "$SKILL_DIR/references/write-path-templates.md" || MISSING="$MISSING write-path-templates.md:'Partition basis:'"
for needle in '{intent}' '## Source dossier' 'Dossier role: candidate' 'Dossier role: context'; do
  grep -qF -- "$needle" "$SKILL_DIR/references/mode-dispatch-flows.md" || MISSING="$MISSING mode-dispatch-flows.md:'$needle'"
done
check "Intake: SKILL.md, sources.md, the decomposer, its input spec, the spawn prompts and the summary carry the source= contract" "$MISSING"
INTAKE_LN="$(grep -n '^## Intake$' "$SKILL_MD" | cut -d: -f1)"
DISPATCH_LN="$(grep -n '^## Mode dispatch$' "$SKILL_MD" | cut -d: -f1)"
MISSING=""
for needle in '# create-ticket' '## Install' '## Usage' '/create-ticket' 'source=file:' 'destination=' 'SELF-EVALUATED' 'FAIL (user-accepted)' 'FAIL (unresolved)' 'confirm=yes' 'scripts/xlsx_to_text.py' '## Limits'; do
  grep -qF -- "$needle" "$SKILL_DIR/README.md" || MISSING="$MISSING README.md:'$needle'"
done
check "README.md documents install, usage, sources, destinations, verdicts, files and limits" "$MISSING"
check "the default destination is local:.local/tickets everywhere (no stale local:tickets)" \
  "$(grep -rn 'local:tickets' "$SKILL_DIR" | cut -c1-160 || true)$(grep -qF 'Absent, and no output statement in the request → `local:.local/tickets`' "$SKILL_MD" || echo ' SKILL.md lacks the .local/tickets default')$(grep -qF '.local/tickets/{parent-slug}' "$SKILL_DIR/references/write-path-templates.md" || echo ' summary examples lack .local/tickets')"
MISSING=""
# shellcheck disable=SC2016  # literal backticks
for needle in '**Prose resolution**' 'Resolved: <' '**Character rule**' 'parent=<id>' '[parent=<id>]'; do
  grep -qF -- "$needle" "$SKILL_MD" || MISSING="$MISSING SKILL.md:'$needle'"
done
for needle in 'Link to a parent item' 'parent-link parameters' '{parent}' 'required or optional'; do
  grep -qF -- "$needle" "$DEST_MD" || MISSING="$MISSING destinations.md:'$needle'"
done
for needle in '?sheet=<name>' '--sheet="<name>"' 'character rule'; do
  grep -qF -- "$needle" "$SOURCES_MD" || MISSING="$MISSING sources.md:'$needle'"
done
for needle in 'parent=<id>' '?sheet=<name>' 'Resolved:' 'local:.local/tickets'; do
  grep -qF -- "$needle" "$SKILL_DIR/README.md" || MISSING="$MISSING README.md:'$needle'"
done
grep -qF -- 'Parent: <id>' "$SKILL_DIR/references/write-path-templates.md" || MISSING="$MISSING write-path-templates.md:'Parent: <id>'"
check "prose resolution, the character rule, parent= and ?sheet= are documented where they apply" "$MISSING"
MISSING=""
# shellcheck disable=SC2016  # literal backticks
for needle in '## Writing a source' '**List split.**' '**Kind inference.**' '`mcp:` is never inferred' '### An MCP item named in prose' 'at most one lookup call is made per candidate server'; do
  grep -qF -- "$needle" "$SOURCES_MD" || MISSING="$MISSING sources.md:'$needle'"
done
for needle in 'comma-separated list of specs' '### An MCP item named in prose'; do
  grep -qF -- "$needle" "$SKILL_MD" || MISSING="$MISSING SKILL.md:'$needle'"
done
for needle in '**Several sources**' '**Kind left out**' '**In prose**' 'source=a.md,docs/,https://example.com/spec' 'A space does not separate sources'; do
  grep -qF -- "$needle" "$SKILL_DIR/README.md" || MISSING="$MISSING README.md:'$needle'"
done
check "comma-separated sources, kind inference (never mcp:) and the prose MCP lookup are documented in SKILL.md, sources.md and the README" "$MISSING"
MISSING=""
# shellcheck disable=SC2016  # literal backticks
for needle in '### Adapting the ticket template' 'with one exception, `references/ticket-template.md`' '**Do not rename or translate**' 'apply it again after updating'; do
  grep -qF -- "$needle" "$SKILL_DIR/README.md" || MISSING="$MISSING README.md:'$needle'"
done
for heading in '## {id}: [Title]' '### Background' '### Scope' '### Acceptance Criteria' '### Implementation Notes' '### Capabilities' '### Advisory Capabilities' '#### Capability Gaps' '#### Capability Skip Rationale' '#### Failure-Class Coverage (Gate 9)' '#### Peer-Set Uniformity (Gate 10)'; do
  grep -qF -- "$heading" "$SKILL_DIR/references/ticket-template.md" || MISSING="$MISSING ticket-template.md:'$heading'"
done
check "the README's template-editing rules name headings the shipped template actually has" "$MISSING"
check "no ASCII-only path pattern remains for user paths" \
  "$(grep -rn -F -e '^[A-Za-z0-9._~/-]+$' -e '^[A-Za-z0-9._/-]+$' "$SKILL_DIR" | cut -c1-160 || true)"
MISSING=""
# shellcheck disable=SC2016  # literal braces
for needle in '### Notes' '### Shapes' '### Images' '--extract-media' '--layout' '{scratch}/sources/S<n>-media' '(layout: cells)' '[unreadable: ...]' 'can show an image'; do
  grep -qF -- "$needle" "$SOURCES_MD" || MISSING="$MISSING sources.md:'$needle'"
done
# shellcheck disable=SC2016  # literal braces
grep -qF -- '{scratch}/sources/S<n>-media/' "$SKILL_MD" || MISSING="$MISSING SKILL.md:'{scratch}/sources/S<n>-media/'"
for needle in '### Notes' '### Shapes' '### Images' 'S<n>-media' 'can show an image' 'pivot tables and macros are not read'; do
  grep -qF -- "$needle" "$SKILL_DIR/README.md" || MISSING="$MISSING README.md:'$needle'"
done
for needle in 'structure-aware' '### Notes' '### Shapes' '### Images' '--extract-media' '--layout' 'S<n>-media'; do
  grep -qF -- "$needle" "$MANIFEST_DIR/README.md" || MISSING="$MISSING generator-README:'$needle'"
done
check "the structure-aware workbook reading (notes, shapes, images, layout, media directory) is documented in sources.md, SKILL.md and both READMEs" "$MISSING"
MISSING=""
ARGS_PART="$(awk '/^## Argument Parsing$/ {a = 1; next} a && /^## / {a = 0} a' "$SKILL_MD")"
# shellcheck disable=SC2016  # literal backticks
for needle in '`render=auto|off|excel|soffice`' '[render=auto|off|excel|soffice]' 'ERROR: render= must be auto, off, excel or soffice' 'prose never sets `confirm=`, `depth=`, `render=`'; do
  grep -qF -- "$needle" <<<"$ARGS_PART" || MISSING="$MISSING SKILL.md-Argument-Parsing:'$needle'"
done
printf '%s\n' "$FM" | grep -E '^argument-hint:' | grep -qF -- '[render=auto|off|excel|soffice]' || MISSING="$MISSING argument-hint:'render='"
grep -qF -- 'xlsx_render.py' "$SKILL_MD" || MISSING="$MISSING SKILL.md:'xlsx_render.py'"
# shellcheck disable=SC2016  # literal braces and backticks
for needle in '**Sheet rendering (optional)**' 'xlsx_render.py' 'Rendered:' '--only-if-structured "{scratch}/sources/S<n>.md"' '--out "{scratch}/sources/S<n>-render"' 'WARNING: source S<n> (<origin>): no sheet render (<reasons>)' '[transcribed from <pdf|image> by the file-read tool; wording and layout may be incomplete]' "ERROR: source=file:<path>: this host's file-read tool cannot show a <pdf|image> file" '[truncated: source S<n> has <k> pages; pages beyond 40 were not read]' 'not an OCR result' 'unsupported file kind (supported: .md .markdown .txt .csv .tsv .json .yaml .yml .html .htm .xlsx .pdf .png .jpg .jpeg .gif .webp and any other text file)'; do
  grep -qF -- "$needle" "$SOURCES_MD" || MISSING="$MISSING sources.md:'$needle'"
done
FILE_TABLE="$(awk '/^## `file:<path>`$/ {f = 1; next} f && /^## / {f = 0} f && /^\|/' "$SOURCES_MD")"
# shellcheck disable=SC2016  # literal backticks
grep -qE -- '^\| `\.pdf` \|' <<<"$FILE_TABLE" || MISSING="$MISSING sources-table:'.pdf'"
# shellcheck disable=SC2016  # literal backticks
grep -qE -- '^\| `\.png`, ' <<<"$FILE_TABLE" || MISSING="$MISSING sources-table:'.png'"
# shellcheck disable=SC2016  # literal backticks
for needle in '### Sheet rendering' '[render=auto|off|excel|soffice]' '`render=auto`' 'scripts/xlsx_render.py' 'Rendered:' '`.docx` sources are not supported' 'no OCR' 'not exercised by the test suite' 'the Windows shell interpreter (powershell.exe)'; do
  grep -qF -- "$needle" "$SKILL_DIR/README.md" || MISSING="$MISSING README.md:'$needle'"
done
grep -qF -- '.docx` and `.pdf` sources are not supported' "$SKILL_DIR/README.md" && MISSING="$MISSING README.md:'stale .pdf limit'"
# shellcheck disable=SC2016  # literal backticks
for needle in 'scripts/xlsx_render.py' 'overrides/scripts-xlsx-render.md' 'render=auto|off|excel|soffice'; do
  grep -qF -- "$needle" "$MANIFEST_DIR/README.md" || MISSING="$MISSING generator-README:'$needle'"
done
grep -qxF -- $'scripts/xlsx_render.py\t-' "$MANIFEST_DIR/files.tsv" || MISSING="$MISSING files.tsv:'scripts/xlsx_render.py'"
HOST_PART="$(awk '/^## Host notes$/ {h = 1; next} h && /^## / {h = 0} h' "$SKILL_MD")"
# shellcheck disable=SC2016  # literal backticks
for needle in 'xlsx_render.py' '`osascript`' 'the Windows shell interpreter (powershell.exe)' '`soffice`' 'approves what it launches' 'is optional'; do
  grep -qF -- "$needle" <<<"$HOST_PART" || MISSING="$MISSING Host-notes:'$needle'"
done
check "render=, the sheet render chain, its Rendered: line and the PDF / image sources are documented in SKILL.md, sources.md and both READMEs" "$MISSING"
check "Intake precedes Mode dispatch in SKILL.md" \
  "$({ [ -n "$INTAKE_LN" ] && [ -n "$DISPATCH_LN" ] && [ "$INTAKE_LN" -lt "$DISPATCH_LN" ]; } || echo "intake=$INTAKE_LN dispatch=$DISPATCH_LN")"
check "the evaluator spawn carries nothing from the dossier" \
  "$(grep -n -i 'dossier' "$SKILL_DIR/references/agents/ticket-evaluator.md" | cut -c1-160 || true)"
check "the xlsx converter is ASCII-only, backtick-free and starts with a python3 shebang" \
  "$(head -n 1 "$XLSX_PY" | grep -qx '#!/usr/bin/env python3' || echo 'no shebang')$(grep -n '`' "$XLSX_PY" | head -n 3 || true)$(LC_ALL=C grep -n '[^ -~]' "$XLSX_PY" | head -n 3 || true)"
if command -v python3 >/dev/null 2>&1; then
  FIX_DIR="$TMP_ROOT/xlsx"
  mkdir -p "$FIX_DIR"
  cat >"$FIX_DIR/make_fixture.py" <<'PYFIX'
import zipfile, sys
out = sys.argv[1]
broken = len(sys.argv) > 2 and sys.argv[2] == "--broken"
SML = "application/vnd.openxmlformats-officedocument.spreadsheetml."
ct = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/xl/workbook.xml" ContentType="''' + SML + '''sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="''' + SML + '''worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="''' + SML + '''worksheet+xml"/><Override PartName="/xl/worksheets/sheet3.xml" ContentType="''' + SML + '''worksheet+xml"/><Override PartName="/xl/worksheets/sheet4.xml" ContentType="''' + SML + '''worksheet+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="''' + SML + '''sharedStrings+xml"/><Override PartName="/xl/styles.xml" ContentType="''' + SML + '''styles+xml"/><Override PartName="/xl/comments1.xml" ContentType="''' + SML + '''comments+xml"/><Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/><Override PartName="/xl/charts/chart1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/><Override PartName="/xl/threadedComments/threadedComment2.xml" ContentType="application/vnd.ms-excel.threadedcomments+xml"/><Override PartName="/xl/persons/person.xml" ContentType="application/vnd.ms-excel.person+xml"/></Types>'''
rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'''
wb = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Backlog" sheetId="1" r:id="rId1"/><sheet name="Notes" sheetId="2" state="hidden" r:id="rId2"/><sheet name="Grid" sheetId="3" r:id="rId5"/><sheet name="Wide" sheetId="4" r:id="rId7"/></sheets></workbook>'''
wbrels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/><Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/><Relationship Id="rId7" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet4.xml"/><Relationship Id="rId6" Type="http://schemas.microsoft.com/office/2017/10/relationships/person" Target="persons/person.xml"/></Relationships>'''
sst = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="6" uniqueCount="6"><si><t>ID</t></si><si><t>Title</t></si><si><r><t>Add </t></r><r><rPr><b/></rPr><t>login | form</t></r><rPh sb="0" eb="3"><t>PHONETIC</t></rPh></si><si><t>Due</t></si><si><r><t>keep </t></r><r><rPr><strike/></rPr><t>struck run</t></r><r><rPr><strike val="0"/></rPr><t> plain run</t></r></si><si><r><rPr><b/></rPr><t>bold</t></r><r><rPr><sz val="11"/></rPr><t> word</t></r></si></sst>'''
styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy/mm/dd"/></numFmts><fonts count="2"><font><sz val="11"/></font><font><strike/><sz val="11"/></font></fonts><cellXfs count="4"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/><xf numFmtId="0" fontId="1"/></cellXfs></styleSheet>'''
s1 = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><cols><col min="5" max="5" width="0" hidden="1"/></cols><sheetData>
<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>3</v></c><c r="D1" t="inlineStr"><is><t>Done</t></is></c><c r="E1" t="inlineStr"><is><t>Owner</t></is></c></row>
<row r="2"><c r="A2"><v>1</v></c><c r="B2" t="s"><v>2</v></c><c r="C2" s="1"><v>45000</v></c><c r="D2" t="b"><v>1</v></c></row>
<row r="4"><c r="A4"><v>2.5</v></c><c r="B4" t="str"><f>CONCATENATE("a","b")</f><v>ab</v></c><c r="C4" s="2"><v>45000.5</v></c><c r="D4" t="e"><v>#N/A</v></c></row>
<row r="5"><c r="A5"><v>3</v></c><c r="BM5"><v>99</v></c></row>
<row r="6"><c r="A6"><v>4</v></c><c r="B6" t="inlineStr"><is><t xml:space="preserve">first line
second   line</t></is></c></row>
<row r="7" hidden="1"><c r="A7"><v>5</v></c><c r="B7" t="inlineStr"><is><t>old version</t></is></c></row>
<row r="8"><c r="A8"><v>6</v></c><c r="B8" t="s"><v>4</v></c><c r="C8" t="inlineStr" s="3"><is><t>whole cell struck</t></is></c><c r="D8" t="s" s="3"><v>5</v></c><c r="E8" t="s" s="3"><v>4</v></c></row>
<row r="9"><c r="A9" t="inlineStr"><is><t>Section heading</t></is></c></row>
</sheetData><mergeCells count="2"><mergeCell ref="A9:C9"/><mergeCell ref="E10:E11"/></mergeCells><drawing r:id="rId2"/></worksheet>'''
s1rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments" Target="../comments1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/><Relationship Id="rId3" Type="http://schemas.microsoft.com/office/2017/10/relationships/threadedComment" Target="../threadedComments/threadedComment2.xml"/></Relationships>'''
comments = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<comments xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><authors><author>Reviewer A</author></authors><commentList><comment ref="C4" authorId="0"><text><r><t xml:space="preserve">confirm the
time zone</t></r></text></comment><comment ref="B2" authorId="0"><text><t>needs a spec</t></text></comment><comment ref="E9" authorId="0"><text><t>[Threaded comment] this note is shown as a threaded comment</t></text></comment></commentList></comments>'''
XDR = 'xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
def frm(tag, col, row):
    return "<xdr:%s><xdr:col>%d</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>%d</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:%s>" % (tag, col, row, tag)
def sp(i, name, paras):
    body = "".join("<a:p><a:r><a:t>%s</a:t></a:r></a:p>" % p for p in paras)
    return '<xdr:sp><xdr:nvSpPr><xdr:cNvPr id="%d" name="%s"/><xdr:cNvSpPr txBox="1"/></xdr:nvSpPr><xdr:spPr/><xdr:txBody><a:bodyPr/>%s</xdr:txBody></xdr:sp>' % (i, name, body)
drawing = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<xdr:wsDr %s>' % XDR
    + "<xdr:twoCellAnchor>" + frm("from", 2, 4) + frm("to", 5, 8) + sp(2, "TextBox 1", ["First paragraph", "Second paragraph"]) + "<xdr:clientData/></xdr:twoCellAnchor>"
    + '<xdr:oneCellAnchor>' + frm("from", 0, 11) + '<xdr:ext cx="1" cy="1"/><xdr:grpSp><xdr:nvGrpSpPr><xdr:cNvPr id="3" name="Group 2"/><xdr:cNvGrpSpPr/></xdr:nvGrpSpPr><xdr:grpSpPr/>' + sp(4, "Callout 3", ["Grouped callout"]) + "</xdr:grpSp><xdr:clientData/></xdr:oneCellAnchor>"
    + "<xdr:oneCellAnchor>" + frm("from", 0, 13) + '<xdr:ext cx="1" cy="1"/>' + sp(8, "Lead 7", ["", "after an empty paragraph"]) + "<xdr:clientData/></xdr:oneCellAnchor>"
    + "<xdr:oneCellAnchor>" + frm("from", 0, 15) + '<xdr:ext cx="1" cy="1"/><xdr:sp><xdr:nvSpPr><xdr:cNvPr id="9" name="Break 8"/><xdr:cNvSpPr txBox="1"/></xdr:nvSpPr><xdr:spPr/><xdr:txBody><a:bodyPr/><a:p><a:r><a:t>ends in a break</a:t></a:r><a:br/></a:p><a:p><a:r><a:t>next paragraph</a:t></a:r></a:p></xdr:txBody></xdr:sp><xdr:clientData/></xdr:oneCellAnchor>'
    + "<xdr:twoCellAnchor>" + frm("from", 6, 1) + frm("to", 8, 3) + '<xdr:cxnSp><xdr:nvCxnSpPr><xdr:cNvPr id="5" name="Connector 4"/><xdr:cNvCxnSpPr/></xdr:nvCxnSpPr><xdr:spPr/></xdr:cxnSp><xdr:clientData/></xdr:twoCellAnchor>'
    + "<xdr:twoCellAnchor>" + frm("from", 9, 1) + frm("to", 14, 12) + '<xdr:graphicFrame><xdr:nvGraphicFramePr><xdr:cNvPr id="6" name="Chart 5"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr><xdr:xfrm/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" r:id="rId2"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>'
    + "<xdr:twoCellAnchor>" + frm("from", 1, 9) + frm("to", 4, 19) + '<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="7" name="Picture 6"/><xdr:cNvPicPr/></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rId1"/></xdr:blipFill><xdr:spPr/></xdr:pic><xdr:clientData/></xdr:twoCellAnchor>'
    + "</xdr:wsDr>")
drels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart1.xml"/></Relationships>'''
chart = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart/></c:chartSpace>'''
png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 62
s2 = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>hidden note</t></is></c></row></sheetData></worksheet>'''
s3 = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
<row r="1"><c r="A1" t="inlineStr"><is><t>Title block</t></is></c><c r="O1" t="inlineStr"><is><t>far right</t></is></c></row>
<row r="2"><c r="T2" t="inlineStr"><is><t>edge</t></is></c></row>
<row r="3"><c r="A3" t="inlineStr"><is><t>footer</t></is></c><c r="T3"><v>7</v></c></row>
</sheetData><mergeCells count="2"><mergeCell ref="A1:B2"/><mergeCell ref="BZ1:CA2"/></mergeCells></worksheet>'''
# Wide: sparse and wide with no merged range, so only the sparse branch of auto applies.
s4 = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
<row r="1"><c r="A1" t="inlineStr"><is><t>wide start</t></is></c><c r="O1" t="inlineStr"><is><t>wide middle</t></is></c></row>
<row r="2"><c r="T2" t="inlineStr"><is><t>wide edge</t></is></c></row>
</sheetData></worksheet>'''
# --broken: the drawing member is left out, the hidden sheet relates a drawing
# whose target climbs out of the package and a threaded comment, the
# declared persons part is malformed, Backlog declares a legacy drawing whose
# id its relationship part lacks, and Grid declares a drawing with no
# relationship part at all; every gap must leave a marker.
s2rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../../../outside.xml"/><Relationship Id="rId2" Type="http://schemas.microsoft.com/office/2017/10/relationships/threadedComment" Target="../threadedComments/threadedComment1.xml"/></Relationships>'''
threaded = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<ThreadedComments xmlns="http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments"><threadedComment ref="A1" dT="2024-01-01T00:00:00.00" personId="{P1}" id="{T1}"><text>threaded text</text></threadedComment></ThreadedComments>'''
threaded2 = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<ThreadedComments xmlns="http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments"><threadedComment ref="E9" dT="2024-01-02T00:00:00.00" personId="{P2}" id="{T2}"><text>threaded body</text></threadedComment></ThreadedComments>'''
persons = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<personList xmlns="http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments"><person displayName="Pat Person" id="{P2}" userId="pat" providerId="None"/></personList>'''
if broken:
    persons = "<personList><person"
    s1 = s1.replace('<drawing r:id="rId2"/>', '<drawing r:id="rId2"/><legacyDrawing r:id="rId9"/>')
    s3 = s3.replace("</mergeCells>", '</mergeCells><drawing xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="rId8"/>')
    ct = ct.replace("</Types>", '<Override PartName="/xl/threadedComments/threadedComment1.xml" ContentType="application/vnd.ms-excel.threadedcomments+xml"/></Types>')
    ct = ct.replace('<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>', "")
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("[Content_Types].xml", ct); z.writestr("_rels/.rels", rels); z.writestr("xl/workbook.xml", wb)
    z.writestr("xl/_rels/workbook.xml.rels", wbrels); z.writestr("xl/sharedStrings.xml", sst); z.writestr("xl/styles.xml", styles)
    z.writestr("xl/worksheets/sheet1.xml", s1); z.writestr("xl/worksheets/sheet2.xml", s2); z.writestr("xl/worksheets/sheet3.xml", s3); z.writestr("xl/worksheets/sheet4.xml", s4)
    z.writestr("xl/worksheets/_rels/sheet1.xml.rels", s1rels); z.writestr("xl/comments1.xml", comments)
    z.writestr("xl/threadedComments/threadedComment2.xml", threaded2); z.writestr("xl/persons/person.xml", persons)
    if broken:
        z.writestr("xl/worksheets/_rels/sheet2.xml.rels", s2rels); z.writestr("xl/threadedComments/threadedComment1.xml", threaded)
    else:
        z.writestr("xl/drawings/drawing1.xml", drawing)
    z.writestr("xl/drawings/_rels/drawing1.xml.rels", drels); z.writestr("xl/charts/chart1.xml", chart); z.writestr("xl/media/image1.png", png)
print("fixture written", out)
PYFIX
  python3 -I "$FIX_DIR/make_fixture.py" "$FIX_DIR/fixture.xlsx" >/dev/null
  set +e
  XLSX_OUT="$(python3 -I "$XLSX_PY" "$FIX_DIR/fixture.xlsx" 2>"$FIX_DIR/err.txt")"; XLSX_RC=$?
  set -e
  MISSING=""
  [ "$XLSX_RC" -eq 0 ] || MISSING="$MISSING rc=$XLSX_RC:$(head -n 1 "$FIX_DIR/err.txt")"
  for needle in '## Sheet: Backlog' '| row | c1 | c2 | c3 | c4 |' '| 1 | ID | Title | Due | Done |' 'Add login \| form' '2023-03-15 | TRUE' '2023-03-15T12:00:00 | #N/A' '| 5 | 3 |  |  |  |' '[truncated: sheet Backlog has columns beyond c64' '## Sheet: Notes (hidden)' 'hidden note'; do
    grep -qF -- "$needle" <<<"$XLSX_OUT" || MISSING="$MISSING '$needle'"
  done
  grep -qF -- 'PHONETIC' <<<"$XLSX_OUT" && MISSING="$MISSING 'phonetic rPh run leaked into the cell text'"
  # The fixture covers: shared / rich / inline strings with a phonetic run,
  # numbers, dates, booleans, errors and formulas, a hidden sheet, the column
  # cap, an in-cell line break, two merged ranges (one with an empty top-left
  # cell), a struck run, a struck cell style (also under runs whose run font
  # holds no strike element, and under a run whose strike val="0"), a hidden
  # row and column, a legacy notes part, a threaded comment on a cell whose
  # legacy note is the threaded placeholder (author from a well-formed persons
  # part), a drawing (text box, a shape whose first paragraph is empty, a shape
  # whose paragraph ends in a line break, group,
  # connector, chart, picture with its media member) and a sparse wide third
  # sheet with a 2x2 merge. The --broken variant drops
  # the drawing member, relates a drawing whose target leaves the package and
  # a threaded comment whose declared persons part is malformed.
  check "xlsx converter: shared / rich / inline strings, numbers, dates, booleans, errors, formulas, hidden sheets and the column cap" "$MISSING"
  XLSX_OUT2="$(python3 -I "$XLSX_PY" "$FIX_DIR/fixture.xlsx" --max-rows 2 --max-cols 3 2>/dev/null)"
  MISSING=""
  grep -qF -- '[truncated: sheet Backlog has more than 2 rows; only the first 2 were read]' <<<"$XLSX_OUT2" || MISSING="$MISSING 'row cap marker'"
  grep -qF -- '[truncated: sheet Backlog has columns beyond c3' <<<"$XLSX_OUT2" || MISSING="$MISSING 'column cap marker'"
  grep -qF -- '| 4 |' <<<"$XLSX_OUT2" && MISSING="$MISSING 'row 4 leaked past the cap'"
  grep -qF -- '[truncated: sheet Grid has columns beyond c64' <<<"$XLSX_OUT" || MISSING="$MISSING 'merged range beyond the column cap not marked'"
  XLSX_OUT3="$(python3 -I "$XLSX_PY" "$FIX_DIR/fixture.xlsx" --max-chars 120 2>/dev/null)"
  grep -qF -- '[truncated: output exceeds 120 characters' <<<"$XLSX_OUT3" || MISSING="$MISSING 'char cap marker'"
  # The cap is a total: the marker line counts toward it (the command
  # substitution drops the one trailing newline, hence the + 1), and a cap
  # shorter than the marker prints the marker alone.
  XLSX_OUT3_LEN="$(python3 -I "$XLSX_PY" "$FIX_DIR/fixture.xlsx" --max-chars 120 2>/dev/null | python3 -c 'import sys; print(len(sys.stdin.buffer.read().decode("utf-8")))')"
  [ "$XLSX_OUT3_LEN" -le 120 ] || MISSING="$MISSING 'char cap exceeded by its marker ($XLSX_OUT3_LEN > 120)'"
  XLSX_OUT3B="$(python3 -I "$XLSX_PY" "$FIX_DIR/fixture.xlsx" --max-chars 10 2>/dev/null)"
  [ "$XLSX_OUT3B" = "$(printf '\n[truncated: output exceeds 10 characters; the rest of the workbook was not emitted]')" ] || MISSING="$MISSING 'a cap below the marker does not print the marker alone'"
  check "xlsx converter: every cap is marked, never silent" "$MISSING"
  XLSX_OUT4="$(python3 -I "$XLSX_PY" --sheet=Notes -- "$FIX_DIR/fixture.xlsx" 2>/dev/null)"
  MISSING=""
  grep -qF -- '## Sheet: Notes (hidden)' <<<"$XLSX_OUT4" || MISSING="$MISSING 'selected sheet missing'"
  grep -qF -- '## Sheet: Backlog' <<<"$XLSX_OUT4" && MISSING="$MISSING 'unselected sheet leaked'"
  set +e
  SHEET_ERR="$(python3 -I "$XLSX_PY" "$FIX_DIR/fixture.xlsx" --sheet Nope 2>&1 >/dev/null)"; SHEET_RC=$?
  set -e
  [ "$SHEET_RC" -eq 2 ] || MISSING="$MISSING 'unknown sheet rc=$SHEET_RC'"
  grep -qF -- 'the workbook has: Backlog, Notes' <<<"$SHEET_ERR" || MISSING="$MISSING 'unknown sheet does not list the names'"
  check "xlsx converter: --sheet selects one worksheet and an unknown name exits 2 listing the names" "$MISSING"
  # has_all OUT NEEDLE... — prints every NEEDLE missing from OUT (fixed strings).
  has_all() {
    local text="$1" n
    shift
    for n in "$@"; do grep -qF -- "$n" <<<"$text" || printf " '%s'" "$n"; done
  }
  check "xlsx converter: an in-cell line break prints as <br>, other whitespace collapses" \
    "$(has_all "$XLSX_OUT" '| 6 | 4 | first line<br>second line |')"
  check "xlsx converter: merged ranges mark their top-left cell, an empty one included" \
    "$(has_all "$XLSX_OUT" '| 9 | [merged c1-c3] Section heading |  |' '|  | [merged rows 10-11] |')"
  check "xlsx converter: a struck run and a struck cell style print as ~~text~~ (val=0 is not struck)" \
    "$(has_all "$XLSX_OUT" '| 8 | 6 | keep ~~struck run~~ plain run | ~~whole cell struck~~ |')"
  check "xlsx converter: a struck cell style strikes the whole value when its runs carry run fonts without a strike element" \
    "$(has_all "$XLSX_OUT" '| ~~whole cell struck~~ | ~~bold word~~ |')"
  check "xlsx converter: a struck cell style strikes the whole value once, a run with strike val=0 included" \
    "$(has_all "$XLSX_OUT" '| ~~bold word~~ | ~~keep struck run plain run~~ |')"
  check "xlsx converter: a hidden row and a hidden column are marked and still printed" \
    "$(has_all "$XLSX_OUT" '| 7 (hidden) | 5 | old version |' '| row | c1 | c2 | c3 | c4 | c5 (hidden) |' '| Done | Owner |')"
  NOTES_PART="$(awk '/^### Notes$/ {n = 1; next} n && /^$/ {exit} n' <<<"$XLSX_OUT")"
  check "xlsx converter: ### Notes lists each note with its cell, author and text in row order" \
    "$(has_all "$XLSX_OUT" '### Notes')$(printf '%s\n' "$NOTES_PART" | sed -n 1p | grep -qxF -- '- c2 row 2 (B2), Reviewer A: needs a spec' || echo ' first note line')$(printf '%s\n' "$NOTES_PART" | sed -n 2p | grep -qxF -- '- c3 row 4 (C4), Reviewer A: confirm the<br>time zone' || echo ' second note line')"
  check "xlsx converter: a threaded comment replaces the legacy placeholder of its cell and takes its author from the persons part" \
    "$(printf '%s\n' "$NOTES_PART" | sed -n 3p | grep -qxF -- '- c5 row 9 (E9), Pat Person: threaded body' || echo ' threaded note line')$([ "$(printf '%s\n' "$NOTES_PART" | grep -c .)" = 3 ] || echo ' ### Notes does not hold exactly 3 lines')$(printf '%s\n' "$XLSX_OUT" | grep -F '[Threaded comment]' || true)"
  SHAPES_PART="$(awk '/^### Shapes$/ {n = 1; next} n && /^$/ {exit} n' <<<"$XLSX_OUT")"
  check "xlsx converter: ### Shapes lists text boxes, grouped shapes and charts, never connectors" \
    "$(has_all "$XLSX_OUT" '### Shapes' '- "TextBox 1" at c3 row 5 to c6 row 9: First paragraph<br>Second paragraph' '- "Callout 3" at c1 row 12: Grouped callout' '- chart "Chart 5" at c10 row 2 to c15 row 13: (chart; data not read)' '- "Lead 7" at c1 row 14: <br>after an empty paragraph' '- "Break 8" at c1 row 16: ends in a break<br><br>next paragraph')$(printf '%s\n' "$XLSX_OUT" | grep -F -e 'Connector 4' -e 'at c7 row 2 to c9 row 4' || true)$([ "$(printf '%s\n' "$SHAPES_PART" | grep -c .)" = 5 ] || echo ' ### Shapes does not hold exactly 5 lines')"
  check "xlsx converter: ### Images lists each picture with its media name and byte count, nothing extracted by default" \
    "$(has_all "$XLSX_OUT" '### Images' '- "Picture 6" at c2 row 10 to c5 row 20: image1.png (70 bytes)')$(printf '%s\n' "$XLSX_OUT" | grep -F 'extracted to' || true)"
  XLSX_MEDIA="$(python3 -I "$XLSX_PY" --extract-media "$FIX_DIR/media" -- "$FIX_DIR/fixture.xlsx" 2>&1)"
  check "xlsx converter: --extract-media writes the image as <sheet-slug>-<media name> and says so" \
    "$(has_all "$XLSX_MEDIA" "image1.png (70 bytes), extracted to $FIX_DIR/media/Backlog-image1.png")$([ "$(wc -c <"$FIX_DIR/media/Backlog-image1.png" 2>/dev/null | tr -d ' ')" = 70 ] || echo ' media file missing or wrong size')$([ "$(find "$FIX_DIR/media" -type f | wc -l | tr -d ' ')" = 1 ] || echo ' unexpected files in the media dir')"
  check "xlsx converter: auto picks the cells layout for the sparse wide sheet and keeps the table elsewhere" \
    "$(has_all "$XLSX_OUT" '## Sheet: Grid (layout: cells)' '- r1 c1 [merged c1-c2 rows 1-2]: Title block' '- r1 c15: far right' '- r2 c20: edge')$(grep -qx '## Sheet: Backlog' <<<"$XLSX_OUT" || echo ' Backlog heading changed')"
  check "xlsx converter: auto picks cells on either branch alone (a sparse wide sheet without a merge; a narrow sheet with a 2x2 merge)" \
    "$(has_all "$XLSX_OUT" '## Sheet: Wide (layout: cells)' '- r2 c20: wide edge')$(has_all "$XLSX_OUT2" '## Sheet: Grid (layout: cells)' '- r1 c1 [merged c1-c2 rows 1-2]: Title block')$(grep -qx '## Sheet: Wide' <<<"$XLSX_OUT2" || echo ' narrow Wide not printed as a table')"
  XLSX_TABLE="$(python3 -I "$XLSX_PY" --layout table --sheet Grid -- "$FIX_DIR/fixture.xlsx" 2>&1)"
  XLSX_CELLS="$(python3 -I "$XLSX_PY" --layout cells --sheet Backlog -- "$FIX_DIR/fixture.xlsx" 2>&1)"
  check "xlsx converter: --layout table and --layout cells force the layout" \
    "$(grep -qx '## Sheet: Grid' <<<"$XLSX_TABLE" || echo ' Grid not forced to table')$(has_all "$XLSX_TABLE" '| 1 | [merged c1-c2 rows 1-2] Title block |')$(has_all "$XLSX_CELLS" '## Sheet: Backlog (layout: cells)' '- r1 c5 (hidden): Owner' '- r7 (hidden) c2: old version' '- r9 c1 [merged c1-c3]: Section heading' '- r10 c5 (hidden) [merged rows 10-11]:')$(printf '%s\n' "$XLSX_CELLS" | grep -F '| row |' || true)"
  python3 -I "$FIX_DIR/make_fixture.py" "$FIX_DIR/broken.xlsx" --broken >/dev/null
  set +e
  XLSX_BROKEN="$(python3 -I "$XLSX_PY" "$FIX_DIR/broken.xlsx" 2>&1)"; BROKEN_RC=$?
  set -e
  check "xlsx converter: a drawing relationship to a missing member prints [unreadable: ...] and exits 0" \
    "$([ "$BROKEN_RC" -eq 0 ] || echo "rc=$BROKEN_RC")$(has_all "$XLSX_BROKEN" '[unreadable: drawing: member xl/drawings/drawing1.xml is missing]' '| 1 | ID | Title | Due | Done |' '### Notes')"
  check "xlsx converter: a relationship target outside the package and a malformed persons part print [unreadable: ...]" \
    "$(has_all "$XLSX_BROKEN" '[unreadable: drawing: relationship rId1 target ../../../outside.xml is outside the package]' '[unreadable: persons: cannot parse xl/persons/person.xml]' '- c1 row 1 (A1): threaded text')$(has_all "$XLSX_OUT" '| 1 | hidden note |')$(printf '%s\n' "$XLSX_OUT" | grep -F 'unreadable' || true)"
  check "xlsx converter: a drawing or legacy drawing the sheet declares without a matching relationship prints [unreadable: ...]" \
    "$(has_all "$XLSX_BROKEN" '[unreadable: legacy drawing relationship rId9 not found; the notes of the sheet may be missing]' '[unreadable: drawing relationship rId8 not found]')$(printf '%s\n' "$XLSX_BROKEN" | grep -F 'relationship rId2 not found' || true)"
  (cd "$FIX_DIR"&& python3 -c "import zipfile; zipfile.ZipFile('nowb.zip', 'w').writestr('a.txt', 'x')")
  set +e
  python3 -I "$XLSX_PY" "$FIX_DIR/make_fixture.py" >/dev/null 2>&1; NOT_ZIP_RC=$?
  python3 -I "$XLSX_PY" "$FIX_DIR/nowb.zip" >/dev/null 2>&1; NO_WB_RC=$?
  set -e
  # A workbook whose xl/workbook.xml member is damaged (its compressed bytes
  # overwritten in place, so the CRC check or the inflate fails).
  (cd "$FIX_DIR" && python3 -c "
import zipfile
data = bytearray(open('fixture.xlsx', 'rb').read())
info = zipfile.ZipFile('fixture.xlsx').getinfo('xl/workbook.xml')
start = info.header_offset + 30 + len(info.filename.encode()) + len(info.extra)
for i in range(start, start + min(info.compress_size, 24)):
    data[i] ^= 0xFF
open('damaged.xlsx', 'wb').write(bytes(data))
")
  set +e
  DAMAGED_ERR="$(python3 -I "$XLSX_PY" "$FIX_DIR/damaged.xlsx" 2>&1 >/dev/null)"; DAMAGED_RC=$?
  set -e
  check "xlsx converter: a damaged member exits 2 with one line, not a traceback" \
    "$([ "$DAMAGED_RC" -eq 2 ] || echo "rc=$DAMAGED_RC")$([ "$(printf '%s\n' "$DAMAGED_ERR" | wc -l | tr -d ' ')" = 1 ] || echo ' more than one line')$(grep -q '^xlsx_to_text: cannot \(read\|parse\) xl/workbook.xml' <<<"$DAMAGED_ERR" || echo " line: $DAMAGED_ERR")"
  check "xlsx converter: a non-zip file and a zip without a workbook exit 2" \
    "$([ "$NOT_ZIP_RC" -eq 2 ] || echo "not-zip rc=$NOT_ZIP_RC")$([ "$NO_WB_RC" -eq 2 ] || echo " no-workbook rc=$NO_WB_RC")"
  # --- the character cap bounds the work, not only the printed text ----------
  # make_cap.py writes small workbooks whose output is large: "plain" and
  # "rich" fill 40 x 50 cells with one 100,000-character shared string (a
  # single run; two runs, whose text is joined per reference), "notes" gives
  # 2000 cell notes one 100,000-character author, "threaded" gives 2000
  # threaded comments one person with a 100,000-character display name,
  # "pictures" shows one media member with a 60,000-character name 2000
  # times, and "boundary" holds a good first sheet and a second sheet whose
  # member is not well-formed XML. The remaining kinds point many references
  # at one part: "blank" fills 40 x 50 cells with one shared string of
  # 100,000 spaces (escaped, it is empty), "dupnotes" has 600 comments
  # relationships on one part whose single note is 100,000 characters long,
  # "dupdraw" has 600 drawing relationships on one drawing with one shape,
  # "dupsheets" has 300 worksheet entries on one worksheet member, and
  # "replay" relates the comments parts A, B, a threaded part, then A again
  # (the notes of one cell must come in relationship order, A's twice) and
  # holds merged cells whose shared value is longer than 1024 characters and
  # used on four rows: one starting with a line break, one with plain text,
  # one with the literal characters <br>.
  CAP_DIR="$TMP_ROOT/xlsx-cap"
  mkdir -p "$CAP_DIR"
  cat >"$CAP_DIR/make_cap.py" <<'PYCAP'
import sys, zipfile
kind, out = sys.argv[1], sys.argv[2]
MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG = "http://schemas.openxmlformats.org/package/2006/relationships"
TC = "http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments"
MS = "http://schemas.microsoft.com/office/2017/10/relationships"
XDR = "http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing"
DML = "http://schemas.openxmlformats.org/drawingml/2006/main"
BIG = "a" * 100000
def col(n):
    s = ""
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s
def sheet(rows, cols):
    body = "".join('<row r="%d">%s</row>' % (r, "".join('<c r="%s%d" t="s"><v>0</v></c>' % (col(c), r) for c in range(1, cols + 1))) for r in range(1, rows + 1))
    return '<worksheet xmlns="%s"><sheetData>%s</sheetData></worksheet>' % (MAIN, body)
def rels(kind_uri, target, count=1):
    return '<Relationships xmlns="%s">%s</Relationships>' % (PKG, "".join('<Relationship Id="rId%d" Type="%s" Target="%s"/>' % (i, kind_uri, target) for i in range(1, count + 1)))
names = ["Data"]
sheet_members = None
parts = {}
if kind in ("threaded", "pictures", "dupnotes", "dupdraw", "dupsheets"):
    parts["xl/sharedStrings.xml"] = '<sst xmlns="%s"><si><t>x</t></si></sst>' % MAIN
    parts["xl/worksheets/sheet1.xml"] = sheet(1, 1)
if kind == "plain":
    parts["xl/sharedStrings.xml"] = '<sst xmlns="%s"><si><t>%s</t></si></sst>' % (MAIN, BIG)
    parts["xl/worksheets/sheet1.xml"] = sheet(40, 50)
elif kind == "rich":
    parts["xl/sharedStrings.xml"] = '<sst xmlns="%s"><si><r><t>%s</t></r><r><t>%s</t></r></si></sst>' % (MAIN, BIG[:50000], BIG[:50000])
    parts["xl/worksheets/sheet1.xml"] = sheet(40, 50)
elif kind == "notes":
    parts["xl/sharedStrings.xml"] = '<sst xmlns="%s"><si><t>x</t></si></sst>' % MAIN
    parts["xl/worksheets/sheet1.xml"] = sheet(1, 1)
    parts["xl/worksheets/_rels/sheet1.xml.rels"] = '<Relationships xmlns="%s"><Relationship Id="rId1" Type="%s/comments" Target="../comments1.xml"/></Relationships>' % (PKG, REL)
    parts["xl/comments1.xml"] = '<comments xmlns="%s"><authors><author>%s</author></authors><commentList>%s</commentList></comments>' % (MAIN, BIG, "".join('<comment ref="A%d" authorId="0"><text><t>n</t></text></comment>' % r for r in range(1, 2001)))
elif kind == "threaded":
    parts["xl/worksheets/_rels/sheet1.xml.rels"] = rels(MS + "/threadedComment", "../threadedComments/threadedComment1.xml")
    parts["xl/threadedComments/threadedComment1.xml"] = '<ThreadedComments xmlns="%s">%s</ThreadedComments>' % (TC, "".join('<threadedComment ref="A%d" personId="{P}" id="{T%d}"><text>n</text></threadedComment>' % (r, r) for r in range(1, 2001)))
    parts["xl/persons/person.xml"] = '<personList xmlns="%s"><person displayName="%s" id="{P}"/></personList>' % (TC, BIG)
elif kind == "pictures":
    media = "a" * 60000 + ".png"
    parts["xl/worksheets/_rels/sheet1.xml.rels"] = rels(REL + "/drawing", "../drawings/drawing1.xml")
    parts["xl/drawings/drawing1.xml"] = '<xdr:wsDr xmlns:xdr="%s" xmlns:a="%s" xmlns:r="%s">%s</xdr:wsDr>' % (XDR, DML, REL, "".join('<xdr:oneCellAnchor><xdr:from><xdr:col>0</xdr:col><xdr:row>%d</xdr:row></xdr:from><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="%d" name="P"/></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rId1"/></xdr:blipFill></xdr:pic></xdr:oneCellAnchor>' % (r, r) for r in range(2000)))
    parts["xl/drawings/_rels/drawing1.xml.rels"] = rels(REL + "/image", "../media/" + media)
    parts["xl/media/" + media] = "png"
elif kind == "blank":
    parts["xl/sharedStrings.xml"] = '<sst xmlns="%s"><si><t xml:space="preserve">%s</t></si></sst>' % (MAIN, " " * 100000)
    parts["xl/worksheets/sheet1.xml"] = sheet(40, 50)
elif kind == "dupnotes":
    parts["xl/worksheets/_rels/sheet1.xml.rels"] = rels(REL + "/comments", "../comments1.xml", 600)
    parts["xl/comments1.xml"] = '<comments xmlns="%s"><authors><author>Ann</author></authors><commentList><comment ref="A1" authorId="0"><text><t xml:space="preserve">a%sb</t></text></comment></commentList></comments>' % (MAIN, " " * 100000)
elif kind == "dupdraw":
    parts["xl/worksheets/_rels/sheet1.xml.rels"] = rels(REL + "/drawing", "../drawings/drawing1.xml", 600)
    parts["xl/drawings/drawing1.xml"] = '<xdr:wsDr xmlns:xdr="%s" xmlns:a="%s"><xdr:oneCellAnchor><xdr:from><xdr:col>0</xdr:col><xdr:row>0</xdr:row></xdr:from><xdr:sp><xdr:nvSpPr><xdr:cNvPr id="1" name="Box"/></xdr:nvSpPr><xdr:txBody><a:p><a:r><a:t>shape text</a:t></a:r></a:p></xdr:txBody></xdr:sp></xdr:oneCellAnchor></xdr:wsDr>' % (XDR, DML)
elif kind == "dupsheets":
    names = ["S%d" % i for i in range(1, 301)]
    sheet_members = [1] * 300
elif kind == "replay":
    long_values = ["\n" + "w" * 1100, "y" * 1100, "&lt;br&gt;" + "x" * 1100]
    parts["xl/sharedStrings.xml"] = '<sst xmlns="%s">%s</sst>' % (MAIN, "".join('<si><t xml:space="preserve">%s</t></si>' % v for v in long_values))
    body = "".join('<row r="%d">%s</row>' % (r, "".join('<c r="%s%d" t="s"><v>%d</v></c>' % (letter, r, i) for i, letter in enumerate("ACE"))) for r in range(1, 5))
    merges = "".join('<mergeCell ref="%s%d:%s%d"/>' % (a, r, b, r) for r in range(1, 5) for a, b in ("AB", "CD", "EF"))
    parts["xl/worksheets/sheet1.xml"] = '<worksheet xmlns="%s"><sheetData>%s</sheetData><mergeCells>%s</mergeCells></worksheet>' % (MAIN, body, merges)
    note = '<comment ref="%s" authorId="0"><text><t>%s</t></text></comment>'
    parts["xl/commentsA.xml"] = '<comments xmlns="%s"><authors><author>Ann</author></authors><commentList>%s</commentList></comments>' % (MAIN, note % ("B2", "A first") + note % ("A1", "A on A1") + note % ("B2", "A second"))
    parts["xl/commentsB.xml"] = '<comments xmlns="%s"><authors><author>Bob</author></authors><commentList>%s</commentList></comments>' % (MAIN, note % ("B2", "B on B2") + note % ("C3", "B under the thread"))
    parts["xl/threadedComments/threadedComment1.xml"] = '<ThreadedComments xmlns="%s"><threadedComment ref="C3" personId="{P}" id="{T}"><text>thread on C3</text></threadedComment></ThreadedComments>' % TC
    parts["xl/persons/person.xml"] = '<personList xmlns="%s"><person displayName="Pat" id="{P}"/></personList>' % TC
    parts["xl/worksheets/_rels/sheet1.xml.rels"] = '<Relationships xmlns="%s">%s</Relationships>' % (PKG, "".join('<Relationship Id="rId%d" Type="%s" Target="../%s"/>' % (i, t, g) for i, (t, g) in enumerate([(REL + "/comments", "commentsA.xml"), (REL + "/comments", "commentsB.xml"), (MS + "/threadedComment", "threadedComments/threadedComment1.xml"), (REL + "/comments", "commentsA.xml")], 1)))
elif kind == "boundary":
    names = ["First", "Second"]
    parts["xl/sharedStrings.xml"] = '<sst xmlns="%s"><si><t>first sheet value</t></si></sst>' % MAIN
    parts["xl/worksheets/sheet1.xml"] = sheet(3, 2)
    parts["xl/worksheets/sheet2.xml"] = "<worksheet><sheetData"
else:
    sys.exit("unknown kind " + kind)
parts["xl/workbook.xml"] = '<workbook xmlns="%s" xmlns:r="%s"><sheets>%s</sheets></workbook>' % (MAIN, REL, "".join('<sheet name="%s" sheetId="%d" r:id="rId%d"/>' % (n, i, i) for i, n in enumerate(names, 1)))
if sheet_members is None:
    sheet_members = list(range(1, len(names) + 1))
parts["xl/_rels/workbook.xml.rels"] = '<Relationships xmlns="%s">%s</Relationships>' % (PKG, "".join('<Relationship Id="rId%d" Type="%s/worksheet" Target="worksheets/sheet%d.xml"/>' % (i, REL, m) for i, m in enumerate(sheet_members, 1)))
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name in sorted(parts):
        z.writestr(name, parts[name])
PYCAP
  # run_capped.py SCRIPT ARGS... runs the converter in-process under
  # tracemalloc and prints "<exit status> <peak traced bytes> <characters
  # printed> <1 when the output ends with the truncation notice, else 0>
  # <XML documents parsed> <characters passed to escape()> <the last character
  # printed before the notice, - when nothing was>". The traced peak counts
  # the Python objects the converter allocates, and the two work counters
  # count calls, so none of them depends on the platform's process accounting
  # or on the speed of the machine.
  cat >"$CAP_DIR/run_capped.py" <<'PYRUN'
import io, runpy, sys, tracemalloc
import xml.etree.ElementTree as ET
script = sys.argv[1]
sys.argv = sys.argv[1:]
work = {"parses": 0, "escaped": 0}
parse = ET.fromstring
def counted(data):
    work["parses"] += 1
    return parse(data)
ET.fromstring = counted
def profile(frame, event, arg):
    if event == "call" and frame.f_code.co_name == "escape":
        work["escaped"] += len(frame.f_locals.get("value", ""))
captured = io.StringIO()
real = sys.stdout
sys.stdout = captured
status = 0
tracemalloc.start()
sys.setprofile(profile)
try:
    runpy.run_path(script, run_name="__main__")
except SystemExit as exc:
    status = exc.code if isinstance(exc.code, int) else (0 if exc.code is None else 1)
sys.setprofile(None)
peak = tracemalloc.get_traced_memory()[1]
tracemalloc.stop()
sys.stdout = real
text = captured.getvalue()
notice = "the rest of the workbook was not emitted]\n"
cut = text[: text.rfind("\n[truncated: output exceeds")] if text.endswith(notice) else text
print(status, peak, len(text), 1 if text.endswith(notice) else 0, work["parses"], work["escaped"], cut[-1:].strip() or "-")
PYRUN
  # A workbook of 2000 references to one 100,000-character string would print
  # 200,000,000 characters; with --max-chars 5000 the converter must stay
  # within 32 MiB of traced memory (it needs about 6 MiB; building the whole
  # text first needs more than 190 MiB). The output is cut inside the long
  # string, so it is exactly 5000 characters long and the last character
  # before the notice is one of that string: a converter that drops the
  # piece crossing the cap instead of cutting it prints far less.
  CAP_PEAK_LIMIT=$((32 * 1024 * 1024))
  MISSING=""
  for kind in plain rich notes threaded pictures; do
    python3 -I "$CAP_DIR/make_cap.py" "$kind" "$CAP_DIR/$kind.xlsx"
    for layout in table cells; do
      CAP_RES="$(python3 -I "$CAP_DIR/run_capped.py" "$XLSX_PY" --max-chars 5000 --layout "$layout" -- "$CAP_DIR/$kind.xlsx" 2>&1 | tail -n 1)"
      read -r _ CAP_PEAK CAP_LEN _ _ _ CAP_LAST <<<"$CAP_RES" || true
      if grep -qE '^0 [0-9]+ [0-9]+ 1 [0-9]+ [0-9]+ [^ ]+$' <<<"$CAP_RES"; then
        [ "$CAP_PEAK" -le "$CAP_PEAK_LIMIT" ] || MISSING="$MISSING $kind/$layout: peak $CAP_PEAK bytes exceeds $CAP_PEAK_LIMIT"
        [ "$CAP_LEN" -eq 5000 ] || MISSING="$MISSING $kind/$layout: $CAP_LEN characters printed under a cap of 5000, expected exactly 5000"
        [ "$CAP_LAST" = a ] || MISSING="$MISSING $kind/$layout: the output is not cut inside the long string (last character before the notice: $CAP_LAST)"
      else
        MISSING="$MISSING $kind/$layout: unexpected result '$CAP_RES' (expected: exit status 0, peak bytes, characters, 1 for the notice, parses, escaped characters, last character)"
      fi
    done
  done
  check "xlsx converter: cells, notes, threaded comments or pictures that share one long string are not turned into text past --max-chars (traced peak memory stays under 32 MiB, the output is cut inside the string)" "$MISSING"
  # Many references to one part: the part is printed once per reference (as
  # it always was) but parsed at most twice, and a long value held by many
  # cells is escaped at most twice per worksheet. Without that, the 600
  # relationships cost 600 parses (and, for the notes, 600 copies of the
  # note), the 300 worksheet entries 300 parses, and the 2000 blank cells
  # 200,000,000 escaped characters for a few thousand characters of output.
  MISSING=""
  cap_work() {
    local kind="$1" max_parses="$2" max_escaped="$3" needle="$4" want="$5" res peak parses escaped got
    shift 5
    python3 -I "$CAP_DIR/make_cap.py" "$kind" "$CAP_DIR/$kind.xlsx"
    res="$(python3 -I "$CAP_DIR/run_capped.py" "$XLSX_PY" "$@" -- "$CAP_DIR/$kind.xlsx" 2>&1 | tail -n 1)"
    read -r _ peak _ _ parses escaped _ <<<"$res" || true
    if grep -qE '^0 [0-9]+ [0-9]+ [01] [0-9]+ [0-9]+ [^ ]+$' <<<"$res"; then
      [ "$peak" -le "$CAP_PEAK_LIMIT" ] || MISSING="$MISSING $kind $*: peak $peak bytes exceeds $CAP_PEAK_LIMIT"
      [ "$parses" -le "$max_parses" ] || MISSING="$MISSING $kind $*: $parses XML documents parsed, expected at most $max_parses"
      [ "$escaped" -le "$max_escaped" ] || MISSING="$MISSING $kind $*: $escaped characters escaped, expected at most $max_escaped"
    else
      MISSING="$MISSING $kind $*: unexpected result '$res'"
    fi
    if [ -n "$needle" ]; then
      got="$(python3 -I "$XLSX_PY" "$@" -- "$CAP_DIR/$kind.xlsx" 2>/dev/null | grep -cF -- "$needle" || true)"
      [ "$got" = "$want" ] || MISSING="$MISSING $kind $*: '$needle' printed $got times, expected $want (once per reference)"
    fi
  }
  cap_work blank 12 1000000 '' 0 --max-chars 5000 --layout table
  cap_work blank 12 1000000 '' 0 --max-chars 5000 --layout cells
  cap_work dupnotes 12 1000000 '- c1 row 1 (A1), Ann: a b' 600
  cap_work dupnotes 12 1000000 '- c1 row 1 (A1), Ann: a b' 12 --max-chars 500
  cap_work dupdraw 12 1000000 '- "Box" at c1 row 1: shape text' 600
  cap_work dupsheets 12 1000000 '## Sheet: S' 300
  check "xlsx converter: a part that many relationships or worksheet entries point at is printed once per reference but not parsed once per reference, and a long value held by many cells is not escaped once per cell" "$MISSING"
  # What the reuse must not change: the notes of a part related twice come
  # twice, each cell's notes in relationship order (A, B, A again; the legacy
  # note under a threaded comment is left out), and a merge marker is followed
  # by a space only when the first line of its cell's value is not blank,
  # also for a long value whose escaped text is reused.
  python3 -I "$CAP_DIR/make_cap.py" replay "$CAP_DIR/replay.xlsx"
  python3 -I "$XLSX_PY" --layout table -- "$CAP_DIR/replay.xlsx" >"$CAP_DIR/replay.out" 2>/dev/null || true
  cat >"$CAP_DIR/replay-notes.expected" <<'NOTES'
### Notes
- c1 row 1 (A1), Ann: A on A1
- c1 row 1 (A1), Ann: A on A1
- c2 row 2 (B2), Ann: A first
- c2 row 2 (B2), Ann: A second
- c2 row 2 (B2), Bob: B on B2
- c2 row 2 (B2), Ann: A first
- c2 row 2 (B2), Ann: A second
- c3 row 3 (C3), Pat: thread on C3
NOTES
  MISSING=""
  [ "$(awk '/^### Notes$/ {n = 1} n && /^$/ {n = 0} n' "$CAP_DIR/replay.out")" = "$(cat "$CAP_DIR/replay-notes.expected")" ] || MISSING="$MISSING the Notes section is not the pinned one"
  for needle in '[merged c1-c2]<br>www' '[merged c3-c4] yyy' '[merged c5-c6] <br>xxx'; do
    [ "$(grep -cF -- "$needle" "$CAP_DIR/replay.out" || true)" = 4 ] || MISSING="$MISSING '$needle' is not on each of the 4 rows"
  done
  grep -qF -- '[merged c1-c2] ' "$CAP_DIR/replay.out" && MISSING="$MISSING a marker before a value that starts with a line break is followed by a space"
  check "xlsx converter: notes of parts related several times keep their order, and a merge marker joins a long reused value as it joins any other" "$MISSING"
  # The boundary: with the cap equal to the text printed up to the end of the
  # first sheet, the second sheet is not parsed (its member is malformed, so
  # parsing it exits 2, as the run one character above the cap shows), and the
  # skipped sheet is still reported.
  python3 -I "$CAP_DIR/make_cap.py" boundary "$CAP_DIR/boundary.xlsx"
  CAP_L="$(python3 -I "$XLSX_PY" --sheet=First -- "$CAP_DIR/boundary.xlsx" 2>/dev/null | python3 -c 'import sys; print(len(sys.stdin.buffer.read().decode("utf-8")))')"
  set +e
  CAP_EXACT="$(python3 -I "$XLSX_PY" --max-chars "$CAP_L" -- "$CAP_DIR/boundary.xlsx" 2>"$CAP_DIR/exact.err")"; CAP_EXACT_RC=$?
  python3 -I "$XLSX_PY" --max-chars "$((CAP_L + 1))" -- "$CAP_DIR/boundary.xlsx" >/dev/null 2>"$CAP_DIR/above.err"; CAP_ABOVE_RC=$?
  set -e
  CAP_EXACT_LEN="$(python3 -I "$XLSX_PY" --max-chars "$CAP_L" -- "$CAP_DIR/boundary.xlsx" 2>/dev/null | python3 -c 'import sys; print(len(sys.stdin.buffer.read().decode("utf-8")))' || true)"
  check "xlsx converter: a worksheet that starts exactly at --max-chars is not parsed, and skipping it is reported" \
    "$([ "$CAP_EXACT_RC" -eq 0 ] || echo "rc=$CAP_EXACT_RC")$([ ! -s "$CAP_DIR/exact.err" ] || echo " stderr: $(head -n 1 "$CAP_DIR/exact.err")")$(printf '%s\n' "$CAP_EXACT" | tail -n 1 | grep -qxF -- "[truncated: output exceeds $CAP_L characters; the rest of the workbook was not emitted]" || echo ' no truncation notice on the last line')$(grep -qF -- '## Sheet: First' <<<"$CAP_EXACT" || echo ' first sheet heading missing')$([ "${CAP_EXACT_LEN:-0}" -le "$CAP_L" ] || echo " $CAP_EXACT_LEN characters printed under a cap of $CAP_L")$([ "$CAP_ABOVE_RC" -eq 2 ] || echo " one character above the cap: rc=$CAP_ABOVE_RC, expected 2")$(grep -q '^xlsx_to_text: cannot parse xl/worksheets/sheet2.xml' "$CAP_DIR/above.err" || echo ' one character above the cap: the second sheet was not parsed')"
  # A sheet that was read keeps its pictures: they are written even when the
  # cap cuts the output before the sheet's ### Images section.
  python3 -I "$XLSX_PY" --max-chars 120 --extract-media "$CAP_DIR/media" -- "$FIX_DIR/fixture.xlsx" >"$CAP_DIR/media.out" 2>/dev/null || true
  check "xlsx converter: --extract-media still writes the pictures of a sheet whose output is cut by --max-chars" \
    "$([ "$(wc -c <"$CAP_DIR/media/Backlog-image1.png" 2>/dev/null | tr -d ' ')" = 70 ] || echo 'media file missing or wrong size')$(grep -qF -- '### Images' "$CAP_DIR/media.out" && echo ' the Images section was printed, so the cap did not cut before it' || true)"
  # The full output of the fixture workbook, pinned: the text below is what
  # the converter printed before --max-chars bounded the text it generates,
  # so a change to it is a change of the converter's output and has to be
  # made here on purpose.
  cat >"$CAP_DIR/full.expected" <<'FULLTEXT'
# Workbook: fixture.xlsx

## Sheet: Backlog

| row | c1 | c2 | c3 | c4 | c5 (hidden) |
|---|---|---|---|---|---|
| 1 | ID | Title | Due | Done | Owner |
| 2 | 1 | Add login \| form | 2023-03-15 | TRUE |  |
| 4 | 2.5 | ab | 2023-03-15T12:00:00 | #N/A |  |
| 5 | 3 |  |  |  |  |
| 6 | 4 | first line<br>second line |  |  |  |
| 7 (hidden) | 5 | old version |  |  |  |
| 8 | 6 | keep ~~struck run~~ plain run | ~~whole cell struck~~ | ~~bold word~~ | ~~keep struck run plain run~~ |
| 9 | [merged c1-c3] Section heading |  |  |  |  |
| 10 |  |  |  |  | [merged rows 10-11] |

[truncated: sheet Backlog has columns beyond c64; they were not read]

### Notes
- c2 row 2 (B2), Reviewer A: needs a spec
- c3 row 4 (C4), Reviewer A: confirm the<br>time zone
- c5 row 9 (E9), Pat Person: threaded body

### Shapes
- "TextBox 1" at c3 row 5 to c6 row 9: First paragraph<br>Second paragraph
- "Callout 3" at c1 row 12: Grouped callout
- "Lead 7" at c1 row 14: <br>after an empty paragraph
- "Break 8" at c1 row 16: ends in a break<br><br>next paragraph
- chart "Chart 5" at c10 row 2 to c15 row 13: (chart; data not read)

### Images
- "Picture 6" at c2 row 10 to c5 row 20: image1.png (70 bytes)

## Sheet: Notes (hidden)

| row | c1 |
|---|---|
| 1 | hidden note |

## Sheet: Grid (layout: cells)

- r1 c1 [merged c1-c2 rows 1-2]: Title block
- r1 c15: far right
- r2 c20: edge
- r3 c1: footer
- r3 c20: 7

[truncated: sheet Grid has columns beyond c64; they were not read]

## Sheet: Wide (layout: cells)

- r1 c1: wide start
- r1 c15: wide middle
- r2 c20: wide edge

FULLTEXT
  python3 -I "$XLSX_PY" "$FIX_DIR/fixture.xlsx" >"$CAP_DIR/full.out" 2>/dev/null || true
  check "xlsx converter: the full output of the fixture workbook is the pinned text, byte for byte" \
    "$(cmp "$CAP_DIR/full.expected" "$CAP_DIR/full.out" 2>&1 | head -n 1 || true)"
  # cap_sweep.py SCRIPT WORKBOOK [ARGS...] runs the converter in-process at a
  # spread of --max-chars values (every third value from 1 to the full length
  # plus 2, the lengths around the notice's own, the output length at the
  # start of every worksheet section and one below and above it, and the full
  # length and its neighbours) and prints one line per value whose output is
  # not the documented one: the uncapped output, whole, when it fits the cap
  # (no notice, also on an exact fit); otherwise the uncapped output cut to
  # the cap minus the notice's length, followed by the notice. Exit status and
  # stderr must be those of the uncapped run.
  cat >"$CAP_DIR/cap_sweep.py" <<'PYSWEEP'
import contextlib, io, sys
script, book, extra = sys.argv[1], sys.argv[2], sys.argv[3:]
with open(script) as handle:
    code = compile(handle.read(), script, "exec")
def run(args):
    out, err = io.StringIO(), io.StringIO()
    saved = sys.argv
    sys.argv = [script] + args
    status = 0
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            exec(code, {"__name__": "__main__"})
    except SystemExit as exc:
        status = exc.code if isinstance(exc.code, int) else (0 if exc.code is None else 1)
    finally:
        sys.argv = saved
    return status, out.getvalue(), err.getvalue()
status, full, err = run(extra + ["--", book])
if status != 0 or not full:
    sys.exit("uncapped run: exit status %d, %d characters" % (status, len(full)))
n = len(full)
notice_of = lambda cap: "\n[truncated: output exceeds %d characters; the rest of the workbook was not emitted]\n" % cap
caps = set(range(1, n + 3, 3)) | set(range(n - 2, n + 3)) | set(range(len(notice_of(100)) - 3, len(notice_of(100)) + 4))
start = full.find("## Sheet: ")
while start != -1:
    caps |= {start - 1, start, start + 1}
    start = full.find("## Sheet: ", start + 1)
bad = 0
for cap in sorted(c for c in caps if c >= 1):
    want = full if n <= cap else full[: max(cap - len(notice_of(cap)), 0)] + notice_of(cap)
    got = run(extra + ["--max-chars", str(cap), "--", book])
    if got != (status, want, err):
        bad += 1
        if bad <= 3:
            what = "exit status %d" % got[0] if got[0] != status else ("stderr differs" if got[2] != err else "stdout is %d characters, expected %d%s" % (len(got[1]), len(want), "" if len(got[1]) != len(want) else " with other content"))
            print("--max-chars %d: %s" % (cap, what))
if bad > 3:
    print("... and %d more" % (bad - 3))
print("checked %d caps, %d wrong" % (len(caps), bad))
PYSWEEP
  MISSING=""
  for sweep_args in "" "--layout table" "--layout cells" "--max-rows 2 --max-cols 3"; do
    # shellcheck disable=SC2086  # the option set is split into words on purpose
    SWEEP_RES="$(python3 -I "$CAP_DIR/cap_sweep.py" "$XLSX_PY" "$FIX_DIR/fixture.xlsx" $sweep_args 2>&1 | tail -n 4)"
    printf '%s\n' "$SWEEP_RES" | tail -n 1 | grep -qE '^checked [0-9]+ caps, 0 wrong$' || MISSING="$MISSING [${sweep_args:-default}] $(printf '%s' "$SWEEP_RES" | tr '\n' ';')"
  done
  check "xlsx converter: at every --max-chars the output is the uncapped output, whole when it fits (no notice on an exact fit), else cut to the cap minus the notice and followed by the notice" "$MISSING"
  # --- sheet renderer, driven by stand-in renderer programs ------------------
  # Contract of the stand-ins: the soffice stand-in finds --outdir and the
  # workbook (its last argument) and writes <outdir>/<stem>.pdf; the
  # interpreter stand-in of the excel renderer writes a PDF to its LAST
  # argument (the renderer passes the generated automation script, the
  # workbook and then the output path, on every platform).
  RENDER_PY="$SKILL_DIR/scripts/xlsx_render.py"
  check "the sheet renderer is ASCII-only, backtick-free and starts with a python3 shebang" \
    "$(head -n 1 "$RENDER_PY" | grep -qx '#!/usr/bin/env python3' || echo 'no shebang')$(grep -n '`' "$RENDER_PY" | head -n 3 || true)$(LC_ALL=C grep -n '[^ -~]' "$RENDER_PY" | head -n 3 || true)"
  cat >"$FIX_DIR/fake-soffice" <<'FAKE'
#!/bin/sh
outdir=""
wb=""
while [ $# -gt 0 ]; do
  case "$1" in
    --outdir) outdir="$2"; shift 2 ;;
    -*) shift ;;
    *) wb="$1"; shift ;;
  esac
done
base="${wb##*/}"
printf '%%PDF-1.4\nfake soffice render\n' >"$outdir/${base%.*}.pdf"
FAKE
  cat >"$FIX_DIR/fake-excel" <<'FAKE'
#!/bin/sh
for last in "$@"; do :; done
printf '%%PDF-1.4\nfake excel render\n' >"$last"
FAKE
  printf '#!/bin/sh\necho boom >&2\nexit 3\n' >"$FIX_DIR/fake-fail"
  # The hanging stand-in records its own pid and its child's, so the test can
  # prove the whole process group was killed.
  cat >"$FIX_DIR/fake-hang" <<'FAKE'
#!/bin/sh
sleep 30 &
echo "$$ $!" >"${HANG_PIDS:-/dev/null}"
wait
FAKE
  cat >"$FIX_DIR/fake-nopdf" <<'FAKE'
#!/bin/sh
outdir=""
prev=""
last=""
for a in "$@"; do
  [ "$prev" = "--outdir" ] && outdir="$a"
  prev="$a"
  last="$a"
done
if [ -n "$outdir" ]; then
  base="${last##*/}"
  printf 'not a pdf\n' >"$outdir/${base%.*}.pdf"
else
  printf 'not a pdf\n' >"$last"
fi
FAKE
  chmod +x "$FIX_DIR/fake-soffice" "$FIX_DIR/fake-excel" "$FIX_DIR/fake-fail" "$FIX_DIR/fake-hang" "$FIX_DIR/fake-nopdf"
  RENDER_OUT="$TMP_ROOT/render-out"
  FIX_BEFORE="$(cd "$FIX_DIR" && find . | sort)"
  # render_run ARGS... — runs the renderer; sets R_OUT (stdout + stderr) and R_RC.
  render_run() {
    set +e
    R_OUT="$(python3 -I "$RENDER_PY" "$@" 2>&1)"
    R_RC=$?
    set -e
  }
  render_run --chain soffice --soffice "$FIX_DIR/fake-soffice" --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  check "sheet renderer: --chain soffice with a stand-in writes <out>/fixture.pdf, creates the directory and prints the success line" \
    "$([ "$R_RC" -eq 0 ] || echo "rc=$R_RC")$(grep -qxE "Rendered: $RENDER_OUT/fixture\.pdf \(by soffice, [0-9]+ bytes, all sheets\)" <<<"$R_OUT" || echo " line: $R_OUT")$(head -c 4 "$RENDER_OUT/fixture.pdf" 2>/dev/null | grep -qx '%PDF' || echo ' no %PDF file')"
  render_run --chain excel --excel-cmd "$FIX_DIR/fake-excel" --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  check "sheet renderer: --chain excel with an interpreter stand-in renders by excel and a second run overwrites the PDF" \
    "$([ "$R_RC" -eq 0 ] || echo "rc=$R_RC")$(grep -qxE "Rendered: $RENDER_OUT/fixture\.pdf \(by excel, [0-9]+ bytes, all sheets\)" <<<"$R_OUT" || echo " line: $R_OUT")$(grep -qF 'fake excel render' "$RENDER_OUT/fixture.pdf" || echo ' PDF not overwritten')"
  render_run --chain excel --excel-cmd "$FIX_DIR/fake-excel" --sheet Backlog --sheet=Grid --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  check "sheet renderer: --sheet names the first selected sheet and says the others were not rendered" \
    "$(grep -qxE "Rendered: $RENDER_OUT/fixture\.pdf \(by excel, [0-9]+ bytes, sheet Backlog; other selected sheets not rendered\)" <<<"$R_OUT" || echo "line: $R_OUT")"
  render_run --chain auto --excel-cmd "$FIX_DIR/fake-fail" --soffice "$FIX_DIR/fake-soffice" --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  check "sheet renderer: auto falls through a failing excel to soffice and prints only the success line" \
    "$([ "$R_RC" -eq 0 ] || echo "rc=$R_RC")$(grep -qxE "Rendered: $RENDER_OUT/fixture\.pdf \(by soffice, [0-9]+ bytes, all sheets\)" <<<"$R_OUT" || echo " line: $R_OUT")$([ "$(printf '%s\n' "$R_OUT" | wc -l | tr -d ' ')" = 1 ] || echo ' more than one line')$(printf '%s\n' "$R_OUT" | grep -F -e 'excel:' -e 'boom' || true)"
  render_run --chain auto --excel-cmd "$FIX_DIR/fake-fail" --soffice "$FIX_DIR/fake-fail" --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  check "sheet renderer: every renderer failing exits 0 with each exit status and the first line of its error output" \
    "$([ "$R_RC" -eq 0 ] || echo "rc=$R_RC")$(grep -qxF 'Rendered: no (excel: exit status 3: boom; soffice: exit status 3: boom)' <<<"$R_OUT" || echo " line: $R_OUT")"
  HANG_PIDS="$TMP_ROOT/hang.pids"
  export HANG_PIDS
  SECONDS=0
  render_run --chain auto --excel-cmd "$FIX_DIR/fake-hang" --soffice "$FIX_DIR/fake-nopdf" --timeout 1 --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  HANG_SECS=$SECONDS
  unset HANG_PIDS
  STRAY=""
  for pid in $(cat "$TMP_ROOT/hang.pids" 2>/dev/null || true); do
    if kill -0 "$pid" 2>/dev/null; then STRAY="$STRAY $pid"; kill -9 "$pid" 2>/dev/null || true; fi
  done
  check "sheet renderer: a hanging renderer times out (its whole process group killed) and a non-PDF output is refused" \
    "$([ "$R_RC" -eq 0 ] || echo "rc=$R_RC")$(grep -qxF 'Rendered: no (excel: timed out after 1 s; soffice: no PDF produced)' <<<"$R_OUT" || echo " line: $R_OUT")$([ "$HANG_SECS" -le 10 ] || echo " took ${HANG_SECS}s")$([ -s "$TMP_ROOT/hang.pids" ] || echo ' the hanging stand-in never ran')$([ -z "$STRAY" ] || echo " stray processes:$STRAY")"
  PY3="$(command -v python3)"
  EMPTY_BIN="$TMP_ROOT/empty-bin"
  mkdir -p "$EMPTY_BIN"
  set +e
  NOSOFF_OUT="$(PATH="$EMPTY_BIN" "$PY3" -I "$RENDER_PY" --chain soffice --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx" 2>&1)"
  set -e
  if [ -e /Applications/LibreOffice.app/Contents/MacOS/soffice ] || [ -e /usr/bin/soffice ] || [ -e /usr/lib/libreoffice/program/soffice ] || [ -e /snap/bin/libreoffice ]; then
    pass "sheet renderer: soffice absent from the PATH and the install locations is not installed (skipped: LibreOffice is installed on this host)"
  else
    check "sheet renderer: soffice absent from the PATH and the install locations is not installed" \
      "$(grep -qxF 'Rendered: no (soffice: not installed)' <<<"$NOSOFF_OUT" || echo "line: $NOSOFF_OUT")"
  fi
  printf 'Source: S1\n\nno structure here\n' >"$TMP_ROOT/plain.md"
  python3 -I "$XLSX_PY" "$FIX_DIR/fixture.xlsx" >"$TMP_ROOT/structured.md" 2>/dev/null
  render_run --only-if-structured "$TMP_ROOT/plain.md" --excel-cmd "$FIX_DIR/fake-excel" --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  GATE_PLAIN="$R_OUT"
  render_run --only-if-structured "$TMP_ROOT/structured.md" --excel-cmd "$FIX_DIR/fake-fail" --soffice "$FIX_DIR/fake-soffice" --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  GATE_STRUCT="$R_OUT"
  render_run --chain soffice --only-if-structured "$TMP_ROOT/plain.md" --soffice "$FIX_DIR/fake-soffice" --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  check "sheet renderer: --only-if-structured skips a converter output without shapes, images, cells layout or merges, unless a renderer is forced" \
    "$(grep -qxF 'Rendered: no (not structured)' <<<"$GATE_PLAIN" || echo "plain: $GATE_PLAIN")$(grep -q '(by soffice, ' <<<"$GATE_STRUCT" || echo " structured: $GATE_STRUCT")$(grep -q '(by soffice, ' <<<"$R_OUT" || echo " forced: $R_OUT")"
  render_run --out "$RENDER_OUT" -- "$FIX_DIR/no-such.xlsx"
  MISSING_RC=$R_RC
  MISSING_ERR=$R_OUT
  render_run --chain bogus --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  BOGUS_RC=$R_RC
  render_run --out "" -- "$FIX_DIR/fixture.xlsx"
  check "sheet renderer: a missing workbook, a bad --chain and an empty --out exit 2 with one line" \
    "$([ "$MISSING_RC" -eq 2 ] || echo "missing rc=$MISSING_RC")$([ "$(printf '%s\n' "$MISSING_ERR" | wc -l | tr -d ' ')" = 1 ] || echo ' missing: more than one line')$([ "$BOGUS_RC" -eq 2 ] || echo " bogus rc=$BOGUS_RC")$([ "$R_RC" -eq 2 ] || echo " empty-out rc=$R_RC")"
  check "sheet renderer: nothing is written outside --out, and --out holds only the PDF" \
    "$(diff <(printf '%s\n' "$FIX_BEFORE") <(cd "$FIX_DIR" && find . | sort) || true)$([ "$(cd "$RENDER_OUT" && find . -mindepth 1 | sort)" = './fixture.pdf' ] || echo " out holds: $(cd "$RENDER_OUT" && find . -mindepth 1 | tr '\n' ' ')")"
  # --- converter --out, UTF-8 streams, the renderer's OSError line -------------
  # The skill runs the converter with --out, so the dossier file is written by
  # the program and never typed out again; stdout then carries one line with
  # the facts of the header (characters, lines, truncation).
  OUTD="$TMP_ROOT/xlsx-out"
  mkdir -p "$OUTD"
  set +e
  python3 -I "$XLSX_PY" "$FIX_DIR/fixture.xlsx" >"$OUTD/stdout.md" 2>/dev/null
  CONV_LINE="$(python3 -I "$XLSX_PY" --out "$OUTD/out.md" -- "$FIX_DIR/fixture.xlsx" 2>&1)"; CONV_RC=$?
  CONV_LINE2="$(python3 -I "$XLSX_PY" --max-chars 120 --out "$OUTD/out120.md" -- "$FIX_DIR/fixture.xlsx" 2>&1)"
  set -e
  CONV_WANT="$(python3 -I -c 'import sys
t = open(sys.argv[1], encoding="utf-8", newline="").read()
print("Converted: %d characters, %d lines, truncated: %s" % (len(t), t.count("\n") + (1 if t and not t.endswith("\n") else 0), "yes" if any(l.startswith("[truncated:") for l in t.split("\n")) else "no"))' "$OUTD/out.md")"
  check "xlsx converter --out: the file is the stdout text byte for byte, and stdout is one Converted: line with its characters, lines and truncation" \
    "$([ "$CONV_RC" -eq 0 ] || echo "rc=$CONV_RC")$(cmp -s "$OUTD/out.md" "$OUTD/stdout.md" || echo ' file differs from stdout')$([ "$CONV_LINE" = "$CONV_WANT" ] || echo " line='$CONV_LINE' want='$CONV_WANT'")$(grep -qxE 'Converted: [0-9]+ characters, [0-9]+ lines, truncated: yes' <<<"$CONV_LINE2" || echo " capped line='$CONV_LINE2'")"
  # A workbook holding Japanese text, an em dash, an emoji and an astral
  # character (written with \u escapes, so this file stays English), run with
  # an ASCII stdout: -X utf8=0 under LC_ALL=C keeps Python from switching to
  # UTF-8 by itself (-I already ignores PYTHONIOENCODING), which is how a
  # Windows pipe in a legacy code page behaves.
  python3 -I - "$OUTD/ja.xlsx" <<'PYJA'
import sys, zipfile
sheet = "\u30b7\u30fc\u30c81"
text = "\u898b\u7a4d\u3082\u308a \u2014 \u78ba\u8a8d \u2705 \U00020bb7"
parts = {
    "[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>',
    "_rels/.rels": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    "xl/workbook.xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="%s" sheetId="1" r:id="rId1"/></sheets></workbook>' % sheet,
    "xl/_rels/workbook.xml.rels": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
    "xl/worksheets/sheet1.xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>%s</t></is></c></row></sheetData></worksheet>' % text,
}
with zipfile.ZipFile(sys.argv[1], "w") as zf:
    for name, body in parts.items():
        zf.writestr(name, body.encode("utf-8"))
PYJA
  JA_TEXT="$(python3 -I -c 'import sys; sys.stdout.buffer.write("\u898b\u7a4d\u3082\u308a \u2014 \u78ba\u8a8d \u2705 \U00020bb7".encode("utf-8"))')"
  set +e
  LC_ALL=C python3 -I -X utf8=0 "$XLSX_PY" -- "$OUTD/ja.xlsx" >"$OUTD/ja-stdout.md" 2>"$OUTD/ja-stdout.err"; JA_RC=$?
  JA_LINE="$(LC_ALL=C python3 -I -X utf8=0 "$XLSX_PY" --out "$OUTD/ja-out.md" -- "$OUTD/ja.xlsx" 2>&1)"; JA_OUT_RC=$?
  python3 -I "$XLSX_PY" -- "$OUTD/ja.xlsx" >"$OUTD/ja-utf8.md" 2>/dev/null
  set -e
  check "xlsx converter: a Japanese workbook under an ASCII stdout prints UTF-8 with line feeds (stdout and --out alike) instead of failing" \
    "$([ "$JA_RC" -eq 0 ] || echo "stdout rc=$JA_RC: $(tail -n 1 "$OUTD/ja-stdout.err")")$(grep -qF -- "$JA_TEXT" "$OUTD/ja-stdout.md" || echo ' stdout lacks the text')$(cmp -s "$OUTD/ja-stdout.md" "$OUTD/ja-utf8.md" || echo ' stdout differs from a UTF-8 run')$([ "$JA_OUT_RC" -eq 0 ] || echo " --out rc=$JA_OUT_RC")$(cmp -s "$OUTD/ja-out.md" "$OUTD/ja-utf8.md" || echo ' --out file differs from a UTF-8 run')$(grep -qxE 'Converted: [0-9]+ characters, [0-9]+ lines, truncated: no' <<<"$JA_LINE" || echo " line='$JA_LINE'")$([ "$(LC_ALL=C grep -c $'\r' "$OUTD/ja-out.md" || true)" = 0 ] || echo ' CR in --out file')"
  set +e
  BAD_OUT_ERR="$(python3 -I "$XLSX_PY" --out "$OUTD/no-such-dir/x.md" -- "$FIX_DIR/fixture.xlsx" 2>&1 >/dev/null)"; BAD_OUT_RC=$?
  cp "$FIX_DIR/fixture.xlsx" "$OUTD/self.xlsx"
  python3 -I "$XLSX_PY" --out "$OUTD/self.xlsx" -- "$OUTD/self.xlsx" >/dev/null 2>&1; SELF_RC=$?
  set -e
  check "xlsx converter --out: an unwritable file exits 1 with one line and no traceback; --out naming the workbook exits 2 and leaves it untouched" \
    "$([ "$BAD_OUT_RC" -eq 1 ] || echo "unwritable rc=$BAD_OUT_RC")$([ "$(printf '%s\n' "$BAD_OUT_ERR" | wc -l | tr -d ' ')" = 1 ] || echo " unwritable: $BAD_OUT_ERR")$([ "$SELF_RC" -eq 2 ] || echo " self rc=$SELF_RC")$(cmp -s "$OUTD/self.xlsx" "$FIX_DIR/fixture.xlsx" || echo ' workbook changed')"
  # Every text file the three scripts write names its line end explicitly,
  # so a Windows Python (whose default would be CR LF) writes the same bytes.
  check "the shipped scripts open every text file they write with an explicit newline=" \
    "$(grep -nE 'open\([^)]*"[wa]t?"' "$XLSX_PY" "$RENDER_PY" "$SKILL_DIR/scripts/ticket_body.py" | grep -v 'newline=' || true)"
  # The renderer: a PDF that cannot be moved into --out (a directory holds its
  # name) and an --out where nothing can be created end with the one
  # documented Rendered: no line and exit 0, never a traceback; stderr is
  # UTF-8 under an ASCII locale too.
  mkdir -p "$OUTD/render-blocked/fixture.pdf"
  set +e
  BLOCK_OUT="$(python3 -I "$RENDER_PY" --chain soffice --soffice "$FIX_DIR/fake-soffice" --out "$OUTD/render-blocked" -- "$FIX_DIR/fixture.xlsx" 2>&1)"; BLOCK_RC=$?
  set -e
  RO_DETAIL=""
  if [ "$(id -u)" != 0 ]; then
    mkdir -p "$OUTD/render-ro"
    chmod 555 "$OUTD/render-ro"
    set +e
    RO_OUT="$(python3 -I "$RENDER_PY" --chain soffice --soffice "$FIX_DIR/fake-soffice" --out "$OUTD/render-ro" -- "$FIX_DIR/fixture.xlsx" 2>&1)"; RO_RC=$?
    set -e
    chmod 755 "$OUTD/render-ro"
    RO_DETAIL="$([ "$RO_RC" -eq 0 ] || echo " read-only rc=$RO_RC")$(grep -qxE 'Rendered: no \(cannot write under --out: [^()]+\)' <<<"$RO_OUT" || echo " read-only line='$RO_OUT'")"
  fi
  # The script runs in-process with an ASCII stderr (what a Windows console
  # in a legacy code page gives it) and a missing workbook whose name is
  # Japanese, built from \u escapes so no non-ASCII text crosses argv or the
  # locale: its one error line must still reach stderr as UTF-8.
  JA_R_OUT="$(python3 -I -c 'import io, runpy, sys
script, out = sys.argv[1], sys.argv[2]
name = out + "/" + "\u672a\u4f5c\u6210.xlsx"
buf = io.BytesIO()
sys.stderr = io.TextIOWrapper(buf, encoding="ascii", errors="backslashreplace")
sys.argv = [script, "--out", out + "/r", "--", name]
code = 0
try:
    runpy.run_path(script, run_name="__main__")
except SystemExit as exc:
    code = exc.code
sys.stderr.flush()
want = "\u672a\u4f5c\u6210.xlsx".encode("utf-8")
sys.stdout.write("rc=%s utf8=%s\n" % (code, "yes" if want in buf.getvalue() else "no"))' "$RENDER_PY" "$OUTD" 2>&1)"
  check "sheet renderer: a PDF that cannot be written and an --out where nothing can be created give one Rendered: no line (exit 0); a Japanese path on an ASCII stderr is written as UTF-8" \
    "$([ "$BLOCK_RC" -eq 0 ] || echo "blocked rc=$BLOCK_RC")$(grep -qxE 'Rendered: no \(soffice: cannot write the PDF: [^()]+\)' <<<"$BLOCK_OUT" || echo " blocked line='$BLOCK_OUT'")$RO_DETAIL$([ "$JA_R_OUT" = "rc=2 utf8=yes" ] || echo " ASCII stderr: $JA_R_OUT")"
else
  fail "xlsx converter checks" "python3 is not on the PATH"
fi

# Kill switches are real request tokens: Argument Parsing defines them, the
# rubric's Terminology entry resolves them, and spawns forward them.
ARGS_SECTION="$(awk '/^## Argument Parsing$/ {a = 1; next} a && /^## / {a = 0} a' "$SKILL_MD")"
TERM_ENTRY="$(grep -E '^- \*\*Policy kill switch\*\*:' "$GEN_RUBRIC" || true)"
MISSING=""
for key in oracle_verification independent_evidence failure_class_coverage peer_uniformity; do
  grep -qF -- "\`$key\`" <<<"$ARGS_SECTION" || MISSING="$MISSING SKILL.md:'$key'"
  grep -qF -- "constraint_$key" "$GEN_RUBRIC" || MISSING="$MISSING rubric:'constraint_$key'"
done
# shellcheck disable=SC2016  # literal backticks
grep -qF -- '`constraint_<key>=off`' <<<"$ARGS_SECTION" || MISSING="$MISSING SKILL.md:'constraint_<key>=off'"
grep -qF -- 'constraint_<key>=off' <<<"$TERM_ENTRY" || MISSING="$MISSING rubric-Terminology:'constraint_<key>=off'"
grep -qF -- 'Constraints:' "$SKILL_DIR/references/agent-spawn-prompts.md" || MISSING="$MISSING agent-spawn-prompts.md:'Constraints:'"
for f in planner ticket-evaluator; do
  grep -qF -- 'Constraints:' "$SKILL_DIR/references/agents/$f.md" || MISSING="$MISSING agents/$f.md:'Constraints:'"
done
check "constraint_<key>=off is parsed in SKILL.md, resolved in the rubric Terminology and forwarded as Constraints:" "$MISSING"

# shellcheck disable=SC2016  # literal braces
TEMPLATE_PATH='{skill_root}/references/ticket-template.md'
MISSING=""
for f in "$SKILL_MD" "$SKILL_DIR/references/agent-spawn-prompts.md" "$SKILL_DIR/references/agents/planner.md"; do
  grep -qF -- "$TEMPLATE_PATH" "$f" || MISSING="$MISSING ${f#"$SKILL_DIR"/}"
done
check "the planner is passed ticket-template.md by path as its output structure" "$MISSING"

MISSING=""
while IFS='|' read -r rel needle; do
  grep -qF -- "$needle" "$SKILL_DIR/$rel" || MISSING="$MISSING $rel:'$needle'"
done <<'NEEDLES'
SKILL.md|ERROR: unknown constraint key <key>
SKILL.md|ERROR: constraint_<key>= accepts only off
SKILL.md|ERROR: cannot resolve FAIL gates non-interactively; re-run interactively, or with confirm=yes to deliver as FAIL (unresolved) (draft saved under {scratch})
references/agent-spawn-prompts.md|ERROR: cannot resolve FAIL gates non-interactively; re-run interactively, or with confirm=yes to deliver as FAIL (unresolved) (draft saved under {scratch})
SKILL.md|ERROR: findings frontmatter is missing title
references/findings-schema.md|ERROR: findings frontmatter is missing title
references/mode-dispatch-flows.md|ERROR: findings frontmatter is missing title
references/destinations.md|ERROR: mcp_<name>= must be <type>
references/destinations.md|contains a character the curl config cannot carry (", \ or a control character such as a line break)
references/destinations.md|case "${VAR:-}" in *\"*|*\\*|*[[:cntrl:]]*) echo bad;; *) echo ok;; esac
references/sources.md|case "${VAR:-}" in *\"*|*\\*|*[[:cntrl:]]*) echo bad;; *) echo ok;; esac
SKILL.md|ERROR: create-ticket write refused — ticket number {NNN} is already used by <path>; fix {dir}/.ticket-counter, or re-run when the other run has finished
references/destinations.md|ERROR: create-ticket write refused — ticket number {NNN} is already used by <path>; fix {dir}/.ticket-counter, or re-run when the other run has finished
SKILL.md|ERROR: create-ticket counter changed during delivery — {dir}/.ticket-counter was <counter> and is now <value>; another run delivered to {dir}; check {dir} for a ticket number used twice and set the counter above the highest one
references/destinations.md|ERROR: create-ticket counter changed during delivery — {dir}/.ticket-counter was <counter> and is now <value>; another run delivered to {dir}; check {dir} for a ticket number used twice and set the counter above the highest one
SKILL.md|ERROR: brief frontmatter is missing slug
references/mode-dispatch-flows.md|ERROR: brief frontmatter is missing slug
SKILL.md|ERROR: unresolved FAIL gates; the user declined to proceed (draft saved under {scratch})
references/agent-spawn-prompts.md|ERROR: unresolved FAIL gates; the user declined to proceed (draft saved under {scratch})
SKILL.md|ERROR: create-ticket counter write failed — set {dir}/.ticket-counter to <counter + N> (<reason>)
references/destinations.md|ERROR: create-ticket counter write failed — set {dir}/.ticket-counter to <counter + N> (<reason>)
SKILL.md|ERROR: unknown destination kind in destination=<spec without query> (expected local:, mcp:, api:, browser: or cli:)
SKILL.md|ERROR: unknown source kind in source=<spec without query> (expected file:, dir:, mcp:, api:, browser: or cli:)
SKILL.md|ERROR: rounds= must be an integer from 1 to 5
SKILL.md|ERROR: max_tickets= must be an integer from 1 to 30
SKILL.md|ERROR: remote delivery declined; nothing created
SKILL.md|ERROR: destination local: <dir> is not a usable directory path (no .. segment, .git, leading -, quote, backtick, dollar or control character)
references/destinations.md|ERROR: destination local: <dir> is not a usable directory path (no .. segment, .git, leading -, quote, backtick, dollar or control character)
SKILL.md|ERROR: template= <path> is not a usable file path (no .. segment, .git, leading -, quote, backtick, dollar or control character)
references/destinations.md|ERROR: template= <path> is not a usable file path (no .. segment, .git, leading -, quote, backtick, dollar or control character)
SKILL.md|ERROR: source api:<url without query string> returned a sign-in page, not the content; re-run with source_auth_env=<VAR>, or pass the URL without the api: kind so a signed-in client or browser can be tried
SKILL.md|WARNING: decomposer dropped <n> work units beyond the <N>-ticket cap: <titles>; re-run with findings=<{scratch} path>/overflow-findings.md to create them
references/mode-dispatch-flows.md|WARNING: decomposer dropped <n> work units beyond the <N>-ticket cap: <titles>; re-run with findings=<{scratch} path>/overflow-findings.md to create them
SKILL.md|WARNING: <field> "<value>" is not kebab-case; using <normalized>
references/mode-dispatch-flows.md|WARNING: <field> "<value>" is not kebab-case; using <normalized>
references/findings-schema.md|WARNING: <field> "<value>" is not kebab-case; using <normalized>
SKILL.md|WARNING: <role> spawn failed (<reason>); retrying once
references/sources.md|WARNING: follow-up read of <item URL without query> via <channel> failed (<outcome>); skipped
SKILL.md|WARNING: follow-up read of <item URL without query> via <channel> failed (<outcome>); skipped
SKILL.md|ERROR: more than 50 sources; narrow the inputs
references/sources.md|ERROR: more than 50 sources; narrow the inputs
README.md|ERROR: more than 50 sources; narrow the inputs
SKILL.md|WARNING: source dir:<path> skipped <k> file(s) beyond the 50-source cap
references/sources.md|WARNING: source dir:<path> skipped <k> file(s) beyond the 50-source cap
README.md|WARNING: source dir:<path> skipped <k> file(s) beyond the 50-source cap
SKILL.md|WARNING: follow-up reads of <item URL without query> stopped at the 50-source cap
references/sources.md|WARNING: follow-up reads of <item URL without query> stopped at the 50-source cap
README.md|WARNING: follow-up reads of <item URL without query> stopped at the 50-source cap
SKILL.md|WARNING: source dir:<path> has <k> directories below 5 levels, which were not read
references/sources.md|WARNING: source dir:<path> has <k> directories below 5 levels, which were not read
README.md|WARNING: source dir:<path> has <k> directories below 5 levels, which were not read
SKILL.md|NOTE: this host has no ask-user tool; running as if confirm=yes was passed (a remote create is not confirmed first, and a ticket still graded FAIL is delivered as FAIL (unresolved)); pass confirm=no to stop instead
README.md|NOTE: this host has no ask-user tool; running as if confirm=yes was passed (a remote create is not confirmed first, and a ticket still graded FAIL is delivered as FAIL (unresolved)); pass confirm=no to stop instead
references/destinations.md|NOTE: this host has no ask-user tool; running as if confirm=yes was passed (a remote create is not confirmed first, and a ticket still graded FAIL is delivered as FAIL (unresolved)); pass confirm=no to stop instead
SKILL.md|ERROR: confirm= must be yes or no
SKILL.md|ERROR: keep_scratch= must be yes or no
SKILL.md|grep -qE '^\*\*/\.local/\*[[:space:]]*$' "<root>/.gitignore"
SKILL.md|[ -e "<root>/.gitignore" ]
SKILL.md|printf '\n%s\n' '**/.local/*' >> "<root>/.gitignore"
SKILL.md|printf '%s\n' '**/.local/*' > "<root>/.gitignore"
SKILL.md|WARNING: could not remove the scratch directory <{scratch}> (<reason>)
references/write-path-templates.md|WARNING: could not remove the scratch directory <{scratch}> (<reason>)
NEEDLES
check "the new ERROR: literals are present where they are raised" "$MISSING"
MISSING=""
for rel in SKILL.md references/destinations.md references/write-path-templates.md references/agent-spawn-prompts.md references/mode-dispatch-flows.md README.md; do
  grep -qF -- 'FAIL (unresolved)' "$SKILL_DIR/$rel" || MISSING="$MISSING $rel"
done
check "the FAIL (unresolved) verdict of confirm=yes at the exhausted-retry question is documented everywhere verdicts are" "$MISSING"
# shellcheck disable=SC2016  # literal braces
check "no stale exhausted-retry ERROR literal (re-run interactively without the confirm=yes route)" \
  "$(grep -rnF -- 're-run interactively (draft saved under {scratch})' "$SKILL_DIR" | cut -c1-160 || true)"
check "no stale three-verdict wording (four verdicts exist)" \
  "$(grep -rnE -- 'three verdicts|Exactly three' "$SKILL_DIR" | cut -c1-160 || true)"
check "SKILL.md names its role section ## Mandatory role invocations" \
  "$(grep -qx '## Mandatory role invocations' "$SKILL_MD" || echo missing)"
# shellcheck disable=SC2016  # literal backslashes and brackets
check "the api: id_path pattern requires a leading .name step" \
  "$(grep -qF -- '`^\.[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*|\[[0-9]+\])*$`' "$DEST_MD" || echo 'id_path pattern missing')"
LATER_REVIEW="A later code review of the implementation, outside this skill, may still report a coverage gap in the code; this skill's gates grade only the ticket text."
check "the rubric defines the downstream implementer/verifier and states the later-code-review rule" \
  "$(awk '/^# / {h = 1; next} h && NF {print; exit}' "$GEN_RUBRIC" | grep -qF '**downstream implementer/verifier**' || echo 'phrase not defined in the opening paragraph')$([ "$(grep -cF -- "$LATER_REVIEW" "$GEN_RUBRIC" || true)" -ge 3 ] || echo ' later-code-review sentence missing')"
check "no Phase 1.5 and no ADVISORY-CONSULT trace in the tree" \
  "$(grep -rnE 'Phase 1\.5|ADVISORY-CONSULT' "$SKILL_DIR" | cut -c1-160 || true)"
check "the ticket template carries no P? priority placeholder" \
  "$(grep -nF 'P?' "$SKILL_DIR/references/ticket-template.md" || true)"
check "SKILL.md has no dynamic !\`...\` probe line" "$(grep -n '!`' "$SKILL_MD" || true)"
check "every shipped agent prompt is frontmatter-free" \
  "$(for f in "$SKILL_DIR"/references/agents/*.md; do [ "$(head -n 1 "$f")" != "---" ] || echo "$f"; done)"

# --- platform item URLs in prose (access channels, best guess, sign-in) --------
MISSING=""
# shellcheck disable=SC2016  # literal backticks, braces and dollars
for needle in '**Platform item URLs**' '**access channel**' '**Best guess**' '**Auth**' '**Sign-in rule**' 'source_content_path=' 'source_auth_scheme=' 'content_type=' 'auth_scheme=' '{scratch}/template-derived.json' 'Derived: input from' 'Derived: output from' 'Derived:' 'Tried: input <item URL without query> via <channel>' 'Probe: output <item URL without query> via <channel>' '**read probe**' 'sign-in page even with a 2xx status' 'once a create has been attempted, nothing falls through' '**re-run tokens**' 'it never reads a value and never prints one' 'the name it uses is always printed on the `Resolved:` line' 'never written into the dossier, a ticket, the Final summary or a spawn prompt' '`source=cli:<command>`' '`source=browser:<item URL>`' '`destination=cli:<command template>`' '`destination=browser:<item URL>`' 'read every way instead of being asked about' 'percent-encoded' 'A `cli:` command (a source or a destination template, typed or derived) is exempt' 'ERROR: auth_scheme= must be bearer, basic or basic-token' 'ERROR: source_auth_scheme= must be bearer, basic or basic-token' 'ERROR: content_type= applies only to an api: destination' 'ERROR: auth_scheme= applies only to an api: destination' 'ERROR: source_auth_scheme= applies only to an api: source'; do
  grep -qF -- "$needle" <<<"$ARGS_SECTION" || MISSING="$MISSING SKILL.md-Argument-Parsing:'$needle'"
done
HOST_SECTION="$(awk '/^## Host notes$/ {h = 1; next} h && /^## / {h = 0} h' "$SKILL_MD")"
# shellcheck disable=SC2016  # literal backticks and dollars
for needle in 'spells out the tokens to pass' 'the **browser tool**' 'never required' 'no `browser:` channel is ever a candidate' 'with one carve-out: a `cli:` command, typed or derived, runs as given and is printed in full before it runs' '`$VAR` references are allowed' 'control characters and newlines are refused' 'may name an account'; do
  grep -qF -- "$needle" <<<"$HOST_SECTION" || MISSING="$MISSING SKILL.md-Host-notes:'$needle'"
done
# shellcheck disable=SC2016  # literal backticks
grep -qF -- 'any other role except the URL-fetch tool → `ERROR: this host offers no <role>`' <<<"$HOST_SECTION" || MISSING="$MISSING SKILL.md-Host-notes:'browser tool exempt from the missing-role ERROR'"
INTAKE_SECTION="$(awk '/^## Intake$/ {h = 1; next} h && /^## / {h = 0} h' "$SKILL_MD")"
# shellcheck disable=SC2016  # literal backticks
for needle in 'source_content_path=' 'Derived from:' '`cli:` by one run of the command' '`browser:` by the browser tool' 'Tried:' 'a `cli:` command'"'"'s first word'; do
  grep -qF -- "$needle" <<<"$INTAKE_SECTION" || MISSING="$MISSING SKILL.md-Intake:'$needle'"
done
# shellcheck disable=SC2016  # literal backticks, braces and dollars
for needle in '### A platform item named by URL in prose' '## `cli:<command>`' '## `browser:<url>`' 'source_content_path=' 'source_auth_scheme=basic' 'Derived from: <' 'has no content at <path>' '**A sign-in page is a failed read.**' 'Tried: input <item URL without query> via <channel>' 'Kind: file | dir | mcp | api | cli | browser' 'A value that begins with `cli:` is always one spec' 'never a transcription of a screenshot' "printf 'header = \"Authorization: Basic %s\"\\n' \"\$(printf '%s' \"\$VAR\" | base64 | tr -d '\\n')\" | curl" 'lines 1-7'; do
  grep -qF -- "$needle" "$SOURCES_MD" || MISSING="$MISSING sources.md:'$needle'"
done
check "the platform-item subsection directly follows the MCP-item subsection in sources.md" \
  "$(awk '/^##+ / {if (prev == "### An MCP item named in prose") print; prev = $0}' "$SOURCES_MD" | grep -qxF '### A platform item named by URL in prose' || echo 'platform-item subsection is not right after the MCP-item subsection')"
# shellcheck disable=SC2016  # literal backticks
check "the cli: and browser: sections follow the api: section, in that order, in both reference files" \
  "$(for f in "$SOURCES_MD" "$DEST_MD"; do seq_="$(grep -E '^## `(api|cli|browser):' "$f" | sed -E 's/^## `([a-z]+):.*/\1/' | tr '\n' ' ')"; [ "$seq_" = 'api cli browser ' ] || printf ' %s:%s' "${f##*/}" "$seq_"; done)"
# shellcheck disable=SC2016  # literal backticks, braces and dollars
for needle in 'content_type=<media type>' 'auth_scheme=bearer|basic' 'ERROR: destination api: unusable content_type <value>' '{scratch}/template-derived.json' 'needs no exception' 'derived from <item URL without query>: via api' '(derived: destination=api:' '(derived: destination="cli:' '(derived: destination=browser:' 'select(contains("{parent}"))' 'Authorization: Basic %s' '-H "Content-Type: <content_type>"' '## `cli:<command template>`' '## `browser:<url>`' '`{title_file}`' '`{body_file}`' '`{request_file}`' 'plain text substitution' 'Probe: output <item URL without query> via api:' 'jq empty' 'form-driven create is fragile' 'never fall through to another access channel once a create was attempted' 'no identifier in the output; the item may exist' 'no identifier on the page after submit; the item may exist' 'Never submit a form again for that ticket'; do
  grep -qF -- "$needle" "$DEST_MD" || MISSING="$MISSING destinations.md:'$needle'"
done
# shellcheck disable=SC2016  # literal braces
grep -qF -- 'select(. == "{parent}")' "$DEST_MD" && MISSING="$MISSING destinations.md:'stale whole-value {parent} test'"
grep -qF -- 'only the `Bearer` scheme is supported' "$DEST_MD" && MISSING="$MISSING destinations.md:'stale Bearer-only claim'"
grep -qF -- 'Derived from: <item URL without query>' "$SKILL_DIR/references/write-path-templates.md" || MISSING="$MISSING write-path-templates.md:'Derived from:'"
grep -qF -- 'seven lines for a source derived from a platform item URL' "$SKILL_DIR/references/spec-decomposer-input.md" || MISSING="$MISSING spec-decomposer-input.md:'seven-line header'"
# shellcheck disable=SC2016  # literal backticks
for needle in 'source_content_path=' 'source_auth_scheme=' 'content_type=' 'auth_scheme=' 'Derived:' 'Tried:' 'Probe:' 'never read or printed' 'inside a longer string' 'source="cli:<command>"' '`source=browser:<url>`' '`cli:<command>`' '`browser:<url>`' 'browser-automation tool' 'form-driven creates are fragile; the orchestrator prefers a client or an API when either exists' 'A typed `cli:` command is your own'; do
  grep -qF -- "$needle" "$SKILL_DIR/README.md" || MISSING="$MISSING README.md:'$needle'"
done
for needle in 'source_content_path=' 'Derived:' 'inside a longer template string' 'Tried:' 'Probe:' 'nine roles' 'the browser tool (optional, never required)'; do
  grep -qF -- "$needle" "$MANIFEST_DIR/README.md" || MISSING="$MISSING generator-README:'$needle'"
done
# shellcheck disable=SC2016  # literal backticks
grep -qF -- 'a signed-in command-line' <<<"$DESC" || MISSING="$MISSING description:'signed-in command-line client'"
grep -qF -- 'browser-automation tool of the session' <<<"$DESC" || MISSING="$MISSING description:'browser-automation tool of the session'"
# The confidence floor and the never-invent rule are replaced by the best
# guess and the set/unset name probe; their literals must be gone everywhere.
STALE_HITS="$(grep -rnF -e 'cannot derive the HTTP API' -e 'never invents an environment-variable name' -e '**Confidence floor**' -e 'needs a token; re-run with' -e 'needs a token`' "$SKILL_DIR" | cut -c1-160 || true)"
[ -z "$STALE_HITS" ] || MISSING="$MISSING stale:$STALE_HITS"
check "platform item URLs in prose: access channels, best guess with Tried:/Probe: lines, the sign-in rule, the cli: and browser: kinds and the derived api: options are documented where they apply" "$MISSING"

# Every ERROR: literal the access-channel feature added appears identically in
# the section of SKILL.md that raises it (a = Argument Parsing), in the Error
# Handling table (e) and in the reference file that defines it (s = sources.md,
# d = destinations.md).
ERR_SECTION="$(awk '/^## Error Handling$/ {h = 1; next} h && /^## / {h = 0} h' "$SKILL_MD")"
MISSING=""
while IFS='|' read -r where needle; do
  case "$where" in *a*) grep -qF -- "$needle" <<<"$ARGS_SECTION" || MISSING="$MISSING Argument-Parsing:'$needle'" ;; esac
  case "$where" in *e*) grep -qF -- "$needle" <<<"$ERR_SECTION" || MISSING="$MISSING Error-Handling:'$needle'" ;; esac
  case "$where" in *s*) grep -qF -- "$needle" "$SOURCES_MD" || MISSING="$MISSING sources.md:'$needle'" ;; esac
  case "$where" in *d*) grep -qF -- "$needle" "$DEST_MD" || MISSING="$MISSING destinations.md:'$needle'" ;; esac
done <<'CHANNEL_ERRORS'
aes|ERROR: could not read <item URL without query> (tried: <channel>: <outcome>; ...); sign in to <host> with the platform's command-line client or the browser, or re-run with <re-run tokens>
ae|ERROR: output <item URL without query>: the derived <channel> could not reach the parent item (<outcome>); nothing created; pass <re-run tokens>
d|could not reach the parent item (<outcome>); nothing created; pass <re-run tokens>
aes|needs a sign-in to <host>: sign in with the platform's command-line client or the browser, or re-run with <re-run tokens, with source_auth_env=<VAR> or auth_env=<VAR> to fill in>
aes|ERROR: this host offers no browser tool; pass source=api:<url> or source=cli:<command>
aed|ERROR: this host offers no browser tool; pass destination=api:<url> or destination=cli:<command>
aes|ERROR: source cli: a credential in the command line; use $VAR
aed|ERROR: destination cli: a credential in the command line; use $VAR
aed|ERROR: destination cli: unusable command template (<rule>)
ae|ERROR: parent= applies only to an mcp:, api:, browser: or cli: destination
ae|ERROR: auth_env=, template= and id_path= apply only to an api: or cli: destination
ae|ERROR: source_content_path= applies only to an api: or cli: source
ae|(expected local:, mcp:, api:, browser: or cli:)
ae|(expected file:, dir:, mcp:, api:, browser: or cli:)
es|ERROR: source api:<url without query string> returned a sign-in page, not the content; re-run with source_auth_env=<VAR>, or pass the URL without the api: kind so a signed-in client or browser can be tried
es|ERROR: source cli: <first word> is not on PATH
es|ERROR: source cli:<command> failed (exit <n>: <first line of the error output, at most 200 characters>)
es|ERROR: source cli:<command> returned no content
es|ERROR: source cli:<command> has no content at <path>
es|ERROR: source browser:<url without query string> could not be read (<first line of the error, at most 200 characters>)
es|ERROR: source browser:<url without query string> returned no content
ed|ERROR: destination cli: <first word> is not on PATH
ed|ERROR: destination cli: the probe <probe command> failed (exit <n>); nothing created
ed|ERROR: destination cli: the command template names none of {title_file}, {body_file} or {request_file}
ed|ERROR: destination cli: {request_file} needs jq 1.6 or later on PATH
ed|ERROR: destination cli: parent= needs a {parent} placeholder in the command template or its template=
ed|ERROR: destination cli: the command template uses {parent} but no parent= was given
ed|ERROR: destination cli: environment variable <VAR> is not set
ed|ERROR: destination browser:<url without query string>: no create form with a title and a body field (<outcome>)
CHANNEL_ERRORS
check "every ERROR: literal of the access channels appears identically where it is raised, in the Error Handling table and in its reference file" "$MISSING"

# --- audit fixes: split FAIL, rounds=, max_tickets=, kind-less URLs, B1 preflight --
# Literals the audit removed must be gone everywhere (case-insensitive, so a
# sentence-initial "Max 2 rounds" or "If any sub-ticket" is caught too).
STALE=""
for needle in 'sources exceed the intake limit' 'must be kebab-case' 'max 2 rounds' '8-ticket cap' 'subdirectories, which were not read' 'must be a relative path inside the repository' 'If ANY sub-ticket FAILs' 'a URL is `api:`' 'a bare URL stays `api:`' 'is read as `api:`' 'after two rounds' 'initial + 1 revision' '(decomposer: 1000' 'nothing is read or written before them' 'a required parameter `<name>`' 'an `mcp:` or `api:` destination' 'or no ask-user tool at all' 'and only here' 'No directories created' 'no directory writes' 'the API with a token variable the request names' 'the API with a named' 'more than 50 sources after directory expansion' 'confirm= accepts only yes' 'the only way to deliver' 'this host cannot ask'; do
  h="$(grep -rniF -- "$needle" "$SKILL_DIR" | cut -c1-160 || true)"
  [ -z "$h" ] || STALE="$STALE
[$needle] $h"
done
check "no literal the audit removed remains (intake ERROR, kebab ERROR, fixed round and ticket caps, dir subdirectory WARNING, relative-only local:, atomic FAIL, URL-is-api inference, one-place ~ rule, destination-neutral stop, named-variable candidate slot, expansion-counting source cap, yes-only confirm=, only-way confirm wording)" "${STALE#$'\n'}"

# A typed mcp_<name>= next to a kind-less destination URL, and a token over
# plain http: for a source, each have one literal, stated where it is raised,
# in the Error Handling table and in the reference file of that adapter.
MISSING=""
MCP_IGNORED='WARNING: mcp_<name>= ignored (the destination is reached via <channel>)'
HTTP_TOKEN='ERROR: source api: a token is not sent over plain http; use https'
grep -qF -- "$MCP_IGNORED" "$DEST_MD" || MISSING="$MISSING destinations.md:'$MCP_IGNORED'"
[ "$(grep -cF -- "$MCP_IGNORED" "$SKILL_MD" || true)" -ge 2 ] || MISSING="$MISSING SKILL.md:'$MCP_IGNORED' (Argument Parsing and Error Handling)"
for f in "$SKILL_MD" "$SOURCES_MD"; do
  grep -qF -- "$HTTP_TOKEN" "$f" || MISSING="$MISSING $(basename "$f"):'$HTTP_TOKEN'"
done
check "the mcp_<name>= ignored WARNING and the plain-http token ERROR appear where they are raised and in the Error Handling table" "$MISSING"

MISSING=""
README_MD="$SKILL_DIR/README.md"
# shellcheck disable=SC2016  # literal backticks
for needle in '`rounds=<N>`' '`max_tickets=<N>`' 'overflow-findings.md' 'ERROR: rounds= must be an integer from 1 to 5' 'ERROR: max_tickets= must be an integer from 1 to 30' '(max `rounds=` rounds (default 3: initial + 2 revisions))' 'ONE question' 'retrying once' '**Follow-up reads**' '(content <jq path>, token variable <VAR> (<scheme>))' '; run one platform per request' "only read-only calls (the resolution's own lookups and file checks, and the sign-in probes of **Auth**) run before the \`Resolved:\` line; nothing is written before it" 'a parameter `<name>`, required or optional' 'is not an unknown kind'; do
  grep -qF -- "$needle" "$SKILL_MD" || MISSING="$MISSING SKILL.md:'$needle'"
done
for needle in '[rounds=<N>]' '[max_tickets=<N>]'; do
  printf '%s\n' "$FM" | grep -E '^argument-hint:' | grep -qF -- "$needle" || MISSING="$MISSING argument-hint:'$needle'"
  printf '%s\n' "$ARGS_SECTION" | grep -F 'print `Usage: /create-ticket' | grep -qF -- "$needle" || MISSING="$MISSING Usage:'$needle'"
  grep -qF -- "$needle" "$README_MD" || MISSING="$MISSING README.md:'$needle'"
done
for needle in 'rounds=<N>' 'max_tickets=<N>' 'overflow-findings.md' 'remote delivery declined; nothing created' 'descends at most 5 directory levels'; do
  grep -qF -- "$needle" "$README_MD" || MISSING="$MISSING README.md:'$needle'"
done
for f in references/agent-spawn-prompts.md references/spec-decomposer-input.md references/agents/decomposer.md; do
  grep -qF -- 'Max tickets:' "$SKILL_DIR/$f" || MISSING="$MISSING $f:'Max tickets:'"
done
# shellcheck disable=SC2016  # literal backticks
for needle in '`400 + 120 x N`' '**Overflow**:'; do
  grep -qF -- "$needle" "$SKILL_DIR/references/agents/decomposer.md" || MISSING="$MISSING decomposer.md:'$needle'"
done
grep -qF -- 'r{n}.md' "$SKILL_DIR/references/agent-spawn-prompts.md" || MISSING="$MISSING agent-spawn-prompts.md:'r{n}.md'"
# shellcheck disable=SC2016  # literal backticks
for needle in '**Text probe**' "od -An -c | grep -q '\\\\0'" '`.html`, `.htm`' 'at most 5 levels' '**Follow-up reads.**' 'sum of min(chars, C)' 'two or three exact matches are each read'; do
  grep -qF -- "$needle" "$SOURCES_MD" || MISSING="$MISSING sources.md:'$needle'"
done
# The B1 confirmation check is the last preflight step of each remote kind,
# and a "no" at the confirmation prints the declined literal in each adapter.
for kind in mcp api cli browser; do
  sect="$(awk -v k="$kind" 'index($0, "## `" k ":") == 1 {s = 1; print; next} s && /^## / {s = 0} s' "$DEST_MD")"
  # shellcheck disable=SC2016  # literal backticks
  for needle in '**Confirmation possible.**' 'ERROR: remote delivery needs an interactive confirmation; re-run with confirm=yes to skip it' 'ERROR: remote delivery declined; nothing created'; do
    grep -qF -- "$needle" <<<"$sect" || MISSING="$MISSING destinations.md-$kind:'$needle'"
  done
done
check "rounds=, max_tickets= (Max tickets: line, overflow file), the B1 preflight confirmation check, the declined literal, follow-up reads, per-source derived values and the text probe are documented where they apply" "$MISSING"

# The argument-hint omits the per-kind options of the api: and cli: kinds
# and the remote kinds' body_format=; the Usage line adds those option groups. Every other part of the two must stay identical,
# the five destination kinds included.
HINT_VALUE="$(printf '%s\n' "$FM" | sed -n 's/^argument-hint: "\(.*\)"$/\1/p')"
# shellcheck disable=SC2016  # literal backticks
USAGE_VALUE="$(printf '%s\n' "$ARGS_SECTION" | grep -oE 'print `Usage: /create-ticket [^`]*`' | sed -e 's|^print `Usage: /create-ticket ||' -e 's|`$||')"
USAGE_STRIPPED="$USAGE_VALUE"
MISSING=""
for group in '[source_auth_env=<VAR>]' '[source_auth_scheme=bearer|basic|basic-token]' '[source_content_path=<jq path>]' '[auth_env=<VAR>]' '[auth_scheme=bearer|basic|basic-token]' '[template=<path>]' '[id_path=<path>]' '[content_type=<media type>]' '[body_format=markdown|markdown-escaped|html]'; do
  case "$USAGE_VALUE" in
    *"$group "*) USAGE_STRIPPED="${USAGE_STRIPPED/"$group "/}" ;;
    *) MISSING="$MISSING Usage:'$group'" ;;
  esac
done
[ -n "$HINT_VALUE" ] || MISSING="$MISSING argument-hint:missing"
[ "$USAGE_STRIPPED" = "$HINT_VALUE" ] || MISSING="$MISSING Usage-minus-api-options!=argument-hint:'$USAGE_STRIPPED'"
DEST_GROUP='[destination=local:<dir> | mcp:<server>[/<tool>] | api:<url> | browser:<url> | cli:<command>]'
case "$HINT_VALUE" in *"$DEST_GROUP"*) ;; *) MISSING="$MISSING argument-hint:'$DEST_GROUP'" ;; esac
case "$USAGE_VALUE" in *"$DEST_GROUP"*) ;; *) MISSING="$MISSING Usage:'$DEST_GROUP'" ;; esac
check "the Usage line names the api: source and destination options and body_format=, both name the five destination kinds, and the two are otherwise equal" "$MISSING"

# Implied confirmation: a host with no ask-user tool runs as if confirm=yes
# was passed, announces it once after the preflight and repeats it in the
# Final summary; confirm=no turns it off.
MISSING=""
IMPLIED_NOTE='NOTE: this host has no ask-user tool; running as if confirm=yes was passed (a remote create is not confirmed first, and a ticket still graded FAIL is delivered as FAIL (unresolved)); pass confirm=no to stop instead'
case "$HINT_VALUE" in *'[confirm=yes|no]'*) ;; *) MISSING="$MISSING argument-hint:'[confirm=yes|no]'" ;; esac
case "$USAGE_VALUE" in *'[confirm=yes|no]'*) ;; *) MISSING="$MISSING Usage:'[confirm=yes|no]'" ;; esac
grep -qF -- '[confirm=yes|no]' "$README_MD" || MISSING="$MISSING README.md:'[confirm=yes|no]'"
HOST_SECTION="$(awk '/^## Host notes$/ {a = 1; next} a && /^## / {a = 0} a' "$SKILL_MD")"
grep -qF -- "$IMPLIED_NOTE" <<<"$ARGS_SECTION" || MISSING="$MISSING SKILL.md-Argument-Parsing:NOTE"
grep -qF -- "$IMPLIED_NOTE" <<<"$HOST_SECTION" || MISSING="$MISSING SKILL.md-Host-notes:NOTE"
[ "$(grep -cF -- "$IMPLIED_NOTE" "$SKILL_MD" || true)" -ge 3 ] || MISSING="$MISSING SKILL.md:NOTE (Argument Parsing, Error Handling, Host notes)"
grep -qF -- "$IMPLIED_NOTE" "$SKILL_DIR/references/write-path-templates.md" || MISSING="$MISSING write-path-templates.md:NOTE (Final summary)"
for kind in mcp api cli browser; do
  sect="$(awk -v k="$kind" 'index($0, "## `" k ":") == 1 {s = 1; print; next} s && /^## / {s = 0} s' "$DEST_MD")"
  # shellcheck disable=SC2016  # literal backticks
  grep -qF -- 'When the request carries `confirm=no` and this host has no ask-user tool' <<<"$sect" || MISSING="$MISSING destinations.md-$kind:'confirm=no preflight stop'"
  # shellcheck disable=SC2016  # literal backticks
  grep -qF -- 'Only `confirm=yes`, typed or implied, skips the question.' <<<"$sect" || MISSING="$MISSING destinations.md-$kind:'typed or implied skip'"
done
check "implied confirm=yes on a host with no ask-user tool: [confirm=yes|no], the NOTE line where it is printed and repeated, and the confirm=no preflight stop" "$MISSING"

# Scratch removal (keep_scratch=), the **/.local/* gitignore line and the
# one-destination rule: every site states the same rule.
MISSING=""
WP_MD="$SKILL_DIR/references/write-path-templates.md"
DELIVERY_SECTION="$(awk '/^## Delivery$/ {d = 1; next} d && /^## / {d = 0} d' "$SKILL_MD")"
# shellcheck disable=SC2016  # literal backticks and braces
for needle in '`rm -rf "{scratch}"`' '`[ -d "{scratch}" ]`' '`rmdir .local/create-ticket-scratch`' '`rmdir .local`' 'WARNING: could not remove the scratch directory <{scratch}> (<reason>)' 'Scratch: removed' 'Scratch: <{scratch} path> (kept: <reason>)' '`keep_scratch=yes`, `error`, `a ticket was delivered with a FAIL verdict` and `overflow findings`' 'is expected and ignored silently' 'the only delete commands of this skill'; do
  grep -qF -- "$needle" <<<"$DELIVERY_SECTION" || MISSING="$MISSING SKILL.md-Delivery:'$needle'"
done
[ "$(grep -cF -- 'WARNING: could not remove the scratch directory <{scratch}> (<reason>)' "$SKILL_MD" || true)" -ge 2 ] || MISSING="$MISSING SKILL.md:WARNING (Delivery and Error Handling)"
# shellcheck disable=SC2016  # literal backticks
for needle in '- `keep_scratch=yes|no`:' 'ERROR: keep_scratch= must be yes or no'; do
  grep -qF -- "$needle" <<<"$ARGS_SECTION" || MISSING="$MISSING SKILL.md-Argument-Parsing:'$needle'"
done
# shellcheck disable=SC2016  # literal backticks
grep -qF -- '| Unknown `keep_scratch=` value | `ERROR: keep_scratch= must be yes or no` |' "$SKILL_MD" || MISSING="$MISSING SKILL.md-Error-Handling:keep_scratch row"
printf '%s\n' "$FM" | grep -E '^argument-hint:' | grep -qF -- '[keep_scratch=yes|no]' || MISSING="$MISSING argument-hint:'[keep_scratch=yes|no]'"
printf '%s\n' "$ARGS_SECTION" | grep -F 'print `Usage: /create-ticket' | grep -qF -- '[keep_scratch=yes|no]' || MISSING="$MISSING Usage:'[keep_scratch=yes|no]'"
for needle in '[keep_scratch=yes|no]' 'ERROR: keep_scratch= must be yes or no' 'Scratch: removed' '(kept: <reason>)' '**/.local/*'; do
  grep -qF -- "$needle" "$SKILL_DIR/README.md" || MISSING="$MISSING README.md:'$needle'"
done
# shellcheck disable=SC2016  # literal braces
for needle in 'Scratch: removed' 'Scratch: .local/create-ticket-scratch/run.k3Qz9a (kept: keep_scratch=yes)' 'Scratch: <the {scratch} path> (kept: error)' 'Scratch: <{scratch} path> (kept: <reason>)'; do
  grep -qF -- "$needle" "$WP_MD" || MISSING="$MISSING write-path-templates.md:'$needle'"
done
# shellcheck disable=SC2016  # literal backticks
ONE_DEST='**One destination.** A run delivers to exactly one destination. When the destination is not `local:`, no `ticket.md`, `split-plan.md` or counter file is written anywhere, and the default `.local/tickets` directory is never created.'
[ "$(awk 'NF {print; exit}' <<<"$DELIVERY_SECTION" | grep -cF -- "$ONE_DEST" || true)" -eq 1 ] || MISSING="$MISSING SKILL.md-Delivery:'One destination' is not the first paragraph"
RULES_SECTION="$(awk '/^## Rules for every destination$/ {r = 1; next} r && /^## / {r = 0} r' "$DEST_MD")"
[ "$(awk 'NF {print; exit}' <<<"$RULES_SECTION" | grep -cF -- "- $ONE_DEST" || true)" -eq 1 ] || MISSING="$MISSING destinations.md:'One destination' is not the first rule"
# shellcheck disable=SC2016  # literal backticks
grep -qF -- 'Absent, and no output statement in the request → `local:.local/tickets`' <<<"$ARGS_SECTION" || MISSING="$MISSING SKILL.md-Argument-Parsing:'Absent, and no output statement'"
# shellcheck disable=SC2016  # literal backticks and braces
grep -qF -- 'the `Resolved:` line is mandatory output and Phase 1 must not start before it is printed; a derived destination'"'"'s body template is written only to `{scratch}/template-derived.json` (no other file name)' <<<"$ARGS_SECTION" || MISSING="$MISSING SKILL.md-Argument-Parsing:'Resolved: mandatory'"
# shellcheck disable=SC2016  # literal backticks
grep -qF -- 'the only line this skill adds to `.gitignore` for them is the `**/.local/*` line' "$DEST_MD" || MISSING="$MISSING destinations.md:'**/.local/*' tickets sentence"
check "keep_scratch=, the scratch removal commands and its WARNING, the Scratch: removed / (kept: ...) forms, the **/.local/* line and the One destination rule are stated at every site" "$MISSING"
# A live run delivered remotely AND saved a local copy: the One destination
# rule forbids a local copy for a destination other than local:, in the first
# paragraph of SKILL.md Delivery and in the first rule of destinations.md.
MISSING=""
# shellcheck disable=SC2016  # literal backticks and braces
NO_COPY='For a destination other than `local:`, no copy of any ticket is saved to a local file (not under `.local/tickets`, not anywhere else outside `{scratch}`), not even as a backup or for reference.'
[ "$(awk 'NF {print; exit}' <<<"$DELIVERY_SECTION" | grep -cF -- "$NO_COPY" || true)" -eq 1 ] || MISSING="$MISSING SKILL.md-Delivery:first paragraph"
[ "$(awk 'NF {print; exit}' <<<"$RULES_SECTION" | grep -cF -- "$NO_COPY" || true)" -eq 1 ] || MISSING="$MISSING destinations.md:first rule"
grep -qF -- 'saves no copy of any ticket to a local file' "$SKILL_DIR/README.md" || MISSING="$MISSING README.md"
check "the One destination rule forbids any local copy of a ticket for a destination other than local:" "$MISSING"
# The same run ended with a free-form recap instead of the summary block.
MISSING=""
# shellcheck disable=SC2016  # literal backticks
RECAP_RULE='with its literal heading and its `Destination:` and `Scratch:` lines (each in the variants that carry it), and is never replaced by a free-form recap.'
grep -qF -- "$RECAP_RULE" <<<"$DELIVERY_SECTION" || MISSING="$MISSING SKILL.md-Delivery"
FINAL_FMT="$(awk '/^## Final summary format/ {f = 1; next} f && /^## / {f = 0} f' "$WP_MD")"
grep -qF -- "$RECAP_RULE" <<<"$FINAL_FMT" || MISSING="$MISSING write-path-templates.md:Final-summary-format"
grep -qF -- 'is never replaced by a free-form recap' "$SKILL_DIR/README.md" || MISSING="$MISSING README.md"
check "the Final summary block keeps its stated format, heading, Destination: and Scratch: lines and is never replaced by a free-form recap" "$MISSING"
# shellcheck disable=SC2016  # literal backticks
check "no stale no-delete, never-gitignored or one-line .gitignore append claim remains" \
  "$(grep -rnE -- 'uses no delete command|deletes nothing|is not removed at the end|never adds them to `\.gitignore`|No delete command is used|one-line `\.gitignore` append' "$SKILL_DIR" | cut -c1-160 || true)"
# The command lists of Host notes (**Shell commands**) and the README ("Approve
# only") hold the same commands, rm, rmdir and grep included.
MISSING=""
SHELL_BULLET="$(printf '%s\n' "$HOST_NOTES" | grep -F -- '- **Shell commands**:' || true)"
APPROVE_PARA="$(grep -F -- 'Approve only the commands the steps name' "$SKILL_DIR/README.md" || true)"
# shellcheck disable=SC2016  # literal backticks
for cmd in '`date`' '`mktemp`' '`mkdir`' '`ls`' '`mv`' '`cp`' '`command mv`' '`command cp`' '`sed`' '`printf`' '`git`' '`command`' '`curl`' '`jq`' '`base64`' '`tr`' '`dd`' '`od`' '`grep`' '`rm`' '`rmdir`' '`python3`' '`python`' '`py -3`' '`[`' '`echo`' '`case`'; do
  grep -qF -- "$cmd" <<<"$SHELL_BULLET" || MISSING="$MISSING Host-notes:$cmd"
  grep -qF -- "$cmd" <<<"$APPROVE_PARA" || MISSING="$MISSING README:$cmd"
done
check "the Host notes and README command lists agree and hold rm, rmdir, grep, cp and sed" "$MISSING"

# A substitutions.tsv row that lost the TAB before its target glues the file
# name onto the text: no generated line may end in a sentence end followed
# directly by a generated file path.
check "no generated line ends in a sentence end glued to a generated file path" \
  "$(grep -rnE -- '[.)](references/[A-Za-z0-9_/-]+\.md|SKILL\.md|README\.md)$' "$SKILL_DIR" | cut -c1-200 || true)"

# The build refuses such a row up front, naming its line number.
GLUE_TOOLS="$TMP_ROOT/glue-tools"
mkdir -p "$GLUE_TOOLS"
cp -R "$REPO_DIR/tools/standalone-skill" "$GLUE_TOOLS/standalone-skill"
cp "$BUILD" "$GLUE_TOOLS/build-standalone-skill.sh"
printf 'Glue fixture sentence\\.\tA glued fixture sentence.references/sources.md\n' >>"$GLUE_TOOLS/standalone-skill/substitutions.tsv"
GLUE_LINE="$(wc -l <"$GLUE_TOOLS/standalone-skill/substitutions.tsv" | tr -d ' ')"
set +e
bash "$GLUE_TOOLS/build-standalone-skill.sh" --src "$REPO_DIR" --out "$TMP_ROOT/glue-out" >"$TMP_ROOT/glue.log" 2>&1
GLUE_RC=$?
set -e
if [ "$GLUE_RC" -eq 2 ] && grep -qF "substitutions.tsv line $GLUE_LINE:" "$TMP_ROOT/glue.log"; then
  pass "a two-field substitution row with a target glued to its replacement fails the build, naming the line"
else
  fail "a two-field substitution row with a target glued to its replacement fails the build, naming the line" "rc=$GLUE_RC $(head -n 3 "$TMP_ROOT/glue.log")"
fi

# Runnable: the Delivery step 3 filter, taken verbatim from the generated
# destinations.md, substitutes {title}/{body} only as whole values and
# {parent} inside a longer string, never inside a substituted body.
JQ_DIR="$TMP_ROOT/jq-fixture"
mkdir -p "$JQ_DIR"
DELIVERY_FILTER="$(grep -F "'walk(if . == \"{title}\"" "$DEST_MD" | sed -n "s/^[[:space:]]*'\(walk(.*)\)' \\\\\$/\1/p")"
if ! command -v jq >/dev/null 2>&1; then
  fail "the Delivery step 3 jq filter substitutes {parent} inside a string and leaves a body's {parent} text alone" "jq not on PATH"
  fail "source_content_path= extraction yields the field of a JSON body and nothing for an HTML body" "jq not on PATH"
else
  # shellcheck disable=SC2016  # literal braces
  printf '%s\n' '{"fields":{"t":"{title}","d":"{body}"},"rel":[{"url":"https://example.invalid/items/{parent}"}]}' >"$JQ_DIR/template.json"
  printf 'Fixture title\n' >"$JQ_DIR/title-0.txt"
  # shellcheck disable=SC2016  # literal braces
  printf '%s\n' '## Fixture title' '' 'The body names {parent} and {title} as plain text.' >"$JQ_DIR/body-0.md"
  JQ_OUT=""
  JQ_RC=0
  JQ_OUT="$(jq -c --rawfile title "$JQ_DIR/title-0.txt" --rawfile body "$JQ_DIR/body-0.md" --arg parent "42" "$DELIVERY_FILTER" "$JQ_DIR/template.json" 2>&1)" || JQ_RC=$?
  DETAIL=""
  [ -n "$DELIVERY_FILTER" ] || DETAIL="filter not found in destinations.md"
  [ "$JQ_RC" -eq 0 ] || DETAIL="$DETAIL jq rc=$JQ_RC: $JQ_OUT"
  # shellcheck disable=SC2016  # literal braces
  EXPECTED='{"fields":{"t":"Fixture title","d":"## Fixture title\n\nThe body names {parent} and {title} as plain text.\n"},"rel":[{"url":"https://example.invalid/items/42"}]}'
  [ "$JQ_OUT" = "$EXPECTED" ] || DETAIL="$DETAIL got: $JQ_OUT"
  check "the Delivery step 3 jq filter substitutes {parent} inside a string and leaves a body's {parent} text alone" "$DETAIL"
  # A host's file-write tool may write the one-line title file with CRLF.
  printf 'Fixture title\r\n' >"$JQ_DIR/title-1.txt"
  JQ_CRLF_RC=0
  JQ_CRLF="$(jq -r --rawfile title "$JQ_DIR/title-1.txt" --rawfile body "$JQ_DIR/body-0.md" --arg parent "42" "$DELIVERY_FILTER" "$JQ_DIR/template.json" 2>&1 | jq -r '.fields.t')" || JQ_CRLF_RC=$?
  check "the Delivery step 3 jq filter drops a trailing CR and LF from the title file" \
    "$([ "$JQ_CRLF_RC" -eq 0 ] && [ "$JQ_CRLF" = 'Fixture title' ] || printf 'rc=%s title=%q' "$JQ_CRLF_RC" "$JQ_CRLF")"

  printf '%s\n' '{"id":7,"content":"# Page\nRequirement text"}' >"$JQ_DIR/S1.body"
  printf '%s\n' '<!DOCTYPE html><html><body>Sign in</body></html>' >"$JQ_DIR/S2.body"
  printf '%s\n' '{"id":8,"title":"no content field"}' >"$JQ_DIR/S3.body"
  DETAIL=""
  JSON_OUT="$(jq -r '.content // empty' "$JQ_DIR/S1.body" 2>/dev/null || true)"
  [ "$JSON_OUT" = "$(printf '# Page\nRequirement text')" ] || DETAIL="JSON body gave: $JSON_OUT"
  HTML_RC=0
  HTML_OUT="$(jq -r '.content // empty' "$JQ_DIR/S2.body" 2>/dev/null)" || HTML_RC=$?
  [ "$HTML_RC" -ne 0 ] || [ -z "$HTML_OUT" ] || DETAIL="$DETAIL HTML body gave rc=0 and: $HTML_OUT"
  MISSING_OUT="$(jq -r '.content // empty' "$JQ_DIR/S3.body" 2>/dev/null || true)"
  [ -z "$MISSING_OUT" ] || DETAIL="$DETAIL JSON body without the field gave: $MISSING_OUT"
  check "source_content_path= extraction yields the field of a JSON body and nothing for an HTML body" "$DETAIL"
fi

# --- body fidelity: whole text, content-field markup, stored-text check ---------
# The delivered text is the whole last evaluated draft, moved by cp and
# file-edit replacements, converted for the content field by a program, and
# read back after every remote create. Each rule is stated once in
# destinations.md `## Rules for every destination` and pointed to elsewhere.
MISSING=""
# shellcheck disable=SC2016  # literal backticks, braces and dollars
for rule in '- **Whole text, never re-typed.**' '- **Logical ids.**' '- **Heading check.**' '- **Content-field markup.**' '- **Stored text check.**'; do
  [ "$(printf '%s\n' "$RULES_SECTION" | grep -cF -- "$rule" || true)" -eq 1 ] || MISSING="$MISSING destinations.md-Rules:'$rule'"
  [ "$(grep -cF -- "${rule#- }" "$DEST_MD" || true)" -eq 1 ] || MISSING="$MISSING destinations.md:'${rule#- }' stated more than once"
done
while IFS='|' read -r rel needle; do
  grep -qF -- "$needle" "$SKILL_DIR/$rel" || MISSING="$MISSING $rel:'$needle'"
done <<'NEEDLES'
SKILL.md|`command cp "<draft file>" "{scratch}/final-{i}.md"`
SKILL.md|its 0-based position in the topological order of Step DL-1, `i` = `0..N-1`
SKILL.md|**Graded draft**
SKILL.md|**last evaluated draft**
SKILL.md|never a path taken from a subagent's return text
SKILL.md|(**Whole text, never re-typed**, [references/destinations.md](references/destinations.md) `## Rules for every destination`)
SKILL.md|`rm -rf "{scratch}"`
SKILL.md|`[ -d "{scratch}" ]`
SKILL.md|the **Stored text check** reads back what the platform stored
references/destinations.md|`command cp "{scratch}/final-{i}.md" "{ticket_dir_i}/ticket.md"`
references/destinations.md|`command cp "{scratch}/final-{i}.md" "{scratch}/body-{i}.md"`
references/destinations.md|runs from the highest part number down to the lowest and replaces whole ids only
references/destinations.md|read with the file-read tool immediately before the call and passed whole and unchanged
references/destinations.md|read with the file-read tool immediately before the fill and passed whole and unchanged
references/destinations.md|The ticket text never goes on the command line
references/destinations.md|never through command substitution, never with the text written inline
references/destinations.md|the word "description" in a request (which names the destination's long-form field), never shorten the delivered text
references/destinations.md|it cannot see text a platform hides only when it renders the field
references/destinations.md|`sed -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "{scratch}/body-{i}.md" >| "{scratch}/send-{i}.md"`
references/destinations.md|`{ printf '<pre>'; sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "{scratch}/body-{i}.md"; printf '</pre>\n'; } >| "{scratch}/send-{i}.html"`
references/destinations.md|`{python} -I "{skill_root}/scripts/ticket_body.py" convert --to html --in "{scratch}/body-{i}.md" --out "{scratch}/send-{i}.html"`
references/destinations.md|`{python} -I "{skill_root}/scripts/ticket_body.py" check --sent "{scratch}/body-{i}.md" --stored "<file>"`
references/destinations.md|`Converted: html (<n> characters)`
references/destinations.md|`Converted: preformatted fallback (<detail>)`
references/destinations.md|`Body check: complete`
references/destinations.md|`Body check: minor differences (<detail>)`
references/destinations.md|`Body check: incomplete (<detail>)`
references/destinations.md|`Body check: no content field (<detail>)`
references/destinations.md|`complete (headings only)`
references/destinations.md|`{scratch}/stored-{i}.json`
references/destinations.md|as `body <format>` on the `Derived: output from` line (followed by `, field markup declared in the request`
references/destinations.md|`<url without query>?[query-omitted]`
references/destinations.md|so a copied token is refused by the URL check (which refuses `[` and `]`)
references/destinations.md|and the identifier of a created item that a **Stored text check** read puts into one
references/destinations.md|only when it matches `^[A-Za-z0-9][A-Za-z0-9._~:/#@%+=,-]*$`
references/destinations.md|and a `cli:` read writes it double-quoted, like `{parent}`; otherwise no read is made, and the item counts as not read back
references/destinations.md|each title searched as a fixed string, never as a pattern
references/destinations.md|made only of ASCII letters, digits, spaces, `-`, `.`, `,` and `:`
references/destinations.md|With a typed `body_format=`, the derived request declares the field markup only for `markdown` or `markdown-escaped`
references/destinations.md|with `html` it declares nothing, and the `Derived:` line then has no `, field markup declared in the request`
references/destinations.md|Through the `browser:` channel the value is chosen, as part of the same guess, for what the form's body field does with the text filled into it
references/destinations.md|for a typed `browser:` destination that belief is about the form's body field and follows the `browser:` channel rule below
references/agents/planner.md|that file holds only the ticket draft (the **Draft file** instruction of your spawn prompt)
references/destinations.md|(an HTTP status of `4xx`, a command error, or an error result of the create tool)
references/destinations.md|(an error result on a derived destination whose request declares the field markup adds the suffix of **Content-field markup**)
references/destinations.md|a second copy of the body in the same response, such as a field returned raw and rendered, counted once
SKILL.md|while every printed line drops them and a re-run token marks them omitted (`references/destinations.md` **Printed URLs**)
SKILL.md|the retry planner spawned in that round, step b of the retry-with-feedback loop
SKILL.md|are both read from that file with the file-read tool right before each spawn, never from memory of an earlier phase
SKILL.md|outside the degraded branch, the orchestrator never writes, moves or repairs a draft itself
SKILL.md|or (planner) returns `Status: partial` or leaves no draft file that passes the check of Phase 4 **Graded draft** is run again ONCE
SKILL.md|edited in place (**Whole text, never re-typed**, [references/destinations.md](references/destinations.md))
references/agent-spawn-prompts.md|**Draft file** (every planner spawn: this Phase 3 spawn and step b of the Phase 4 retry-with-feedback loop)
references/agent-spawn-prompts.md|"Your output file holds the ticket and nothing else: its first line is the ticket's `## <logical id>: <Title>` heading
references/agent-spawn-prompts.md|the text is not wrapped in a code fence, and notes, analysis, file contents and your return envelope never go into it
references/agent-spawn-prompts.md|the previous round's draft, read from its file as SKILL.md Phase 4 **Graded draft** says and inlined verbatim into the spawn prompt); the **Draft file** instruction of Phase 3;
references/destinations.md|($title | rtrimstr("\n") | rtrimstr("\r"))
references/destinations.md|--rawfile body "<sent body>"
references/destinations.md|`auth_scheme=bearer|basic|basic-token`
references/destinations.md|"$(printf ':%s' "$VAR" | base64 | tr -d '\n')"
references/sources.md|"$(printf ':%s' "$VAR" | base64 | tr -d '\n')"
references/sources.md|`source_auth_scheme=bearer|basic|basic-token`
references/agent-spawn-prompts.md|**Section check** (after the retry planner of step b returns, before step c)
references/write-path-templates.md|`Body: <body_format>; stored text: complete (<k> of <N>)`
references/write-path-templates.md|`, <m> with minor differences` and `, <u> not read back`
references/write-path-templates.md|Body: html; stored text: complete (2 of 2)
references/write-path-templates.md|`Destination:`, `Derived from:`, `Parent:`, `Body:`, `Sources:` and `Partition basis:`
README.md|`body_format=markdown|markdown-escaped|html`
README.md|`auth_scheme=bearer|basic|basic-token`
README.md|`source_auth_scheme=bearer|basic|basic-token`
README.md|`scripts/ticket_body.py`
README.md|a `Body:` line for a remote destination
README.md|it is never typed out again, summarized or converted by the agent
README.md|`rm -rf` on that one directory
references/destinations.md|each searched by its own path
references/destinations.md|an empty list never counts as equal
references/destinations.md|`; partial output quarantined at {dir}/.rollback/{parent-slug}-{ts}/`
references/destinations.md|(after a refusal of the **Heading check**, its own line instead)
references/destinations.md|together with the character that follows it, one replacement per distinct following character other than a digit
references/destinations.md|with the extended regular expression `<kept id>([^0-9]|$)` (the whole id: an occurrence followed by a further digit is another id)
references/destinations.md|an occurrence that ends the file with no line end together with the character before it, as one replacement of that occurrence alone
references/destinations.md|the same search with `<logical id of a created ticket>([^0-9]|$)` finds no logical id of an already-created ticket, followed by a non-digit or by the end of a line, left in `{scratch}/body-{i}.md`
references/destinations.md|finds each kept id that begins with the id of an already-created ticket (the only kept ids a replacement can reach) on as many lines of `{scratch}/body-{i}.md` as of `{scratch}/final-{i}.md`, the first heading line of each left out (the adapter rewrites it)
references/destinations.md|a read that (b) calls for is never skipped while a read-only tool or the page is at hand
references/destinations.md|when that rule finds no Python 3, every conversion and check of the run takes its no-Python form, with its `NOTE:`, and no `ticket_body.py` command runs
references/destinations.md|a `convert` command that exits with a status other than 0 is replaced by the same shell command, without the `NOTE:`
references/destinations.md|A check that exits with a status other than 0 counts as `no content field`.
references/destinations.md|a ticket not yet created, the one being built included, keeps its logical id (a **kept id**)
references/destinations.md|When the check of (a) reports, or counts as, `no content field` or `incomplete`, ONE read of the new item
references/destinations.md|whose output is never checked as stored text
references/destinations.md|`; start of the ticket only`
references/destinations.md|fewer than 20% of its words are found, or no 12 of them stand in a row (half of those found, when fewer than 24 are found), a letter of a script written without word spaces counting as half a word
references/destinations.md|counts as `incomplete`, at (a) and at (b) alike
references/destinations.md|A `no content field` of (a) never stops the run
references/destinations.md|Without Python 3 (the heading lookup of step 2), an `incomplete` of (a) stops the run only when the read of (b) confirms it with an `incomplete` of its own
references/destinations.md|with no read possible, a read that failed, or a read in which no title is found, the outcome is `no content field`, with the `could not be read back` `NOTE:` below
SKILL.md|without Python 3, also an `incomplete` of the create response that no read confirmed
references/agent-spawn-prompts.md|an empty list is a search that did not read the file, never a draft without headings
references/write-path-templates.md|`Body: <body_format>; stored text: complete, headings only (<k> of <N>)`
SKILL.md|before any create, and for `local:` before `split-plan.md` and the counter are written
README.md|Before a ticket is created remotely or kept locally
NEEDLES
# shellcheck disable=SC2016  # literal backticks and braces
grep -qF -- 'body <format>[, field markup declared in the request]' <<<"$ARGS_SECTION" || MISSING="$MISSING SKILL.md-Argument-Parsing:'Derived: output from ... body <format>'"
grep -qF -- '`body_format=markdown|markdown-escaped|html`' <<<"$ARGS_SECTION" || MISSING="$MISSING SKILL.md-Argument-Parsing:'body_format= option'"
grep -qF -- '`content_type=...`, `auth_env=...`, `auth_scheme=...`, `body_format=...`' <<<"$ARGS_SECTION" || MISSING="$MISSING SKILL.md-Argument-Parsing:'Resolved: body_format='"
grep -qF -- '`references/destinations.md` **Printed URLs**' <<<"$ARGS_SECTION" || MISSING="$MISSING SKILL.md-Argument-Parsing:'query kept, Printed URLs'"
for kind in mcp api cli browser; do
  sect="$(awk -v k="$kind" 'index($0, "## `" k ":") == 1 {s = 1; print; next} s && /^## / {s = 0} s' "$DEST_MD")"
  printf '%s\n' "$sect" | grep -F -- '(derived: destination=' | grep -qF -- 'body_format=...)' || MISSING="$MISSING destinations.md-$kind:'(derived: ... body_format=...)'"
  grep -qF -- 'body_format=<format>)?' <<<"$sect" || MISSING="$MISSING destinations.md-$kind:'question body_format=<format>'"
  grep -qF -- '**Stored text check**' <<<"$sect" || MISSING="$MISSING destinations.md-$kind:'Stored text check step'"
done
grep -qxF -- $'scripts/ticket_body.py\t-' "$MANIFEST_DIR/files.tsv" || MISSING="$MISSING files.tsv:'scripts/ticket_body.py'"
for needle in 'scripts/ticket_body.py' 'overrides/scripts-ticket-body.md' 'body_format=markdown|markdown-escaped|html' 'basic-token' '**Whole text, never re-typed**' '**Stored text check**' 'rm -rf "{scratch}"'; do
  grep -qF -- "$needle" "$MANIFEST_DIR/README.md" || MISSING="$MISSING generator-README:'$needle'"
done
check "body fidelity: DL-2 copies the graded draft, every adapter copies the final text, the five delivery rules are stated once in destinations.md and named at every site" "$MISSING"

# Step DL-3 names the Whole-text rule; the Draft file paragraph closes the
# Phase 3 planner section (before the decomposer partition section).
DL3_SECTION="$(awk '/^### Step DL-3/ {s = 1; next} s && /^### / {s = 0} s' "$SKILL_DIR/SKILL.md")"
DF_LN="$(grep -n '^\*\*Draft file\*\*' "$SKILL_DIR/references/agent-spawn-prompts.md" | cut -d: -f1)"
PART_LN="$(grep -n '^### Partition is owned by the decomposer' "$SKILL_DIR/references/agent-spawn-prompts.md" | cut -d: -f1)"
P4_LN="$(grep -n '^## Phase 4' "$SKILL_DIR/references/agent-spawn-prompts.md" | cut -d: -f1)"
check "Step DL-3 points to Whole text, never re-typed, and the Draft file rule sits in Phase 3 of the spawn prompts" \
  "$(grep -qF -- '**Whole text, never re-typed**' <<<"$DL3_SECTION" || echo 'DL-3 pointer missing')$({ [ -n "$DF_LN" ] && [ -n "$PART_LN" ] && [ -n "$P4_LN" ] && [ "$DF_LN" -lt "$PART_LN" ] && [ "$PART_LN" -lt "$P4_LN" ]; } || echo " draft-file=$DF_LN partition=$PART_LN phase4=$P4_LN")"

# The Section check sits between the retry planner (step b) and the retry
# evaluator (step c) of the retry loop.
SPAWN_MD="$SKILL_DIR/references/agent-spawn-prompts.md"
B_LN="$(grep -n '^b\. Re-spawn the \*\*planner\*\*' "$SPAWN_MD" | cut -d: -f1)"
SC_LN="$(grep -n '^\*\*Section check\*\*' "$SPAWN_MD" | cut -d: -f1)"
C_LN="$(grep -n '^c\. Re-spawn the \*\*ticket-evaluator\*\*' "$SPAWN_MD" | cut -d: -f1)"
check "the Section check follows the retry planner and precedes the retry evaluator" \
  "$({ [ -n "$B_LN" ] && [ -n "$SC_LN" ] && [ -n "$C_LN" ] && [ "$B_LN" -lt "$SC_LN" ] && [ "$SC_LN" -lt "$C_LN" ]; } || echo "b=$B_LN section-check=$SC_LN c=$C_LN")"

# Every new ERROR:, WARNING: and NOTE: literal appears identically where it is
# raised (a = Argument Parsing, d = destinations.md, p = agent-spawn-prompts.md)
# and in the Error Handling table (e).
MISSING=""
while IFS='|' read -r where needle; do
  case "$where" in *a*) grep -qF -- "$needle" <<<"$ARGS_SECTION" || MISSING="$MISSING Argument-Parsing:'$needle'" ;; esac
  case "$where" in *e*) grep -qF -- "$needle" <<<"$ERR_SECTION" || MISSING="$MISSING Error-Handling:'$needle'" ;; esac
  case "$where" in *d*) grep -qF -- "$needle" "$DEST_MD" || MISSING="$MISSING destinations.md:'$needle'" ;; esac
  case "$where" in *p*) grep -qF -- "$needle" "$SPAWN_MD" || MISSING="$MISSING agent-spawn-prompts.md:'$needle'" ;; esac
done <<'BODY_LITERALS'
ae|ERROR: body_format= must be one of markdown, markdown-escaped, html
ae|WARNING: body_format= ignored (a local: destination always writes Markdown)
ae|ERROR: auth_scheme= must be bearer, basic or basic-token
ae|ERROR: source_auth_scheme= must be bearer, basic or basic-token
ed|NOTE: no Python 3 on this host; the ticket is delivered as preformatted text inside the HTML field
ed|ERROR: create-ticket delivery refused — the text of <logical id> lost sections while it was prepared (<missing headings>)
ed|ERROR: destination <kind>:<...>: the stored text of <id> is incomplete (<detail>); the item exists and was not changed; the content field may take another markup: re-run with body_format=markdown, body_format=markdown-escaped or body_format=html (final ticket texts: {scratch}/final-*.md)
ed|WARNING: the stored text of <id> differs slightly from the ticket (<detail>)
ed|NOTE: the stored text of <id> could not be read back; its completeness was not checked
ed|NOTE: no Python 3 on this host; the stored text was checked by its heading titles only
ed| (the request declared the field markup; a platform version that does not take the declaration needs body_format=html)
ep|WARNING: the round-<n> draft of <logical id> dropped sections (<headings>)
BODY_LITERALS
check "every new body-fidelity ERROR:, WARNING: and NOTE: literal appears where it is raised and in the Error Handling table" "$MISSING"

# Old wording that re-typed the ticket, the old scheme list and the old
# removal command must be gone from the whole tree.
check "no stale re-type, scheme, removal or heading-check wording remains (file-write of a ticket, bearer|basic without basic-token, rm -r, a heading check before any write)" \
  "$(grep -rnF -e 'with the file-write tool, write the title to' -e 'write `{ticket_dir_i}/ticket.md` with the file-write tool' -e 'starting from its last evaluated draft:' -e 'must be bearer or basic' -e 'rm -r "' -e 'a failed `rm -r`' -e 'a body shape, a parent link' -e '--rawfile body "{scratch}/body-{i}.md"' -e '?<query omitted>' -e 'every printed line and re-run token drops them' -e 'the retry planner of the round before' -e 'before any write or create' -e 'Before a write or create' -e 'nothing written or created for that ticket' -e '(headings only)` included' -e 'the read is never skipped while' -e 'finds each kept id on as many lines' -e 'When the check of (a) reports `no content field` or `incomplete`' -e '(an occurrence at the end of a line together with its line end)' "$SKILL_DIR" | cut -c1-160 || true)$(grep -rnE -- 'bearer\|basic([^|]|$)' "$SKILL_DIR" | cut -c1-160 || true)$(grep -nE -- 'rm -r "|`rm -r`' "$MANIFEST_DIR/README.md" | cut -c1-160 || true)"

TB_PY="$SKILL_DIR/scripts/ticket_body.py"
check "the ticket body script is ASCII-only, backtick-free and starts with a python3 shebang" \
  "$(head -n 1 "$TB_PY" | grep -qx '#!/usr/bin/env python3' || echo 'no shebang')$(grep -n '`' "$TB_PY" | head -n 3 || true)$(LC_ALL=C grep -n '[^ -~]' "$TB_PY" | head -n 3 || true)"
if command -v python3 >/dev/null 2>&1; then
  TBD="$TMP_ROOT/ticket-body"
  mkdir -p "$TBD"
  check "the ticket body script parses as Python 3.8" \
    "$(python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="ascii").read(), feature_version=(3, 8))' "$TB_PY" 2>&1 | tail -n 1)"
  # The Basic headers: every encoding substitution of the generated curl
  # forms (destinations.md and sources.md, basic and basic-token) is run as
  # printed and compared with an independent base64 of the expected string.
  cat >"$TBD/basic-cmds.py" <<'PYBASIC'
import sys
for path in sys.argv[1:]:
    for line in open(path, encoding="utf-8"):
        if line.lstrip().startswith("printf 'header = \"Authorization: Basic %s\"") and '"$(' in line:
            i = line.index('"$(')
            sub = line[i:line.index(')"', i) + 2]
            print(("basic-token" if "':%s'" in sub else "basic") + "\t" + sub)
PYBASIC
  MISSING=""; N_BASIC=0; N_TOKEN=0
  while IFS=$'\t' read -r kind sub; do
    got="$(VAR='tok-123' sh -c "printf '%s' $sub")"
    if [ "$kind" = basic-token ]; then
      N_TOKEN=$((N_TOKEN + 1)); want="$(python3 -I -c 'import base64; print(base64.b64encode(b":tok-123").decode())')"
    else
      N_BASIC=$((N_BASIC + 1)); want="$(python3 -I -c 'import base64; print(base64.b64encode(b"tok-123").decode())')"
    fi
    [ -n "$got" ] && [ "$got" = "$want" ] || MISSING="$MISSING $kind:got='$got',want='$want'"
  done < <(python3 -I "$TBD/basic-cmds.py" "$DEST_MD" "$SOURCES_MD")
  check "the Basic header substitutions of destinations.md and sources.md encode the value (basic) and \":\" plus the value (basic-token)" \
    "$MISSING$([ "$N_BASIC" = 2 ] && [ "$N_TOKEN" = 2 ] || echo " forms: basic=$N_BASIC basic-token=$N_TOKEN")"
  # Fixtures in the shape of references/ticket-template.md: Japanese text
  # (written with \u escapes, so this file stays English), angle-bracket
  # placeholders inside and outside code, count<limit ... ->, >=, an
  # ampersand and an entity reference, an HTML comment, tables with escaped
  # pipes, a fenced block holding table syntax. Further fixtures pin the
  # three thresholds at their limits, comment markers in list items and
  # table rows, stored JSON nested in a string or printed after a line, a
  # body returned twice, a heading holding a link and angle-bracket texts,
# letters of a script written without word spaces, a section whose title
# recurs in prose, reference links and a second level-two heading.
  cat >"$TBD/make.py" <<'PYTB'
import importlib.util, json, os, sys, unicodedata
d = sys.argv[1]
spec = importlib.util.spec_from_file_location("tb", sys.argv[2])
tb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tb)
BT = chr(96)
F = BT * 3
JA = "\u65e5\u672c\u8a9e\u306e\u8aac\u660e\u6587\u3067\u3059"
JA2 = "\u5883\u754c\u5024"
t = """## fixture-part-1: Limit batch size of the importer

| Field | Value |
|-------|-------|
| Priority | **P1 \\| P2 \\| P3** |
| Category | Feature |
| Size | M |
| Dependencies | -- |

### Background

The importer reads every row at once. """ + JA + """ and the operators see timeouts (a & b, x &lt; y).
<!-- reviewer note: this comment is not part of the ticket -->
Sources: S1:L1-L5

### Scope

| File | Lines | Change |
|------|-------|--------|
| src/import.py | 10-40 | add a limit check |
| src/config.py | 5 | read the limit (""" + BT + "a \\| b" + BT + """) |

### Acceptance Criteria

1. """ + BT + "import" + BT + """ rejects a batch when count<limit is false and prints """ + BT + "batch too large" + BT + """ for the """ + JA2 + """ case.
2. An empty batch is accepted and the exit status is 0.
3. A batch of exactly the limit (>= 1 row) is accepted.

#### Failure-Class Coverage (Gate 9)

**Boundary: """ + BT + "<surface name>" + BT + """** and the <surface name> placeholder outside code.

| Failure class | AC(s) or n/a justification |
|------|------|
| R1 FULL-DOMAIN INVARIANT (whole valid domain incl. min/max/empty) | AC-2 \\| AC-3 |
| R2 HOSTILE (malformed/oversized -> bounded error in bounded time) | AC-1 |

### Implementation Notes

- Batch limit comes from config, default 5000 rows.
  The value is validated at start-up.
- Run the checks:

  """ + F + """bash
  | not | a | table |
  |---|---|
  python3 -m importer --limit 10 <input.csv
  """ + F + """

- Nested:
  - first nested item
  - second nested item

### Capabilities

| Name | Type | Purpose | Used by | Bound AC(s) |
|------|------|---------|---------|-------------|
| pytest | test runner | runs the importer tests | implementer | AC-1, AC-2 |
"""
def w(name, text, raw=False):
    with open(os.path.join(d, name), "wb") as fh:
        fh.write(text if raw else text.encode("utf-8"))
w("ticket.md", t)
a = t.index("<limit"); b = t.index("->", a) + 2
w("s-swallow.md", t[:a] + t[b:])
a = t.index("### Implementation Notes"); b = t.index("### Capabilities")
w("s-section.md", t[:a] + t[b:])
w("s-surface.md", t.replace("the <surface name> placeholder", "the  placeholder"))
w("s-decoded.md", t)
w("s-idurl.json", json.dumps({"id": 42, "url": "https://tracker.example.invalid/items/42"}))
w("s-uescape.json", json.dumps({"id": 43, "fields": {"title": "x", "description": t}}, ensure_ascii=True))
w("crlf.md", ("\ufeff" + t).replace("\n", "\r\n").encode("utf-8"), raw=True)
w("bad.md", b"abc \xff\xfe\xfd", raw=True)
hostile = ("## T\n### H\nWrite \\<script\\>alert(1)\\</script\\> and \\<img src=x\\> as text.\nText <script>alert(1)</script> <img src=x onerror=y> <<>> </p> x<y a&b &amp; &lt;tag&gt;\n"
           "- a <b>\n  - b\n    1. c\n       continued\n- d\n\n| <th> | x \\| y | " + BT + "p | q" + BT + " |\n|---|---|---|\n| </table> | 1 | 2 | extra |\n\n"
           + F + "\n| a | b |\n|---|---|\n### not a heading\n<!-- kept as code -->\n" + F + "\n"
           "text <!-- unclosed comment stays visible\n" + ("long" * 5000) + "\n"
           + F + "html\n<p>caf&eacute; &#65;</p>\n" + F + "\nentity in a code span " + BT + "caf&eacute;" + BT + " and outside &#65;BC\n\n"
           "3. three\n4. four\n\nbetween\n\n1. one\n2. two\n5. five\n\n- lazy item\ncontinues here\n- next\n\n"
           + F + "\"><img src=x onerror=y>\ninfo string\n" + F + "\n"
           + F + "js\nunclosed fence <x>\n")
w("hostile.md", hostile)
# A stray comment opener whose only closing marker is an arrow inside a later
# fenced block: an HTML renderer would hide everything between the two.
stray = ("## fixture-part-2: Stray comment opener\n\n### Background\n\nOperators upload spreadsheets every morning, and large uploads time out "
         "before any row is stored, which blocks the nightly reconciliation job and the weekly audit export.\n"
         "The importer <!-- note about the importer\nreads rows.\n\n"
         "### Scope\n\n| File | Change |\n|---|---|\n| src/import.py | add a limit check |\n\n### Acceptance Criteria\n\n"
         "1. Rejects a batch above the configured limit with a bounded error.\n2. Accepts an empty batch and exits with status zero.\n\n"
         "### Implementation Notes\n\n" + F + "mermaid\nimporter --> limit check\n" + F + "\n\n"
         "The limit is read once at start-up from the configuration file, logged with the effective value, "
         "and exposed through the health endpoint so that operators can confirm what the running process enforces.\n")
w("stray.md", stray)
a = stray.index("<!-- note"); b = stray.index("-->") + 3
w("stray-swallowed.md", stray[:a] + stray[b:])
# Entity references and decomposed characters in a faithful store.
w("s-ncr.md", t.replace(JA, "".join("&#%d;" % ord(c) for c in JA)))
w("s-nfd.md", unicodedata.normalize("NFD", t))
# JSON nested in a string value (a tool result whose text block is the
# response) and JSON printed after a line of text (a client's output).
w("s-mcp.json", json.dumps({"content": [{"type": "text", "text": json.dumps({"id": 77, "description": t})}], "isError": False}))
w("s-cli.txt", "Created item 77\n" + json.dumps({"id": 77, "body": t}) + "\n")
# The body returned twice, both copies without acceptance criterion 2.
ac2 = "2. An empty batch is accepted and the exit status is 0.\n"
lossy = t.replace(ac2, "")
obj = {"id": 9, "fields": {"description": lossy}}
w("s-dup-block.json", json.dumps({"content": [{"type": "text", "text": json.dumps(obj)}], "structuredContent": obj}))
w("s-dup-rendered.json", json.dumps({"id": 9, "fields": {"description": lossy}, "renderedFields": {"description": tb.to_html(lossy)}}))
w("s-dup-nested.json", json.dumps({"content": [{"type": "text", "text": json.dumps({"id": 9, "fields": {"description": lossy}, "renderedFields": {"description": tb.to_html(lossy)}})}]}))
# A lost passage holding a control character: the excerpt shows a space.
ctl = ("## fixture-part-8: Control\n\n### Notes\n\nThe notes keep these words in this order so that the excerpt has context around them: "
       "alpha\x07bravo \"charlie\" delta echo foxtrot golf hotel india juliet kilo lima mike and a few more words close the paragraph.\n")
w("ctl.md", ctl)
w("ctl-lost.md", ctl.replace("alpha\x07bravo \"charlie\" delta echo foxtrot golf hotel india juliet kilo lima mike ", ""))
w("s-once.json", json.dumps(obj))
# The same loss in two copies that are not separate values: one text that
# holds the body twice; a faithful body followed by a 90 percent copy.
w("s-dup-text.txt", lossy + "\n\n" + lossy)
w("s-partial.txt", t + "\n\n" + t[: len(t) * 9 // 10])
# The lossy body next to a preview of its first 90 percent, as two values.
w("s-dup-preview.json", json.dumps({"id": 9, "fields": {"description": lossy, "preview": lossy[: len(lossy) * 9 // 10]}}))
# A UTF-16 file with its byte order mark.
w("s-utf16.md", t.encode("utf-16"), raw=True)
# A content field that keeps only the first 255 characters.
w("s-cut255.json", json.dumps({"id": 7, "fields": {"description": t[:255]}}))
# A structured document stores each paragraph as its own value: two
# near-identical criteria are distinct parts of the ticket, never copies.
ac = "The importer rejects a batch of %d rows with exit status 2 and prints the line batch too large to standard error before any row is stored."
w("peer.md", "## fixture-part-7: Peer criteria\n\n### Acceptance Criteria\n\n1. " + ac % 5001 + "\n2. " + ac % 5002 + "\n")
w("s-peer.json", json.dumps({"type": "doc", "content": [{"type": "heading", "text": "Acceptance Criteria"}] + [{"type": "listItem", "text": ac % n} for n in (5001, 5002)]}))
# Three criteria whose numbers are no words: losing the second loses no word
# the others do not hold. A structured document (one value per criterion)
# next to the rendered field, and a page text showing the field twice.
bg = "Operators upload spreadsheets every morning and large uploads time out, which blocks the nightly reconciliation job and the weekly audit export."
w("peer3.md", "## fixture-part-9: Peer criteria\n\n### Background\n\n" + bg + "\n\n### Acceptance Criteria\n\n" + "".join("%d. %s\n" % (k + 1, ac % n) for k, n in enumerate((501, 502, 503))))
def peer_store(ns):
    doc = {"type": "doc", "content": [{"type": "heading", "text": "Background"}, {"type": "paragraph", "text": bg}, {"type": "heading", "text": "Acceptance Criteria"}] + [{"type": "listItem", "text": ac % n} for n in ns]}
    return json.dumps({"id": 11, "fields": {"description": doc}, "renderedFields": {"description": "<h3>Background</h3><p>" + bg + "</p><h3>Acceptance Criteria</h3><ol>" + "".join("<li>%s</li>" % (ac % n) for n in ns) + "</ol>"}})
w("s-peer3.json", peer_store((501, 502, 503)))
w("s-peer3-lost.json", peer_store((501, 503)))
page = "Background\n" + bg + "\nAcceptance Criteria\n" + "".join("%s\n" % (ac % n) for n in (501, 503))
w("s-peer3-page.txt", page + "\n" + page)
# Threshold fixtures: 394 unique words and four headings, 400 words in all.
def zq(k):
    s = ""
    for _ in range(3):
        s = chr(97 + k % 26) + s
        k //= 26
    return "zq" + s
body = [zq(k) for k in range(394)]
heads = [("Background", 0, 100), ("Scope", 100, 200), ("Acceptance Criteria", 200, 300), ("Implementation Notes", 300, 394)]
def thr(drop=()):
    out = ["## fixture-part-3: Thresholds", ""]
    for h, a, b in heads:
        out += ["### " + h, "", " ".join(body[k] for k in range(a, b) if k not in drop), ""]
    return "\n".join(out)
w("thr.md", thr())
w("thr-run11.md", thr(range(150, 161)))
w("thr-run12.md", thr(range(150, 162)))
w("thr-scatter12.md", thr([10 + 30 * j for j in range(12)]))
w("thr-scatter13.md", thr([10 + 28 * j for j in range(13)]))
order = ["background"] + body[0:100] + ["scope"] + body[100:200] + ["acceptance", "criteria"] + body[200:300] + ["implementation", "notes"] + body[300:394]
w("thr-found79.txt", " ".join(order[::5][:79]) + "\n")
w("thr-start79.txt", " ".join(order[:79]) + "\n")
w("thr-found80.txt", " ".join(order[:80]) + "\n")
# Comment markers inside list items and table rows, an empty comment, and a
# block comment that holds list and table lines.
lst = ("## fixture-part-4: Comment markers in list items\n\n### Acceptance Criteria\n\n"
       "1. The scanner reports an opening <!-- marker that is never closed.\n"
       "2. The importer rejects a batch above the configured limit with a bounded error and exit status 2.\n"
       "3. An empty batch is accepted and the exit status is 0.\n"
       "4. The state machine only allows draft --> review and review --> published.\n\n"
       "### Scope\n\n| File | Change |\n|------|--------|\n| src/scan.py | report <!-- without a closer |\n"
       "| src/import.py | add the limit check and the bounded error |\n| src/flow.py | allow draft --> review only |\n\n"
       "### Implementation Notes\n\nUse <!--> as the shortest comment, then alpha bravo charlie.\n"
       "Second line foxtrot golf --> hotel india.\n\n<!--\n- hidden item\n| hidden | row |\n-->\nAfter the block comment.\n")
w("list.md", lst)
w("list-lost.md", lst.replace("2. The importer rejects a batch above the configured limit with a bounded error and exit status 2.\n", "")
  .replace("3. An empty batch is accepted and the exit status is 0.\n", "").replace("| src/import.py | add the limit check and the bounded error |\n", ""))
# A heading that holds a link, and autolinks, stored as a renderer writes them.
w("link.md", "## fixture-part-5: Link heading\n\n### See [the design note](https://example.invalid/design) first\n\nBody text of the section with several words in it.\n"
  "See <https://example.invalid/x> and <ops@example.invalid> for the Map<K, V> details.\n")
w("link.html", '<h3>See <a href="https://example.invalid/design">the design note</a> first</h3>\n<p>Body text of the section with several words in it.<br>\n'
  'See <a href="https://example.invalid/x">https://example.invalid/x</a> and <a href="mailto:ops@example.invalid">ops@example.invalid</a> for the Map&lt;K, V&gt; details.</p>\n')
# A link whose long target a page text never shows, and line-break tags
# written in table cells, which a renderer turns into line breaks.
lt = ("## fixture-part-10: Link target\n\n### Background\n\nThe limit is described in [the design note]"
      "(https://git.example.invalid/org/repo/blob/main/docs/design/importer-limits.md#batch-size \"Importer limits\") of the importer.\n\n"
      "### Scope\n\n| File | Change |\n|---|---|\n| src/import.py | add the check<br>log the limit |\n| src/config.py | read the limit<br />once |\n")
w("lt.md", lt)
# Link syntax inside a code span is text: its target counts in full.
lc = "## fixture-part-11: Code link\n\n### Notes\n\nWrite " + BT + "[the guide](https://docs.example.invalid/very/long/path/to/one/page/with/many/segments/here)" + BT + " exactly as shown.\n"
w("lc.md", lc)
w("lc-lost.md", lc.replace("https://docs.example.invalid/very/long/path/to/one/page/with/many/segments/here", ""))
w("lt-page.txt", "Link target\nBackground\nThe limit is described in the design note of the importer.\nScope\nFile Change\nsrc/import.py add the check\nlog the limit\nsrc/config.py read the limit\nonce\n")
# Angle-bracket texts whose letters are too short to count as words.
kv = ("## fixture-part-6: Types\n\n### Type <!-- checked --> Notes\n\nThe cache is a Map<K, V> of List<T> values and Result<T, E> errors; use Option<T> for the key.\n"
      "A pair is written Pair<A, <!-- second type --> B> in the notes.\n")
w("kv.md", kv)
w("kv-lost.md", kv.replace("<K, V>", "").replace("<T>", "").replace("<T, E>", ""))
# Letters of a script written without word spaces: each is a word of its own,
# weighing half a word in the thresholds (1000 distinct letters and six
# heading words: 1006 words, weight 506, 3 percent of it 15.18).
U = [chr(0x4E00 + k) for k in range(1000)]
cheads = [("Background", 0, 250), ("Scope", 250, 500), ("Acceptance Criteria", 500, 750), ("Implementation Notes", 750, 1000)]
def cjk(drop=()):
    out = ["## fixture-part-12: Unspaced thresholds", ""]
    for h, a, b in cheads:
        out += ["### " + h, "", "".join(U[k] for k in range(a, b) if k not in drop), ""]
    return "\n".join(out)
w("cjk.md", cjk())
w("cjk-run23.md", cjk(range(300, 323)))
w("cjk-run24.md", cjk(range(300, 324)))
w("cjk-scatter30.md", cjk([5 + 33 * j for j in range(30)]))
w("cjk-scatter31.md", cjk([5 + 32 * j for j in range(31)]))
# Such a clause next to code spans and bold text, and the page text a browser
# shows for it, where nothing separates the code or bold text from the clause.
jl = ["1. " + BT + "import" + BT + JA + "**" + JA2 + "**" + JA,
      "2. " + JA2 + BT + "2" + BT + JA + BT + "batch too large" + BT + JA2,
      "3. " + JA + BT + "IMPORT_BATCH_LIMIT" + BT + JA2 + "**" + JA + "**"]
w("jp.md", "## fixture-part-13: Unspaced page text\n\n### Acceptance Criteria\n\n" + "\n".join(jl) + "\n")
w("jp-page.txt", "Unspaced page text\nAcceptance Criteria\n" + "\n".join(l[3:].replace(BT, "").replace("**", "") for l in jl) + "\n")
# A removed section whose one-word title also occurs in prose; the same
# heading kept while the title word is lost from a placeholder and a link
# target only.
rk = ("## fixture-part-14: Risk section\n\n### Background\n\n" + bg + " The main risks are listed below, and the reviewers read them first. "
      "Fill in the <risks list> placeholder and see [the register](https://example.invalid/risks) before review.\n\n"
      "### Acceptance Criteria\n\n1. " + ac % 5001 + "\n2. " + ac % 5002 + "\n3. " + ac % 5003 + "\n\n"
      "### Risks\n\n- A slow disk.\n\n### Implementation Notes\n\nRead the limit once at start-up and log the effective value.\n")
w("rk.md", rk)
w("rk-lost.md", rk.replace("### Risks\n\n- A slow disk.\n\n", ""))
w("rk-page.txt", rk.replace("<risks list> ", "").replace("(https://example.invalid/risks)", "").replace("[the register]", "the register"))
# A reference link and its definition, which a page text never shows, and a
# line in the same shape that is no definition (its text is no destination
# and title), which a page text shows.
rf = ("## fixture-part-15: Reference link\n\n### Background\n\n" + bg + " See [the design note][imp lim spec ref] for the limits of the importer.\n\n"
      "[AC-9]: the importer rejects a batch above the configured limit with a bounded error and exit status two\n\n"
      "### Acceptance Criteria\n\n1. " + ac % 5001 + "\n2. " + ac % 5002 + "\n\n"
      "[imp lim spec ref]: https://git.example.invalid/org/repo/blob/main/docs/design/importer-limits.md 'Importer limits'\n")
w("rf.md", rf)
w("rf-page.txt", rf.replace("[the design note][imp lim spec ref]", "the design note").replace("[imp lim spec ref]: https://git.example.invalid/org/repo/blob/main/docs/design/importer-limits.md 'Importer limits'\n", ""))
w("rf-nodef.txt", rf.replace("[AC-9]: the importer rejects a batch above the configured limit with a bounded error and exit status two\n\n", ""))
# A second level-two heading after the title line, its heading line lost.
h2 = "## fixture-part-16: Second heading\n\n### Background\n\n" + bg + "\n\n## Follow-up Work\n\n" + ac % 7 + "\n"
w("h2.md", h2)
w("h2-lost.md", h2.replace("## Follow-up Work\n\n", ""))
# The first sentence of the Background lost from a store of HTML, the title
# line sharing its letters: the views of the HTML hold as many sent words
# with and without the tag names, and the one without them is aligned, so
# the lost sentence is one span (600 filler words keep the missing share
# under 3 percent).
TJ = "\u6ce8\u6587CSV\u30a8\u30af\u30b9\u30dd\u30fc\u30c8\u306e\u30b7\u30ea\u30a2\u30e9\u30a4\u30b6\u3092\u8ffd\u52a0\u3059\u308b"
S1 = "\u6ce8\u6587\u4e00\u89a7\u753b\u9762\u304b\u3089\u6ce8\u6587\u30c7\u30fc\u30bf\u3092 CSV \u3067\u53d6\u308a\u51fa\u3057\u305f\u3044\u3068\u3044\u3046\u8981\u671b\u304c\u3042\u308b\u3002"
S2 = ("\u73fe\u72b6\u306f " + BT + "src/orders/list.ts" + BT + " \u304c JSON \u3092\u8fd4\u3059\u3060\u3051\u3067\u3001"
      "\u8868\u8a08\u7b97\u30bd\u30d5\u30c8\u306b\u53d6\u308a\u8fbc\u3080\u624b\u6bb5\u304c\u306a\u3044\u3002")
def lead(s1):
    return ("## fixture-part-17: " + TJ + "\n\n| Field | Value |\n|-------|-------|\n| Priority | **P1** |\n| Category | Feature |\n| Size | M |\n"
            "| Dependencies | -- |\n\n### Background\n\n" + s1 + S2 + "\n\n### Scope\n\n- Add the serializer in " + BT + "src/orders/csv.ts" + BT
            + " and export it from the module index.\n\n### Implementation Notes\n\n" + " ".join(zq(k) for k in range(600)) + "\n")
w("lead.md", lead(S1))
w("lead-lost.html", tb.to_html(lead("")))
# Letters of an unspaced script drawn from one set of 200: a stored text
# holding other text of that set (the letters in another order, no run of
# them in a row) holds none of the body, both when it holds a fifth of the
# words and more and when it holds every word as often as the ticket; the
# body itself with 30 letters lost holds its runs and is incomplete. Such a
# text that also holds the first words of the ticket in a row holds its start.
P = [chr(0x4E00 + k) for k in range(200)]
def letters(step, start, count):
    return "".join(P[(start + step * k) % 200] + ("\u3002" if k % 40 == 39 else "") for k in range(count))
jn = "## fixture-part-18: Unspaced other text\n\n### Background\n\n" + letters(7, 0, 300) + "\n\n### Acceptance Criteria\n\n" + letters(7, 100, 300) + "\n"
w("jn.md", jn)
w("jn-other.txt", "Unspaced other text\n" + letters(13, 5, 400) + "\n")
w("jn-every.txt", "Unspaced other text\nBackground\nAcceptance Criteria\n" + letters(13, 5, 800) + "\n")
w("jn-start.txt", "Unspaced other text\nBackground\n" + letters(7, 0, 300)[:15] + "\n" + letters(13, 5, 400) + "\n")
w("jn-lost.md", jn.replace(letters(7, 0, 300)[100:131], ""))
# A store followed by many comment openers that one marker at its end closes.
w("openers.txt", t + "<!-- x\n" * 100000 + "-->")
PYTB
  python3 -I "$TBD/make.py" "$TBD" "$TB_PY"
  # has_tb OUT NEEDLE... — prints every NEEDLE missing from OUT (fixed strings).
  has_tb() {
    local text="$1" n
    shift
    for n in "$@"; do grep -qF -- "$n" <<<"$text" || printf " missing:'%s'" "$n"; done
  }
  tb_check() {
    python3 -I "$TB_PY" check --sent "$1" --stored "$2" 2>&1
  }
  set +e
  CONV_OUT="$(python3 -I "$TB_PY" convert --to html --in "$TBD/ticket.md" --out "$TBD/ticket.html" 2>&1)"; CONV_RC=$?
  set -e
  HTML_OUT="$(cat "$TBD/ticket.html" 2>/dev/null || true)"
  # Every tag of the output is one the converter writes; a text "<" never
  # opens one (parsed with the standard library's HTML parser).
  cat >"$TBD/tags.py" <<'PYTAGS'
import sys
from html.parser import HTMLParser
OK = {"h1", "h2", "h3", "h4", "h5", "h6", "p", "br", "table", "thead", "tbody", "tr", "th", "td", "ol", "ul", "li", "pre", "code", "strong"}
class P(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.bad = []
        self.stack = []
    def handle_starttag(self, tag, attrs):
        if tag not in OK:
            self.bad.append("<%s>" % tag)
        for k, v in attrs:
            if not ((tag, k) in (("ol", "start"), ("li", "value")) and (v or "").isdigit()) and (tag, k) != ("code", "class"):
                self.bad.append("%s %s=" % (tag, k))
        if tag != "br":
            self.stack.append(tag)
    def handle_endtag(self, tag):
        if not self.stack or self.stack[-1] != tag:
            self.bad.append("</%s> unbalanced" % tag)
        else:
            self.stack.pop()
    def handle_comment(self, data):
        self.bad.append("comment")
p = P()
p.feed(open(sys.argv[1], encoding="utf-8").read())
p.close()
print(" ".join(p.bad + ["unclosed %s" % t for t in p.stack]))
PYTAGS
  check "ticket_body.py convert --to html: one Converted: line, the structure kept, every text < escaped, the comment dropped, only converter tags" \
    "$([ "$CONV_RC" -eq 0 ] || echo "rc=$CONV_RC")$(grep -qxE 'Converted: html \([0-9]+ characters\)' <<<"$CONV_OUT" || echo " line='$CONV_OUT'")$(has_tb "$HTML_OUT" '<h2>fixture-part-1: Limit batch size of the importer</h2>' '<td><strong>P1 | P2 | P3</strong></td>' '<code>a | b</code>' 'count&lt;limit is false' '<code>&lt;surface name&gt;</code>' 'the &lt;surface name&gt; placeholder' '(&gt;= 1 row)' 'oversized -&gt; bounded' '<li><code>import</code> rejects' '<pre><code class="language-bash">| not | a | table |' 'python3 -m importer --limit 10 &lt;input.csv' '<li>first nested item</li>')$(printf '%s\n' "$HTML_OUT" | grep -nE '<surface|<limit|<input|reviewer note' || true)$(python3 -I "$TBD/tags.py" "$TBD/ticket.html")"
  python3 -I -c 'import json, sys; json.dump({"id": 7, "fields": {"title": "x", "description": open(sys.argv[1], encoding="utf-8").read()}}, open(sys.argv[2], "w"))' "$TBD/ticket.html" "$TBD/s-json-html.json"
  python3 -I "$TB_PY" convert --to markdown-escaped --in "$TBD/ticket.md" --out "$TBD/s-escaped.md" >/dev/null
  python3 -I -c 'import html, sys; open(sys.argv[2], "w", encoding="utf-8").write(html.unescape(open(sys.argv[1], encoding="utf-8").read()))' "$TBD/s-escaped.md" "$TBD/s-escaped-decoded.md"
  MISSING=""
  for pair in 'ticket.html|Body check: complete' 's-json-html.json|Body check: complete' 's-escaped.md|Body check: complete' 's-escaped-decoded.md|Body check: complete' 's-uescape.json|Body check: complete' 's-decoded.md|Body check: complete'; do
    got="$(tb_check "$TBD/ticket.md" "$TBD/${pair%%|*}")"
    [ "$got" = "${pair#*|}" ] || MISSING="$MISSING ${pair%%|*}:'$got'"
  done
  grep -qF '\u' "$TBD/s-uescape.json" || MISSING="$MISSING s-uescape.json:no-\\u-escape"
  check "ticket_body.py check: the converted HTML, a JSON response holding it, the escaped Markdown (stored as is or entity-decoded) and a \\uXXXX-escaped JSON copy are complete" "$MISSING"
  SWALLOW="$(tb_check "$TBD/ticket.md" "$TBD/s-swallow.md")"
  SECTION="$(tb_check "$TBD/ticket.md" "$TBD/s-section.md")"
  SURFACE="$(tb_check "$TBD/ticket.md" "$TBD/s-surface.md")"
  IDURL="$(tb_check "$TBD/ticket.md" "$TBD/s-idurl.json")"
  check "ticket_body.py check: a text swallowed from <limit to -> is incomplete and names the heading it lost" \
    "$(grep -qE '^Body check: incomplete \(missing [0-9]+ of [0-9]+ words in 1 spans and 2 angle-bracket texts; headings missing: "Failure-Class Coverage \(Gate 9\)"; longest span under "Acceptance Criteria": "limit is false' <<<"$SWALLOW" || echo "got: $SWALLOW")"
  SECTION_EXCERPT="$(printf '%s\n' "$SECTION" | sed -n 's/.*longest span under "Implementation Notes": "\(.*\)")$/\1/p')"
  check "ticket_body.py check: a whole ### section removed is incomplete, with that heading listed and its excerpt cut to 80 characters" \
    "$(grep -qE '^Body check: incomplete \(.*headings missing: "Implementation Notes"; longest span under "Implementation Notes"' <<<"$SECTION" || echo "got: $SECTION")$([ "${#SECTION_EXCERPT}" -eq 80 ] && [ "${SECTION_EXCERPT%...}" != "$SECTION_EXCERPT" ] || echo " excerpt of ${#SECTION_EXCERPT} characters: '$SECTION_EXCERPT'")"
  check "ticket_body.py check: only <surface name> dropped from a stored Markdown copy is a minor difference" \
    "$(grep -qxF 'Body check: minor differences (missing 2 of 185 words in 1 spans and 1 angle-bracket texts; first under "Failure-Class Coverage (Gate 9)": "surface name")' <<<"$SURFACE" || echo "got: $SURFACE")"
  check "ticket_body.py check: a create response with only an id and a URL holds no content field" \
    "$(grep -qxF 'Body check: no content field (0 of 185 words found)' <<<"$IDURL" || echo "got: $IDURL")"
  python3 -I "$TB_PY" convert --to html --in "$TBD/crlf.md" --out "$TBD/crlf.html" >/dev/null
  check "ticket_body.py: a CRLF ticket with a byte order mark converts to the same HTML (UTF-8, LF, no BOM) and checks complete" \
    "$(cmp -s "$TBD/crlf.html" "$TBD/ticket.html" || echo 'html differs')$([ "$(LC_ALL=C grep -c $'\r' "$TBD/crlf.html" || true)" = 0 ] || echo ' CR in output')$(head -c 3 "$TBD/crlf.html" | od -An -tx1 | grep -q 'ef bb bf' && echo ' BOM in output' || true)$(tb_check "$TBD/crlf.md" "$TBD/ticket.html" | grep -qxF 'Body check: complete' || echo ' check not complete')"
  # The two shell conversions of destinations.md, run as printed, write what
  # the script's own --to markdown-escaped and --to pre write.
  cat >"$TBD/cmds.py" <<'PYCMDS'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
out = []
for start in ("written by the shell tool running `", "the shell tool writes that preformatted form, `"):
    i = text.index(start) + len(start)
    out.append(text[i:text.index("`", i)])
print("\n".join(out))
PYCMDS
  SHELL_CMDS="$(python3 -I "$TBD/cmds.py" "$DEST_MD" | sed -e "s#{scratch}#$TBD#g" -e 's#{i}#0#g')"
  cp "$TBD/ticket.md" "$TBD/body-0.md"
  printf '%s\n' "$SHELL_CMDS" | sh
  python3 -I "$TB_PY" convert --to pre --in "$TBD/body-0.md" --out "$TBD/py-pre.html" >/dev/null
  check "the markdown-escaped and preformatted shell commands of destinations.md write what ticket_body.py writes" \
    "$([ "$(printf '%s\n' "$SHELL_CMDS" | wc -l | tr -d ' ')" = 2 ] || echo "commands: $SHELL_CMDS")$(cmp -s "$TBD/send-0.md" "$TBD/s-escaped.md" || echo ' markdown-escaped differs')$(cmp -s "$TBD/send-0.html" "$TBD/py-pre.html" || echo ' pre differs')$([ "$(grep -c '<surface' "$TBD/send-0.html" || true)" = 0 ] || echo ' unescaped < in pre')$(has_tb "$(cat "$TBD/send-0.html")" 'timeouts (a &amp; b, x &amp;lt; y).')$(has_tb "$(cat "$TBD/send-0.md")" 'timeouts (a & b, x &lt; y).')"
  set +e
  HOST_OUT="$(python3 -I "$TB_PY" convert --to html --in "$TBD/hostile.md" --out "$TBD/hostile.html" 2>&1)"
  python3 -I "$TB_PY" >/dev/null 2>&1; RC_NONE=$?
  python3 -I "$TB_PY" convert --to xml --in "$TBD/ticket.md" --out "$TBD/x.out" >/dev/null 2>&1; RC_TO=$?
  python3 -I "$TB_PY" convert --to html --in "$TBD/ticket.md" --out "$TBD/ticket.md" >/dev/null 2>&1; RC_SAME=$?
  python3 -I "$TB_PY" check --sent "$TBD/missing.md" --stored "$TBD/ticket.html" >/dev/null 2>&1; RC_MISS=$?
  python3 -I "$TB_PY" convert --to html --in "$TBD/bad.md" --out "$TBD/bad.html" >/dev/null 2>&1; RC_BAD=$?
  python3 -I "$TB_PY" convert --to html --in "$TBD/ticket.md" --out "$TBD/no-such-dir/x.html" >/dev/null 2>&1; RC_OUT=$?
  INC_RC=0; tb_check "$TBD/ticket.md" "$TBD/s-section.md" >/dev/null || INC_RC=$?
  # -X utf8=0 keeps Python from switching to UTF-8 by itself under the C
  # locale, so stdout really is ASCII and only the script's own stream
  # reconfiguration lets the Japanese excerpt through.
  LC_OUT="$(LC_ALL=C python3 -I -X utf8=0 "$TB_PY" check --sent "$TBD/ticket.md" --stored "$TBD/s-swallow.md" 2>&1)"; RC_LC=$?
  set -e
  check "ticket_body.py: hostile Markdown (tags, nested lists, escaped and code-span pipes, fences holding tables, unclosed comment and fence, a long line, an info string that would close its attribute, list numbers that start at 3 or jump, a lazy continuation line) converts to escaped HTML with converter tags only and checks complete" \
    "$(grep -qxE 'Converted: html \([0-9]+ characters\)' <<<"$HOST_OUT" || echo "line='$HOST_OUT'")$(python3 -I "$TBD/tags.py" "$TBD/hostile.html")$(tb_check "$TBD/hostile.md" "$TBD/hostile.html" | grep -qxF 'Body check: complete' || echo ' check not complete')$(has_tb "$(cat "$TBD/hostile.html")" '&lt;script&gt;alert(1)&lt;/script&gt;' 'Write &lt;script&gt;alert(1)&lt;/script&gt; and &lt;img src=x&gt; as text.' '<th>x | y</th>' '<code>p | q</code>' '<td>extra</td>' '### not a heading' '&lt;!-- kept as code --&gt;' 'text &lt;!-- unclosed comment stays visible' 'unclosed fence &lt;x&gt;' '<li>c<br>' '&lt;p&gt;caf&amp;eacute; &amp;#65;&lt;/p&gt;' '<code>caf&amp;eacute;</code> and outside ABC' '<pre><code class="language-&quot;&gt;&lt;img src=x onerror=y&gt;">info string' '<ol start="3">' '<li value="5">five</li>' '<li>lazy item<br>' 'continues here</li>')"
  python3 -I "$TB_PY" convert --to html --in "$TBD/stray.md" --out "$TBD/stray.html" >/dev/null
  STRAY_HTML="$(cat "$TBD/stray.html")"
  STRAY_SELF="$(tb_check "$TBD/stray.md" "$TBD/stray.html")"
  STRAY_LOST="$(tb_check "$TBD/stray.md" "$TBD/stray-swallowed.md")"
  check "ticket_body.py: a comment opener that is not closed within its paragraph is text, so the sections after it are converted and a store that hid them up to a later --> is incomplete" \
    "$(has_tb "$STRAY_HTML" 'The importer &lt;!-- note about the importer<br>' '<h3>Scope</h3>' '<td>src/import.py</td>' '<li>Accepts an empty batch and exits with status zero.</li>' 'importer --&gt; limit check')$([ "$STRAY_SELF" = 'Body check: complete' ] || echo " self-check: $STRAY_SELF")$(grep -qE '^Body check: incomplete \(.*headings missing: "Scope", "Acceptance Criteria", "Implementation Notes"' <<<"$STRAY_LOST" || echo " hidden middle: $STRAY_LOST")"
  # A text stored exactly as sent is complete, whatever comment markers it
  # holds; so are entity references and decomposed characters, and a JSON
  # response that reaches the file inside a string or after a line of text.
  MISSING=""
  for f in ticket.md hostile.md stray.md list.md link.md kv.md thr.md cjk.md jp.md rk.md rf.md h2.md; do
    got="$(tb_check "$TBD/$f" "$TBD/$f")"
    [ "$got" = 'Body check: complete' ] || MISSING="$MISSING $f:'$got'"
  done
  cmp -s "$TBD/ticket.md" "$TBD/s-nfd.md" && MISSING="$MISSING s-nfd.md:not-decomposed"
  for f in s-ncr.md s-nfd.md s-mcp.json s-cli.txt s-partial.txt s-utf16.md; do
    got="$(tb_check "$TBD/ticket.md" "$TBD/$f")"
    [ "$got" = 'Body check: complete' ] || MISSING="$MISSING $f:'$got'"
  done
  got="$(tb_check "$TBD/peer.md" "$TBD/s-peer.json")"
  [ "$got" = 'Body check: complete' ] || MISSING="$MISSING s-peer.json:'$got'"
  got="$(tb_check "$TBD/peer3.md" "$TBD/s-peer3.json")"
  [ "$got" = 'Body check: complete' ] || MISSING="$MISSING s-peer3.json:'$got'"
  check "ticket_body.py check: a store identical to the sent text is complete (comments in code, stray openers, a comment inside an angle-bracket text), as are numeric character references, decomposed characters, JSON inside a tool-result string, JSON printed after a line, near-identical criteria stored as separate values, a structured document next to its rendered field, a body followed by a 90 percent copy of itself, and a UTF-16 file with its byte order mark" "$MISSING"
  MISSING=""
  for f in s-once.json s-dup-block.json s-dup-rendered.json s-dup-nested.json s-dup-text.txt s-dup-preview.json; do
    got="$(tb_check "$TBD/ticket.md" "$TBD/$f")"
    grep -qE '^Body check: incomplete \(missing [0-9]+ of 185 words in 1 spans; headings missing: none; longest span under "Acceptance Criteria": "An empty batch is accepted' <<<"$got" || MISSING="$MISSING $f:'$got'"
  done
  CTL="$(tb_check "$TBD/ctl.md" "$TBD/ctl-lost.md")"
  grep -qF -- "longest span under \"Notes\": \"alpha bravo 'charlie' delta" <<<"$CTL" || MISSING="$MISSING ctl-lost.md:'$CTL'"
  printf '%s' "$CTL" | LC_ALL=C grep -q '[[:cntrl:]]' && MISSING="$MISSING ctl-lost.md:control-character-in-line"
  python3 -I "$TB_PY" convert --to html --in "$TBD/ctl.md" --out "$TBD/ctl.html" >/dev/null
  tr -d '\n' <"$TBD/ctl.html" | LC_ALL=C grep -q '[[:cntrl:]]' && MISSING="$MISSING ctl.html:control-character-in-html"
  for f in s-peer3-lost.json s-peer3-page.txt; do
    got="$(tb_check "$TBD/peer3.md" "$TBD/$f")"
    grep -qE '^Body check: incomplete \(missing 24 of 96 words in 1 spans; headings missing: none; longest span under "Acceptance Criteria": "The importer rejects a batch of 50[0-9] rows' <<<"$got" || MISSING="$MISSING $f:'$got'"
  done
  check "ticket_body.py check: a criterion lost from a body the response returns twice (a JSON text block and a structured field, raw and rendered, both inside a tool-result string, twice in one text, a structured document next to the rendered field, a page text showing the field twice) is incomplete, as with one copy, also when its words occur in other criteria or a second value is a shorter preview; an excerpt shows a control character as a space and a double quote as a single one, and the HTML holds no control character" "$MISSING"
  # The three thresholds, each on both sides of its limit (400 words).
  MISSING=""
  while IFS='|' read -r f want; do
    got="$(tb_check "$TBD/thr.md" "$TBD/$f")"
    grep -qE -- "$want" <<<"$got" || MISSING="$MISSING $f:'$got'"
  done <<'THRESHOLDS'
thr-run11.md|^Body check: minor differences \(missing 11 of 400 words in 1 spans; first under "Scope"
thr-run12.md|^Body check: incomplete \(missing 12 of 400 words in 1 spans; headings missing: none; longest span under "Scope"
thr-scatter12.md|^Body check: minor differences \(missing 12 of 400 words in 12 spans;
thr-scatter13.md|^Body check: incomplete \(missing 13 of 400 words in 13 spans; headings missing: none;
thr-found79.txt|^Body check: no content field \(79 of 400 words found\)$
thr-start79.txt|^Body check: no content field \(79 of 400 words found; start of the ticket only\)$
thr-found80.txt|^Body check: incomplete \(missing 320 of 400 words
THRESHOLDS
  got="$(tb_check "$TBD/ticket.md" "$TBD/s-cut255.json")"
  [ "$got" = 'Body check: no content field (34 of 185 words found; start of the ticket only)' ] || MISSING="$MISSING s-cut255.json:'$got'"
  check "ticket_body.py check thresholds: 11 lost words in a row minor, 12 incomplete; 12 of 400 scattered (3%) minor, 13 incomplete; 79 of 400 found (under 20%) no content field, 80 incomplete; under 20% found, the first words in a row (a field that keeps the first 255 characters) mark the start of the ticket" "$MISSING"
  # Comment markers inside list items and table rows.
  LIST_OUT="$(python3 -I "$TB_PY" convert --to html --in "$TBD/list.md" --out "$TBD/list-out.html" 2>&1)"
  LIST_HTML="$(cat "$TBD/list-out.html")"
  LIST_LOST="$(tb_check "$TBD/list.md" "$TBD/list-lost.md")"
  check "ticket_body.py: a comment opener inside a list item or table row is text, so the items and rows after it are converted; <!--> hides nothing; a block comment holding list and table lines is dropped; a store without the items is incomplete" \
    "$(grep -qxE 'Converted: html \([0-9]+ characters\)' <<<"$LIST_OUT" || echo "line='$LIST_OUT'")$(has_tb "$LIST_HTML" '<li>The scanner reports an opening &lt;!-- marker that is never closed.</li>' '<li>The importer rejects a batch above the configured limit with a bounded error and exit status 2.</li>' '<li>An empty batch is accepted and the exit status is 0.</li>' '<tr><td>src/import.py</td>' '<td>add the limit check and the bounded error</td></tr>' '<td>allow draft --&gt; review only</td>' '<p>Use  as the shortest comment, then alpha bravo charlie.<br>' 'Second line foxtrot golf --&gt; hotel india.</p>' '<p>After the block comment.</p>')$(printf '%s\n' "$LIST_HTML" | grep -n 'hidden' || true)$(grep -qE '^Body check: incomplete \(missing 35 of 94 words in 2 spans' <<<"$LIST_LOST" || echo " lossy: $LIST_LOST")"
  # A link target a page text never shows is at most a minor difference;
  # line-break tags are markup, not text.
  python3 -I "$TB_PY" convert --to html --in "$TBD/lt.md" --out "$TBD/lt.html" >/dev/null
  LT_PAGE="$(tb_check "$TBD/lt.md" "$TBD/lt-page.txt")"
  check "ticket_body.py check: a page text without a long link target is a minor difference, never incomplete; line-break tags in table cells are not counted; the converted HTML is complete; the target of link syntax inside a code span is text" \
    "$(grep -qE '^Body check: minor differences \(missing 17 of 48 words in 1 spans; first under "Background": "https://git\.example\.invalid/org/repo/blob/main/docs/design/importer-limits\.md' <<<"$LT_PAGE" || echo "page text: $LT_PAGE")$(tb_check "$TBD/lt.md" "$TBD/lt.html" | grep -qxF 'Body check: complete' || echo ' converted')$(tb_check "$TBD/lc.md" "$TBD/lc-lost.md" | grep -qE '^Body check: incomplete \(missing 1[0-9] of [0-9]+ words in 1 spans' || echo " link in a code span: $(tb_check "$TBD/lc.md" "$TBD/lc-lost.md")")"
  # A heading holding a link, and angle-bracket texts of one-letter words.
  python3 -I "$TB_PY" convert --to html --in "$TBD/kv.md" --out "$TBD/kv-out.html" >/dev/null
  python3 -I "$TB_PY" convert --to markdown-escaped --in "$TBD/kv.md" --out "$TBD/kv-esc.md" >/dev/null
  KV_LOST="$(tb_check "$TBD/kv.md" "$TBD/kv-lost.md")"
  check "ticket_body.py check: a heading holding a link, and autolinks, are found in a renderer's HTML; angle-bracket texts are counted (dropped: minor differences; converted or escaped: complete)" \
    "$(tb_check "$TBD/link.md" "$TBD/link.html" | grep -qxF 'Body check: complete' || echo ' link heading')$(grep -qxF 'Body check: minor differences (missing 0 of 24 words in 0 spans and 4 angle-bracket texts; first under "Type Notes": "<K, V>")' <<<"$KV_LOST" || echo " dropped: $KV_LOST")$(tb_check "$TBD/kv.md" "$TBD/kv-out.html" | grep -qxF 'Body check: complete' || echo ' converted')$(tb_check "$TBD/kv.md" "$TBD/kv-esc.md" | grep -qxF 'Body check: complete' || echo ' escaped')"
  # Letters of a script written without word spaces: a word each, half a
  # word in the thresholds (weight 506 here, 3 percent of it 15.18).
  MISSING=""
  while IFS='|' read -r f want; do
    got="$(tb_check "$TBD/cjk.md" "$TBD/$f")"
    grep -qE -- "$want" <<<"$got" || MISSING="$MISSING $f:'$got'"
  done <<'UNSPACED'
cjk-run23.md|^Body check: minor differences \(missing 23 of 1006 words in 1 spans; first under "Scope"
cjk-run24.md|^Body check: incomplete \(missing 24 of 1006 words in 1 spans; headings missing: none; longest span under "Scope"
cjk-scatter30.md|^Body check: minor differences \(missing 30 of 1006 words in 30 spans;
cjk-scatter31.md|^Body check: incomplete \(missing 31 of 1006 words in 31 spans; headings missing: none;
UNSPACED
  got="$(tb_check "$TBD/jp.md" "$TBD/jp-page.txt")"
  [ "$got" = 'Body check: complete' ] || MISSING="$MISSING jp-page.txt:'$got'"
  for f in cjk jp rk rf h2; do
    python3 -I "$TB_PY" convert --to html --in "$TBD/$f.md" --out "$TBD/$f.html" >/dev/null
    got="$(tb_check "$TBD/$f.md" "$TBD/$f.html")"
    [ "$got" = 'Body check: complete' ] || MISSING="$MISSING $f.html:'$got'"
  done
  check "ticket_body.py check: each letter of a script written without word spaces is a word that weighs half a word (24 in a row incomplete, 23 minor; 31 scattered incomplete, 30 minor), a page text joining such text with code spans and bold text is complete, and the converted HTML of the new fixtures is complete" "$MISSING"
  RK_LOST="$(tb_check "$TBD/rk.md" "$TBD/rk-lost.md")"
  RK_PAGE="$(tb_check "$TBD/rk.md" "$TBD/rk-page.txt")"
  H2_LOST="$(tb_check "$TBD/h2.md" "$TBD/h2-lost.md")"
  check "ticket_body.py check: a short section removed is incomplete with its heading listed although its title occurs in prose, the title word lost from a placeholder and a link target only leaves the heading found, and a lost ## heading line after the title line is listed" \
    "$(grep -qxF 'Body check: incomplete (missing 3 of 144 words in 1 spans; headings missing: "Risks"; longest span under "Risks": "Risks - A slow disk")' <<<"$RK_LOST" || echo "section: $RK_LOST")$(grep -qE '^Body check: minor differences \(missing 6 of 144 words in 2 spans and 1 angle-bracket texts; first under "Background"' <<<"$RK_PAGE" || echo " placeholder: $RK_PAGE")$(grep -qE '^Body check: incomplete \(.*; headings missing: "Follow-up Work";' <<<"$H2_LOST" || echo " level two: $H2_LOST")"
  RF_PAGE="$(tb_check "$TBD/rf.md" "$TBD/rf-page.txt")"
  RF_LINE="$(tb_check "$TBD/rf.md" "$TBD/rf-nodef.txt")"
  check "ticket_body.py check: a page text without a reference link's label and definition is a minor difference, while a lost line of the same shape that is no definition is incomplete" \
    "$(grep -qxF 'Body check: minor differences (missing 23 of 123 words in 2 spans; first under "Background": "imp lim spec ref")' <<<"$RF_PAGE" || echo "page text: $RF_PAGE")$(grep -qE '^Body check: incomplete \(missing 16 of 123 words in 1 spans; headings missing: none;' <<<"$RF_LINE" || echo " no definition: $RF_LINE")"
  # The alignment view: of the views that hold nearly as many sent words as
  # the best one, the shortest (the HTML without its tag names).
  LEAD="$(tb_check "$TBD/lead.md" "$TBD/lead-lost.html")"
  check "ticket_body.py check: a first sentence lost from a store of HTML whose views hold as many sent words with and without the tag names is one span of the view without them (incomplete)" \
    "$(grep -qE '^Body check: incomplete \(missing 24 of 688 words in 1 spans; headings missing: none; longest span under "Background": ' <<<"$LEAD" || echo "got: $LEAD")"
  # No run of the body in a row: no content field, whatever share is found.
  MISSING=""
  while IFS='|' read -r f want; do
    got="$(tb_check "$TBD/jn.md" "$TBD/$f")"
    grep -qE -- "$want" <<<"$got" || MISSING="$MISSING $f:'$got'"
  done <<'NORUN'
jn-other.txt|^Body check: no content field \([0-9]+ of 603 words found\)$
jn-every.txt|^Body check: no content field \(603 of 603 words found\)$
jn-start.txt|^Body check: no content field \(416 of 603 words found; start of the ticket only\)$
jn-lost.md|^Body check: incomplete \(missing 30 of 603 words in 1 spans; headings missing: none; longest span under "Background"
NORUN
  check "ticket_body.py check: a stored text that holds the letters of an unspaced-script ticket only out of order (no run of 12 words' weight in a row) is no content field, with a fifth of the words found or all of them (start of the ticket only when it also holds the first 12 words in a row), while the body with 30 letters lost is incomplete" "$MISSING"
  # A page text that joins the text nodes of the converted HTML without a
  # separator: the line feed between table cells keeps them apart.
  cat >"$TBD/pagetext.py" <<'PYPAGE'
import sys
from html.parser import HTMLParser
BLOCK = {"p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "ul", "ol", "table", "thead", "tbody", "tr", "pre"}
class P(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out = []
    def handle_starttag(self, tag, attrs):
        if tag == "br" or tag in BLOCK:
            self.out.append("\n")
    def handle_endtag(self, tag):
        if tag in BLOCK:
            self.out.append("\n")
    def handle_data(self, data):
        self.out.append(data)
p = P()
p.feed(open(sys.argv[1], encoding="utf-8").read())
p.close()
open(sys.argv[2], "w", encoding="utf-8").write("".join(p.out))
PYPAGE
  python3 -I "$TBD/pagetext.py" "$TBD/ticket.html" "$TBD/s-joined.txt"
  JOINED="$(tb_check "$TBD/ticket.md" "$TBD/s-joined.txt")"
  check "ticket_body.py convert --to html: a line feed between table cells keeps them apart in a page text that joins text nodes without a separator (complete)" \
    "$([ "$JOINED" = 'Body check: complete' ] || echo "got: $JOINED")$(grep -q '^<td>' "$TBD/ticket.html" || echo ' no cell starts a line')$(grep -q '^<th>' "$TBD/ticket.html" || echo ' no header cell starts a line')"
  # Many comment openers closed by one marker at the end: linear time.
  OPENERS="$(python3 -I -c 'import subprocess, sys, time
start = time.time()
try:
    out = subprocess.run([sys.executable, "-I", sys.argv[1], "check", "--sent", sys.argv[2], "--stored", sys.argv[3]], stdout=subprocess.PIPE, timeout=20).stdout.decode("utf-8", "replace").strip()
except subprocess.TimeoutExpired:
    out = "timed out"
print("%s|%.1f s" % (out, time.time() - start))' "$TB_PY" "$TBD/ticket.md" "$TBD/openers.txt")"
  check "ticket_body.py check: a store followed by 100000 comment openers that one closing marker at its end closes is checked within 20 seconds (complete)" \
    "$(grep -qE '^Body check: complete\|' <<<"$OPENERS" || echo "got: $OPENERS")"
  # Every conversion under a non-UTF-8 locale writes the same UTF-8 file.
  LC_CONV=""
  for to in html markdown-escaped pre; do
    LC_ALL=C python3 -I -X utf8=0 "$TB_PY" convert --to "$to" --in "$TBD/ticket.md" --out "$TBD/lc-$to.out" >/dev/null 2>&1 || LC_CONV="$LC_CONV $to:rc=$?"
    python3 -I "$TB_PY" convert --to "$to" --in "$TBD/ticket.md" --out "$TBD/utf-$to.out" >/dev/null 2>&1 || LC_CONV="$LC_CONV $to:utf-rc=$?"
    cmp -s "$TBD/lc-$to.out" "$TBD/utf-$to.out" || LC_CONV="$LC_CONV $to:differs"
  done
  check "ticket_body.py convert under LC_ALL=C (no UTF-8 mode) writes the same files as under a UTF-8 locale (html, markdown-escaped, pre)" "$LC_CONV"
  # The converter's own fallback: a structured result that fails the
  # self-check is replaced by the preformatted form.
  FB_OUT="$(python3 -I -c 'import importlib.util, sys
spec = importlib.util.spec_from_file_location("tb", sys.argv[1])
tb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tb)
tb.to_html = lambda text: "<p>" + text[: len(text) // 2] + "</p>\n"
sys.exit(tb.main(["convert", "--to", "html", "--in", sys.argv[2], "--out", sys.argv[3]]))' "$TB_PY" "$TBD/ticket.md" "$TBD/fallback.html" 2>&1)"
  check "ticket_body.py convert --to html: a result that fails its self-check is replaced by the preformatted form and says so" \
    "$(grep -qxE 'Converted: preformatted fallback \(.+\)' <<<"$FB_OUT" || echo "line='$FB_OUT'")$(cmp -s "$TBD/fallback.html" "$TBD/py-pre.html" || echo ' output is not the pre form')"
  check "ticket_body.py exit status: 0 for an incomplete check, 2 on a usage error (no subcommand, unknown --to, --in equal to --out), 3 on an unreadable input or output; a non-UTF-8 locale still prints the Japanese excerpt line" \
    "$([ "$INC_RC" -eq 0 ] || echo "incomplete rc=$INC_RC")$([ "$RC_NONE" -eq 2 ] || echo " none rc=$RC_NONE")$([ "$RC_TO" -eq 2 ] || echo " --to rc=$RC_TO")$([ "$RC_SAME" -eq 2 ] || echo " same rc=$RC_SAME")$([ "$RC_MISS" -eq 3 ] || echo " missing rc=$RC_MISS")$([ "$RC_BAD" -eq 3 ] || echo " non-UTF-8 rc=$RC_BAD")$([ "$RC_OUT" -eq 3 ] || echo " unwritable rc=$RC_OUT")$([ "$RC_LC" -eq 0 ] && [ "$LC_OUT" = "$SWALLOW" ] || echo " LC_ALL=C rc=$RC_LC: $LC_OUT")$(printf '%s' "$LC_OUT" | LC_ALL=C grep -q '[^ -~]' || echo ' LC_ALL=C: no non-ASCII excerpt')"
else
  fail "ticket_body.py checks" "python3 is not on the PATH"
fi

# Path grammar and other OS assumptions: drive and network share paths, the
# home-path comparison, byte order marks and CR LF line ends, the interpreter
# choice written once as {python}, the shell fallback of a host without a
# search tool and the login-shell options, each stated once and named where
# it applies.
MISSING=""
HOST_NOTES_NOW="$(awk '/^## Host notes$/ {h = 1; next} h && /^## / {h = 0} h' "$SKILL_MD")"
# shellcheck disable=SC2016  # literal backticks, braces and dollars
while IFS='|' read -r where needle; do
  case "$where" in
    ARGS) grep -qF -- "$needle" <<<"$ARGS_SECTION" || MISSING="$MISSING SKILL.md-Argument-Parsing:'$needle'" ;;
    HOST) grep -qF -- "$needle" <<<"$HOST_NOTES_NOW" || MISSING="$MISSING SKILL.md-Host-notes:'$needle'" ;;
    *) grep -qF -- "$needle" "$SKILL_DIR/$where" || MISSING="$MISSING $where:'$needle'" ;;
  esac
done <<'NEEDLES'
ARGS|**Drive and share paths**: a path value, or a `source=` spec, that starts with one letter, `:` and `/` or `\` (a drive path, such as `C:\work\spec.md`), or with `\\` or `//` (a network share path), is a path, never a `<kind>:` prefix
ARGS|it counts as an absolute path wherever these rules tell an absolute path from a relative one, whatever the host
ARGS|its frontmatter is still the block between its first two `---` lines, read with the byte order mark and every line's trailing CR disregarded
ARGS|grep -qE '^\*\*/\.local/\*[[:space:]]*$' "<root>/.gitignore"
references/sources.md|A drive or network share path (SKILL.md Argument Parsing, **Drive and share paths**
references/sources.md|the shell tool runs `python3 --version`, then `python --version`, then `py -3 --version`, one command each, stopping at the first whose output starts with `Python 3.`
references/sources.md|is `{python}` for the rest of the run, written unquoted at the start of every Python command (`py -3` is two words)
references/sources.md|`ERROR: reading an .xlsx source needs Python 3 on the PATH (tried python3, python, py -3)`
references/sources.md|--out "{scratch}/sources/S<n>.md" [--sheet="<name>" ...] -- "<path>"
references/sources.md|`Converted: <chars> characters, <lines> lines, truncated: yes|no`; the orchestrator never types that text out to build this file
references/sources.md|The header block of **Normalized file** is then inserted at the top of that file with the file-edit tool
references/sources.md|with the file-edit tool (the file's last lines, as many as make the match unique, replaced by themselves followed by that line), never by writing the file again
references/sources.md|`Rendered: no (cannot write under --out: <error>)`
references/sources.md|`<command> >|"{scratch}/sources/S<n>.body" 2>|"{scratch}/sources/S<n>.err"`
SKILL.md|its text written by the converter itself to `{scratch}/sources/S<n>.md` (`--out`), never typed out by the orchestrator
HOST|case-insensitively on a host whose file system ignores case, and for every spelling the host uses for the home directory (illustrative only: a drive-letter form)
HOST|the search tools → the shell tool does each search the steps name, read-only and one file per command: it lists the matching lines of one file with `grep -nE '<pattern>' "<file>"`
HOST|- **Login-shell options**:
HOST|`cp` and `mv` run as `command cp` and `command mv`, the scratch removal is `rm -rf`
references/destinations.md|with a leading byte order mark and surrounding whitespace (a trailing CR LF included) removed
references/destinations.md|a printed path is a match, and anything else is none: no output, or an exit status other than 0 and only an error that the pattern matched nothing
references/destinations.md|`command mv "<entry>" "{dir}/.rollback/{parent-slug}-{ts}/"`
references/destinations.md|then `printf '\n%s\n' "{rel}/.rollback/" >> "<root>/.gitignore"` for a file that exists, or `printf '%s\n' "{rel}/.rollback/" > "<root>/.gitignore"` for one that does not
references/destinations.md|"<template>" >|"{scratch}/request-{i}.json"
references/destinations.md|`<command> >|"{scratch}/response-{i}.txt" 2>|"{scratch}/response-{i}.err"`
references/destinations.md|`<command> >|"{scratch}/stored-{i}.txt" 2>|"{scratch}/stored-{i}.err"`
NEEDLES
[ "$(grep -cF -- '**Drive and share paths**:' "$SKILL_MD" || true)" -eq 1 ] || MISSING="$MISSING SKILL.md:'Drive and share paths' defined more than once"
[ "$(grep -cF -- '**Python interpreter.**' "$SOURCES_MD" || true)" -eq 1 ] || MISSING="$MISSING sources.md:'Python interpreter' defined more than once"
[ "$(grep -cF -- '**Login-shell options**' "$SKILL_MD" || true)" -eq 1 ] || MISSING="$MISSING SKILL.md:'Login-shell options' stated more than once"
# shellcheck disable=SC2016  # literal braces
[ "$(cat "$SKILL_MD" "$SKILL_DIR"/references/*.md | grep -oF -- '{python} -I "{skill_root}/scripts/' | wc -l | tr -d ' ')" -ge 4 ] || MISSING="$MISSING fewer than 4 {python} -I commands"
check "drive and share paths, the home-path comparison, BOM and CR LF tolerance, the interpreter choice as {python}, the converter's --out, the no-search-tool fallback and the login-shell forms are stated once and named where they apply" "$MISSING"
# shellcheck disable=SC2016  # literal backticks
check "no stale interpreter or shell form remains (python3 -I, python3 not found, exit status 127, grep -qxF on .gitignore, plain cp/mv, > onto a rebuilt file, a re-written workbook file)" \
  "$(grep -rnE -- 'python3 -I|python3 not found|exit status 127|grep -qxF|`(cp|mv) "|" > "\{scratch\}|[^|]>"\{scratch\}|write the file again and compute' "$SKILL_MD" "$SKILL_DIR/README.md" "$SKILL_DIR"/references/*.md | cut -c1-160 || true)"

# --- POSIX forms under login-shell options (no-clobber, nomatch, aliases) ------
# A host's shell tool may be a login shell with a no-clobber option, an
# unmatched pattern raised as an error, and rm / cp / mv aliased to forms that
# ask first. The forms the generated tree prints are taken from it as printed
# (placeholders filled with fixture values), run with stdin closed under zsh
# (setopt noclobber; nomatch is its default), sh and bash (set -C), each with
# interactive rm, cp and mv aliases defined on earlier lines, every form run
# twice so the second run meets the files of the first; canaries prove that
# the options and aliases were in force.
if command -v python3 >/dev/null 2>&1; then
  FORMS_DIR="$TMP_ROOT/forms"
  mkdir -p "$FORMS_DIR"
  cat >"$FORMS_DIR/forms.py" <<'PYFORMS'
import json, os, re, sys

# gen SKILL_DIR KIND WORK: write WORK/run.sh, the POSIX forms of the skill as
# printed (placeholders filled with fixture values), run twice where a second
# run meets the files of the first, under the shell options and aliases of KIND.
# verify WORK KIND: print one line per problem.

def spans(path):
    text = open(path, encoding="utf-8").read()
    out = []
    for line in text.split("\n"):
        parts = line.split("`")
        out.extend(parts[k] for k in range(1, len(parts), 2))
    return text, out

def one(found, name, start, exact=False):
    hits = sorted(set(s for s in found if (s == start if exact else s.startswith(start))))
    if len(hits) != 1:
        sys.exit("form %s: %d spans start with %r" % (name, len(hits), start))
    return hits[0]

def gen(skill, kind, work):
    skill_md, sk = spans(os.path.join(skill, "SKILL.md"))
    dest_md, de = spans(os.path.join(skill, "references", "destinations.md"))
    src_md, so = spans(os.path.join(skill, "references", "sources.md"))
    f = {}
    f["mkdir_scratch"] = one(sk, "mkdir_scratch", "mkdir -p .local/create-ticket-scratch", True)
    f["mktemp"] = one(sk, "mktemp", "mktemp -d .local/create-ticket-scratch/run.XXXXXX", True)
    f["gi_check"] = one(sk, "gi_check", "grep -qE '^\\*\\*/\\.local/")
    f["gi_exist"] = one(sk, "gi_exist", '[ -e "<root>/.gitignore" ]', True)
    f["gi_append"] = one(sk, "gi_append", "printf '\\n%s\\n' '**/.local/*' >>")
    f["gi_create"] = one(sk, "gi_create", "printf '%s\\n' '**/.local/*' > ")
    f["cp_final"] = one(sk, "cp_final", 'command cp "<draft file>"')
    f["cp_body"] = one(de, "cp_body", 'command cp "{scratch}/final-{i}.md" "{scratch}/body-{i}.md"', True)
    f["cp_ticket"] = one(de, "cp_ticket", 'command cp "{scratch}/final-{i}.md" "{ticket_dir_i}/ticket.md"', True)
    f["sed_esc"] = one(de, "sed_esc", "sed -e 's/</")
    f["pre"] = one(de, "pre", "{ printf '<pre>';")
    f["cli_resp"] = one(de, "cli_resp", '<command> >|"{scratch}/response-{i}.txt"')
    f["cli_stored"] = one(de, "cli_stored", '<command> >|"{scratch}/stored-{i}.txt"')
    f["cli_src"] = one(so, "cli_src", '<command> >|"{scratch}/sources/S<n>.body"')
    f["ls_coll"] = one(de, "ls_coll", 'ls -d "{dir}"/*/{NNN}-*')
    f["mkdir_parent"] = one(de, "mkdir_parent", 'mkdir -p "{dir}/{parent-slug}"', True)
    f["mkdir_td"] = one(de, "mkdir_td", 'mkdir -p "{ticket_dir_i}"', True)
    f["mkdir_rb"] = one(de, "mkdir_rb", 'mkdir -p "{dir}/.rollback/{parent-slug}-{ts}"', True)
    f["mv_rb"] = one(de, "mv_rb", 'command mv "<entry>"')
    f["rb_append"] = one(de, "rb_append", "printf '\\n%s\\n' \"{rel}/.rollback/\" >>")
    f["rb_create"] = one(de, "rb_create", "printf '%s\\n' \"{rel}/.rollback/\" > ")
    f["nul"] = one(so, "nul", 'dd if="<path>"')
    f["rm"] = one(sk, "rm", 'rm -rf "{scratch}"', True)
    f["exist_scr"] = one(sk, "exist_scr", '[ -d "{scratch}" ]', True)
    f["rmdir1"] = one(sk, "rmdir1", "rmdir .local/create-ticket-scratch", True)
    f["rmdir2"] = one(sk, "rmdir2", "rmdir .local", True)
    m = re.search(r"```bash\n( *)(jq --rawfile title .*?)\n *```", dest_md, re.S)
    if not m:
        sys.exit("form jq_build: no fenced jq block")
    f["jq_build"] = "\n".join(l[len(m.group(1)):] if l.startswith(m.group(1)) else l for l in m.group(2).split("\n"))
    fill = [("{scratch}", "$SCR"), ("{ticket_dir_i}", "tickets/p/001-x"), ("{i}", "0"),
            ("<draft file>", "draft.md"), ("{dir}", "tickets"), ("{parent-slug}", "p"),
            ("<entry>", "tickets/p/split-plan.md"), ("{rel}", "tickets"), ("S<n>", "S1"),
            ("<command>", "printf 'ID-1\\n'"), ("<sent body>", "$SCR/body-0.md"), ("<id>", "P-1"),
            ("<template>", "template.json")]
    for k in f:
        for a, b in fill:
            f[k] = f[k].replace(a, b)
    alias = ["alias rm='rm -i'", "alias cp='cp -i'", "alias mv='mv -i'"]
    if kind == "zsh":
        prelude = ["setopt noclobber"] + alias
    elif kind == "bash":
        prelude = ["set -C", "shopt -s expand_aliases"] + alias
    else:
        prelude = ["set -C"] + alias
    L = prelude + ['cd "$1" || exit 99']
    def rc(name, form):
        L.append(form)
        L.append('echo "rc %s $?" >>log.txt' % name)
    def out(name, form):
        L.append("OUT=$(%s)" % form)
        L.append('echo "rc %s $? out=[$OUT]" >>log.txt' % name)
    # canaries: the conditions are in force in this shell
    L.append("printf 'one\\n' >canary.txt")
    L.append("printf 'two\\n' >canary.txt")
    L.append('echo "rc canary_clobber $?" >>log.txt')
    L.append("cp draft.md canary.txt")
    L.append('echo "rc canary_alias $?" >>log.txt')
    if kind == "zsh":
        L.append("OUT=$(ls -d tickets/*/999-* 2>/dev/null)")
        L.append('echo "rc canary_nomatch $?" >>log.txt')
    # scratch, once
    rc("mkdir_scratch", f["mkdir_scratch"])
    L.append("SCR=$(%s)" % f["mktemp"])
    L.append('echo "rc mktemp $? out=[$SCR]" >>log.txt')
    L.append('mkdir -p "$SCR/sources"')
    for g in ("g1", "g2", "g3"):
        for run in (1, 2):
            chk = f["gi_check"].replace("<root>", g)
            ex = f["gi_exist"].replace("<root>", g)
            L.append(chk)
            L.append("if [ $? -ne 0 ]; then")
            L.append(ex)
            L.append("if [ $? -eq 0 ]; then")
            L.append(f["gi_append"].replace("<root>", g))
            L.append('echo "rc gi_append_%s_%d $?" >>log.txt' % (g, run))
            L.append("else")
            L.append(f["gi_create"].replace("<root>", g))
            L.append('echo "rc gi_create_%s_%d $?" >>log.txt' % (g, run))
            L.append("fi")
            L.append("fi")
    for g in ("r1", "r2"):
        L.append(f["gi_exist"].replace("<root>", g))
        L.append("if [ $? -eq 0 ]; then")
        L.append(f["rb_append"].replace("<root>", g))
        L.append('echo "rc rb_append_%s $?" >>log.txt' % g)
        L.append("else")
        L.append(f["rb_create"].replace("<root>", g))
        L.append('echo "rc rb_create_%s $?" >>log.txt' % g)
        L.append("fi")
    for run in (1, 2):
        if run == 2:
            L.append("printf 'second run line\\n' >>draft.md")
        rc("cp_final_%d" % run, f["cp_final"])
        rc("mkdir_parent_%d" % run, f["mkdir_parent"])
        rc("mkdir_td_%d" % run, f["mkdir_td"])
        rc("cp_ticket_%d" % run, f["cp_ticket"])
        rc("cp_body_%d" % run, f["cp_body"])
        rc("sed_esc_%d" % run, f["sed_esc"])
        rc("pre_%d" % run, f["pre"])
        L.append("printf 'Title of the ticket\\r\\n' >|\"$SCR/title-0.txt\"")
        L.append("if command -v jq >/dev/null 2>&1; then")
        L.append(f["jq_build"])
        L.append('echo "rc jq_build_%d $?" >>log.txt' % run)
        L.append("fi")
        rc("cli_resp_%d" % run, f["cli_resp"])
        rc("cli_stored_%d" % run, f["cli_stored"])
        rc("cli_src_%d" % run, f["cli_src"])
        out("ls001_%d" % run, f["ls_coll"].replace("{NNN}", "001"))
        out("ls002_%d" % run, f["ls_coll"].replace("{NNN}", "002"))
        out("nul_text_%d" % run, f["nul"].replace("<path>", "draft.md"))
        out("nul_bin_%d" % run, f["nul"].replace("<path>", "bin.dat"))
        L.append("printf 'plan %d\\n' >|tickets/p/split-plan.md" % run)
        rc("mkdir_rb_%d" % run, f["mkdir_rb"].replace("{ts}", "T%d" % run))
        rc("mv_rb_%d" % run, f["mv_rb"].replace("{ts}", "T%d" % run))
    for name in ("final-0.md", "body-0.md", "send-0.md", "send-0.html", "request-0.json", "response-0.txt", "response-0.err", "stored-0.txt", "stored-0.err", "sources/S1.body", "sources/S1.err"):
        L.append('if [ -f "$SCR/%s" ]; then cat "$SCR/%s" >|"snap-%s"; fi' % (name, name, name.replace("/", "-")))
    L.append("chmod 444 \"$SCR/final-0.md\"")
    for run in (1, 2):
        rc("rm_%d" % run, f["rm"])
        rc("exist_scr_%d" % run, f["exist_scr"])
        rc("rmdir1_%d" % run, f["rmdir1"])
        rc("rmdir2_%d" % run, f["rmdir2"])
    os.makedirs(work, exist_ok=True)
    def put(name, data):
        with open(os.path.join(work, name), "wb") as fh:
            fh.write(data)
    draft = ("## T: Ticket \u898b\u7a4d\u3082\u308a\n\n### Scope\n\n| a \\| b | count<limit -> x >= 3 & y |\n"
             "\n<surface name> and `<code>`\n\n```\n<tag> & </tag>\n```\n")
    put("draft.md", draft.encode("utf-8"))
    put("bin.dat", b"abc\x00def")
    put("canary.txt", b"")
    os.remove(os.path.join(work, "canary.txt"))
    put("log.txt", b"")
    put("template.json", b'[{"fields": {"summary": "{title}", "description": "{body}", "parent": {"key": "{parent}"}}}]\n')
    for g, data in (("g2", b"a\r\nb"), ("g3", b"x\r\n**/.local/*\r\n"), ("r1", b"y")):
        os.makedirs(os.path.join(work, g), exist_ok=True)
        put(os.path.join(g, ".gitignore"), data)
    for g in ("g1", "r2"):
        os.makedirs(os.path.join(work, g), exist_ok=True)
    os.makedirs(os.path.join(work, ".local", "tickets"), exist_ok=True)
    put(os.path.join(".local", "tickets", "keep.md"), b"keep\n")
    put("run.sh", ("\n".join(L) + "\n").encode("utf-8"))

def verify(work, kind):
    bad = []
    def rd(name):
        try:
            with open(os.path.join(work, name), "rb") as fh:
                return fh.read()
        except OSError:
            return None
    log = {}
    for line in (rd("log.txt") or b"").decode("utf-8", "replace").split("\n"):
        m = re.match(r"rc (\S+) (\d+)(?: out=\[(.*)\])?$", line)
        if m:
            log[m.group(1)] = (int(m.group(2)), m.group(3))
    def rcis(name, want=0):
        got = log.get(name)
        if got is None:
            bad.append("%s did not run" % name)
        elif (got[0] == 0) != (want == 0):
            bad.append("%s exit %d" % (name, got[0]))
        return got
    # the conditions were in force
    if log.get("canary_clobber", (0,))[0] == 0:
        bad.append("canary: > onto an existing file was not refused (no-clobber not in force)")
    if rd("canary.txt") != b"two\n" and rd("canary.txt") != b"one\n":
        bad.append("canary file holds %r" % rd("canary.txt"))
    if rd("canary.txt") == rd("draft.md"):
        bad.append("canary: plain cp overwrote a file (interactive alias not in force)")
    if kind == "zsh" and log.get("canary_nomatch", (0,))[0] == 0:
        bad.append("canary: an unmatched pattern was not an error (nomatch not in force)")
    rcis("mkdir_scratch")
    mk = rcis("mktemp")
    if mk and not re.match(r"^\.local/create-ticket-scratch/run\.[A-Za-z0-9]{6}$", mk[1] or ""):
        bad.append("mktemp printed %r" % (mk[1],))
    want_gi = {"g1": b"**/.local/*\n", "g2": b"a\r\nb\n**/.local/*\n", "g3": b"x\r\n**/.local/*\r\n"}
    for g, want in want_gi.items():
        got = rd(os.path.join(g, ".gitignore"))
        if got != want:
            bad.append("%s/.gitignore is %r, want %r" % (g, got, want))
    for k in ("gi_create_g1_1", "gi_append_g2_1"):
        rcis(k)
    for k in ("gi_create_g1_2", "gi_append_g1_2", "gi_append_g1_1", "gi_append_g2_2", "gi_create_g2_1", "gi_append_g3_1", "gi_append_g3_2", "gi_create_g3_1"):
        if k in log:
            bad.append("%s ran (the line was already there, or the file existed)" % k)
    for g, want in (("r1", b"y\ntickets/.rollback/\n"), ("r2", b"tickets/.rollback/\n")):
        got = rd(os.path.join(g, ".gitignore"))
        if got != want:
            bad.append("%s/.gitignore is %r, want %r" % (g, got, want))
    rcis("rb_append_r1")
    rcis("rb_create_r2")
    draft = rd("draft.md")
    for run in (1, 2):
        for k in ("cp_final", "mkdir_parent", "mkdir_td", "cp_ticket", "cp_body", "sed_esc", "pre", "cli_resp", "cli_stored", "cli_src", "mkdir_rb", "mv_rb"):
            rcis("%s_%d" % (k, run))
        if ("jq_build_%d" % run) in log:
            rcis("jq_build_%d" % run)
        l1 = log.get("ls001_%d" % run)
        if not l1 or (l1[1] or "").strip() != "tickets/p/001-x":
            bad.append("ls001_%d printed %r" % (run, l1))
        l2 = log.get("ls002_%d" % run)
        if not l2 or (l2[1] or "") != "":
            bad.append("ls002_%d printed %r (no match must print no path)" % (run, l2))
        for k, want in (("nul_text", "text"), ("nul_bin", "binary")):
            got = log.get("%s_%d" % (k, run))
            if not got or got[1] != want:
                bad.append("%s_%d printed %r" % (k, run, got))
        mv = rd("tickets/.rollback/p-T%d/split-plan.md" % run)
        if mv != b"plan %d\n" % run:
            bad.append("quarantine T%d holds %r" % (run, mv))
    body = draft.decode("utf-8")
    want = {
        "snap-final-0.md": draft,
        "snap-body-0.md": draft,
        "snap-send-0.md": body.replace("<", "&lt;").replace(">", "&gt;").encode("utf-8"),
        "snap-send-0.html": ("<pre>" + body.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;") + "</pre>\n").encode("utf-8"),
        "snap-response-0.txt": b"ID-1\n", "snap-response-0.err": b"",
        "snap-stored-0.txt": b"ID-1\n", "snap-stored-0.err": b"",
        "snap-sources-S1.body": b"ID-1\n", "snap-sources-S1.err": b"",
    }
    for name, data in want.items():
        got = rd(name)
        if got != data:
            bad.append("%s is %r, want %r" % (name[5:], (got or b"")[:80], data[:80]))
    if "jq_build_2" in log:
        try:
            req = json.loads(rd("snap-request-0.json").decode("utf-8"))
            fields = req[0]["fields"]
            if not (isinstance(req, list) and len(req) == 1 and fields["summary"] == "Title of the ticket"
                    and fields["description"] == body and fields["parent"]["key"] == "P-1"):
                bad.append("request-0.json holds %r" % (req,))
        except Exception as exc:
            bad.append("request-0.json: %s" % exc)
    if os.path.exists(os.path.join(work, "tickets", "p", "split-plan.md")):
        bad.append("split-plan.md was not moved")
    if rd("tickets/p/001-x/ticket.md") != draft:
        bad.append("ticket.md is not the second run's text (a copy did not overwrite)")
    if (rd("canary.txt") or b"")[:3] == b"two":
        bad.append("canary: > onto an existing file overwrote it")
    for run in (1, 2):
        rcis("rm_%d" % run)
        rcis("exist_scr_%d" % run, 1)
    rcis("rmdir1_1")
    if os.path.exists(os.path.join(work, ".local", "create-ticket-scratch")):
        bad.append(".local/create-ticket-scratch is still there")
    if rd(".local/tickets/keep.md") != b"keep\n":
        bad.append(".local/tickets/keep.md was touched")
    if log.get("rmdir2_1", (0,))[0] == 0:
        bad.append("rmdir .local removed a non-empty directory")
    return bad

if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        for line in verify(sys.argv[2], sys.argv[3]):
            print(line)
PYFORMS
  for kind in zsh sh bash; do
    if ! command -v "$kind" >/dev/null 2>&1; then
      printf '  SKIP %s\n' "POSIX forms under $kind: $kind is not installed"
      continue
    fi
    FW="$FORMS_DIR/$kind"
    GEN_ERR="$(python3 -I "$FORMS_DIR/forms.py" gen "$SKILL_DIR" "$kind" "$FW" 2>&1)" || { fail "POSIX forms under $kind" "$GEN_ERR"; continue; }
    set +e
    if [ "$kind" = zsh ]; then
      zsh -f "$FW/run.sh" "$FW" <&- >"$FORMS_DIR/$kind.out" 2>&1
    else
      "$kind" "$FW/run.sh" "$FW" <&- >"$FORMS_DIR/$kind.out" 2>&1
    fi
    set -e
    check "POSIX forms under $kind (no-clobber, $([ "$kind" = zsh ] && echo 'nomatch, ')interactive rm/cp/mv aliases, stdin closed, each form run twice): scratch, .gitignore check/create/append (CRLF, no final newline), copies, both conversions, request build, captured outputs, collision listing, quarantine, text probe, removal" \
      "$(python3 -I "$FORMS_DIR/forms.py" verify "$FW" "$kind" 2>&1)"
  done
else
  fail "POSIX forms under login-shell options" "python3 is not on the PATH"
fi

# --- PowerShell forms (references/shell-powershell.md) -------------------------
# Static checks of the PowerShell file: every fenced powershell block sits
# under an id heading, uses no syntax of PowerShell 7 only, no POSIX alias at
# the start of a statement, no cmdlet that writes a file in another encoding,
# no redirection and no exit; Remove-Item appears once, with -LiteralPath and
# -Recurse, in the scratch removal; every POSIX form the three files print is
# quoted verbatim in the file (coverage), and every command of the Host notes
# approval list appears in a quoted POSIX form. The forms themselves are run by
# tests/test-standalone-skill-powershell.ps1 (PowerShell 5.1 and 7).
if command -v python3 >/dev/null 2>&1; then
  cat >"$TMP_ROOT/ps-static.py" <<'PYPS'
import re, sys
skill = sys.argv[1]
def rd(rel):
    return open(skill + "/" + rel, encoding="utf-8").read()
md = rd("references/shell-powershell.md")
mode = sys.argv[2]
out = []
# entries: id heading -> body up to the next ## or ### heading
entries = []
for m in re.finditer(r"^### (PS-[A-Z]+-[0-9]+): .*$", md, re.M):
    entries.append((m.group(1), m.start(), m.end()))
bodies = {}
for k, (eid, st, en) in enumerate(entries):
    nxt = re.compile(r"^##+ ", re.M).search(md, en)
    bodies[eid] = md[en:nxt.start() if nxt else len(md)]
blocks = []
for m in re.finditer(r"^```powershell\n(.*?)^```$", md, re.M | re.S):
    owner = None
    for eid, st, en in entries:
        if st < m.start():
            owner = eid
    head = md.rfind("\n## ", 0, m.start())
    if owner is not None and md.rfind("\n### ", 0, m.start()) < head:
        owner = None
    blocks.append((owner, m.group(1)))
def strip_strings(t):
    t = re.sub(r"'[^'\n]*'", "''", t)
    return re.sub(r'"[^"\n]*"', '""', t)
if mode == "blocks":
    ids = [e[0] for e in entries]
    if len(ids) != len(set(ids)):
        out.append("duplicate ids: " + " ".join(sorted(set(i for i in ids if ids.count(i) > 1))))
    if len(blocks) < 30:
        out.append("only %d powershell blocks" % len(blocks))
    seen = {}
    for owner, code in blocks:
        if owner is None:
            out.append("a powershell block without an id heading: " + code[:60])
            continue
        seen[owner] = seen.get(owner, 0) + 1
        bare = strip_strings(code)
        for tok, why in (("&&", "&&"), ("||", "||"), (" ?? ", "??"), ("Out-File", "Out-File"), ("Set-Content", "Set-Content"),
                         ("Add-Content", "Add-Content"), ("Tee-Object", "Tee-Object"), ("Get-Content", "Get-Content"),
                         ("-Encoding UTF8", "-Encoding UTF8"), ("/dev/null", "/dev/null"), ("-AsHashtable", "-AsHashtable"),
                         ("-NoEnumerate", "-NoEnumerate"), ("-AsByteStream", "-AsByteStream"), ("-SkipHttpErrorCheck", "-SkipHttpErrorCheck"),
                         ("utf8NoBOM", "utf8NoBOM"), ("::new(", "::new("), ("Invoke-Expression", "Invoke-Expression"), ("Start-Process", "Start-Process")):
            if tok in code:
                out.append("%s: %s" % (owner, why))
        if re.search(r"(^|[;{(|]\s*|&\s+)(rm|rmdir|ls|cat|cp|mv|curl|echo|mkdir|wget|sort|tee|del|dir|type|copy|move)\s", bare):
            out.append("%s: a POSIX alias at the start of a statement" % owner)
        if re.search(r" \? [^:]* : ", bare):
            out.append("%s: a ternary" % owner)
        if re.search(r"(^|[^-\w])exit(\s|$)", bare):
            out.append("%s: an exit statement" % owner)
        red = re.sub(r"2>&1|2>\$null|<[^<>\n]+>", "", bare)
        if ">" in red.replace("-gt", "").replace("-ge", ""):
            out.append("%s: a > redirection" % owner)
        if "@\"" in code or "@'" in code:
            out.append("%s: an unquoted @ before a quoted argument" % owner)
        if "Remove-Item" in code and not ("-LiteralPath" in code and "-Recurse" in code):
            out.append("%s: Remove-Item without -LiteralPath and -Recurse" % owner)
        if re.search(r"[^\x00-\x7f]", code):
            out.append("%s: a non-ASCII character" % owner)
    for owner, n in seen.items():
        if n > 1:
            out.append("%s: %d blocks" % (owner, n))
    ri = [o for o, c in blocks if "Remove-Item" in c]
    if ri != ["PS-DL-2"]:
        out.append("Remove-Item appears in %s, want PS-DL-2 only" % (ri,))
    if "Directory]::Delete(" not in dict(blocks).get("PS-DL-4", "") or ", $false)" not in dict(blocks).get("PS-DL-4", ""):
        out.append("PS-DL-4 does not remove the parents with the .NET call that refuses a directory that is not empty")
    for eid, body in bodies.items():
        if "POSIX" not in body:
            out.append("%s: no quoted POSIX form" % eid)
        if "```powershell" not in body and not re.search(r"No (PowerShell )?form", body):
            out.append("%s: neither a form nor a No form line" % eid)
    for ref in sorted(set(re.findall(r"PS-[A-Z]+-[0-9]+", md))):
        if ref not in bodies:
            out.append("reference to a missing id " + ref)
    if re.search(r"[^\x00-\x7f]", md):
        out.append("the file holds a non-ASCII character")
elif mode == "coverage":
    words = r"(date|ls|mkdir|mktemp|git|grep|printf|command|cp|mv|rm|rmdir|sed|jq|curl|dd|od|base64|tr|python3|python|py|\{python\}|\[|case|echo|<command>|<probe command>|\{ printf)"
    skip = {"[ -d ]", "[ -e ]", "command -v", "command cp", "command mv", "rm -rf", "curl -K -", "curl -v", "git check-ignore", "py -3", "{python} -I"}
    for rel in ("SKILL.md", "references/sources.md", "references/destinations.md"):
        text = rd(rel)
        for line in text.split("\n"):
            parts = line.split("`")
            for k in range(1, len(parts), 2):
                sp = parts[k]
                if not re.match(r"^" + words + r"(\s|$)", sp) or " " not in sp or "..." in sp or sp in skip:
                    continue
                if sp not in md:
                    out.append("%s: `%s` has no entry" % (rel, sp))
        for m in re.finditer(r"^( *)```bash\n(.*?)^ *```$", text, re.M | re.S):
            ind = m.group(1)
            code = "\n".join(l[len(ind):] if l.startswith(ind) else l for l in m.group(2).rstrip("\n").split("\n"))
            if code not in md:
                out.append("%s: fenced form `%s` has no entry" % (rel, code.split("\n")[0][:70]))
    quoted = " ".join(re.findall(r"^POSIX.*$", md, re.M)) + " " + " ".join(re.findall(r"^```text\n(.*?)^```$", md, re.M | re.S))
    host = re.search(r"^- \*\*Shell commands\*\*:.*$", rd("SKILL.md"), re.M).group(0)
    names = set(re.findall(r"`([a-z0-9[]+)`", host.split("Under PowerShell")[0]))
    for n in sorted(names):
        if n in ("allowed-tools", "cli", "api"):
            continue
        if not re.search(r"`[^`]*(^|[^\w-])" + re.escape(n) + r"([^\w-]|$)[^`]*`|(^|\s)" + re.escape(n) + r"\s", quoted):
            out.append("approval-list command `%s` is in no quoted POSIX form" % n)
print("\n".join(out))
PYPS
  check "references/shell-powershell.md: every powershell block sits under one PS-<AREA>-<n> heading, uses no 7-only syntax, no POSIX alias, no file-writing cmdlet, no > redirection, no exit, is ASCII; Remove-Item only in PS-DL-2 with -LiteralPath and -Recurse; parents removed by the .NET call that refuses a non-empty directory; every entry quotes its POSIX form" \
    "$(python3 -I "$TMP_ROOT/ps-static.py" "$SKILL_DIR" blocks 2>&1)"
  check "references/shell-powershell.md covers every POSIX form of SKILL.md, sources.md and destinations.md verbatim, and every command of the Host notes approval list appears in a quoted POSIX form" \
    "$(python3 -I "$TMP_ROOT/ps-static.py" "$SKILL_DIR" coverage 2>&1)"
else
  fail "references/shell-powershell.md static checks" "python3 is not on the PATH"
fi
# The dialect rule, stated once and named where it applies.
MISSING=""
HOST_NOTES_PS="$(awk '/^## Host notes$/ {h = 1; next} h && /^## / {h = 0} h' "$SKILL_MD")"
PCC="$(awk '/^## Pre-computed Context$/ {h = 1; next} h && /^## / {h = 0} h' "$SKILL_MD")"
# shellcheck disable=SC2016  # literal backticks, braces and dollars
while IFS='|' read -r where needle; do
  case "$where" in
    PCC) grep -qF -- "$needle" <<<"$PCC" || MISSING="$MISSING Pre-computed-Context:'$needle'" ;;
    HOST) grep -qF -- "$needle" <<<"$HOST_NOTES_PS" || MISSING="$MISSING Host-notes:'$needle'" ;;
    *) grep -qF -- "$needle" "$SKILL_DIR/$where" || MISSING="$MISSING $where:'$needle'" ;;
  esac
done <<'NEEDLES'
PCC|1. `Shell:` the dialect of the shell tool
PCC|`echo $PSVersionTable.PSVersion.Major`
PCC|`ERROR: this host's shell tool is neither a POSIX shell nor PowerShell`
PCC|forwarded verbatim into the researcher spawn prompt and every planner spawn prompt
HOST|the **shell tool** (run a shell command; every command this skill names is written in its POSIX form
HOST|- **Shell dialect**:
HOST|NEVER run a POSIX form
HOST|Under PowerShell the forms PS-HN-1 to PS-HN-3 of `references/shell-powershell.md`
HOST|Under PowerShell the commands to approve are the forms of `references/shell-powershell.md`
HOST|Under PowerShell only the forms that `references/shell-powershell.md` marks one statement are single commands
HOST|the spelling is the same under PowerShell
SKILL.md|compatibility: Any agent host that loads SKILL.md skills and offers file read, file write, file edit, a shell tool (a POSIX shell, or PowerShell 5.1 or later)
SKILL.md|| The shell tool is neither a POSIX shell nor PowerShell
SKILL.md|no typographic quote (U+2018 to U+201E), which PowerShell reads as a quote
SKILL.md|(also written `${NAME}`, `$env:NAME` or `%NAME%`, each naming the variable `NAME`)
references/sources.md|each one runs as the PowerShell form that `references/shell-powershell.md` lists for it
references/destinations.md|each one runs as the PowerShell form that `references/shell-powershell.md` lists for it
references/agent-spawn-prompts.md|the `Shell:` and `Available user skills:` lines verbatim (Pre-computed Context)
references/agent-spawn-prompts.md|it also carries the `Shell:` line of Pre-computed Context verbatim
references/agents/researcher.md|When your spawn prompt carries a `Shell: powershell <n>` line
references/agents/planner.md|When your spawn prompt carries a `Shell: powershell <n>` line
README.md|a shell tool (a POSIX shell, or PowerShell 5.1 or later; the skill finds out which before it starts)
README.md|### Windows
README.md|| `references/shell-powershell.md` |
README.md|are exercised by an automated test under Windows PowerShell 5.1 and PowerShell 7 on Windows
README.md|A POSIX shell on Windows without `jq` cannot use an `api:` destination
README.md|when other text follows it in the stored file (a field after the content field, the rest of a page)
references/shell-powershell.md|1. **Syntax of both versions.**
references/shell-powershell.md|`$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("<path>")`
NEEDLES
[ "$(grep -cF -- '- **Shell dialect**:' "$SKILL_MD" || true)" -eq 1 ] || MISSING="$MISSING SKILL.md:'Shell dialect' stated more than once"
[ "$(grep -cF -- 'references/shell-powershell.md` lists for it' "$SOURCES_MD" || true)" -eq 1 ] || MISSING="$MISSING sources.md: the pointer sentence is not there exactly once"
[ "$(grep -cF -- 'references/shell-powershell.md` lists for it' "$DEST_MD" || true)" -eq 1 ] || MISSING="$MISSING destinations.md: the pointer sentence is not there exactly once"
grep -qF -- 'Get-ChildItem' "$SOURCES_MD" "$DEST_MD" && MISSING="$MISSING a PowerShell form is duplicated into sources.md or destinations.md"
COMPAT_LEN="$(printf '%s\n' "$FM" | sed -n 's/^compatibility:[[:space:]]*//p' | awk '{printf "%d", length($0)}')"
[ "$COMPAT_LEN" -le 500 ] || MISSING="$MISSING compatibility is $COMPAT_LEN characters (more than 500)"
check "the Shell: item, the Shell dialect rule (stated once), the pointer sentences, the frontmatter and README requirements, the Windows subsection, the role sentence and the spawn-prompt carriers name the PowerShell forms where they apply" "$MISSING"

# --- mutation: the audit is the exit gate ----------------------------------------
MUT_SRC="$TMP_ROOT/mutated-src"
mkdir -p "$MUT_SRC/skills/brief"
cp -R "$REPO_DIR/skills/create-ticket" "$MUT_SRC/skills/create-ticket"
cp -R "$REPO_DIR/skills/brief/references" "$MUT_SRC/skills/brief/references"
cp -R "$REPO_DIR/agents" "$MUT_SRC/agents"
cp -R "$REPO_DIR/.claude-plugin" "$MUT_SRC/.claude-plugin"
# The pristine copy is not a git repository: it builds clean and stamps
# source-commit "unknown" (asserted only when the temp dir really is outside
# every git work tree).
set +e
bash "$BUILD" --src "$MUT_SRC" --out "$TMP_ROOT/nogit-out" >"$TMP_ROOT/nogit.log" 2>&1
NOGIT_RC=$?
set -e
if git -C "$MUT_SRC" rev-parse --git-dir >/dev/null 2>&1; then
  pass "a --src outside git stamps source-commit unknown (skipped: temp dir is inside a git work tree)"
elif [ "$NOGIT_RC" -eq 0 ] && grep -qx '  source-commit: "unknown"' "$TMP_ROOT/nogit-out/create-ticket/SKILL.md"; then
  pass "a --src outside git stamps source-commit unknown"
else
  fail "a --src outside git stamps source-commit unknown" "rc=$NOGIT_RC $(head -n 5 "$TMP_ROOT/nogit.log")"
fi
check "control: the unmodified source copy builds clean (exit 0, exit audit clean)" \
  "$([ "$NOGIT_RC" -eq 0 ] || echo "rc=$NOGIT_RC")$(grep -qF 'exit audit clean' "$TMP_ROOT/nogit.log" || echo " log: $(head -n 3 "$TMP_ROOT/nogit.log")")"

# The exit audit's variant check: one paragraph planted in a copy of the
# source, before a heading whose section passes through to the tree, holds one
# other spelling of the name per line. The build fails for the default name
# and for --name (the check runs on the canonical text), each form is named by
# its own finding, and nothing is published to <out>.
VAR_SRC="$TMP_ROOT/variant-src"
cp -R "$MUT_SRC" "$VAR_SRC"
awk '/^### Form A / && !done {
       print "Variant fixture underscore: create_ticket."
       print "Variant fixture camel case: createTicket."
       print "Variant fixture capitalised: Create-Ticket."
       print "Variant fixture plural glue: create-tickets."
       print "Variant fixture prefix glue: pre-create-ticket."
       print "Variant fixture wrapped pair: the create-"
       print "ticket skill."
       print "Variant fixture upstream path: <repo>/skills/create-ticket/SKILL.md."
       print "Variant fixture trailing blank: the create- "
       print "ticket skill again."
       print "> Quoted variant fixture: the create-"
       print "> ticket skill quoted."
       print "Variant fixture versioned path: plugin-v1.2.3/skills/create-ticket/SKILL.md."
       print "Variant fixture slashless path: the upstream directory <repo>/skills/create-ticket."
       print "Variant fixture host root: the directory .claude/skills/create-ticket stays."
       print ""
       done = 1
     }
     { print }' "$MUT_SRC/agents/decomposer.md" >"$VAR_SRC/agents/decomposer.md"
VARIANT_FORMS='name variant (another spelling of the name)|Variant fixture underscore: create_ticket.
name variant (another spelling of the name)|Variant fixture camel case: createTicket.
name variant (another spelling of the name)|Variant fixture capitalised: Create-Ticket.
name variant (glued to another word)|Variant fixture plural glue: create-tickets.
name variant (glued to another word)|Variant fixture prefix glue: pre-create-ticket.
name variant (wrapped over a line end)|Variant fixture wrapped pair: the create- ticket skill.
upstream path of the skill|Variant fixture upstream path: <repo>/skills/create-ticket/SKILL.md.
name variant (wrapped over a line end)|Variant fixture trailing blank: the create- ticket skill again.
name variant (wrapped over a line end)|> Quoted variant fixture: the create- > ticket skill quoted.
upstream path of the skill|Variant fixture versioned path: plugin-v1.2.3/skills/create-ticket/SKILL.md.
upstream path of the skill|Variant fixture slashless path: the upstream directory <repo>/skills/create-ticket.'
if [ "$(grep -c '^Variant fixture ' "$VAR_SRC/agents/decomposer.md" || true)" = 11 ]; then
  for n in create-ticket zq-x7; do
    VOUT="$TMP_ROOT/variant-out-$n"
    set +e
    bash "$BUILD" --src "$VAR_SRC" --out "$VOUT" --name "$n" >"$TMP_ROOT/variant-$n.log" 2>&1
    VRC=$?
    set -e
    VDETAIL="$([ "$VRC" -eq 1 ] || echo "rc=$VRC")$(grep -qF 'exit audit FAILED' "$TMP_ROOT/variant-$n.log" || echo ' no exit audit failure')"
    while IFS='|' read -r kind text; do
      awk -v K="  $kind references/agents/decomposer.md:" -v T=": $text" 'index($0, K) == 1 && index($0, T) {f = 1} END {exit !f}' "$TMP_ROOT/variant-$n.log" ||
        VDETAIL="$VDETAIL missing:'$kind ... $text'"
    done <<<"$VARIANT_FORMS"
    # A host skill root (the dot first in its path segment) is not an upstream path.
    ! grep -qF 'Variant fixture host root' "$TMP_ROOT/variant-$n.log" || VDETAIL="$VDETAIL host-root-reported"
    [ -z "$(entries_of "$VOUT")" ] || VDETAIL="$VDETAIL published:$(entries_of "$VOUT")"
    check "exit audit variant check ($n): each other spelling planted in the source (underscore, camel case, capitalised, plural glue, prefix glue, a pair wrapped plainly, behind a trailing blank and inside a quote, an upstream skills/create-ticket path with a slash, without one and behind a versioned directory) is named by its own finding, a host skill root is not, the build exits 1 and nothing is published" \
      "$VDETAIL"
  done
else
  fail "exit audit variant check: the fixture paragraph could not be planted before ### Form A of agents/decomposer.md"
fi
MUT2_SRC="$TMP_ROOT/mutated-src-2"
cp -R "$MUT_SRC" "$MUT2_SRC"
# shellcheck disable=SC2016  # the literal plugin variable is the mutation
printf '\nSee ${CLAUDE_PLUGIN_ROOT}/x\n' >>"$MUT_SRC/skills/create-ticket/references/ac-quality-criteria.md"
set +e
bash "$BUILD" --src "$MUT_SRC" --out "$TMP_ROOT/mutated-out" >"$TMP_ROOT/mutated.log" 2>&1
MUT_RC=$?
set -e
if [ "$MUT_RC" -eq 1 ] && grep -q 'denylist \[CLAUDE_\] references/ac-quality-criteria.md' "$TMP_ROOT/mutated.log"; then
  pass "mutation: an injected \${CLAUDE_PLUGIN_ROOT} line in the rubric fails the build"
else
  fail "mutation: an injected \${CLAUDE_PLUGIN_ROOT} line in the rubric fails the build" "rc=$MUT_RC $(head -n 5 "$TMP_ROOT/mutated.log")"
fi

# A plugin backlog path reintroduced by an upstream edit fails the build too.
printf '\nTickets live under .simple-workflow/backlog/product_backlog/x/.\n' >>"$MUT2_SRC/skills/create-ticket/references/spec-decomposer-input.md"
set +e
bash "$BUILD" --src "$MUT2_SRC" --out "$TMP_ROOT/mutated-out-2" >"$TMP_ROOT/mutated-2.log" 2>&1
MUT2_RC=$?
set -e
if [ "$MUT2_RC" -eq 1 ] && grep -qF 'denylist [\.simple-workflow] references/spec-decomposer-input.md' "$TMP_ROOT/mutated-2.log" \
   && grep -qF 'denylist [product_backlog] references/spec-decomposer-input.md' "$TMP_ROOT/mutated-2.log"; then
  pass "mutation: an injected plugin backlog path fails the build"
else
  fail "mutation: an injected plugin backlog path fails the build" "rc=$MUT2_RC $(head -n 8 "$TMP_ROOT/mutated-2.log")"
fi

# Review wording (v11.8.7): the curl examples carry the content type as a
# placeholder, the intake caps say what they bound, and the read-only rule
# names the one input it cannot verify.
# shellcheck disable=SC2016  # literal backticks
check "review wording: content type placeholder in the three curl forms, cap excess stated, typed cli: command named unverified" \
  "$({ [ "$(grep -cF -- '-H "Content-Type: <content_type>"' "$DEST_MD" || true)" = 3 ] || printf ' destinations.md:placeholder-count';
       grep -qF -- '-H "Content-Type: application/json"' "$DEST_MD" && printf ' destinations.md:literal-content-type';
       grep -qF -- 'or `application/json` when none is given' "$DEST_MD" || printf ' destinations.md:default';
       grep -qF -- 'are counted by `Chars:` but by neither limit' "$SOURCES_MD" || printf ' sources.md:cap-excess';
       grep -qF -- 'is run as given and is not checked for what it does' "$SOURCES_MD" || printf ' sources.md:read-only-exception';
       grep -qF -- 'is not checked for what it does' "$SKILL_DIR/README.md" || printf ' README.md:limit';
       grep -qF -- 'the one input the skill does not check' "$SKILL_DIR/SKILL.md" || printf ' SKILL.md:host-notes'; } || true)"

# Shell-dialect review fixes: braced variable references in a cli: command,
# the typographic-quote ban for URLs, follow-up URLs under the derived rule,
# searches before {scratch} exists, the prompt-free scratch removal, the
# link-safe parent removal, the emphasis-free agent grep form, the decomposer
# without shell commands, and the README limits.
PS_MD="$SKILL_DIR/references/shell-powershell.md"
# shellcheck disable=SC2016  # literal backticks, braces and dollars
check "shell-dialect review: \${env:NAME} rule, URL typographic quotes, follow-up URLs, pre-scratch lookups, -Confirm:\$false, reparse points kept, agent grep projection, decomposer, README limits" \
  "$({ grep -qF -- 'and one already written `$env:NAME`, is written `${env:NAME}` before the command runs' "$PS_MD" || printf ' shell-powershell.md:env-braces';
       grep -qF -- 'a `$NAME` reference becomes `${env:NAME}`' "$PS_MD" || printf ' shell-powershell.md:PS-SRC-11-braces';
       grep -qF -- 'and, when the `Shell:` line of Pre-computed Context names PowerShell, no typographic quote (U+2018 to U+201E), which PowerShell reads as a quote (`references/shell-powershell.md`, general rule 4). Else `ERROR: destination api: unusable URL (<rule>)`' "$DEST_MD" || printf ' destinations.md:url-typographic';
       grep -qF -- "a further request's URL, taken from a response, follows the **Derived URL rule** below" "$SKILL_MD" || printf ' SKILL.md:follow-up-url';
       grep -qF -- 'before `{scratch}` exists, when nothing may be written yet (the lookups of **Prose resolution**, Argument Parsing), the shell tool instead tests each path a statement names with PS-SRC-1 and PS-SRC-2' "$SKILL_MD" || printf ' SKILL.md:pre-scratch-lookup';
       grep -qF -- '(for the listing of a `dir:` source, `{scratch}/sources/shell-result.txt`)' "$SKILL_MD" || printf ' SKILL.md:dir-result-file';
       grep -qF -- 'so two such searches never run at the same time or in one batch of tool calls' "$SKILL_MD" || printf ' SKILL.md:one-search-at-a-time';
       grep -qF -- 'running `mkdir -p`, before any `dir:` source is listed' "$SKILL_MD" || printf ' SKILL.md:sources-dir-first';
       grep -qF -- 'Remove-Item -LiteralPath $s -Recurse -Force -Confirm:$false -ErrorAction Stop' "$PS_MD" || printf ' shell-powershell.md:confirm';
       grep -qF -- '[System.IO.FileAttributes]::ReparsePoint) -ne 0) { '"'kept'"' }' "$PS_MD" || printf ' shell-powershell.md:reparse';
       grep -qF -- 'the `created` of `references/split-plan-schema.md`' "$PS_MD" || printf ' shell-powershell.md:created';
       grep -qF -- 'ERROR: destination api: needs curl.exe on PATH' "$PS_MD" || printf ' shell-powershell.md:curl-exe-error';
       grep -qF -- '-CaseSensitive -Encoding UTF8 | ForEach-Object { [string]$_.LineNumber + '"':'"' + $_.Line }' "$SKILL_DIR/references/agents/researcher.md" || printf ' researcher.md:grep-projection';
       grep -qF -- 'read-only shell commands' "$SKILL_DIR/references/agents/decomposer.md" && printf ' decomposer.md:shell-commands';
       grep -qF -- 'read-only shell commands' "$SKILL_DIR/references/agents/planner.md" || printf ' planner.md:shell-commands';
       grep -qF -- 'nor an error that names `PSVersionTable` as an unset variable' "$SKILL_MD" || printf ' SKILL.md:dialect-error-row';
       grep -qF -- 'copied verbatim, followed by' "$SOURCES_MD" && printf ' sources.md:xlsx-verbatim';
       grep -qF -- "PowerShell's full language mode" "$SKILL_DIR/README.md" || printf ' README.md:language-mode';
       grep -qF -- 'that holds a typographic quote (U+2018 to U+201E) is refused' "$SKILL_DIR/README.md" || printf ' README.md:typographic';
       grep -qF -- 'may accept text that `jq` refuses' "$SKILL_DIR/README.md" || printf ' README.md:json-reader'; } || true)"

# Second review of the PowerShell forms: the dialect is settled before any other
# shell command; a client's first word is the program file PS-AP-1 printed and a
# command that does not start says why; an interpreter that cannot start is
# skipped; the header pipe is ASCII through a static encoding; a relative path
# with a colon gets ./; an empty probe body is JSON as for jq empty; an
# unreadable sibling does not hide a taken number; matches stay case-sensitive.
# shellcheck disable=SC2016  # literal backticks, braces and dollars
check "shell-dialect review 2: Shell: item first, found: <file name> and not started (<reason>), interpreter try/catch, ASCII header pipe, ./ before a colon path, empty probe body, unreadable sibling skipped, case-sensitive matches, login-shell output, dossier limit" \
  "$({ grep -qF -- 'it is settled before any other shell command of the run, the probes and existence tests of Argument Parsing included' "$SKILL_MD" || printf ' SKILL.md:shell-first';
       grep -qF -- 'is written as the file name PS-AP-1 printed for it after `found: `' "$PS_MD" || printf ' shell-powershell.md:rule2-file-name';
       grep -qF -- "{ 'found: ' + @(Get-Command -Name \"<first word>\" -CommandType Application -ErrorAction SilentlyContinue)[0].Name }" "$PS_MD" || printf ' shell-powershell.md:PS-AP-1';
       [ "$(grep -cF -- "catch { 'not started (' + \$_.Exception.Message + ')' }" "$PS_MD" || true)" = 2 ] || printf ' shell-powershell.md:not-started-count';
       grep -qF -- "\$v = ''; try { \$v = [string](& \$exe @rest --version 2>\$null | Out-String) } catch { };" "$PS_MD" || printf ' shell-powershell.md:PS-SRC-4-try';
       [ "$(grep -cF -- '$OutputEncoding = [System.Text.Encoding]::ASCII;' "$PS_MD" || true)" = 2 ] || printf ' shell-powershell.md:ascii-pipe-count';
       [ "$(grep -cF -- '$ci = $null; try { $ci = [Console]::InputEncoding; [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { };' "$PS_MD" || true)" = 2 ] || printf ' shell-powershell.md:console-input-no-mark-count';
       [ "$(grep -cF -- 'if ($null -ne $ci) { try { [Console]::InputEncoding = $ci } catch { } };' "$PS_MD" || true)" = 2 ] || printf ' shell-powershell.md:console-input-put-back-count';
       grep -qF -- 'New-Object System.Text.ASCIIEncoding' "$PS_MD" && printf ' shell-powershell.md:new-object-ascii';
       grep -qF -- 'A relative path that holds a `:` is written with `./` in front' "$PS_MD" || printf ' shell-powershell.md:colon-path';
       grep -qF -- "if (\$t.Trim() -eq '') { 'json' }" "$PS_MD" || printf ' shell-powershell.md:PS-DST-16-empty';
       grep -qF -- 'or with an empty key, cannot be read by PowerShell' "$PS_MD" || printf ' shell-powershell.md:empty-key';
       grep -qF -- 'try { $es = [System.IO.Directory]::GetFileSystemEntries($a) } catch { }' "$PS_MD" || printf ' shell-powershell.md:PS-DST-7-sibling';
       [ "$(grep -cF -- '-ceq $m.Groups[1].Value' "$PS_MD" || true)" = 2 ] || printf ' shell-powershell.md:ceq-count';
       grep -qF -- "if (\$l.Contains('<text>'))" "$PS_MD" || printf ' shell-powershell.md:PS-HN-2-case';
       grep -qF -- 'prints on its standard output exactly what it prints in a plain shell; the only other output is that error line of the collision listing' "$SKILL_MD" || printf ' SKILL.md:login-shell-output';
       grep -qF -- 'so the orchestrator types that text (up to 60,000 characters) out once more there' "$SKILL_DIR/README.md" || printf ' README.md:dossier-limit'; } || true)"

print_summary
