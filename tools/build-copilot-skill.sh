#!/usr/bin/env bash
# build-copilot-skill.sh — generate a self-contained, host-neutral Agent
# Skill `create-ticket/` (SKILL.md + references/) from this plugin's sources.
#
# The output needs no plugin, no hooks and no custom agent files, and
# names tools by role, never by a host's tool name: drop it into the skill
# root the host reads (.github/skills/, .claude/skills/ or .agents/skills/)
# and invoke it by name. The output is never committed; correctness is
# enforced by the exit audit below and by tests/test-copilot-skill-build.sh.
#
# Usage:
#   bash tools/build-copilot-skill.sh --out <dir> [--src <dir>] [--force]
#   bash tools/build-copilot-skill.sh --help
#
# Inputs (tools/copilot-skill/, see its README.md):
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
# Every manifest entry must match at least once in its scope; a stale entry
# fails the build so the manifests never rot silently.
#
# Tooling: bash + sed/awk/grep only (BSD and GNU compatible, LC_ALL=C).

set -euo pipefail
export LC_ALL=C

print_help() {
  cat <<'EOF'
build-copilot-skill.sh — generate the standalone, host-neutral `create-ticket` skill

Usage:
  bash tools/build-copilot-skill.sh --out <dir> [--src <dir>] [--force]
  bash tools/build-copilot-skill.sh --help

Options:
  --out <dir>   Output directory. The skill is written to <dir>/create-ticket/.
  --src <dir>   Plugin source root to read (default: this repository's root).
                Manifests are always read from tools/copilot-skill/ next to
                this script. Its short git commit is stamped into the
                frontmatter as metadata.source-commit ("unknown" outside git).
  --force       Replace a non-empty <dir>/create-ticket/ (refused otherwise).
  --help        Print this message and exit 0.

Exit status:
  0  skill generated and the exit audit is clean
  1  exit audit failed or a manifest entry is stale (details on stderr)
  2  usage error, missing source file, or refused overwrite
EOF
}

err() {
  printf '[build-copilot-skill] %s\n' "$*" >&2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="$SCRIPT_DIR/copilot-skill"
SRC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) print_help; exit 0 ;;
    --out) [ $# -ge 2 ] || { err "--out requires a value"; exit 2; }; OUT_DIR="$2"; shift 2 ;;
    --src) [ $# -ge 2 ] || { err "--src requires a value"; exit 2; }; SRC_ROOT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    *) err "unknown argument: $1 (see --help)"; exit 2 ;;
  esac
done

[ -n "$OUT_DIR" ] || { err "--out is required (see --help)"; exit 2; }
[ -d "$SRC_ROOT" ] || { err "--src is not a directory: $SRC_ROOT"; exit 2; }
SRC_ROOT="$(cd "$SRC_ROOT" && pwd)"
[ -d "$MANIFEST_DIR" ] || { err "manifest directory missing: $MANIFEST_DIR"; exit 2; }

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
TARGET="$OUT_DIR/create-ticket"
if [ -d "$TARGET" ] && [ -n "$(ls -A "$TARGET")" ]; then
  if [ "$FORCE" -ne 1 ]; then
    err "refusing to overwrite non-empty $TARGET (pass --force)"
    exit 2
  fi
  [ "$(basename "$TARGET")" = "create-ticket" ] || { err "unexpected target $TARGET"; exit 2; }
  rm -rf "$TARGET"
fi
mkdir -p "$TARGET"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/build-copilot-skill.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
STALE="$WORK/stale.txt"
: >"$STALE"

DELIM="$(printf '\001')"

# Read a manifest, dropping comment and blank lines.
manifest_lines() {
  grep -vE '^[[:space:]]*(#|$)' "$1" || true
}

# scope_match DEST GLOB — bash pattern match ('*' matches across '/').
scope_match() {
  # shellcheck disable=SC2053
  [[ $1 == $2 ]]
}

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

# (a) denylist
while IFS= read -r pat; do
  for f in "${GEN_FILES[@]}"; do
    (cd "$TARGET" && grep -nE -- "$pat" "$f" || true) | prefix "denylist [$pat] $f:" | cut -c1-240 >>"$FAIL"
  done
done < <(manifest_lines "$MANIFEST_DIR/denylist.txt")

# (b) foreign tool names in backticks (tool-vocabulary.txt "deny <Name>")
DENY_TOOLS="$(manifest_lines "$MANIFEST_DIR/tool-vocabulary.txt" | awk '$1 == "deny" {printf "%s%s", sep, $2; sep = "|"}')"
if [ -n "$DENY_TOOLS" ]; then
  for f in "${GEN_FILES[@]}"; do
    (cd "$TARGET" && grep -nE -- "\`($DENY_TOOLS)(\\([^\`]*\\))?\`" "$f" || true) | prefix "foreign tool name $f:" | cut -c1-240 >>"$FAIL"
  done
fi

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
for f in "${GEN_FILES[@]}"; do
  awk -v F="$f" '/^ ? ? ?(```|~~~)/ { fz = !fz; next }
    !fz { n = gsub(/`/, "`"); if (n % 2) printf "unbalanced backticks %s:%d\n", F, NR }' "$TARGET/$f" >>"$FAIL"
done

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
  err "exit audit FAILED ($(wc -l <"$FAIL" | tr -d ' ') finding(s)); output left at $TARGET for inspection:"
  sed 's/^/  /' "$FAIL" >&2
  exit 1
fi

printf '[build-copilot-skill] wrote %s (%s files, source version %s, commit %s); exit audit clean\n' \
  "$TARGET" "${#GEN_FILES[@]}" "$SOURCE_VERSION" "$SOURCE_COMMIT"
