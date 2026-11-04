#!/usr/bin/env bash
# Contract test for tools/build-copilot-skill.sh: the generated, standalone
# GitHub Copilot skill `create-ticket/`.
#
# The generated tree is never committed, so this suite builds it into a temp
# directory and re-checks it independently of the build's own exit audit:
#   - the build succeeds, refuses a non-empty target, and honours --force
#   - the tree holds exactly SKILL.md + the shipped references
#   - the SKILL.md frontmatter follows the Agent Skills contract
#   - every relative link and backticked references/ path resolves
#   - zero denylist hits and zero backticked Claude Code tool names
#   - the AC rubric keeps its Gate headings, Terminology and word count
#   - SKILL.md carries the host notes, Step W-0 and the degraded branch
#   - a mutation (a plugin variable injected into a copied source) FAILS the
#     build, proving the audit is the exit gate
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=./test-helper.sh
source "$SCRIPT_DIR/test-helper.sh"
export LC_ALL=C

BUILD="$REPO_DIR/tools/build-copilot-skill.sh"
MANIFEST_DIR="$REPO_DIR/tools/copilot-skill"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/test-copilot-skill.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
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

echo "=== Copilot standalone create-ticket skill build ==="
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

# --- tree shape ---------------------------------------------------------------
EXPECTED="SKILL.md
references/ac-quality-criteria.md
references/ac-quality-grading.md
references/agent-spawn-prompts.md
references/agents/decomposer.md
references/agents/planner.md
references/agents/researcher.md
references/agents/ticket-evaluator.md
references/brief-template.md
references/findings-schema.md
references/interview-templates.md
references/mode-dispatch-flows.md
references/spec-decomposer-input.md
references/split-plan-schema.md
references/ticket-template.md
references/write-path-templates.md"
ACTUAL="$(cd "$SKILL_DIR" && find . -type f | sed 's#^\./##' | sort)"
check "tree holds exactly SKILL.md + the 15 shipped references" \
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
check "frontmatter carries no allowed-tools key" "$(printf '%s\n' "$FM" | grep '^allowed-tools:' || true)"
check "frontmatter metadata names the source version" \
  "$(printf '%s\n' "$FM" | grep -qE '^  source-version: "[0-9]+\.[0-9]+\.[0-9]+"$' || echo missing)"

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
[$pat] $(printf '%s\n' "$h" | head -n 3 | cut -c1-160)"
done < <(manifest_lines "$MANIFEST_DIR/denylist.txt")
check "every denylist pattern has zero hits" "${HITS#$'\n'}"

DENY_TOOLS="$(manifest_lines "$MANIFEST_DIR/tool-vocabulary.txt" | awk '$1 == "deny" {printf "%s%s", sep, $2; sep = "|"}')"
check "no backticked Claude Code tool name remains" \
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
check "rubric word count within 3% of the source ($GEN_WC vs $SRC_WC)" \
  "$([ $((DELTA * 100)) -le $((SRC_WC * 3)) ] || echo "delta=$DELTA")"

# --- SKILL.md content ------------------------------------------------------------
SKILL_MD="$SKILL_DIR/SKILL.md"
MISSING=""
# shellcheck disable=SC2016  # literal backticks
for needle in '## Host notes' 'Step W-0' 'SELF-EVALUATED' '`task`' 'agent_type: general-purpose' '`ask_user`'; do
  grep -qF -- "$needle" "$SKILL_MD" || MISSING="$MISSING '$needle'"
done
check "SKILL.md carries Host notes, Step W-0, SELF-EVALUATED, task, ask_user" "$MISSING"
check "SKILL.md has no dynamic !\`...\` probe line" "$(grep -n '!`' "$SKILL_MD" || true)"
check "every shipped agent prompt is frontmatter-free" \
  "$(for f in "$SKILL_DIR"/references/agents/*.md; do [ "$(head -n 1 "$f")" != "---" ] || echo "$f"; done)"

# --- mutation: the audit is the exit gate ----------------------------------------
MUT_SRC="$TMP_ROOT/mutated-src"
mkdir -p "$MUT_SRC/skills/brief"
cp -R "$REPO_DIR/skills/create-ticket" "$MUT_SRC/skills/create-ticket"
cp -R "$REPO_DIR/skills/brief/references" "$MUT_SRC/skills/brief/references"
cp -R "$REPO_DIR/agents" "$MUT_SRC/agents"
cp -R "$REPO_DIR/.claude-plugin" "$MUT_SRC/.claude-plugin"
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

print_summary
