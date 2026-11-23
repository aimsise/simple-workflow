target: scripts/ticket_body.py
heading: (end of file)
mode: append
---
#!/usr/bin/env python3
"""Move a ticket body into the markup of a destination's content field, and
check what a destination stored.

Standard library only, ASCII-only source; run it as

    python3 -I ticket_body.py convert --to html|markdown-escaped|pre --in TICKET.md --out FILE
    python3 -I ticket_body.py check --sent TICKET.md --stored FILE

convert writes FILE and prints one line on stdout:

    Converted: html (N characters)
    Converted: preformatted fallback (DETAIL)
    Converted: markdown-escaped (N characters)
    Converted: pre (N characters)

  --to html             a line-oriented Markdown-to-HTML converter for the
                        ticket subset: ATX headings, paragraphs (a line break
                        inside one is kept as <br>), pipe tables (a backslash
                        before a pipe makes it a literal pipe), ordered and
                        unordered lists (nested, with continuation lines),
                        fenced code blocks (the info string kept as the class
                        name), code spans, **bold**, backslash escapes and
                        entity references ending in a semicolon; an HTML
                        comment is dropped, an opening comment marker whose
                        closing marker does not follow before the next blank
                        line, heading or fence line (or, for a marker with
                        anything before it on its line, the next list item or
                        table row; for one in a heading, the line end) is
                        text. Every text character is
                        HTML-escaped before any tag is added, so no text of
                        the ticket can open a tag. The result is then checked
                        against the input with the check below; when the check
                        is not complete, the structured result is discarded and
                        the preformatted form is written instead.
  --to markdown-escaped the Markdown text with every "<" written "&lt;" and
                        every ">" written "&gt;", code included.
  --to pre              the whole text with "&", "<" and ">" escaped, inside
                        one <pre> element.

check prints exactly one line on stdout:

    Body check: complete
    Body check: minor differences (missing M of T words in S spans[ and A angle-bracket texts]; first under "H": "EXCERPT")
    Body check: incomplete (missing M of T words in S spans[ and A angle-bracket texts]; headings missing: TITLES; longest span under "H": "EXCERPT")
    Body check: no content field (F of T words found[; start of the ticket only])

("longest span: none" when only a heading title is missing; "start of the
ticket only" when one view holds the first 12 words of the ticket in a row,
a text cut off after its start.) The stored
file is JSON (the text is every string value in it, joined; a string value
that is itself a JSON object or array as a whole is replaced by its own
string values) or plain text (Markdown, HTML or anything else, and a JSON
object or array found inside such a text, a line printed before a JSON
response for one, adds a text of its own: its string values, joined).
Before the values are joined, a second copy of the body is left out: a
value of at least 20 words of the sent text that holds more than half of
the sent words and of whose words 90 percent are held by a longer such
value (a field returned both raw and rendered), so a passage both copies
lost is still missing. Copies that are not separate values (a page text
showing the field twice, a structured document of one value per paragraph
next to the rendered field) are counted instead: the stored count that 98
percent of the words the ticket holds once reach is the number of copies,
and every stored count is divided by it, rounded up, so a word one copy
holds is found. Three views of each text, NFC-normalized, are
compared with the sent Markdown: the text and the text with HTML tags
removed, both with entity references decoded, and the text as stored (an
entity reference written inside code stays as written in Markdown); HTML
comments are kept in them. The sent Markdown is normalized
the same way and its entity references are decoded outside code spans and
fenced blocks, as a Markdown renderer decodes them. Words are maximal runs
of letters and digits of any script (a run of at least two characters holding
a letter, or of at least four digits), compared case-insensitively, except
that each letter of a script written without spaces between words (Han,
kana, Hangul, Thai, Lao, Myanmar, Khmer) is a word of its own, since a page
text joins such a clause with the code span or bold text next to it; such a
word weighs half a word in the span length and the 3 percent share below.
The stored count of a word is the largest of its counts in the three views.
A word that occurs k times in the sent text and c times in the stored text has
max(0, k - c) missing occurrences, the count a walk over the sent words in
order, each taking one stored occurrence, leaves without one; the
occurrences flagged are chosen so that a lost passage stays together, and
consecutive missing words, grown over the stretch an alignment of the two
texts leaves unmatched around them, form a span. Every "## " to "#### "
heading title of the sent text (outside code blocks) must occur in one view,
its words in a row (also when a link or an image in it is reduced to its
text, or when a comment closed on its line is taken out of the view), and a
heading whose line has every word missing counts as missing although its
title occurs elsewhere (in prose or in a longer heading). Every
angle-bracket text of the sent text ("<" and a letter up to the next ">" on
the line, with no pipe, asterisk or backtick in between, outside lines that
held a comment, an autolink such as "<https://...>" excepted) is counted
like a word, compared on its letters, digits
and angle brackets against the view that holds it most often; a missing one
is a minor difference, so a stored text that dropped "<K, V>" from
"Map<K, V>" is not complete although no word of two letters went. HTML comments, the info string of a code fence, a
line-break tag ("<br>") outside code, which a renderer turns into a line
break, and the first line of the sent text when it is a "## " heading (the
title, which a destination keeps in its title field) are not counted. The
target and title of an inline link, a whole inline image, a link reference
definition line and the label of a reference link, outside code, which a
renderer moves into an attribute or drops and a page text never shows, are
counted, but a missing word of them neither lengthens a span nor counts
toward the 3 percent below. Thresholds: fewer than 20 percent of the words
found is no content field; a missing heading, a missing span of 12 or more
words, or more than 3 percent of the words missing is incomplete; any other
missing word is a minor difference.

Files are read as UTF-8 (a byte order mark is dropped; a UTF-16 file with its
byte order mark is read too) and written as UTF-8 with LF line ends. Exit
status: 0 when the operation completed (also for an incomplete check), 2 on a
usage error, 3 when an input cannot be read or the output cannot be written.
"""

import argparse
import bisect
import difflib
import html
import json
import os
import re
import sys
import unicodedata

# Check thresholds.
NO_CONTENT_FOUND_RATIO = 0.20   # fewer words found than this share: the file holds no body
LONG_SPAN_WORDS = 12            # a missing span of this many words is a lost passage
MISSING_RATIO_LIMIT = 0.03      # more words missing than this share: incomplete
EXCERPT_CHARS = 80              # longest excerpt quoted on the result line
MAX_NESTING = 12                # list nesting deeper than this is kept as plain lines
HEADING_WORDS = 32              # words of a heading title looked up together
ALIGN_LIMIT = 15000000          # alignment work (each sent word times its stored count) above which spans are placed without it
COPY_WORDS = 20                 # a stored value this long can be a second copy of the body,
COPY_HELD = 0.50                # ... when it holds more than this share of the sent words (two
                                # distinct parts of the ticket cannot both hold more than half)
COPY_SHARE = 0.90               # ... and this share of its words is held by a longer value
MAX_JSON_DEPTH = 4              # JSON documents nested in string values that are expanded
MAX_EMBEDDED = 64               # attempts to decode a JSON document inside a text
MAX_ANGLE_TEXTS = 2000          # angle-bracket texts of the sent ticket looked up
START_WORDS = 12                # the first words of the ticket, found in a row: the stored text holds its start
COPIES_MIN_WORDS = 5            # words the ticket holds once that a copy count is estimated from
COPIES_QUANTILE = 0.02          # the stored count that 98 percent of those words reach is the number of copies
UNSPACED_WEIGHT = 0.5           # a letter of a script written without word spaces, counted as a word of its own,
                                # weighs half a word in the span length and the missing share

BT = chr(96)                    # the backtick, written so the source holds none
EXIT_USAGE = 2
EXIT_INPUT = 3

class InputError(Exception):
    """An input that cannot be read, or an output that cannot be written."""

def setup_streams():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace", newline="\n")
        except (AttributeError, ValueError, OSError):
            pass

def read_text(path, what):
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except OSError as exc:
        raise InputError("cannot read the %s file %s (%s)" % (what, path, exc.strerror or exc))
    if data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        encoding = "utf-16"
    else:
        encoding = "utf-8-sig"
    try:
        text = data.decode(encoding)
    except UnicodeDecodeError:
        raise InputError("the %s file %s is not UTF-8 text" % (what, path))
    return text.replace("\r\n", "\n").replace("\r", "\n")

def write_text(path, text):
    try:
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
    except OSError as exc:
        raise InputError("cannot write %s (%s)" % (path, exc.strerror or exc))

CONTROL_RE = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")

def escape(text):
    """HTML-escaped text; a control character other than tab and line feed
    becomes a space, so a destination that requires well-formed markup takes it."""
    return html.escape(CONTROL_RE.sub(" ", text), quote=False)

ENTITY_RE = re.compile(r"&(?:#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});")

def decode_entities(text):
    """Decode the entity references that end in a semicolon (html.unescape on
    each), so a bare ampersand in a URL query stays as written."""
    if "&" not in text:
        return text
    return ENTITY_RE.sub(lambda m: html.unescape(m.group(0)), text)

# ---------------------------------------------------------------- fences

MARKER_RE = re.compile(r"(?:[-*+]|[0-9]{1,9}[.)])(?:[ \t]+|$)")
FENCE_RE = re.compile(r"^([ \t]*)(" + BT + r"{3,}|~{3,})(.*)$")

def fence_open(line):
    """(indent, char, length, info string) when the line opens a fenced code block."""
    m = FENCE_RE.match(line)
    if not m:
        return None
    marker = m.group(2)
    if marker[0] == BT and BT in m.group(3):
        return None
    return (len(m.group(1).expandtabs(4)), marker[0], len(marker), m.group(3).strip())

def strip_list_prefix(line):
    """The line without its list markers ("- 1. " and the like), so a fence
    that opens inside a list item is seen as one."""
    pos = 0
    n = len(line)
    while True:
        p = pos
        while p < n and line[p] in " \t":
            p += 1
        m = MARKER_RE.match(line, p)
        if not m:
            return line[pos:] if pos else line
        pos = m.end()

def fence_closes(line, fence):
    s = line.strip()
    return len(s) >= fence[2] and s == fence[1] * len(s)

# ---------------------------------------------------------------- code spans

BT_RUN_RE = re.compile(BT + "+")

def code_span_ranges(s):
    """(start, end) of every code span of one line: a run of N backticks up
    to the next run of exactly N backticks. An unmatched run is text."""
    runs = [(m.start(), m.end() - m.start()) for m in BT_RUN_RE.finditer(s)]
    if len(runs) < 2:
        return []
    by_len = {}
    for idx, (_, ln) in enumerate(runs):
        by_len.setdefault(ln, []).append(idx)
    pointer = dict((ln, 0) for ln in by_len)
    ranges = []
    i = 0
    while i < len(runs):
        start, ln = runs[i]
        lst = by_len[ln]
        p = pointer[ln]
        while p < len(lst) and lst[p] <= i:
            p += 1
        pointer[ln] = p
        if p < len(lst):
            j = lst[p]
            ranges.append((start, runs[j][0] + ln))
            i = j + 1
        else:
            i += 1
    return ranges

def in_ranges(pos, ranges, starts):
    k = bisect.bisect_right(starts, pos) - 1
    return k >= 0 and ranges[k][0] <= pos < ranges[k][1]

# ---------------------------------------------------------------- comments

def strip_comments(lines, changed=None):
    """Drop HTML comments outside fenced blocks and code spans. A comment
    runs from its opening marker to the first closing marker ("<!-->" and
    "<!--->" are whole comments); it may go on over the following lines only
    while none of them is blank, a heading or a fence line, and, for an
    opening marker that does not start its line (text, indentation or a list
    marker before it), a list item or a piped table row; one opened in a
    heading ends on that line. So a stray opening marker never hides a
    section, a fenced block, a paragraph, or a list item or table row after
    its own: an opening marker with no closing marker before such a line is
    text. A line that held nothing but comments is dropped. When changed is
    a list, it gets one flag per line returned: whether a comment was taken
    out of it."""
    n = len(lines)
    next_close = [n] * (n + 1)
    next_bound = [n] * (n + 1)
    next_inline_bound = [n] * (n + 1)
    for k in range(n - 1, -1, -1):
        next_close[k] = k if "-->" in lines[k] else next_close[k + 1]
        line = lines[k]
        bound = (not line.strip() or heading_of(line) is not None
                 or fence_open(strip_list_prefix(line)) is not None or line.strip()[:3] in (BT * 3, "~~~"))
        next_bound[k] = k if bound else next_bound[k + 1]
        inline_bound = bound or list_marker(line.expandtabs(4)) is not None or split_row(line)[1]
        next_inline_bound[k] = k if inline_bound else next_inline_bound[k + 1]
    out = []
    fence = None
    i = 0
    while i < n:
        line = lines[i]
        if fence is not None:
            out.append(line)
            if changed is not None:
                changed.append(False)
            if fence_closes(line, fence):
                fence = None
            i += 1
            continue
        opened = fence_open(strip_list_prefix(line))
        if opened is not None:
            fence = opened
            out.append(line)
            if changed is not None:
                changed.append(False)
            i += 1
            continue
        heading = heading_of(line) is not None
        pieces = []
        cur = line
        pos = 0
        removed = False
        ranges = code_span_ranges(cur)
        starts = [r[0] for r in ranges]
        while True:
            j = cur.find("<!--", pos)
            while j >= 0 and in_ranges(j, ranges, starts):
                j = cur.find("<!--", j + 1)
            if j < 0:
                pieces.append(cur[pos:])
                break
            end = cur.find("-->", j + 2)
            if end >= 0:
                pieces.append(cur[pos:j])
                pos = end + 3
                removed = True
                continue
            k = next_close[i + 1]
            bounds = next_bound if j == 0 else next_inline_bound
            if k >= n or bounds[i + 1] <= k or heading:
                pieces.append(cur[pos:j + 4])
                pos = j + 4
                continue
            pieces.append(cur[pos:j])
            i = k
            cur = lines[i]
            pos = cur.find("-->") + 3
            ranges = [(a + pos, b + pos) for a, b in code_span_ranges(cur[pos:])]
            starts = [r[0] for r in ranges]
            removed = True
        text = "".join(pieces)
        if not (removed and not text.strip()):
            out.append(text)
            if changed is not None:
                changed.append(removed)
        i += 1
    return out

# ---------------------------------------------------------------- inline

ESCAPABLE = set("!\"#$%&'()*+,-./:;<=>?@[\\]^_{|}~" + BT)

def render_inline(s):
    """One line of text as HTML: code spans, **bold**, backslash escapes and
    entity references; everything else is escaped text."""
    ranges = code_span_ranges(s)
    atoms = []  # ("text", str) | ("code", str) | ("delim", None)
    pos = 0
    for a, b in ranges + [(len(s), len(s))]:
        seg = s[pos:a]
        buf = []
        i = 0
        while i < len(seg):
            c = seg[i]
            if c == "\\" and i + 1 < len(seg) and seg[i + 1] in ESCAPABLE:
                buf.append(("lit", seg[i + 1]))
                i += 2
            elif c == "*" and seg.startswith("**", i):
                buf.append(("delim", None))
                i += 2
            else:
                buf.append(("chr", c))
                i += 1
        text = []
        for kind, val in buf:
            if kind == "delim":
                if text:
                    atoms.append(("text", "".join(text)))
                    text = []
                atoms.append(("delim", None))
            elif kind == "chr":
                text.append(val)
            else:
                if text:
                    atoms.append(("text", "".join(text)))
                    text = []
                atoms.append(("lit", val))
        if text:
            atoms.append(("text", "".join(text)))
        if a < len(s):
            run = len(s[a:b]) - len(s[a:b].lstrip(BT))
            content = s[a + run:b - run]
            if len(content) >= 2 and content[0] == " " and content[-1] == " " and content.strip(" "):
                content = content[1:-1]
            atoms.append(("code", content))
        pos = b

    def neighbour(idx, step):
        k = idx + step
        while 0 <= k < len(atoms):
            kind, val = atoms[k]
            if kind == "delim":
                return "*"
            if kind == "code":
                return BT
            if val:
                return val[0] if step > 0 else val[-1]
            k += step
        return " "

    pair = {}
    opener = None
    for idx, (kind, _) in enumerate(atoms):
        if kind != "delim":
            continue
        after = neighbour(idx, 1)
        before = neighbour(idx, -1)
        if opener is None:
            if not after.isspace():
                opener = idx
        elif not before.isspace() and idx > opener + 1:
            pair[opener] = "<strong>"
            pair[idx] = "</strong>"
            opener = None
        elif not after.isspace():
            opener = idx
    out = []
    for idx, (kind, val) in enumerate(atoms):
        if kind == "text":
            out.append(escape(decode_entities(val)))
        elif kind == "lit":
            out.append(escape(val))
        elif kind == "code":
            out.append("<code>" + escape(val) + "</code>")
        else:
            out.append(pair.get(idx, "**"))
    return "".join(out)

# ---------------------------------------------------------------- blocks

LIST_RE = re.compile(r"^( *)([-*+]|[0-9]{1,9}[.)])([ \t]+|$)")
SEP_CELL_RE = re.compile(r"^ *:?-+:? *$")

def heading_of(line):
    """(level, title) of an ATX heading line, its closing hashes removed."""
    i = 0
    while i < 3 and i < len(line) and line[i] == " ":
        i += 1
    j = i
    while j < len(line) and line[j] == "#":
        j += 1
    level = j - i
    if level < 1 or level > 6 or (j < len(line) and line[j] not in " \t"):
        return None
    text = line[j:].strip(" \t")
    k = len(text)
    while k > 0 and text[k - 1] == "#":
        k -= 1
    if k == 0:
        text = ""
    elif k < len(text) and text[k - 1] in " \t":
        text = text[:k].rstrip(" \t")
    return level, text

def list_marker(line):
    m = LIST_RE.match(line)
    if not m:
        return None
    indent = len(m.group(1))
    marker = m.group(2)
    gap = m.group(3)
    spaces = len(gap)
    rest = line[m.end():]
    if spaces == 0 or spaces > 4 or "\t" in gap:
        spaces = 1
        rest = line[m.end(2):].lstrip(" \t") if gap else ""
    ordered = marker[-1] in ".)"
    return {
        "indent": indent,
        "ordered": ordered,
        "kind": marker[-1] if ordered else marker,
        "number": int(marker[:-1]) if ordered else None,
        "content": indent + len(marker) + spaces,
        "rest": rest,
    }

def split_row(line):
    """The cells of a table row: split on unescaped pipes outside code spans."""
    s = line.strip()
    ranges = code_span_ranges(s)
    starts = [r[0] for r in ranges]
    cuts = []
    for i, c in enumerate(s):
        if c != "|" or in_ranges(i, ranges, starts):
            continue
        k = i - 1
        slashes = 0
        while k >= 0 and s[k] == "\\":
            slashes += 1
            k -= 1
        if slashes % 2 == 0:
            cuts.append(i)
    cells = []
    prev = 0
    for c in cuts:
        cells.append(s[prev:c])
        prev = c + 1
    cells.append(s[prev:])
    if cuts and cuts[0] == 0:
        cells = cells[1:]
    if cuts and cuts[-1] == len(s) - 1:
        cells = cells[:-1]
    return [c.strip().replace("\\|", "|") for c in cells], bool(cuts)

def is_separator(line):
    if "-" not in line:
        return False
    cells, piped = split_row(line)
    if not cells:
        return False
    return all(SEP_CELL_RE.match(c) for c in cells) and (piped or len(cells) == 1)

def table_start(lines, i):
    if i + 1 >= len(lines) or "|" not in lines[i]:
        return False
    cells, piped = split_row(lines[i])
    return piped and is_separator(lines[i + 1])

def block_start(lines, i):
    line = lines[i]
    return (fence_open(line) is not None or heading_of(line) is not None
            or list_marker(line) is not None or table_start(lines, i))

def lead(line):
    return len(line) - len(line.lstrip(" "))

def dedent(line, k):
    return line[min(k, lead(line)):]

def render_paragraph(lines, tight):
    parts = []
    last = len(lines) - 1
    for idx, raw in enumerate(lines):
        text = raw.strip(" \t")
        if idx < last and text.endswith("\\") and not text.endswith("\\\\"):
            text = text[:-1]
        parts.append(render_inline(text))
    inner = "<br>\n".join(parts)
    return inner if tight else "<p>" + inner + "</p>"

def render_table(rows):
    head, _ = split_row(rows[0])
    out = ["<table>", "<thead>", "<tr>" + "".join("<th>" + render_inline(c) + "</th>" for c in head) + "</tr>", "</thead>"]
    body = rows[2:]
    if body:
        out.append("<tbody>")
        for row in body:
            cells, _ = split_row(row)
            while len(cells) < len(head):
                cells.append("")
            out.append("<tr>" + "".join("<td>" + render_inline(c) + "</td>" for c in cells) + "</tr>")
        out.append("</tbody>")
    out.append("</table>")
    return "\n".join(out)

def render_fence(lines, fence, closed):
    body = []
    for raw in lines:
        body.append(dedent(raw, fence[0]))
    text = "\n".join(body)
    if body:
        text += "\n"
    attrs = ""
    if fence[3]:
        # The info string is kept as the class name, so no word of the ticket is dropped.
        attrs = ' class="language-%s"' % html.escape(CONTROL_RE.sub(" ", decode_entities(fence[3])), quote=True)
    return "<pre><code%s>" % attrs + escape(text) + "</code></pre>"

def collect_list(lines, i):
    """Items of the list that starts at line i: [(marker, [body lines])], the
    index after the list, and whether the list is loose."""
    first = list_marker(lines[i])
    items = []
    loose = False
    n = len(lines)
    while i < n:
        m = list_marker(lines[i])
        if m is None or m["ordered"] != first["ordered"] or m["kind"] != first["kind"]:
            break
        if items and m["indent"] >= items[-1][0]["content"]:
            break
        if m["indent"] > first["indent"] + 3:
            break
        body = [m["rest"]]
        content = m["content"]
        i += 1
        fence = fence_open(m["rest"])
        blank_run = 0
        while i < n:
            line = lines[i]
            if fence is not None:
                body.append(dedent(line, content))
                if fence_closes(line, fence):
                    fence = None
                i += 1
                continue
            if not line.strip():
                blank_run += 1
                i += 1
                continue
            ind = lead(line)
            if ind >= content:
                if blank_run:
                    body.extend([""] * blank_run)
                    loose = True
                    blank_run = 0
                body.append(dedent(line, content))
                fence = fence_open(dedent(line, content))
                i += 1
                continue
            if blank_run:
                break
            if block_start(lines, i):
                break
            prev = body[-1] if body else ""
            if prev.strip() and fence_open(prev) is None and heading_of(prev) is None:
                body.append(line.strip(" "))
                i += 1
                continue
            break
        items.append((m, body))
        if blank_run:
            nxt = list_marker(lines[i]) if i < n else None
            if (nxt is not None and nxt["ordered"] == first["ordered"] and nxt["kind"] == first["kind"]
                    and nxt["indent"] < m["content"]):
                loose = True
            else:
                i -= blank_run
                break
    return items, i, loose

def render_list(items, loose, depth):
    first = items[0][0]
    tag = "ol" if first["ordered"] else "ul"
    attrs = ""
    if first["ordered"] and first["number"] != 1:
        attrs = ' start="%d"' % first["number"]
    out = ["<%s%s>" % (tag, attrs)]
    expected = first["number"]
    for m, body in items:
        value = ""
        if m["ordered"]:
            if m["number"] != expected:
                value = ' value="%d"' % m["number"]
            expected = m["number"] + 1
        while body and not body[-1].strip():
            body = body[:-1]
        if depth >= MAX_NESTING:
            inner = render_paragraph([b for b in body if b.strip()], True)
        else:
            inner = render_blocks(body, depth + 1, not loose)
        out.append("<li%s>%s</li>" % (value, inner))
    out.append("</%s>" % tag)
    return "\n".join(out)

def render_blocks(lines, depth, tight):
    out = []
    para = []

    def flush():
        if para:
            out.append(render_paragraph(para, tight))
            del para[:]

    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if not line.strip():
            flush()
            i += 1
            continue
        fence = fence_open(line)
        if fence is not None:
            flush()
            j = i + 1
            body = []
            closed = False
            while j < n:
                if fence_closes(lines[j], fence):
                    closed = True
                    j += 1
                    break
                body.append(lines[j])
                j += 1
            out.append(render_fence(body, fence, closed))
            i = j
            continue
        head = heading_of(line)
        if head is not None:
            flush()
            out.append("<h%d>%s</h%d>" % (head[0], render_inline(head[1]), head[0]))
            i += 1
            continue
        if table_start(lines, i):
            flush()
            j = i + 2
            while j < n and lines[j].strip() and split_row(lines[j])[1] and not (
                    fence_open(lines[j]) is not None or heading_of(lines[j]) is not None):
                j += 1
            out.append(render_table(lines[i:j]))
            i = j
            continue
        m = list_marker(line)
        if m is not None and (not para or not m["ordered"] or m["number"] == 1) and (m["rest"].strip() or not para):
            flush()
            items, j, loose = collect_list(lines, i)
            if not items:
                para.append(line)
                i += 1
                continue
            out.append(render_list(items, loose, depth))
            i = j
            continue
        para.append(line)
        i += 1
    flush()
    return "\n".join(out)

def expand_leading_tabs(lines):
    """Leading tabs outside fenced blocks become spaces (tab stops of 4)."""
    out = []
    fence = None
    for line in lines:
        if fence is not None:
            out.append(line)
            if fence_closes(line, fence):
                fence = None
            continue
        lead_ws = len(line) - len(line.lstrip(" \t"))
        if "\t" in line[:lead_ws]:
            line = line[:lead_ws].expandtabs(4) + line[lead_ws:]
        fence = fence_open(line)
        out.append(line)
    return out

def split_lines(text):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines

def to_html(text):
    lines = expand_leading_tabs(strip_comments(split_lines(text)))
    body = render_blocks(lines, 0, False)
    return body + "\n" if body else ""

def to_pre(text):
    return "<pre>" + escape(text) + "</pre>\n"

def to_markdown_escaped(text):
    return text.replace("<", "&lt;").replace(">", "&gt;")

# ---------------------------------------------------------------- check

# Scripts written without spaces between words (Han, kana, Hangul, Thai, Lao,
# Myanmar, Khmer): a page text joins such a clause with the code span or bold
# text next to it, so each of their letters is a word of its own.
UNSPACED_RANGES = ((0x0e00, 0x0eff), (0x1000, 0x109f), (0x1100, 0x11ff), (0x1780, 0x17ff), (0x19e0, 0x19ff),
                   (0x2e80, 0x9fff), (0xac00, 0xd7ff), (0xf900, 0xfaff), (0xff66, 0xffdc), (0x1b000, 0x1b2ff),
                   (0x20000, 0x3ffff))
UNSPACED = "".join("%s-%s" % (chr(lo), chr(hi)) for lo, hi in UNSPACED_RANGES)
WORD_RE = re.compile(r"(?![\W_])[" + UNSPACED + r"]|[^\W_" + UNSPACED + r"]+")
UNSPACED_RE = re.compile(r"[" + UNSPACED + r"]")
TAG_RE = re.compile(r"<![A-Za-z\[][^<>]*>|</?[A-Za-z][A-Za-z0-9:-]*(?:[ \t\n/][^<>]*)?>")
SPACE_RE = re.compile(r"\s+")

def keep_word(w):
    if len(w) < 2:
        return bool(UNSPACED_RE.match(w))
    if any(c.isalpha() for c in w):
        return True
    return len(w) >= 4

def word_weight(w):
    """A letter of an unspaced script weighs UNSPACED_WEIGHT of a word in the
    span length and the missing share."""
    return UNSPACED_WEIGHT if len(w) == 1 else 1.0

def words_of(text):
    return [w.casefold() for w in WORD_RE.findall(text) if keep_word(w)]

def nfc(text):
    return unicodedata.normalize("NFC", text)

def decode_outside_code(line):
    """Entity references decoded outside the code spans of one line, as a
    Markdown renderer and the converter decode them."""
    if "&" not in line:
        return line
    out = []
    pos = 0
    for a, b in code_span_ranges(line):
        out.append(decode_entities(line[pos:a]))
        out.append(line[a:b])
        pos = b
    out.append(decode_entities(line[pos:]))
    return "".join(out)

BREAK_RE = re.compile(r"<br[ \t]*/?>", re.IGNORECASE)
REF_DEF_RE = re.compile(r"^ {0,3}\[[^\[\]\n]+\]:[ \t]*(?:<[^<>\n]*>|[^\s<>]+)"
                        r"(?:[ \t]+(?:\"[^\"\n]*\"|'[^'\n]*'|\([^()\n]*\)))?[ \t]*$")
REF_USE_RE = re.compile(r"\]\[([^\[\]\n]+)\]")

def rendered_away(line):
    """The parts of one line, outside code spans, that a renderer turns into
    markup instead of text: (targets, breaks). A target is the target and
    title of an inline link, or a whole inline image, which a renderer moves
    into an attribute, so a page text lacks it while the source keeps it; so
    are a whole link reference definition line ("[label]: <url> 'title'")
    and the label of a reference link ("[text][label]"). A break is a
    line-break tag, markup the author wrote, not ticket text."""
    spans = code_span_ranges(line)
    starts = [a for a, _ in spans]
    targets = []
    breaks = []
    if "]:" in line and REF_DEF_RE.match(line):
        targets.append((0, len(line)))
    if "][" in line:
        for m in REF_USE_RE.finditer(line):
            if not in_ranges(m.start(), spans, starts):
                targets.append((m.start(1), m.end(1)))
    if "](" in line:
        for m in LINK_RE.finditer(line):
            if in_ranges(m.start(), spans, starts):
                continue
            if m.group(0).startswith("!"):
                targets.append((m.start(), m.end()))
            else:
                targets.append((m.start() + 3 + len(m.group(1)), m.end()))
    if "<" in line:
        for m in BREAK_RE.finditer(line):
            if not in_ranges(m.start(), spans, starts):
                breaks.append((m.start(), m.end()))
    return targets, breaks

def inside(pos, ranges):
    return any(a <= pos < b for a, b in ranges)

def sent_model(text):
    """Words of the sent Markdown with their places, its heading titles, its
    angle-bracket texts and the decoded lines the excerpts are cut from, and
    which words are link targets (soft: they cannot make a text incomplete)."""
    changed = []
    lines = strip_comments(split_lines(text), changed)
    decoded = []
    words = []      # (word, line index, start, end)
    soft = []       # per word: whether it is part of a link target or an image
    angles = []     # (line index, start, end, skeleton) of every angle-bracket text
    labels = []     # (line index, title) of every heading
    required = []   # (title, line index) of the #{2,4} headings the stored text must hold
    fence = None
    first_content = True
    for idx, raw in enumerate(lines):
        targets = breaks = ()
        if fence is not None:
            line = nfc(raw)
            decoded.append(line)
            if fence_closes(raw, fence):
                fence = None
                continue
        else:
            line = nfc(decode_outside_code(raw))
            decoded.append(line)
            opened = fence_open(strip_list_prefix(raw))
            if opened is not None:
                fence = opened
                first_content = False
                continue
            head = heading_of(raw)
            if head is not None:
                title = nfc(decode_outside_code(head[1]))
                labels.append((idx, title))
                if first_content and head[0] == 2:
                    first_content = False
                    continue
                if 2 <= head[0] <= 4 and words_of(title):
                    required.append((title, idx))
            targets, breaks = rendered_away(line)
        if raw.strip():
            first_content = False
        for m in WORD_RE.finditer(line):
            if keep_word(m.group(0)) and not (breaks and inside(m.start(), breaks)):
                words.append((m.group(0).casefold(), idx, m.start(), m.end()))
                soft.append(bool(targets) and inside(m.start(), targets))
        if "<" in line and not changed[idx] and len(angles) < MAX_ANGLE_TEXTS:
            for a, b, sk in angle_texts(line):
                if not (breaks and inside(a, breaks)):
                    angles.append((idx, a, b, sk))
    return words, soft, labels, required, decoded, angles[:MAX_ANGLE_TEXTS]

def json_strings(obj):
    out = []
    stack = [obj]
    while stack:
        cur = stack.pop()
        if isinstance(cur, str):
            out.append(cur)
        elif isinstance(cur, dict):
            stack.extend(reversed(list(cur.values())))
        elif isinstance(cur, list):
            stack.extend(reversed(cur))
    return out

def parse_json(text, scalar=False):
    """The JSON document a text holds as a whole (an object or an array; with
    scalar, also a string), or None."""
    s = text.strip()
    if s[:1] not in (("{", "[", '"') if scalar else ("{", "[")):
        return None
    try:
        obj = json.loads(s)
    except (ValueError, RecursionError):
        return None
    return obj if isinstance(obj, (dict, list, str)) else None

def json_values(obj, depth):
    """The string values of a JSON document in order; a value that is itself
    a JSON object or array as a whole (a tool result carrying the response as
    text) is replaced by its own string values."""
    out = []
    for s in json_strings(obj):
        inner = parse_json(s) if depth < MAX_JSON_DEPTH else None
        if inner is None:
            out.append(s)
        else:
            out.extend(json_values(inner, depth + 1))
    return out

JSON_START_RE = re.compile(r'[{\[][ \t\r\n]*["{\[]')

def embedded_json(text):
    """The objects and arrays inside a text that is not JSON as a whole (a
    line printed before a JSON response), each decoded where it starts."""
    found = []
    decoder = json.JSONDecoder()
    pos = 0
    for _ in range(MAX_EMBEDDED):
        m = JSON_START_RE.search(text, pos)
        if not m:
            break
        try:
            obj, end = decoder.raw_decode(text, m.start())
        except (ValueError, RecursionError):
            pos = m.start() + 1
            continue
        if isinstance(obj, (dict, list)):
            found.append(obj)
        pos = max(end, m.start() + 1)
    return found

def body_words(value, sent_count):
    """The counts of the words of a stored value that the sent text holds,
    taken from the value as written or with its HTML tags removed, whichever
    holds more of them."""
    best = {}
    for text in (value, TAG_RE.sub(" ", value)):
        c = count([w for w in words_of(nfc(decode_entities(text))) if w in sent_count])
        if sum(c.values()) > sum(best.values()):
            best = c
    return best

def drop_copies(values, sent_count, sent_total):
    """The values without second copies of the body (a field returned both
    raw and rendered): a value of at least COPY_WORDS words of the sent text
    that holds more than COPY_HELD of the sent words by itself, and of whose
    words COPY_SHARE are already held by a longer such value, is left out,
    so a passage both copies lost is not found in the other copy."""
    if len(values) < 2 or not sent_total:
        return values
    infos = []
    for idx, v in enumerate(values):
        c = body_words(v, sent_count)
        size = sum(c.values())
        held = sum(min(k, sent_count[w]) for w, k in c.items())
        infos.append((size, idx, c, held))
    kept = []
    dropped = set()
    for size, idx, c, held in sorted(infos, key=lambda x: (-x[0], x[1])):
        if size < COPY_WORDS or held <= COPY_HELD * sent_total:
            continue
        if any(sum(min(k, other.get(w, 0)) for w, k in c.items()) >= COPY_SHARE * size for other in kept):
            dropped.add(idx)
        else:
            kept.append(c)
    return [v for idx, v in enumerate(values) if idx not in dropped]

def stored_views(text, sent_count, sent_total):
    """The views of the stored text: for its text and for the JSON documents
    found inside it, the text, the text with HTML tags removed (both
    entity-decoded) and the text as stored, undecoded (an entity reference
    written inside code). A file that is JSON as a whole contributes its
    string values, a string value that is JSON as a whole its own values."""
    obj = parse_json(text, scalar=True)
    values = [text] if obj is None else json_values(obj, 0)
    bases = ["\n".join(drop_copies(values, sent_count, sent_total))]
    found = []
    for v in values:
        for inner in embedded_json(v):
            found.extend(json_values(inner, 1))
    if found:
        bases.append("\n".join(drop_copies(found, sent_count, sent_total)))
    views = []
    for raw in bases:
        views.extend([nfc(decode_entities(raw)), nfc(decode_entities(TAG_RE.sub(" ", raw))), nfc(raw)])
    return views

def without_comments(text):
    """The text with every HTML comment that closes on its own line replaced
    by a space (for the heading lookup only: a comment inside a stored
    heading line does not hide the title)."""
    out = []
    pos = 0
    while True:
        j = text.find("<!--", pos)
        if j < 0:
            break
        end = text.find("-->", j + 2)
        if end < 0:
            break
        nl = text.find("\n", j, end)
        if nl >= 0:
            out.append(text[pos:nl + 1])
            pos = nl + 1
            continue
        out.append(text[pos:j])
        out.append(" ")
        pos = end + 3
    out.append(text[pos:])
    return "".join(out)

def count(words):
    counts = {}
    for w in words:
        counts[w] = counts.get(w, 0) + 1
    return counts

def clean(text):
    out = []
    for ch in text:
        cat = unicodedata.category(ch)
        out.append(" " if cat in ("Cc", "Zl", "Zp", "Cs") else ch)
    return SPACE_RE.sub(" ", "".join(out)).strip()

def excerpt(span, words, decoded):
    first = words[span[0]]
    last = words[span[1]]
    if first[1] == last[1]:
        text = decoded[first[1]][first[2]:last[3]]
    else:
        parts = [decoded[first[1]][first[2]:]]
        parts.extend(decoded[first[1] + 1:last[1]])
        parts.append(decoded[last[1]][:last[3]])
        text = " ".join(parts)
    text = clean(text).replace('"', "'")
    if len(text) > EXCERPT_CHARS:
        text = text[:EXCERPT_CHARS - 3] + "..."
    return text

def label_for(line_idx, labels):
    title = ""
    for idx, t in labels:
        if idx > line_idx:
            break
        title = t
    return clean(title).replace('"', "'") or "(top)"

LINK_RE = re.compile(r"!?\[([^\[\]\n]*)\]\([^()\s]*(?:[ \t]+(?:\"[^\"\n]*\"|'[^'\n]*'))?[ \t]*\)")

def heading_present(title, views, view_words):
    """Whether the title's words occur in a row in one view; a title holding
    a link or an image is also looked up with each reduced to its text, as a
    renderer moves the target into an attribute."""
    for t in (title, LINK_RE.sub(r"\1", title)):
        tw = words_of(t)[:HEADING_WORDS]
        if tw:
            needle = "\x00" + "\x00".join(tw) + "\x00"
            if any(needle in hay for hay in view_words):
                return True
            continue
        plain = SPACE_RE.sub(" ", t).strip().casefold()
        if not plain or any(plain in SPACE_RE.sub(" ", v).casefold() for v in views):
            return True
    return False

ANGLE_RE = re.compile(r"<[^\W\d_][^<>|*\n" + BT + r"]*>")
ANGLE_SEG_RE = re.compile(r"<[^<>]*>")
AUTOLINK_RE = re.compile(r"<(?:[A-Za-z][A-Za-z0-9+.-]{1,31}:[^\s<>]*|[^\s<>@]+@[^\s<>@]+)>")

def skeleton(text):
    """The letters, digits and angle brackets of a text, case-folded: an
    angle-bracket text compared on it survives escaping, entity references
    and whitespace changes."""
    return "".join(c for c in text.casefold() if c.isalnum() or c in "<>")

def angle_texts(line):
    """The angle-bracket texts of one line ("<" and a letter up to the next
    ">", with no pipe, asterisk or backtick in between, which a table cell,
    bold text or a code span would split; an autolink, which a renderer turns
    into a link, is not one), as (start, end, skeleton)."""
    out = []
    for m in ANGLE_RE.finditer(line):
        if AUTOLINK_RE.fullmatch(m.group(0)):
            continue
        sk = skeleton(m.group(0))
        if len(sk) > 2:
            out.append((m.start(), m.end(), sk))
    return out

def mark_missing(sent_words, stored_count, view_lists):
    """Which sent words are missing. A word that occurs k times in the sent
    text and c times in the stored text has max(0, k - c) missing occurrences:
    the count a walk over the sent words in order, each taking one stored
    occurrence, leaves without one. Which of its occurrences are flagged is
    then chosen so that a lost passage stays one span: first the last ones (as
    that walk would), then, in a few rounds, the occurrences that an alignment
    of the sent words with the closer view leaves unmatched or that sit next
    to other missing words. Returns (flagged, unaligned, whether the
    alignment ran)."""
    n = len(sent_words)
    positions = {}
    for k, w in enumerate(sent_words):
        positions.setdefault(w, []).append(k)
    need = {}
    for w, occ in positions.items():
        if len(occ) > stored_count.get(w, 0):
            need[w] = len(occ) - stored_count.get(w, 0)
    flagged = [False] * n
    unaligned = [False] * n
    if not need:
        return flagged, unaligned, False

    def overlap(view):
        c = count(view)
        return sum(min(len(occ), c.get(w, 0)) for w, occ in positions.items())
    best = max(view_lists, key=overlap)
    best_count = count(best)
    aligned = sum(best_count.get(w, 0) for w in sent_words) <= ALIGN_LIMIT
    if aligned:
        matcher = difflib.SequenceMatcher(None, sent_words, best, autojunk=False)
        for tag, i1, i2, _, _ in matcher.get_opcodes():
            if tag != "equal":
                for k in range(i1, i2):
                    unaligned[k] = True
    for w, d in need.items():
        for k in positions[w][-d:]:
            flagged[k] = True

    def score(k):
        near = (1 if k > 0 and flagged[k - 1] else 0) + (1 if k + 1 < n and flagged[k + 1] else 0)
        return (2 if unaligned[k] else 0) + near
    for _ in range(4):
        changed = False
        for w, d in need.items():
            occ = positions[w]
            if d >= len(occ):
                continue
            chosen = set(sorted(occ, key=lambda k: (score(k), k), reverse=True)[:d])
            for k in occ:
                if flagged[k] != (k in chosen):
                    flagged[k] = k in chosen
                    changed = True
        if not changed:
            break
    return flagged, unaligned, aligned

def missing_spans(missing, unaligned):
    """(first, last) word index of every span: a run of missing words, grown
    over the stretch the alignment left unmatched around it, so a lost
    passage whose common words also occur elsewhere is still one span."""
    n = len(missing)
    mask = list(missing)
    k = 0
    while k < n:
        if not unaligned[k]:
            k += 1
            continue
        j = k
        while j < n and unaligned[j]:
            j += 1
        if any(missing[k:j]):
            for x in range(k, j):
                mask[x] = True
        k = j
    spans = []
    start = None
    for k, gone in enumerate(mask + [False]):
        if gone and start is None:
            start = k
        elif not gone and start is not None:
            spans.append((start, k - 1))
            start = None
    return spans

def body_copies(sent_count, stored_count):
    """How many whole copies of the body the stored text holds, also when
    they cannot be told apart as values (a page text showing the field twice,
    a structured document next to the rendered field): the stored count that
    nearly every word the ticket holds once reaches. The stored counts are
    divided by it, so a passage every copy lost is missing even when its words
    occur elsewhere in the ticket."""
    held = sorted(stored_count[w] for w, k in sent_count.items() if k == 1 and stored_count.get(w, 0) > 0)
    if len(held) < COPIES_MIN_WORDS:
        return 1
    return max(1, held[int(len(held) * COPIES_QUANTILE)])

def holds_start(words, soft, view_words):
    """Whether one view holds the first START_WORDS words of the ticket in a
    row (with or without its link targets): a text cut off after its start."""
    if len(words) < START_WORDS:
        return False
    for keep in (lambda k: True, lambda k: not soft[k]):
        first = [w for k, (w, _, _, _) in enumerate(words) if keep(k)][:START_WORDS]
        if len(first) == START_WORDS:
            needle = "\x00" + "\x00".join(first) + "\x00"
            if any(needle in hay for hay in view_words):
                return True
    return False

def check_texts(sent_text, stored_text):
    """(kind, line) with kind one of complete, minor, incomplete, nocontent."""
    words, soft, labels, required, decoded, angles = sent_model(sent_text)
    total = len(words)
    sent_count = count([w for w, _, _, _ in words])
    views = stored_views(stored_text, sent_count, total)
    view_lists = [words_of(v) for v in views]
    counts = [count(v) for v in view_lists]
    remaining = {}
    for c in counts:
        for w, k in c.items():
            if k > remaining.get(w, 0):
                remaining[w] = k
    copies = body_copies(sent_count, remaining)
    if copies > 1:
        remaining = dict((w, -(-k // copies)) for w, k in remaining.items())
    missing, unaligned, aligned = mark_missing([w for w, _, _, _ in words], remaining, view_lists)
    lost = sum(1 for x in missing if x)
    found = total - lost
    view_words = ["\x00" + "\x00".join(v) + "\x00" for v in view_lists]
    if total and found < NO_CONTENT_FOUND_RATIO * total:
        line = "Body check: no content field (%d of %d words found" % (found, total)
        if holds_start(words, soft, view_words):
            line += "; start of the ticket only"
        return "nocontent", line + ")"
    view_words.extend("\x00" + "\x00".join(words_of(without_comments(v))) + "\x00" for v in views if "<!--" in v)
    on_line = {}
    for k, (_, idx, _, _) in enumerate(words):
        on_line.setdefault(idx, []).append(k)

    def line_lost(idx):
        # Every word of the heading line itself is missing: its title words
        # found elsewhere (in prose, in a longer heading) do not stand in for
        # it. Decided only when the alignment placed the missing words.
        ks = [k for k in on_line.get(idx, ()) if not soft[k]]
        return aligned and bool(ks) and all(missing[k] for k in ks)
    absent = [t for t, idx in required if not heading_present(t, views, view_words) or line_lost(idx)]
    gone = []
    if angles:
        have = {}
        for v in views:
            for sk, k in count(ANGLE_SEG_RE.findall(skeleton(v))).items():
                if k > have.get(sk, 0):
                    have[sk] = k
        # Not divided by the copies: an angle-bracket text that occurs once is
        # missing from every copy or found, and an undivided count can never
        # report one lost that a copy holds.
        for a in angles:
            if have.get(a[3], 0) > 0:
                have[a[3]] -= 1
            else:
                gone.append(a)
    if not lost and not absent and not gone:
        return "complete", "Body check: complete"
    spans = missing_spans(missing, unaligned)
    wts = [word_weight(w) for w, _, _, _ in words]

    def weight(sp):
        # A link target (soft) neither lengthens a span nor counts toward the
        # missing share: a page text never shows it. A letter of an unspaced
        # script weighs UNSPACED_WEIGHT of a word.
        return sum(wts[k] for k in range(sp[0], sp[1] + 1) if not soft[k])
    longest = max(spans, key=weight) if spans else None
    longest_len = weight(longest) if longest else 0
    hard_lost = sum(wts[k] for k, x in enumerate(missing) if x and not soft[k])
    head = "missing %d of %d words in %d spans" % (lost, total, len(spans))
    if gone:
        head += " and %d angle-bracket texts" % len(gone)
    if absent or longest_len >= LONG_SPAN_WORDS or hard_lost > MISSING_RATIO_LIMIT * sum(wts):
        titles = ", ".join('"%s"' % clean(t).replace('"', "'") for t in absent) or "none"
        if longest:
            where = 'longest span under "%s": "%s"' % (
                label_for(words[longest[0]][1], labels), excerpt(longest, words, decoded))
        else:
            where = "longest span: none"
        return "incomplete", clean("Body check: incomplete (%s; headings missing: %s; %s)" % (head, titles, where))
    if spans:
        first = spans[0]
        where = 'first under "%s": "%s"' % (label_for(words[first[0]][1], labels), excerpt(first, words, decoded))
    else:
        idx, a, b, _ = gone[0]
        text = clean(decoded[idx][a:b]).replace('"', "'")
        if len(text) > EXCERPT_CHARS:
            text = text[:EXCERPT_CHARS - 3] + "..."
        where = 'first under "%s": "%s"' % (label_for(idx, labels), text)
    return "minor", clean("Body check: minor differences (%s; %s)" % (head, where))

# ---------------------------------------------------------------- commands

def same_file(a, b):
    try:
        if os.path.exists(b):
            return os.path.samefile(a, b)
    except OSError:
        pass
    return os.path.abspath(a) == os.path.abspath(b)

def cmd_convert(args):
    if same_file(args.inp, args.out):
        sys.stderr.write("ticket_body.py: --in and --out name the same file\n")
        return EXIT_USAGE
    text = read_text(args.inp, "input")
    if args.to == "markdown-escaped":
        result = to_markdown_escaped(text)
        line = "Converted: markdown-escaped (%d characters)" % len(result)
    elif args.to == "pre":
        result = to_pre(text)
        line = "Converted: pre (%d characters)" % len(result)
    else:
        try:
            result = to_html(text)
            kind, verdict = check_texts(text, result)
        except Exception as exc:  # any converter failure falls back to the preformatted form
            kind, verdict = "error", "Body check: incomplete (converter error: %s)" % type(exc).__name__
        if kind == "complete":
            line = "Converted: html (%d characters)" % len(result)
        else:
            result = to_pre(text)
            detail = verdict[verdict.find("(") + 1:-1] if "(" in verdict else verdict
            line = "Converted: preformatted fallback (%s)" % detail
    write_text(args.out, result)
    print(line)
    return 0

def cmd_check(args):
    sent = read_text(args.sent, "sent")
    stored = read_text(args.stored, "stored")
    _, line = check_texts(sent, stored)
    print(line)
    return 0

def main(argv=None):
    setup_streams()
    parser = argparse.ArgumentParser(
        prog="ticket_body.py",
        description="Convert a Markdown ticket for a destination's content field, or check the text a destination stored (standard library only).")
    sub = parser.add_subparsers(dest="command")
    conv = sub.add_parser("convert", help="write the ticket in the markup of the content field")
    conv.add_argument("--to", required=True, choices=["html", "markdown-escaped", "pre"])
    conv.add_argument("--in", dest="inp", required=True, metavar="TICKET_MD")
    conv.add_argument("--out", required=True, metavar="FILE")
    chk = sub.add_parser("check", help="compare the text a destination stored with the sent ticket")
    chk.add_argument("--sent", required=True, metavar="TICKET_MD")
    chk.add_argument("--stored", required=True, metavar="FILE")
    args = parser.parse_args(argv)
    if args.command is None:
        parser.print_usage(sys.stderr)
        return EXIT_USAGE
    try:
        if args.command == "convert":
            return cmd_convert(args)
        return cmd_check(args)
    except InputError as exc:
        sys.stderr.write("ticket_body.py: %s\n" % exc)
        return EXIT_INPUT

if __name__ == "__main__":
    sys.exit(main())
