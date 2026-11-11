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
#     and every cap, and marks a missing part instead of failing
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
check "the build reports 21 files and a clean exit audit" \
  "$(grep -qF '(21 files, ' "$BUILD_LOG" || echo 'file count is not 21')$(grep -qF 'exit audit clean' "$BUILD_LOG" || echo ' audit not clean')"

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
references/sources.md
references/spec-decomposer-input.md
references/split-plan-schema.md
references/ticket-template.md
references/write-path-templates.md
scripts/xlsx_render.py
scripts/xlsx_to_text.py"
ACTUAL="$(cd "$SKILL_DIR" && find . -type f | sed 's#^\./##' | sort)"
check "tree holds exactly README.md + SKILL.md + the 17 shipped references + the xlsx converter and the sheet renderer (21 files)" \
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
  "$(printf '%s\n' "$DESC" | grep -q 'Invoke only when the user names this skill' || echo 'name-only rule missing')$(printf '%s\n' "$DESC" | grep -E -o 'Triggers on|Only invoke when called by name|\(2\) user' || true)"
check "frontmatter carries no allowed-tools key" "$(printf '%s\n' "$FM" | grep '^allowed-tools:' || true)"
check "frontmatter metadata names the source version" \
  "$(printf '%s\n' "$FM" | grep -qE '^  source-version: "[0-9]+\.[0-9]+\.[0-9]+"$' || echo missing)"
COMMIT_VAL="$(printf '%s\n' "$FM" | sed -n 's/^  source-commit: //p')"
check "frontmatter metadata names the source commit (short sha or unknown)" \
  "$(printf '%s\n' "$COMMIT_VAL" | grep -qE '^"([0-9a-f]{7,40}|unknown)"$' || echo "source-commit='$COMMIT_VAL'")"
check "frontmatter metadata.source is neutral (no plugin name, no generator path)" \
  "$(printf '%s\n' "$FM" | grep -qx '  source: generated skill; do not edit by hand' || echo "$(printf '%s\n' "$FM" | grep '^  source:')")"

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
[$pat] $(printf '%s\n' "$h" | head -n 3 | cut -c1-160)"
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
[$pat] $(printf '%s\n' "$h" | head -n 3 | cut -c1-160)"
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
  "$(printf '%s\n' "$HOST_NOTES" | grep -q 'auth_env' || echo 'no auth_env')$(printf '%s\n' "$HOST_NOTES" | grep -q 'not transactional' || echo ' no non-transactional note')"
check "the run scratch directory comes from mktemp -d" \
  "$(grep -qF 'mktemp -d' "$SKILL_MD" || echo 'mktemp -d missing from SKILL.md')"
check "the run scratch directory lives inside the working directory and is gitignored" \
  "$(grep -qF 'mktemp -d .create-ticket-scratch/run.XXXXXX' "$SKILL_MD" || echo 'relative mktemp template missing')$(grep -qF 'git check-ignore -q .create-ticket-scratch/x' "$SKILL_MD" || echo ' check-ignore step missing')$(grep -qF 'cannot create the scratch directory .create-ticket-scratch/' "$SKILL_MD" || echo ' scratch ERROR line missing')$(grep -rqF 'it may be absolute' "$SKILL_DIR/references/agents" && echo ' agent bodies keep the absolute-scratch exception' || true)$(grep -qF 'mkdir -p .create-ticket-scratch &&' "$SKILL_MD" && echo ' scratch creation is a joined command' || true)$(grep -qF '>> "<root>/.gitignore"' "$SKILL_MD" || echo ' gitignore append does not target the repository root file')$(grep -cF 'Scratch: .create-ticket-scratch/run.k3Qz9a' "$SKILL_DIR/references/write-path-templates.md" | grep -qx 2 || echo ' success summaries lack the Scratch line')$(grep -rqE 'system temporary directory \(|may be absolute \(Host|TMPDIR' "$SKILL_DIR" && echo ' stale system-temp wording' || true)"
check "the researcher and planner are banned from running the product and from delete commands" \
  "$(for a in researcher planner; do grep -qF 'execution is not inspection' "$SKILL_DIR/references/agents/$a.md" || echo "no execution ban in $a.md"; grep -qF 'never run a delete command' "$SKILL_DIR/references/agents/$a.md" || echo "no delete ban in $a.md"; done)"
check "Phase 4 spawns every ticket's evaluator in one message" \
  "$(grep -qF 'spawn the initial evaluator of every ticket in one message' "$SKILL_MD" || echo 'concurrent evaluator rule missing')"
check "README names the scratch directory and no longer claims the skill was never run" \
  "$(grep -qF '.create-ticket-scratch/run.<id>/' "$SKILL_DIR/README.md" || echo 'scratch dir missing from README')$(grep -qF 'not yet been exercised' "$SKILL_DIR/README.md" && echo ' stale never-run claim' || true)"
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
for needle in '## `file:<path>`' '## `dir:<path>`' '## `mcp:<server>/<tool>' '## `api:<url>`' 'xlsx_to_text.py' 'python3 -I' 'S<n>:L<a>-L<b>' '60,000' '150,000' 'source_auth_env' '## Source excerpts' 'Sources:' '## Partition basis'; do
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
  "$(grep -rn 'local:tickets' "$SKILL_DIR" | cut -c1-160 || true)$(grep -qF 'Absent → `local:.local/tickets`' "$SKILL_MD" || echo ' SKILL.md lacks the .local/tickets default')$(grep -qF '.local/tickets/{parent-slug}' "$SKILL_DIR/references/write-path-templates.md" || echo ' summary examples lack .local/tickets')"
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
for needle in '`render=auto|off|excel|soffice`' '[render=auto|off|excel|soffice]' 'ERROR: render= must be auto, off, excel or soffice' 'prose never sets `confirm=yes`, `depth=`, `render=`'; do
  printf '%s\n' "$ARGS_PART" | grep -qF -- "$needle" || MISSING="$MISSING SKILL.md-Argument-Parsing:'$needle'"
done
printf '%s\n' "$FM" | grep -E '^argument-hint:' | grep -qF -- '[render=auto|off|excel|soffice]' || MISSING="$MISSING argument-hint:'render='"
grep -qF -- 'xlsx_render.py' "$SKILL_MD" || MISSING="$MISSING SKILL.md:'xlsx_render.py'"
# shellcheck disable=SC2016  # literal braces and backticks
for needle in '**Sheet rendering (optional)**' 'xlsx_render.py' 'Rendered:' '--only-if-structured "{scratch}/sources/S<n>.md"' '--out "{scratch}/sources/S<n>-render"' 'WARNING: source S<n> (<origin>): no sheet render (<reasons>)' '[transcribed from <pdf|image> by the file-read tool; wording and layout may be incomplete]' "ERROR: source=file:<path>: this host's file-read tool cannot show a <pdf|image> file" '[truncated: source S<n> has <k> pages; pages beyond 40 were not read]' 'not an OCR result' 'unsupported file kind (supported: .md .markdown .txt .csv .tsv .json .yaml .yml .html .htm .xlsx .pdf .png .jpg .jpeg .gif .webp and any other text file)'; do
  grep -qF -- "$needle" "$SOURCES_MD" || MISSING="$MISSING sources.md:'$needle'"
done
FILE_TABLE="$(awk '/^## `file:<path>`$/ {f = 1; next} f && /^## / {f = 0} f && /^\|/' "$SOURCES_MD")"
# shellcheck disable=SC2016  # literal backticks
printf '%s\n' "$FILE_TABLE" | grep -qE -- '^\| `\.pdf` \|' || MISSING="$MISSING sources-table:'.pdf'"
# shellcheck disable=SC2016  # literal backticks
printf '%s\n' "$FILE_TABLE" | grep -qE -- '^\| `\.png`, ' || MISSING="$MISSING sources-table:'.png'"
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
  printf '%s\n' "$HOST_PART" | grep -qF -- "$needle" || MISSING="$MISSING Host-notes:'$needle'"
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
    printf '%s\n' "$XLSX_OUT" | grep -qF -- "$needle" || MISSING="$MISSING '$needle'"
  done
  printf '%s\n' "$XLSX_OUT" | grep -qF -- 'PHONETIC' && MISSING="$MISSING 'phonetic rPh run leaked into the cell text'"
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
  printf '%s\n' "$XLSX_OUT2" | grep -qF -- '[truncated: sheet Backlog has more than 2 rows; only the first 2 were read]' || MISSING="$MISSING 'row cap marker'"
  printf '%s\n' "$XLSX_OUT2" | grep -qF -- '[truncated: sheet Backlog has columns beyond c3' || MISSING="$MISSING 'column cap marker'"
  printf '%s\n' "$XLSX_OUT2" | grep -qF -- '| 4 |' && MISSING="$MISSING 'row 4 leaked past the cap'"
  printf '%s\n' "$XLSX_OUT" | grep -qF -- '[truncated: sheet Grid has columns beyond c64' || MISSING="$MISSING 'merged range beyond the column cap not marked'"
  XLSX_OUT3="$(python3 -I "$XLSX_PY" "$FIX_DIR/fixture.xlsx" --max-chars 120 2>/dev/null)"
  printf '%s\n' "$XLSX_OUT3" | grep -qF -- '[truncated: output exceeds 120 characters' || MISSING="$MISSING 'char cap marker'"
  check "xlsx converter: every cap is marked, never silent" "$MISSING"
  XLSX_OUT4="$(python3 -I "$XLSX_PY" --sheet=Notes -- "$FIX_DIR/fixture.xlsx" 2>/dev/null)"
  MISSING=""
  printf '%s\n' "$XLSX_OUT4" | grep -qF -- '## Sheet: Notes (hidden)' || MISSING="$MISSING 'selected sheet missing'"
  printf '%s\n' "$XLSX_OUT4" | grep -qF -- '## Sheet: Backlog' && MISSING="$MISSING 'unselected sheet leaked'"
  set +e
  SHEET_ERR="$(python3 -I "$XLSX_PY" "$FIX_DIR/fixture.xlsx" --sheet Nope 2>&1 >/dev/null)"; SHEET_RC=$?
  set -e
  [ "$SHEET_RC" -eq 2 ] || MISSING="$MISSING 'unknown sheet rc=$SHEET_RC'"
  printf '%s\n' "$SHEET_ERR" | grep -qF -- 'the workbook has: Backlog, Notes' || MISSING="$MISSING 'unknown sheet does not list the names'"
  check "xlsx converter: --sheet selects one worksheet and an unknown name exits 2 listing the names" "$MISSING"
  # has_all OUT NEEDLE... — prints every NEEDLE missing from OUT (fixed strings).
  has_all() {
    local text="$1" n
    shift
    for n in "$@"; do printf '%s\n' "$text" | grep -qF -- "$n" || printf " '%s'" "$n"; done
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
  NOTES_PART="$(printf '%s\n' "$XLSX_OUT" | awk '/^### Notes$/ {n = 1; next} n && /^$/ {exit} n')"
  check "xlsx converter: ### Notes lists each note with its cell, author and text in row order" \
    "$(has_all "$XLSX_OUT" '### Notes')$(printf '%s\n' "$NOTES_PART" | sed -n 1p | grep -qxF -- '- c2 row 2 (B2), Reviewer A: needs a spec' || echo ' first note line')$(printf '%s\n' "$NOTES_PART" | sed -n 2p | grep -qxF -- '- c3 row 4 (C4), Reviewer A: confirm the<br>time zone' || echo ' second note line')"
  check "xlsx converter: a threaded comment replaces the legacy placeholder of its cell and takes its author from the persons part" \
    "$(printf '%s\n' "$NOTES_PART" | sed -n 3p | grep -qxF -- '- c5 row 9 (E9), Pat Person: threaded body' || echo ' threaded note line')$([ "$(printf '%s\n' "$NOTES_PART" | grep -c .)" = 3 ] || echo ' ### Notes does not hold exactly 3 lines')$(printf '%s\n' "$XLSX_OUT" | grep -F '[Threaded comment]' || true)"
  SHAPES_PART="$(printf '%s\n' "$XLSX_OUT" | awk '/^### Shapes$/ {n = 1; next} n && /^$/ {exit} n')"
  check "xlsx converter: ### Shapes lists text boxes, grouped shapes and charts, never connectors" \
    "$(has_all "$XLSX_OUT" '### Shapes' '- "TextBox 1" at c3 row 5 to c6 row 9: First paragraph<br>Second paragraph' '- "Callout 3" at c1 row 12: Grouped callout' '- chart "Chart 5" at c10 row 2 to c15 row 13: (chart; data not read)' '- "Lead 7" at c1 row 14: <br>after an empty paragraph' '- "Break 8" at c1 row 16: ends in a break<br><br>next paragraph')$(printf '%s\n' "$XLSX_OUT" | grep -F -e 'Connector 4' -e 'at c7 row 2 to c9 row 4' || true)$([ "$(printf '%s\n' "$SHAPES_PART" | grep -c .)" = 5 ] || echo ' ### Shapes does not hold exactly 5 lines')"
  check "xlsx converter: ### Images lists each picture with its media name and byte count, nothing extracted by default" \
    "$(has_all "$XLSX_OUT" '### Images' '- "Picture 6" at c2 row 10 to c5 row 20: image1.png (70 bytes)')$(printf '%s\n' "$XLSX_OUT" | grep -F 'extracted to' || true)"
  XLSX_MEDIA="$(python3 -I "$XLSX_PY" --extract-media "$FIX_DIR/media" -- "$FIX_DIR/fixture.xlsx" 2>&1)"
  check "xlsx converter: --extract-media writes the image as <sheet-slug>-<media name> and says so" \
    "$(has_all "$XLSX_MEDIA" "image1.png (70 bytes), extracted to $FIX_DIR/media/Backlog-image1.png")$([ "$(wc -c <"$FIX_DIR/media/Backlog-image1.png" 2>/dev/null | tr -d ' ')" = 70 ] || echo ' media file missing or wrong size')$([ "$(find "$FIX_DIR/media" -type f | wc -l | tr -d ' ')" = 1 ] || echo ' unexpected files in the media dir')"
  check "xlsx converter: auto picks the cells layout for the sparse wide sheet and keeps the table elsewhere" \
    "$(has_all "$XLSX_OUT" '## Sheet: Grid (layout: cells)' '- r1 c1 [merged c1-c2 rows 1-2]: Title block' '- r1 c15: far right' '- r2 c20: edge')$(printf '%s\n' "$XLSX_OUT" | grep -qx '## Sheet: Backlog' || echo ' Backlog heading changed')"
  check "xlsx converter: auto picks cells on either branch alone (a sparse wide sheet without a merge; a narrow sheet with a 2x2 merge)" \
    "$(has_all "$XLSX_OUT" '## Sheet: Wide (layout: cells)' '- r2 c20: wide edge')$(has_all "$XLSX_OUT2" '## Sheet: Grid (layout: cells)' '- r1 c1 [merged c1-c2 rows 1-2]: Title block')$(printf '%s\n' "$XLSX_OUT2" | grep -qx '## Sheet: Wide' || echo ' narrow Wide not printed as a table')"
  XLSX_TABLE="$(python3 -I "$XLSX_PY" --layout table --sheet Grid -- "$FIX_DIR/fixture.xlsx" 2>&1)"
  XLSX_CELLS="$(python3 -I "$XLSX_PY" --layout cells --sheet Backlog -- "$FIX_DIR/fixture.xlsx" 2>&1)"
  check "xlsx converter: --layout table and --layout cells force the layout" \
    "$(printf '%s\n' "$XLSX_TABLE" | grep -qx '## Sheet: Grid' || echo ' Grid not forced to table')$(has_all "$XLSX_TABLE" '| 1 | [merged c1-c2 rows 1-2] Title block |')$(has_all "$XLSX_CELLS" '## Sheet: Backlog (layout: cells)' '- r1 c5 (hidden): Owner' '- r7 (hidden) c2: old version' '- r9 c1 [merged c1-c3]: Section heading' '- r10 c5 (hidden) [merged rows 10-11]:')$(printf '%s\n' "$XLSX_CELLS" | grep -F '| row |' || true)"
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
  check "xlsx converter: a non-zip file and a zip without a workbook exit 2" \
    "$([ "$NOT_ZIP_RC" -eq 2 ] || echo "not-zip rc=$NOT_ZIP_RC")$([ "$NO_WB_RC" -eq 2 ] || echo " no-workbook rc=$NO_WB_RC")"
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
    "$([ "$R_RC" -eq 0 ] || echo "rc=$R_RC")$(printf '%s\n' "$R_OUT" | grep -qxE "Rendered: $RENDER_OUT/fixture\.pdf \(by soffice, [0-9]+ bytes, all sheets\)" || echo " line: $R_OUT")$(head -c 4 "$RENDER_OUT/fixture.pdf" 2>/dev/null | grep -qx '%PDF' || echo ' no %PDF file')"
  render_run --chain excel --excel-cmd "$FIX_DIR/fake-excel" --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  check "sheet renderer: --chain excel with an interpreter stand-in renders by excel and a second run overwrites the PDF" \
    "$([ "$R_RC" -eq 0 ] || echo "rc=$R_RC")$(printf '%s\n' "$R_OUT" | grep -qxE "Rendered: $RENDER_OUT/fixture\.pdf \(by excel, [0-9]+ bytes, all sheets\)" || echo " line: $R_OUT")$(grep -qF 'fake excel render' "$RENDER_OUT/fixture.pdf" || echo ' PDF not overwritten')"
  render_run --chain excel --excel-cmd "$FIX_DIR/fake-excel" --sheet Backlog --sheet=Grid --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  check "sheet renderer: --sheet names the first selected sheet and says the others were not rendered" \
    "$(printf '%s\n' "$R_OUT" | grep -qxE "Rendered: $RENDER_OUT/fixture\.pdf \(by excel, [0-9]+ bytes, sheet Backlog; other selected sheets not rendered\)" || echo "line: $R_OUT")"
  render_run --chain auto --excel-cmd "$FIX_DIR/fake-fail" --soffice "$FIX_DIR/fake-soffice" --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  check "sheet renderer: auto falls through a failing excel to soffice and prints only the success line" \
    "$([ "$R_RC" -eq 0 ] || echo "rc=$R_RC")$(printf '%s\n' "$R_OUT" | grep -qxE "Rendered: $RENDER_OUT/fixture\.pdf \(by soffice, [0-9]+ bytes, all sheets\)" || echo " line: $R_OUT")$([ "$(printf '%s\n' "$R_OUT" | wc -l | tr -d ' ')" = 1 ] || echo ' more than one line')$(printf '%s\n' "$R_OUT" | grep -F -e 'excel:' -e 'boom' || true)"
  render_run --chain auto --excel-cmd "$FIX_DIR/fake-fail" --soffice "$FIX_DIR/fake-fail" --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  check "sheet renderer: every renderer failing exits 0 with each exit status and the first line of its error output" \
    "$([ "$R_RC" -eq 0 ] || echo "rc=$R_RC")$(printf '%s\n' "$R_OUT" | grep -qxF 'Rendered: no (excel: exit status 3: boom; soffice: exit status 3: boom)' || echo " line: $R_OUT")"
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
    "$([ "$R_RC" -eq 0 ] || echo "rc=$R_RC")$(printf '%s\n' "$R_OUT" | grep -qxF 'Rendered: no (excel: timed out after 1 s; soffice: no PDF produced)' || echo " line: $R_OUT")$([ "$HANG_SECS" -le 10 ] || echo " took ${HANG_SECS}s")$([ -s "$TMP_ROOT/hang.pids" ] || echo ' the hanging stand-in never ran')$([ -z "$STRAY" ] || echo " stray processes:$STRAY")"
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
      "$(printf '%s\n' "$NOSOFF_OUT" | grep -qxF 'Rendered: no (soffice: not installed)' || echo "line: $NOSOFF_OUT")"
  fi
  printf 'Source: S1\n\nno structure here\n' >"$TMP_ROOT/plain.md"
  python3 -I "$XLSX_PY" "$FIX_DIR/fixture.xlsx" >"$TMP_ROOT/structured.md" 2>/dev/null
  render_run --only-if-structured "$TMP_ROOT/plain.md" --excel-cmd "$FIX_DIR/fake-excel" --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  GATE_PLAIN="$R_OUT"
  render_run --only-if-structured "$TMP_ROOT/structured.md" --excel-cmd "$FIX_DIR/fake-fail" --soffice "$FIX_DIR/fake-soffice" --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  GATE_STRUCT="$R_OUT"
  render_run --chain soffice --only-if-structured "$TMP_ROOT/plain.md" --soffice "$FIX_DIR/fake-soffice" --out "$RENDER_OUT" -- "$FIX_DIR/fixture.xlsx"
  check "sheet renderer: --only-if-structured skips a converter output without shapes, images, cells layout or merges, unless a renderer is forced" \
    "$(printf '%s\n' "$GATE_PLAIN" | grep -qxF 'Rendered: no (not structured)' || echo "plain: $GATE_PLAIN")$(printf '%s\n' "$GATE_STRUCT" | grep -q '(by soffice, ' || echo " structured: $GATE_STRUCT")$(printf '%s\n' "$R_OUT" | grep -q '(by soffice, ' || echo " forced: $R_OUT")"
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
else
  fail "xlsx converter checks" "python3 is not on the PATH"
fi

# Kill switches are real request tokens: Argument Parsing defines them, the
# rubric's Terminology entry resolves them, and spawns forward them.
ARGS_SECTION="$(awk '/^## Argument Parsing$/ {a = 1; next} a && /^## / {a = 0} a' "$SKILL_MD")"
TERM_ENTRY="$(grep -E '^- \*\*Policy kill switch\*\*:' "$GEN_RUBRIC" || true)"
MISSING=""
for key in oracle_verification independent_evidence failure_class_coverage peer_uniformity; do
  printf '%s\n' "$ARGS_SECTION" | grep -qF -- "\`$key\`" || MISSING="$MISSING SKILL.md:'$key'"
  grep -qF -- "constraint_$key" "$GEN_RUBRIC" || MISSING="$MISSING rubric:'constraint_$key'"
done
# shellcheck disable=SC2016  # literal backticks
printf '%s\n' "$ARGS_SECTION" | grep -qF -- '`constraint_<key>=off`' || MISSING="$MISSING SKILL.md:'constraint_<key>=off'"
printf '%s\n' "$TERM_ENTRY" | grep -qF -- 'constraint_<key>=off' || MISSING="$MISSING rubric-Terminology:'constraint_<key>=off'"
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
references/destinations.md|contains a character the curl config cannot carry
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
for needle in '**Platform item URLs**' '**access channel**' '**Best guess**' '**Auth**' '**Sign-in rule**' 'source_content_path=' 'source_auth_scheme=' 'content_type=' 'auth_scheme=' '{scratch}/template-derived.json' 'Derived: input from' 'Derived: output from' 'Derived:' 'Tried: input <item URL without query> via <channel>' 'Probe: output <item URL without query> via <channel>' '**read probe**' 'sign-in page even with a 2xx status' 'once a create has been attempted, nothing falls through' '**re-run tokens**' 'it never reads a value and never prints one' 'the name it uses is always printed on the `Resolved:` line' 'never written into the dossier, a ticket, the Final summary or a spawn prompt' '`source=cli:<command>`' '`source=browser:<item URL>`' '`destination=cli:<command template>`' '`destination=browser:<item URL>`' 'read every way instead of being asked about' 'percent-encoded' 'A `cli:` command (a source or a destination template, typed or derived) is exempt' 'ERROR: auth_scheme= must be bearer or basic' 'ERROR: source_auth_scheme= must be bearer or basic' 'ERROR: content_type= applies only to an api: destination' 'ERROR: auth_scheme= applies only to an api: destination' 'ERROR: source_auth_scheme= applies only to an api: source'; do
  printf '%s\n' "$ARGS_SECTION" | grep -qF -- "$needle" || MISSING="$MISSING SKILL.md-Argument-Parsing:'$needle'"
done
HOST_SECTION="$(awk '/^## Host notes$/ {h = 1; next} h && /^## / {h = 0} h' "$SKILL_MD")"
# shellcheck disable=SC2016  # literal backticks and dollars
for needle in 'spells out the tokens to pass' 'the **browser tool**' 'never required' 'no `browser:` channel is ever a candidate' 'with one carve-out: a `cli:` command, typed or derived, runs as given and is printed in full before it runs' '`$VAR` references are allowed' 'control characters and newlines are refused' 'may name an account'; do
  printf '%s\n' "$HOST_SECTION" | grep -qF -- "$needle" || MISSING="$MISSING SKILL.md-Host-notes:'$needle'"
done
# shellcheck disable=SC2016  # literal backticks
printf '%s\n' "$HOST_SECTION" | grep -qF -- 'any other role except the URL-fetch tool → `ERROR: this host offers no <role>`' || MISSING="$MISSING SKILL.md-Host-notes:'browser tool exempt from the missing-role ERROR'"
INTAKE_SECTION="$(awk '/^## Intake$/ {h = 1; next} h && /^## / {h = 0} h' "$SKILL_MD")"
# shellcheck disable=SC2016  # literal backticks
for needle in 'source_content_path=' 'Derived from:' '`cli:` by one run of the command' '`browser:` by the browser tool' 'Tried:' 'a `cli:` command'"'"'s first word'; do
  printf '%s\n' "$INTAKE_SECTION" | grep -qF -- "$needle" || MISSING="$MISSING SKILL.md-Intake:'$needle'"
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
printf '%s\n' "$DESC" | grep -qF -- 'a signed-in command-line' || MISSING="$MISSING description:'signed-in command-line client'"
printf '%s\n' "$DESC" | grep -qF -- 'browser-automation tool of the session' || MISSING="$MISSING description:'browser-automation tool of the session'"
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
  case "$where" in *a*) printf '%s\n' "$ARGS_SECTION" | grep -qF -- "$needle" || MISSING="$MISSING Argument-Parsing:'$needle'" ;; esac
  case "$where" in *e*) printf '%s\n' "$ERR_SECTION" | grep -qF -- "$needle" || MISSING="$MISSING Error-Handling:'$needle'" ;; esac
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
for needle in 'sources exceed the intake limit' 'must be kebab-case' 'max 2 rounds' '8-ticket cap' 'which were not read' 'must be a relative path inside the repository' 'If ANY sub-ticket FAILs' 'a URL is `api:`' 'a bare URL stays `api:`' 'is read as `api:`' 'after two rounds' 'initial + 1 revision' '(decomposer: 1000' 'nothing is read or written before them' 'a required parameter `<name>`' 'an `mcp:` or `api:` destination' 'or no ask-user tool at all' 'and only here' 'No directories created' 'no directory writes' 'the API with a token variable the request names' 'the API with a named'; do
  h="$(grep -rniF -- "$needle" "$SKILL_DIR" | cut -c1-160 || true)"
  [ -z "$h" ] || STALE="$STALE
[$needle] $h"
done
check "no literal the audit removed remains (intake ERROR, kebab ERROR, fixed round and ticket caps, dir subdirectory WARNING, relative-only local:, atomic FAIL, URL-is-api inference, one-place ~ rule, destination-neutral stop, named-variable candidate slot)" "${STALE#$'\n'}"

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
    printf '%s\n' "$sect" | grep -qF -- "$needle" || MISSING="$MISSING destinations.md-$kind:'$needle'"
  done
done
check "rounds=, max_tickets= (Max tickets: line, overflow file), the B1 preflight confirmation check, the declined literal, follow-up reads, per-source derived values and the text probe are documented where they apply" "$MISSING"

# The argument-hint omits the per-kind api: and cli: options; the Usage line
# adds those option groups. Every other part of the two must stay identical,
# the five destination kinds included.
HINT_VALUE="$(printf '%s\n' "$FM" | sed -n 's/^argument-hint: "\(.*\)"$/\1/p')"
# shellcheck disable=SC2016  # literal backticks
USAGE_VALUE="$(printf '%s\n' "$ARGS_SECTION" | grep -oE 'print `Usage: /create-ticket [^`]*`' | sed -e 's|^print `Usage: /create-ticket ||' -e 's|`$||')"
USAGE_STRIPPED="$USAGE_VALUE"
MISSING=""
for group in '[source_auth_env=<VAR>]' '[source_auth_scheme=bearer|basic]' '[source_content_path=<jq path>]' '[auth_env=<VAR>]' '[auth_scheme=bearer|basic]' '[template=<path>]' '[id_path=<path>]' '[content_type=<media type>]'; do
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
check "the Usage line names the api: source and destination options, both name the five destination kinds, and the two are otherwise equal" "$MISSING"

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
