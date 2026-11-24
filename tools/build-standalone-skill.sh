#!/usr/bin/env bash
# build-standalone-skill.sh — generate a self-contained, host-neutral Agent
# Skill (SKILL.md + references/) from this plugin's sources, named
# `create-ticket` by default or any valid skill name given with --name.
#
# The output needs no plugin, no hooks and no custom agent files, and
# names tools by role, never by a host's tool name: drop it into the skill
# root the host reads (.github/skills/, .claude/skills/ or .agents/skills/)
# and invoke it by name. The output is never committed; correctness is
# enforced by the exit audit below and by tests/test-standalone-skill-build.sh.
#
# Usage:
#   bash tools/build-standalone-skill.sh --out <dir> [--name <skill-name>] [--src <dir>] [--force]
#   bash tools/build-standalone-skill.sh --help
#
# Inputs (tools/standalone-skill/, see its README.md):
#   files.tsv            shipped file map (destination <TAB> source, or "-"
#                        for a file whose whole content is an append override)
#   drop-sections.txt    sections removed by exact heading (scoped)
#   overrides/*.md       replacement / inserted section bodies
#   drop-paragraphs.txt  paragraphs / list items / table rows removed by ERE
#   substitutions.tsv    sed -E substitutions, applied in file order
#   denylist.txt         exit-audit EREs (any hit fails the build)
#   tool-vocabulary.txt  host tool names (allow) and foreign tool names (deny)
#
# Transform layers, in this order, per shipped file:
#   1. section drop / override by heading
#   2. paragraph drops by anchor ERE
#   3. token substitutions
#   4. exit audit over the whole generated tree
#   5. with --name: the canonical name `create-ticket` is replaced by the
#      chosen name in every generated file, then the name audit runs
# Every manifest entry must match at least once in its scope; a stale entry
# fails the build so the manifests never rot silently. The manifests always
# carry the canonical name: layers 1-4 build and audit the canonical text,
# and the chosen name is applied only to a tree whose exit audit is clean.
#
# Tooling: bash + sed/awk/grep only (BSD and GNU compatible, LC_ALL=C).

set -euo pipefail
export LC_ALL=C

print_help() {
  cat <<'EOF'
build-standalone-skill.sh — generate the standalone, host-neutral ticket-creation skill

Usage:
  bash tools/build-standalone-skill.sh --out <dir> [--name <skill-name>] [--src <dir>] [--force]
  bash tools/build-standalone-skill.sh --help

Options:
  --out <dir>          Output directory. The skill is written to <dir>/<skill-name>/.
  --name <skill-name>  Name of the generated skill (default: create-ticket): its
                       directory name, its frontmatter name and every place the
                       skill names itself (invocation, skill-root paths, scratch
                       directory, ERROR: messages). 1 to 64 lowercase ASCII
                       letters, digits and hyphens, no hyphen first, last or
                       next to another (^[a-z0-9]+(-[a-z0-9]+)*$). Refused: the
                       role names used inside the skill (planner, researcher,
                       decomposer, ticket-evaluator), a name YAML reads as a
                       number, boolean, null or date (123, true, yes, 1e3,
                       2024-01-01), and a name the exit audit would reject in
                       one of the places the name takes.
  --src <dir>          Plugin source root to read (default: this repository's
                       root). Manifests are always read from tools/standalone-skill/
                       next to this script. Its short git commit is stamped into
                       the frontmatter as metadata.source-commit ("unknown"
                       outside git).
  --force              Replace a non-empty <dir>/<skill-name>/ (refused otherwise).
                       Nothing else under <dir> is ever removed.
  --help               Print this message and exit 0.

Exit status:
  0  skill generated; the exit audit (and with --name, the name audit) is clean
  1  exit audit or name audit failed, or a manifest entry is stale (details
     on stderr)
  2  usage error (an invalid or reserved --name included), missing source
     file, malformed manifest row (a substitution target glued to its
     replacement), or refused overwrite
EOF
}

err() {
  printf '[build-standalone-skill] %s\n' "$*" >&2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="$SCRIPT_DIR/standalone-skill"
SRC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR=""
FORCE=0
# The canonical name: every manifest, override and audit rule is written
# with it; --name replaces it in the generated tree after the exit audit.
CANON_NAME="create-ticket"
NAME="$CANON_NAME"

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) print_help; exit 0 ;;
    --out) [ $# -ge 2 ] || { err "--out requires a value"; exit 2; }; OUT_DIR="$2"; shift 2 ;;
    --name) [ $# -ge 2 ] || { err "--name requires a value"; exit 2; }; NAME="$2"; shift 2 ;;
    --src) [ $# -ge 2 ] || { err "--src requires a value"; exit 2; }; SRC_ROOT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    *) err "unknown argument: $1 (see --help)"; exit 2 ;;
  esac
done

# --- name validation (before any filesystem action) ----------------------------

NAME_RULE='a skill name is 1 to 64 lowercase ASCII letters, digits and hyphens, with no hyphen first, last or next to another (^[a-z0-9]+(-[a-z0-9]+)*$)'
# The name as printed in a message: control and non-ASCII bytes shown as '?'.
NAME_SHOWN="$(printf '%s' "$NAME" | tr -c '[:print:]' '?')"
case "$NAME" in
  ''|*[!a-z0-9-]*|-*|*-|*--*) err "invalid --name '$NAME_SHOWN': $NAME_RULE"; exit 2 ;;
esac
[ "${#NAME}" -le 64 ] || { err "invalid --name '$NAME_SHOWN' (${#NAME} characters): $NAME_RULE"; exit 2; }
# The frontmatter writes the name as a plain YAML scalar, so a name a YAML
# reader resolves to a number, a boolean, null or a date (YAML 1.1 or 1.2) is
# refused: the frontmatter name would not be the name.
if grep -qxE '(null|true|false|yes|no|on|off|y|n|[0-9]+|0x[0-9a-f]+|0o[0-7]+|0b[01]+|[0-9]+e-?[0-9]+|[0-9]{4}-[0-9]{2}-[0-9]{2})' <<<"$NAME"; then
  err "invalid --name '$NAME': a YAML reader takes it for a number, a boolean, null or a date, not a string, so the frontmatter name of SKILL.md would not be the name"
  exit 2
fi
case "$NAME" in
  planner|researcher|decomposer|ticket-evaluator)
    err "reserved --name '$NAME': planner, researcher, decomposer and ticket-evaluator are the role names used inside the skill, whose role prompts tell each role never to run the skill by its name"
    exit 2 ;;
esac

[ -n "$OUT_DIR" ] || { err "--out is required (see --help)"; exit 2; }
[ -d "$SRC_ROOT" ] || { err "--src is not a directory: $SRC_ROOT"; exit 2; }
SRC_ROOT="$(cd "$SRC_ROOT" && pwd)"
[ -d "$MANIFEST_DIR" ] || { err "manifest directory missing: $MANIFEST_DIR"; exit 2; }

# Read a manifest, dropping comment and blank lines.
manifest_lines() {
  grep -vE '^[[:space:]]*(#|$)' "$1" || true
}

# Foreign tool names of the exit audit (tool-vocabulary.txt "deny <Name>").
DENY_TOOLS="$(manifest_lines "$MANIFEST_DIR/tool-vocabulary.txt" | awk '$1 == "deny" {printf "%s%s", sep, $2; sep = "|"}')"
# shellcheck disable=SC2016  # literal backticks, no expansion intended
DENY_TOOLS_RE='`('"$DENY_TOOLS"')(\([^`]*\))?`'

# A name that would trip the exit audit: the probe holds the name in each
# context it takes in the generated tree, and a denylist or foreign-tool-name
# rule that matches a probe line with the name, but not the same line with
# the canonical name, refuses the name. The name audit after the rename is
# the backstop for a context the probe does not hold.
name_probe() {
  printf '%s\n' "/$1" "\`$1\`" ".claude/skills/$1/" ".local/$1-scratch/run.XXXXXX" \
    "ERROR: $1 write failed" "the $1 skill" "# $1" "name: $1"
}
# probe_findings LABEL ERE — one line per probe line the ERE matches with the
# name and not with the canonical name.
probe_findings() {
  local hc hn ln
  hc=" $(name_probe "$CANON_NAME" | { grep -nE -- "$2" || true; } | cut -d: -f1 | tr '\n' ' ')"
  hn="$(name_probe "$NAME" | { grep -nE -- "$2" || true; } | cut -d: -f1)"
  for ln in $hn; do
    case "$hc" in *" $ln "*) continue ;; esac
    printf '%s matches "%s"\n' "$1" "$(name_probe "$NAME" | sed -n "${ln}p")"
  done
}
if [ "$NAME" != "$CANON_NAME" ]; then
  PROBE_FAIL="$(
    while IFS= read -r pat; do
      probe_findings "denylist rule [$pat] (denylist.txt)" "$pat"
    done < <(manifest_lines "$MANIFEST_DIR/denylist.txt")
    if [ -n "$DENY_TOOLS" ]; then
      probe_findings "foreign tool name rule (a deny row of tool-vocabulary.txt)" "$DENY_TOOLS_RE"
    fi
  )"
  if [ -n "$PROBE_FAIL" ]; then
    err "invalid --name '$NAME': the generated text would fail the exit audit with this name:"
    printf '%s\n' "$PROBE_FAIL" | sed 's/^/  /' >&2
    exit 2
  fi
fi

PLUGIN_JSON="$SRC_ROOT/.claude-plugin/plugin.json"
[ -f "$PLUGIN_JSON" ] || { err "missing $PLUGIN_JSON"; exit 2; }
SOURCE_VERSION="$(sed -nE 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$PLUGIN_JSON" | head -n 1)"
[ -n "$SOURCE_VERSION" ] || { err "cannot read version from $PLUGIN_JSON"; exit 2; }
# Short commit of the source tree; "unknown" when --src is not a git
# repository or git is not on PATH.
SOURCE_COMMIT=""
if command -v git >/dev/null 2>&1; then
  SOURCE_COMMIT="$(git -C "$SRC_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
fi
printf '%s\n' "$SOURCE_COMMIT" | grep -qxE '[0-9a-f]{7,40}' || SOURCE_COMMIT="unknown"

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
TARGET="$OUT_DIR/$NAME"
if [ -d "$TARGET" ] && [ -n "$(ls -A "$TARGET")" ]; then
  if [ "$FORCE" -ne 1 ]; then
    err "refusing to overwrite non-empty $TARGET (pass --force)"
    exit 2
  fi
  [ "$(basename "$TARGET")" = "$NAME" ] || { err "unexpected target $TARGET"; exit 2; }
  rm -rf "$TARGET"
fi
mkdir -p "$TARGET"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/build-standalone-skill.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
STALE="$WORK/stale.txt"
: >"$STALE"

DELIM="$(printf '\001')"

# scope_match DEST GLOB — bash pattern match ('*' matches across '/').
scope_match() {
  # shellcheck disable=SC2053
  [[ $1 == $2 ]]
}

# Glued-target guard: a two-field row whose replacement ends in a generated
# file path (SKILL.md, README.md or references/<path>.md) directly preceded
# by sentence punctuation lost the TAB before its target file. Such a row
# would apply to every file and glue the file name onto the output text, so
# it fails the build. A replacement that is itself a path (\1SKILL.md) is
# preceded by a backreference or a space and passes.
GLUED_RE='[].)!?:;,*`'"'\""'](SKILL\.md|README\.md|references/[A-Za-z0-9_./-]+\.md)$'
GLUED="$(RE="$GLUED_RE" awk -F'\t' '
  /^[[:space:]]*(#|$)/ { next }
  NF == 2 && match($2, ENVIRON["RE"]) {
    printf "substitutions.tsv line %d: the replacement ends in \"%s\" glued to the text before it; a TAB is missing before the target file\n", NR, substr($2, RSTART + 1)
  }' "$MANIFEST_DIR/substitutions.tsv")"
if [ -n "$GLUED" ]; then
  printf '%s\n' "$GLUED" | while IFS= read -r g; do err "$g"; done
  exit 2
fi

# --- Layer 0: copy sources ------------------------------------------------

# Source "-" marks a file with no plugin source: it starts empty and an
# "append" override supplies its whole content.
DESTS=()
PURE=()
while IFS=$'\t' read -r dest src; do
  [ -n "$dest" ] || continue
  if [ "$src" = "-" ]; then
    mkdir -p "$(dirname "$TARGET/$dest")"
    : >"$TARGET/$dest"
    DESTS+=("$dest")
    PURE+=("$dest")
    continue
  fi
  if [ ! -f "$SRC_ROOT/$src" ]; then
    err "source file missing: $src"
    exit 2
  fi
  mkdir -p "$(dirname "$TARGET/$dest")"
  case "$dest" in
    references/agents/*)
      # Agent bodies become task prompts: strip the frontmatter block.
      awk 'NR==1 && $0=="---" {fm=1; next}
           fm && $0=="---" {fm=0; skip=1; next}
           fm {next}
           skip && $0=="" {skip=0; next}
           {skip=0; print}' "$SRC_ROOT/$src" >"$TARGET/$dest"
      ;;
    *) cat "$SRC_ROOT/$src" >"$TARGET/$dest" ;;
  esac
  DESTS+=("$dest")
done < <(manifest_lines "$MANIFEST_DIR/files.tsv")

# --- Layer 1: sections ----------------------------------------------------

# section_op FILE HEADING OP CONTENT_FILE — OP is drop|replace|before|after.
# A section runs from its heading to the next heading of the same or a
# higher level at the same fence depth, so a heading inside a fenced
# template block never swallows the fence that closes it.
# HEADING "(frontmatter)" addresses the leading YAML frontmatter block.
section_op() {
  local file="$1" heading="$2" op="$3" content="$4"
  local rc=0
  H="$heading" OP="$op" CF="$content" awk '
    function lvl(s) { match(s, /^#+/); return RLENGTH }
    function isfence(s) { return s ~ /^ ? ? ?(```|~~~)/ }
    BEGIN {
      H = ENVIRON["H"]; OP = ENVIRON["OP"]; CF = ENVIRON["CF"]
      body = ""
      if (CF != "") {
        while ((getline l < CF) > 0) { body = body l "\n"; last = l }
        if (last != "") body = body "\n"
      }
      fs = 0; found = 0; inside = 0
    }
    {
      line = $0
      if (H == "(frontmatter)") {
        if (NR == 1 && line == "---") { found = 1; inside = 1; next }
        if (inside) { if (line == "---") { inside = 0; printf "%s", body } ; next }
        print line; next
      }
      if (inside) {
        if (fs == hfs && line ~ /^#+ / && lvl(line) <= hl) {
          inside = 0
          if (OP == "after") printf "%s", body
        } else {
          if (isfence(line)) fs = !fs
          if (OP == "before" || OP == "after") print line
          next
        }
      }
      if (!found && line == H) {
        found = 1; inside = 1; hl = lvl(H); hfs = fs
        if (OP == "replace") printf "%s", body
        else if (OP == "before") { printf "%s", body; print line }
        else if (OP == "after") print line
        next
      }
      if (isfence(line)) fs = !fs
      print line
    }
    END {
      if (inside && OP == "after") printf "%s", body
      if (!found) exit 3
    }' "$file" >"$file.tmp" || rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -f "$file.tmp"
    return "$rc"
  fi
  mv "$file.tmp" "$file"
}

append_content() {
  local file="$1" content="$2"
  { printf '\n'; cat "$content"; } >>"$file"
}

# Drop sections: "<dest-glob><TAB><exact heading line>".
while IFS=$'\t' read -r glob heading; do
  [ -n "$glob" ] || continue
  hit=0
  for dest in "${DESTS[@]}"; do
    scope_match "$dest" "$glob" || continue
    if section_op "$TARGET/$dest" "$heading" drop ""; then hit=1; fi
  done
  [ "$hit" -eq 1 ] || printf 'drop-sections.txt: heading not found in %s: %s\n' "$glob" "$heading" >>"$STALE"
done < <(manifest_lines "$MANIFEST_DIR/drop-sections.txt")

# Overrides: header lines "target:", "heading:", "mode:", then a "---" line,
# then the content. target may list several destinations (space-separated).
for ovr in "$MANIFEST_DIR"/overrides/*.md; do
  [ -f "$ovr" ] || continue
  o_target="$(sed -n 's/^target:[[:space:]]*//p' "$ovr" | head -n 1)"
  o_heading="$(sed -n 's/^heading:[[:space:]]*//p' "$ovr" | head -n 1)"
  o_mode="$(sed -n 's/^mode:[[:space:]]*//p' "$ovr" | head -n 1)"
  content="$WORK/$(basename "$ovr").content"
  awk 'done {print; next} $0 == "---" {done = 1}' "$ovr" >"$content"
  case "$o_mode" in
    replace|before|after|append) ;;
    *) err "override $(basename "$ovr"): invalid mode '$o_mode'"; exit 2 ;;
  esac
  for dest in $o_target; do
    if [ ! -f "$TARGET/$dest" ]; then
      printf 'overrides/%s: target not shipped: %s\n' "$(basename "$ovr")" "$dest" >>"$STALE"
      continue
    fi
    if [ "$o_mode" = "append" ]; then
      append_content "$TARGET/$dest" "$content"
    elif ! section_op "$TARGET/$dest" "$o_heading" "$o_mode" "$content"; then
      printf 'overrides/%s: heading not found in %s: %s\n' "$(basename "$ovr")" "$dest" "$o_heading" >>"$STALE"
    fi
  done
done

# A file with no plugin source must have received its content from an override.
for dest in ${PURE[@]+"${PURE[@]}"}; do
  grep -q '[^[:space:]]' "$TARGET/$dest" || printf 'files.tsv: %s has no source and no override filled it\n' "$dest" >>"$STALE"
done

# --- Layer 2: paragraph drops ---------------------------------------------

# drop_paragraphs FILE ERE — exit 3 when the ERE matches nothing.
# A hit on a list item drops that item (plus its indented continuation), a
# hit on a table row or on a line inside a fenced block drops that line
# only, and any other hit drops its whole paragraph (up to blank lines,
# headings and fences).
drop_paragraphs() {
  local file="$1" ere="$2"
  local rc=0
  RE="$ere" awk '
    function isfence(s) { return s ~ /^ ? ? ?(```|~~~)/ }
    function isitem(s) { return s ~ /^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]/ }
    function stop(s) { return s == "" || s ~ /^#+ / || isfence(s) }
    BEGIN { RE = ENVIRON["RE"] }
    { line[NR] = $0 }
    END {
      fs = 0
      for (i = 1; i <= NR; i++) {
        if (isfence(line[i])) { infence[i] = 0; fs = !fs } else infence[i] = fs
      }
      hits = 0
      for (i = 1; i <= NR; i++) {
        if (drop[i] || line[i] !~ RE) continue
        hits++
        if (infence[i] || line[i] ~ /^[[:space:]]*\|/) { drop[i] = 1; continue }
        if (isitem(line[i])) {
          drop[i] = 1
          for (j = i + 1; j <= NR && !stop(line[j]) && !isitem(line[j]) && line[j] ~ /^[[:space:]]/; j++) drop[j] = 1
          continue
        }
        s = i; while (s > 1 && !stop(line[s - 1]) && !infence[s - 1]) s--
        e = i; while (e < NR && !stop(line[e + 1]) && !infence[e + 1]) e++
        for (j = s; j <= e; j++) drop[j] = 1
      }
      for (i = 1; i <= NR; i++) if (!drop[i]) print line[i]
      if (hits == 0) exit 3
    }' "$file" >"$file.tmp" || rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -f "$file.tmp"
    return "$rc"
  fi
  mv "$file.tmp" "$file"
}

while IFS=$'\t' read -r glob ere; do
  [ -n "$glob" ] || continue
  hit=0
  for dest in "${DESTS[@]}"; do
    scope_match "$dest" "$glob" || continue
    if drop_paragraphs "$TARGET/$dest" "$ere"; then hit=1; fi
  done
  [ "$hit" -eq 1 ] || printf 'drop-paragraphs.txt: no match in %s: %s\n' "$glob" "$ere" >>"$STALE"
done < <(manifest_lines "$MANIFEST_DIR/drop-paragraphs.txt")

# --- Layer 3: substitutions -----------------------------------------------

# "<ERE><TAB><replacement>[<TAB><dest-glob>]"; sed -E replacement syntax
# (& is the whole match, \1..\9 are groups, \& is a literal ampersand).
# Fields are split by hand: `read` would collapse an empty replacement.
TAB=$'\t'
while IFS= read -r row; do
  pat="${row%%"$TAB"*}"
  rep=""; glob=""
  if [ "$pat" != "$row" ]; then
    rest="${row#*"$TAB"}"
    rep="${rest%%"$TAB"*}"
    [ "$rep" = "$rest" ] || glob="${rest#*"$TAB"}"
  fi
  [ -n "$pat" ] || continue
  glob="${glob:-*}"
  case "$pat$rep" in *"$DELIM"*) err "substitution contains the delimiter: $pat"; exit 2 ;; esac
  hit=0
  for dest in "${DESTS[@]}"; do
    scope_match "$dest" "$glob" || continue
    f="$TARGET/$dest"
    if grep -qE -- "$pat" "$f"; then
      sed -E "s${DELIM}${pat}${DELIM}${rep}${DELIM}g" "$f" >"$f.tmp"
      mv "$f.tmp" "$f"
      hit=1
    fi
  done
  [ "$hit" -eq 1 ] || printf 'substitutions.tsv: no match in %s: %s\n' "$glob" "$pat" >>"$STALE"
done < <(manifest_lines "$MANIFEST_DIR/substitutions.tsv")

# Normalise: collapse blank-line runs, strip leading/trailing blank lines.
for dest in "${DESTS[@]}"; do
  f="$TARGET/$dest"
  awk 'NF == 0 { blank = 1; next }
       { if (blank && printed) print ""; blank = 0; printed = 1; print }' "$f" >"$f.tmp"
  mv "$f.tmp" "$f"
done

# Frontmatter placeholders: the version from plugin.json and the source commit.
sed -E -e "s${DELIM}@SOURCE_VERSION@${DELIM}${SOURCE_VERSION}${DELIM}g" \
  -e "s${DELIM}@SOURCE_COMMIT@${DELIM}${SOURCE_COMMIT}${DELIM}g" "$TARGET/SKILL.md" >"$TARGET/SKILL.md.tmp"
mv "$TARGET/SKILL.md.tmp" "$TARGET/SKILL.md"

# --- Layer 4: exit audit --------------------------------------------------

FAIL="$WORK/audit.txt"
: >"$FAIL"

# prefix TEXT — prepend TEXT verbatim (no escape processing) to each line.
prefix() {
  P="$1" awk '{ print ENVIRON["P"] $0 }'
}
cat "$STALE" >>"$FAIL"

GEN_FILES=()
while IFS= read -r f; do GEN_FILES+=("$f"); done < <(cd "$TARGET" && find . -type f | sed 's#^\./##' | sort)

# Checks (a), (b) and (e) run again in the name audit (Layer 5); LABEL
# prefixes each finding ("" in the exit audit).

# (a) denylist
audit_denylist() {
  while IFS= read -r pat; do
    for f in "${GEN_FILES[@]}"; do
      (cd "$TARGET" && grep -nE -- "$pat" "$f" || true) | prefix "${1}denylist [$pat] $f:" | cut -c1-240
    done
  done < <(manifest_lines "$MANIFEST_DIR/denylist.txt")
}
audit_denylist "" >>"$FAIL"

# (b) foreign tool names in backticks (tool-vocabulary.txt "deny <Name>",
#     read into DENY_TOOLS before the build)
audit_tool_names() {
  [ -n "$DENY_TOOLS" ] || return 0
  for f in "${GEN_FILES[@]}"; do
    (cd "$TARGET" && grep -nE -- "$DENY_TOOLS_RE" "$f" || true) | prefix "${1}foreign tool name $f:" | cut -c1-240
  done
}
audit_tool_names "" >>"$FAIL"

# (c) English only: no CJK / Hangul / fullwidth lead bytes (U+3000..U+D7FF).
CJK="$(printf '[\343-\355]')"
for f in "${GEN_FILES[@]}"; do
  (cd "$TARGET" && grep -nE -- "$CJK" "$f" || true) | prefix "non-English text $f:" | cut -c1-120 >>"$FAIL"
done

# (d) relative links and backticked references/ paths resolve in the tree
for f in "${GEN_FILES[@]}"; do
  case "$f" in *.md) ;; *) continue ;; esac
  fdir="$(dirname "$f")"
  { grep -noE '\]\([^)[:space:]]+\)' "$TARGET/$f" || true; } | while IFS= read -r m; do
    ln="${m%%:*}"; link="${m#*:](}"; link="${link%)}"; link="${link%%#*}"
    case "$link" in ''|http://*|https://*|mailto:*) continue ;; esac
    [ -f "$TARGET/$fdir/$link" ] || printf 'broken link %s:%s: %s\n' "$f" "$ln" "$link" >>"$FAIL"
  done
  # shellcheck disable=SC2016  # literal backticks, no expansion intended
  { grep -noE '`references/[A-Za-z0-9_./-]+`' "$TARGET/$f" || true; } | while IFS= read -r m; do
    ln="${m%%:*}"; p="${m#*:\`}"; p="${p%\`}"
    [ -e "$TARGET/$p" ] || printf 'unresolved path %s:%s: %s\n' "$f" "$ln" "$p" >>"$FAIL"
  done
done

# (e) inline code spans stay balanced outside fences (catches a substitution
#     that nests a backticked token inside a backticked phrase)
audit_backticks() {
  for f in "${GEN_FILES[@]}"; do
    awk -v F="$f" -v L="$1" '/^ ? ? ?(```|~~~)/ { fz = !fz; next }
      !fz { n = gsub(/`/, "`"); if (n % 2) printf "%sunbalanced backticks %s:%d\n", L, F, NR }' "$TARGET/$f"
  done
}
audit_backticks "" >>"$FAIL"

# (f) frontmatter
FM="$(awk 'NR == 1 && $0 == "---" {fm = 1; next} fm && $0 == "---" {exit} fm {print}' "$TARGET/SKILL.md")"
printf '%s\n' "$FM" | grep -qx 'name: create-ticket' || printf 'frontmatter: name is not create-ticket\n' >>"$FAIL"
if printf '%s\n' "$FM" | grep -q '^allowed-tools:'; then printf 'frontmatter: allowed-tools must be omitted\n' >>"$FAIL"; fi
DESC_LEN="$(printf '%s\n' "$FM" | awk '/^description:/ {d = 1; next} d && /^[a-z-]+:/ {d = 0} d {sub(/^ +/, ""); s = s (s == "" ? "" : " ") $0} END {printf "%d", length(s)}')"
{ [ "$DESC_LEN" -gt 0 ] && [ "$DESC_LEN" -le 1024 ]; } || printf 'frontmatter: description length %s not in 1..1024\n' "$DESC_LEN" >>"$FAIL"
printf '%s\n' "$FM" | grep -qE '^  source-commit: "([0-9a-f]{7,40}|unknown)"$' || printf 'frontmatter: metadata.source-commit missing or malformed\n' >>"$FAIL"

# (g) rubric parity (zero-loss: renaming only)
SRC_RUBRIC="$SRC_ROOT/skills/create-ticket/references/ac-quality-criteria.md"
GEN_RUBRIC="$TARGET/references/ac-quality-criteria.md"
gates() { grep -E '^#{2,3} Gate ' "$1" || true; }
terms() { awk '/^## Terminology/ {t = 1; next} t && /^## / {t = 0} t && /^- \*\*/ {n++} END {printf "%d", n}' "$1"; }
if [ "$(gates "$SRC_RUBRIC")" != "$(gates "$GEN_RUBRIC")" ]; then
  printf 'rubric parity: Gate heading set differs from the source\n' >>"$FAIL"
fi
[ "$(terms "$SRC_RUBRIC")" = "$(terms "$GEN_RUBRIC")" ] || printf 'rubric parity: Terminology entry count differs\n' >>"$FAIL"
SRC_WC="$(wc -w <"$SRC_RUBRIC" | tr -d ' ')"
GEN_WC="$(wc -w <"$GEN_RUBRIC" | tr -d ' ')"
DELTA=$((GEN_WC - SRC_WC)); [ "$DELTA" -ge 0 ] || DELTA=$((-DELTA))
[ $((DELTA * 100)) -le $((SRC_WC * 5)) ] || printf 'rubric parity: word count %s vs source %s (> 5%%)\n' "$GEN_WC" "$SRC_WC" >>"$FAIL"

if [ -s "$FAIL" ]; then
  CANON_NOTE=""
  [ "$NAME" = "$CANON_NAME" ] || CANON_NOTE=" (still the canonical text: --name is applied only after a clean exit audit)"
  err "exit audit FAILED ($(wc -l <"$FAIL" | tr -d ' ') finding(s)); output left at $TARGET for inspection$CANON_NOTE:"
  sed 's/^/  /' "$FAIL" >&2
  exit 1
fi

if [ "$NAME" = "$CANON_NAME" ]; then
  printf '[build-standalone-skill] wrote %s (%s files, source version %s, commit %s); exit audit clean\n' \
    "$TARGET" "${#GEN_FILES[@]}" "$SOURCE_VERSION" "$SOURCE_COMMIT"
  exit 0
fi

# --- Layer 5: the chosen name and the name audit ----------------------------

# The generated tree names the skill only by the exact token create-ticket
# (no case, underscore or line-wrapped variant), so one sed pass per file
# renames it; the validated name needs no escaping in sed. The name audit
# then proves the pass per file: the occurrences of the name, minus those the
# canonical text already held (counted with every create-ticket masked),
# equal the create-ticket occurrences counted before the pass, and no
# create-ticket is left outside an occurrence of the name. Every check that
# the name can change runs again on the renamed tree; the canonical tree
# passed the exit audit, so any finding is caused by the name.
NFAIL="$WORK/name-audit.txt"
: >"$NFAIL"
NLABEL="name audit (caused by --name $NAME): "
MASK="$(printf '\002')"
# count_in WORD — occurrences (not lines) of WORD on standard input.
count_in() { { grep -oF -- "$1" || true; } | wc -l | tr -d ' '; }
RENAMED=0
for f in "${GEN_FILES[@]}"; do
  p="$TARGET/$f"
  c="$(count_in "$CANON_NAME" <"$p")"
  [ "$c" -gt 0 ] || continue
  base="$(sed "s/$CANON_NAME/$MASK/g" "$p" | count_in "$NAME")"
  sed "s/$CANON_NAME/$NAME/g" "$p" >"$p.tmp"
  mv "$p.tmp" "$p"
  after="$(count_in "$NAME" <"$p")"
  [ $((after - base)) -eq "$c" ] ||
    printf '%s%s: %s occurrence(s) of the name after the rename, expected %s (%s of create-ticket renamed, %s of the name already in the text)\n' \
      "$NLABEL" "$f" "$after" $((base + c)) "$c" "$base" >>"$NFAIL"
  RENAMED=$((RENAMED + c))
done
for f in "${GEN_FILES[@]}"; do
  case "$NAME" in
    *"$CANON_NAME"*) left="$(sed "s/$NAME/$MASK/g" "$TARGET/$f" | count_in "$CANON_NAME")" ;;
    *) left="$(count_in "$CANON_NAME" <"$TARGET/$f")" ;;
  esac
  [ "$left" -eq 0 ] || printf '%s%s: %s occurrence(s) of create-ticket left after the rename\n' "$NLABEL" "$f" "$left" >>"$NFAIL"
done

FM_N="$(awk 'NR == 1 && $0 == "---" {fm = 1; next} fm && $0 == "---" {exit} fm {print}' "$TARGET/SKILL.md")"
FM_N_NAME="$(printf '%s\n' "$FM_N" | sed -n 's/^name: //p')"
{ [ "$FM_N_NAME" = "$NAME" ] && [ "$FM_N_NAME" = "$(basename "$TARGET")" ]; } ||
  printf '%sfrontmatter: name is "%s", not the name and directory name %s\n' "$NLABEL" "$FM_N_NAME" "$NAME" >>"$NFAIL"
DESC_LEN_N="$(printf '%s\n' "$FM_N" | awk '/^description:/ {d = 1; next} d && /^[a-z-]+:/ {d = 0} d {sub(/^ +/, ""); s = s (s == "" ? "" : " ") $0} END {printf "%d", length(s)}')"
if [ "$DESC_LEN_N" -gt 1024 ]; then
  printf '%sfrontmatter: description length %s not in 1..1024: the name is too long for the description (%s characters with this %s-character name, %s with create-ticket)\n' \
    "$NLABEL" "$DESC_LEN_N" "$DESC_LEN_N" "${#NAME}" "$DESC_LEN" >>"$NFAIL"
elif [ "$DESC_LEN_N" -lt 1 ]; then
  printf '%sfrontmatter: description length %s not in 1..1024\n' "$NLABEL" "$DESC_LEN_N" >>"$NFAIL"
fi

{
  audit_denylist "$NLABEL"
  audit_tool_names "$NLABEL"
  audit_backticks "$NLABEL"
} >>"$NFAIL"

if [ -s "$NFAIL" ]; then
  err "name audit FAILED ($(wc -l <"$NFAIL" | tr -d ' ') finding(s)); the name '$NAME' caused them, since the canonical text passed the exit audit; output left at $TARGET for inspection:"
  sed 's/^/  /' "$NFAIL" >&2
  exit 1
fi

printf '[build-standalone-skill] wrote %s (%s files, source version %s, commit %s); exit audit clean; name audit clean (%s occurrences of create-ticket renamed to %s)\n' \
  "$TARGET" "${#GEN_FILES[@]}" "$SOURCE_VERSION" "$SOURCE_COMMIT" "$RENAMED" "$NAME"
