#!/usr/bin/env bash
# Contract test for tools/build-copilot-skill.sh: the generated, standalone,
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
#     argument and the degraded branch; destinations.md defines all three kinds
#   - the constraint_<key>=off kill-switch tokens are parsed, resolved in the
#     rubric Terminology and forwarded; the planner gets the ticket template
#     by path; the new ERROR: literals are present
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
scripts/xlsx_to_text.py"
ACTUAL="$(cd "$SKILL_DIR" && find . -type f | sed 's#^\./##' | sort)"
check "tree holds exactly README.md + SKILL.md + the 17 shipped references + the xlsx converter" \
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
build-copilot-skill
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
for needle in '# create-ticket' '## Install' '## Usage' '/create-ticket' 'source=file:' 'destination=' 'SELF-EVALUATED' 'FAIL (user-accepted)' 'confirm=yes' 'scripts/xlsx_to_text.py' '## Limits'; do
  grep -qF -- "$needle" "$SKILL_DIR/README.md" || MISSING="$MISSING README.md:'$needle'"
done
check "README.md documents install, usage, sources, destinations, verdicts, files and limits" "$MISSING"
check "the default destination is local:.docs/tickets everywhere (no stale local:tickets)" \
  "$(grep -rn 'local:tickets' "$SKILL_DIR" | cut -c1-160 || true)$(grep -qF 'Absent → `local:.docs/tickets`' "$SKILL_MD" || echo ' SKILL.md lacks the .docs/tickets default')$(grep -qF '.docs/tickets/{parent-slug}' "$SKILL_DIR/references/write-path-templates.md" || echo ' summary examples lack .docs/tickets')"
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
for needle in 'parent=<id>' '?sheet=<name>' 'Resolved:' 'local:.docs/tickets'; do
  grep -qF -- "$needle" "$SKILL_DIR/README.md" || MISSING="$MISSING README.md:'$needle'"
done
grep -qF -- 'Parent: <id>' "$SKILL_DIR/references/write-path-templates.md" || MISSING="$MISSING write-path-templates.md:'Parent: <id>'"
check "prose resolution, the character rule, parent= and ?sheet= are documented where they apply" "$MISSING"
MISSING=""
# shellcheck disable=SC2016  # literal backticks
for needle in '## Writing a source' '**List split.**' '**Kind inference.**' '`mcp:` is never inferred' '### An MCP item named in prose' 'at most one lookup call is made per statement'; do
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
ct = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'''
rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'''
wb = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Backlog" sheetId="1" r:id="rId1"/><sheet name="Notes" sheetId="2" state="hidden" r:id="rId2"/></sheets></workbook>'''
wbrels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/><Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'''
sst = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="4" uniqueCount="4"><si><t>ID</t></si><si><t>Title</t></si><si><r><t>Add </t></r><r><rPr><b/></rPr><t>login | form</t></r><rPh sb="0" eb="3"><t>PHONETIC</t></rPh></si><si><t>Due</t></si></sst>'''
styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy/mm/dd"/></numFmts><cellXfs count="3"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/></cellXfs></styleSheet>'''
s1 = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>3</v></c><c r="D1" t="inlineStr"><is><t>Done</t></is></c></row>
<row r="2"><c r="A2"><v>1</v></c><c r="B2" t="s"><v>2</v></c><c r="C2" s="1"><v>45000</v></c><c r="D2" t="b"><v>1</v></c></row>
<row r="4"><c r="A4"><v>2.5</v></c><c r="B4" t="str"><f>CONCATENATE("a","b")</f><v>ab</v></c><c r="C4" s="2"><v>45000.5</v></c><c r="D4" t="e"><v>#N/A</v></c></row>
<row r="5"><c r="A5"><v>3</v></c><c r="BM5"><v>99</v></c></row>
</sheetData></worksheet>'''
s2 = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>hidden note</t></is></c></row></sheetData></worksheet>'''
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("[Content_Types].xml", ct); z.writestr("_rels/.rels", rels); z.writestr("xl/workbook.xml", wb)
    z.writestr("xl/_rels/workbook.xml.rels", wbrels); z.writestr("xl/sharedStrings.xml", sst); z.writestr("xl/styles.xml", styles)
    z.writestr("xl/worksheets/sheet1.xml", s1); z.writestr("xl/worksheets/sheet2.xml", s2)
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
  check "xlsx converter: shared / rich / inline strings, numbers, dates, booleans, errors, formulas, hidden sheets and the column cap" "$MISSING"
  XLSX_OUT2="$(python3 -I "$XLSX_PY" "$FIX_DIR/fixture.xlsx" --max-rows 2 --max-cols 3 2>/dev/null)"
  MISSING=""
  printf '%s\n' "$XLSX_OUT2" | grep -qF -- '[truncated: sheet Backlog has more than 2 rows; only the first 2 were read]' || MISSING="$MISSING 'row cap marker'"
  printf '%s\n' "$XLSX_OUT2" | grep -qF -- '[truncated: sheet Backlog has columns beyond c3' || MISSING="$MISSING 'column cap marker'"
  printf '%s\n' "$XLSX_OUT2" | grep -qF -- '| 4 |' && MISSING="$MISSING 'row 4 leaked past the cap'"
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
  (cd "$FIX_DIR" && python3 -c "import zipfile; zipfile.ZipFile('nowb.zip', 'w').writestr('a.txt', 'x')")
  set +e
  python3 -I "$XLSX_PY" "$FIX_DIR/make_fixture.py" >/dev/null 2>&1; NOT_ZIP_RC=$?
  python3 -I "$XLSX_PY" "$FIX_DIR/nowb.zip" >/dev/null 2>&1; NO_WB_RC=$?
  set -e
  check "xlsx converter: a non-zip file and a zip without a workbook exit 2" \
    "$([ "$NOT_ZIP_RC" -eq 2 ] || echo "not-zip rc=$NOT_ZIP_RC")$([ "$NO_WB_RC" -eq 2 ] || echo " no-workbook rc=$NO_WB_RC")"
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
SKILL.md|ERROR: cannot resolve FAIL gates non-interactively; re-run interactively (draft saved under {scratch})
references/agent-spawn-prompts.md|ERROR: cannot resolve FAIL gates non-interactively; re-run interactively (draft saved under {scratch})
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
SKILL.md|ERROR: unknown destination kind in destination=<spec without query>
NEEDLES
check "the new ERROR: literals are present where they are raised" "$MISSING"
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
