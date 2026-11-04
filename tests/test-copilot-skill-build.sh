#!/usr/bin/env bash
# Contract test for tools/build-copilot-skill.sh: the generated, standalone
# GitHub Copilot skill `create-ticket/`.
#
# The generated tree is never committed, so this suite builds it into a temp
# directory and re-checks it independently of the build's own exit audit:
#   - the build succeeds, refuses a non-empty target, and honours --force
#   - the tree holds exactly SKILL.md + the shipped references (including
#     the override-only references/destinations.md)
#   - the SKILL.md frontmatter follows the Agent Skills contract and names
#     the source version and the source commit
#   - every relative link and backticked references/ path resolves
#   - zero denylist hits (the decoupling entries included) and zero
#     backticked Claude Code tool names
#   - the AC rubric keeps its Gate headings, Terminology and word count
#   - SKILL.md carries the host notes, the Delivery section, the destination
#     argument and the degraded branch; destinations.md defines all three kinds
#   - a --src outside git stamps source-commit "unknown"
#   - two mutations (a plugin variable, a plugin backlog path, each injected
#     into a copied source) FAIL the build, proving the audit is the exit gate
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
references/destinations.md
references/findings-schema.md
references/interview-templates.md
references/mode-dispatch-flows.md
references/spec-decomposer-input.md
references/split-plan-schema.md
references/ticket-template.md
references/write-path-templates.md"
ACTUAL="$(cd "$SKILL_DIR" && find . -type f | sed 's#^\./##' | sort)"
check "tree holds exactly SKILL.md + the 16 shipped references" \
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
COMMIT_VAL="$(printf '%s\n' "$FM" | sed -n 's/^  source-commit: //p')"
check "frontmatter metadata names the source commit (short sha or unknown)" \
  "$(printf '%s\n' "$COMMIT_VAL" | grep -qE '^"([0-9a-f]{7,40}|unknown)"$' || echo "source-commit='$COMMIT_VAL'")"
check "frontmatter metadata.source is neutral (no plugin name)" \
  "$(printf '%s\n' "$FM" | grep -qx '  source: generated by tools/build-copilot-skill.sh; do not edit by hand' || echo "$(printf '%s\n' "$FM" | grep '^  source:')")"

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
[$pat] $(printf '%s\n' "$h" | head -n 3 | cut -c1-160)"
done <<<"$DECOUPLE_ERES"
check "no plugin name, backlog layout, ticket-dir or reuse key in the tree" "${DECOUPLE_HITS#$'\n'}"

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
check "rubric word count within 5% of the source ($GEN_WC vs $SRC_WC)" \
  "$([ $((DELTA * 100)) -le $((SRC_WC * 5)) ] || echo "delta=$DELTA")"

# --- SKILL.md content ------------------------------------------------------------
SKILL_MD="$SKILL_DIR/SKILL.md"
MISSING=""
# shellcheck disable=SC2016  # literal backticks
for needle in '## Host notes' '## Delivery' 'SELF-EVALUATED' '`task`' 'agent_type: general-purpose' '`ask_user`'; do
  grep -qF -- "$needle" "$SKILL_MD" || MISSING="$MISSING '$needle'"
done
check "SKILL.md carries Host notes, Delivery, SELF-EVALUATED, task, ask_user" "$MISSING"

DEST_MD="$SKILL_DIR/references/destinations.md"
MISSING=""
for f in "$SKILL_MD" "$DEST_MD"; do
  # shellcheck disable=SC2016  # literal backticks
  for needle in 'destination=' '`local:' '`mcp:' '`api:'; do
    grep -qF -- "$needle" "$f" || MISSING="$MISSING ${f#"$SKILL_DIR"/}:'$needle'"
  done
done
check "SKILL.md and destinations.md name destination= and the local:/mcp:/api: kinds" "$MISSING"
HOST_NOTES="$(awk '/^## Host notes$/ {h = 1; next} h && /^## / {h = 0} h' "$SKILL_MD")"
check "Host notes cover the auth_env secret and non-transactional remote creates" \
  "$(printf '%s\n' "$HOST_NOTES" | grep -q 'auth_env' || echo 'no auth_env')$(printf '%s\n' "$HOST_NOTES" | grep -q 'not transactional' || echo ' no non-transactional note')"
check "the run scratch directory comes from mktemp -d" \
  "$(grep -qF 'mktemp -d' "$SKILL_MD" || echo 'mktemp -d missing from SKILL.md')"
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
check "no Phase 1.5 and no ADVISORY-CONSULT trace in the tree" \
  "$(grep -rnE 'Phase 1\.5|ADVISORY-CONSULT' "$SKILL_DIR" | cut -c1-160 || true)"
check "the ticket template carries no P? priority placeholder" \
  "$(grep -nF 'P?' "$SKILL_DIR/references/ticket-template.md" || true)"
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

print_summary
