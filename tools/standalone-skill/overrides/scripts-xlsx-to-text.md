target: scripts/xlsx_to_text.py
heading: (end of file)
mode: append
---
#!/usr/bin/env python3
"""Dump every worksheet of an .xlsx workbook as Markdown text.

Standard library only (zipfile + xml.etree), so it runs wherever python3
runs; no third-party package is required. Run it as

    python3 -I xlsx_to_text.py WORKBOOK.xlsx [--max-rows N] [--max-cols N]
                                           [--max-chars N] [--sheet NAME ...]
                                           [--layout table|cells|auto]
                                           [--extract-media DIR]

Output (stdout): one "## Sheet: NAME" section per worksheet (every
worksheet, or only those named by --sheet, exact match; an unknown name
exits 2 and lists the names the workbook has). By default each section is
a Markdown table whose first column is the 1-based row number of the
worksheet, so every cell keeps its worksheet address (sheet name and row)
in the text that the skill reads and cites. Caps: --max-rows rows
per sheet (default 2000), --max-cols columns per sheet (default 64),
--max-chars characters of output in total (default 200000); a cap that is
hit is reported as a line starting with "[truncated:" at the point it
applies, never silently. Everything below counts toward --max-chars, and so
does its own "[truncated:" line: the text is cut so that the text and that
line together stay within the cap (a cap shorter than the line prints the
line alone, whole). A worksheet that starts after the cap is reached is not
read at all.

Cell values: shared and inline strings, numbers (a cell whose number format
is a date format is printed as an ISO date or date-time from its serial
value), booleans as TRUE / FALSE, cell errors as their text (#N/A, ...),
formulas as their cached value. Hidden sheets are included and marked.
The date detection reads the cell's number format; a custom elapsed-time
format such as mm:ss is only approximated and may print as a date-time
near the epoch.

Structure kept from the workbook:
- A line break inside a cell, a note or a shape text is printed as the
  literal <br>; any other run of whitespace collapses to one space.
- Merged ranges are not expanded: the top-left cell carries the marker
  "[merged c<a>-c<b> rows <x>-<y>]" before its value (the column part is
  left out when the range is one column wide, the row part when it is one
  row high); an empty top-left cell gets the marker as its whole value, and
  the other cells of the range stay blank. A range whose top-left column
  lies beyond --max-cols is not read and counts as a column beyond the cap
  (its "[truncated:" line).
- Strikethrough is printed as ~~text~~: a rich-text run whose run font
  strikes (<strike/> or <strike val="1"/>; <strike val="0"/> does not
  strike), or the whole value of a cell whose cell style font strikes. In
  a struck cell the whole value is struck once, whatever its runs say, so
  a run with <strike val="0"/> inside it is struck too. No other
  formatting is printed.
- A hidden row prints its number as "3 (hidden)", a hidden column its
  header as "c2 (hidden)"; hidden content is still printed.
- "### Notes" (after the sheet's table and its truncation markers) lists
  each cell note or comment as "- c2 row 3 (B3), <author>: <text>" in
  row-then-column order. A threaded comment is preferred over the legacy
  note of the same cell (which then only holds a placeholder); the author
  part is left out when it is unknown.
- "### Shapes" lists each shape, text box or callout of the sheet's drawing
  as '- "<name>" at c3 row 5 to c6 row 9: <text>' (paragraphs joined by
  <br>; "(no text)" for a shape without text). The anchor is 1-based; a
  one-cell anchor prints no "to" part and an absolute anchor prints "at an
  absolute position". Group shapes are walked and their members printed
  with the group's anchor; connectors are skipped. A chart prints
  '- chart "<name>" at ...: (chart; data not read)', any other graphic
  frame '- graphic frame "<name>" at ...: (graphic frame; content not read)'.
- "### Images" lists each picture as
  '- "<name>" at ...: image1.png (12345 bytes)', plus
  ", extracted to DIR/<file>" with --extract-media DIR, which writes each
  referenced media member to DIR/<sheet-slug>-<media name> (DIR is created
  only when there is something to write; the slug is the sheet name with
  every character outside A-Z a-z 0-9 . _ - replaced by _, cut to 40
  characters; the media name is the member's base name with the same
  replacement, so a written name never holds a path separator or another
  character a file system may refuse; a name already taken, by another
  member or by another sheet whose slug is the same, gets -2, -3, ...
  before its extension; the same member shown twice on one sheet is
  written once). Nothing is written anywhere else, and the image
  content is never decoded. A linked (external) picture prints
  "(linked image; not read)".
- A part that is missing or malformed (a note part, a drawing, a
  relationship part, a persons part, a media member), a relationship
  whose target points outside the package, or a drawing or legacy drawing
  that the sheet declares but whose relationship id its relationship part
  does not hold (or the sheet has no relationship part), never stops the
  run: the sheet section gets a one-line "[unreadable: ...]" marker
  instead. A relationship marked external is not followed and needs no
  marker.

Layout (--layout, default auto): "table" prints the Markdown table above;
"cells" prints, instead of the table, one line per non-empty cell in
row-then-column order, "- r3 c1 [merged c1-c3 rows 3-5]: <text>" (the
merge marker only on a top-left cell; a hidden row prints "r3 (hidden)", a
hidden column "c1 (hidden)"), under the heading
"## Sheet: NAME (layout: cells)"; the row and column caps and their
markers apply the same way. "auto" picks cells for a sheet when its table
would have more than 12 columns AND fewer than 30 percent of the cells of
its bounding box (rows printed x widest column) are non-empty (a merge
marker counts as a value), or when a merged range spans at least 2 rows
AND at least 2 columns; otherwise it picks table, whose heading is
unchanged.

Exit status: 0 success (possibly with truncation or unreadable markers), 2
the file is not a readable .xlsx workbook, 3 the workbook exceeds the
safety limits (member count, uncompressed size) applied before anything is
parsed.
"""
import argparse
import datetime
import os
import posixpath
import re
import sys
import xml.etree.ElementTree as ET
import zipfile

MAX_MEMBERS = 4096
MAX_MEMBER_BYTES = 64 * 1024 * 1024
MAX_TOTAL_BYTES = 256 * 1024 * 1024

NS_MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
NS_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
NS_PKG = "http://schemas.openxmlformats.org/package/2006/relationships"
BUILTIN_DATE_FORMATS = {14, 15, 16, 17, 18, 19, 20, 21, 22, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 45, 46, 47, 50, 51, 52, 53, 54, 55, 56, 57, 58}
DATE_FORMAT_RE = re.compile(r"[dmyhs]", re.IGNORECASE)
CELL_REF_RE = re.compile(r"^\$?([A-Za-z]{1,3})\$?([0-9]+)$")
SLUG_RE = re.compile(r"[^A-Za-z0-9._-]")
UNKNOWN_POS = 10 ** 9


def fail(code, message):
    sys.stderr.write("xlsx_to_text: " + message + "\n")
    sys.exit(code)


def column_index(ref):
    """B3 -> 2 (1-based column number)."""
    n = 0
    for ch in ref:
        if ch.isalpha():
            n = n * 26 + (ord(ch.upper()) - 64)
        else:
            break
    return n


def cell_ref(ref):
    """B3 -> (2, 3) as (column, row); None when ref is not a cell address."""
    m = CELL_REF_RE.match((ref or "").strip())
    if m is None:
        return None
    return column_index(m.group(1)), int(m.group(2))


def local(tag):
    """Element name without its namespace."""
    if not isinstance(tag, str):
        return ""
    return tag.rsplit("}", 1)[-1]


def child(node, name):
    """First direct child of node whose local name is name, or None."""
    if node is None:
        return None
    for item in node:
        if local(item.tag) == name:
            return item
    return None


def path(node, *names):
    for name in names:
        node = child(node, name)
    return node


def flag_on(element):
    """A boolean property element (<strike/>, <strike val="1"/>) is on."""
    return (element.get("val") or "1").strip().lower() not in ("0", "false", "off")


def text_of(node):
    """Concatenate the t elements below node (rich text runs included),
    skipping rPh phonetic-guide runs, which are reading aids and not part
    of the cell text."""
    parts = []
    for item in node:
        if item.tag == "{%s}rPh" % NS_MAIN:
            continue
        if item.tag == "{%s}t" % NS_MAIN:
            parts.append(item.text or "")
        else:
            parts.append(text_of(item))
    return "".join(parts)


def runs_of(node):
    """[(text, strike)] for the runs below node, rPh runs skipped. strike is
    True / False for a run whose run font holds a strike element, None for
    text that follows the cell style."""
    runs = []
    for item in node:
        if item.tag == "{%s}rPh" % NS_MAIN:
            continue
        if item.tag == "{%s}t" % NS_MAIN:
            runs.append((item.text or "", None))
        elif item.tag == "{%s}r" % NS_MAIN:
            props = item.find("{%s}rPr" % NS_MAIN)
            strike = None
            if props is not None:
                mark = props.find("{%s}strike" % NS_MAIN)
                if mark is not None:
                    strike = flag_on(mark)
            runs.append((text_of(item), strike))
        else:
            runs.extend(runs_of(item))
    return runs


def struck(text):
    """~~text~~, with surrounding whitespace kept outside the markers."""
    core = text.strip()
    if not core:
        return text
    lead = text[: len(text) - len(text.lstrip())]
    trail = text[len(text.rstrip()):]
    return lead + "~~" + core + "~~" + trail


def render_runs(runs, cell_strike):
    if cell_strike:
        return struck("".join(text for text, _ in runs))
    groups = []
    for text, strike in runs:
        on = bool(strike)
        if groups and groups[-1][0] == on:
            groups[-1][1] += text
        else:
            groups.append([on, text])
    return "".join(struck(text) if on else text for on, text in groups)


def check_limits(zf):
    infos = zf.infolist()
    if len(infos) > MAX_MEMBERS:
        fail(3, "workbook has %d members (limit %d)" % (len(infos), MAX_MEMBERS))
    total = 0
    for info in infos:
        if info.file_size > MAX_MEMBER_BYTES:
            fail(3, "member %s is %d bytes uncompressed (limit %d)" % (info.filename, info.file_size, MAX_MEMBER_BYTES))
        total += info.file_size
    if total > MAX_TOTAL_BYTES:
        fail(3, "workbook is %d bytes uncompressed (limit %d)" % (total, MAX_TOTAL_BYTES))


def read_xml(zf, name):
    try:
        data = zf.read(name)
    except KeyError:
        return None
    except Exception as exc:
        # A damaged member (bad CRC, broken or unsupported compression,
        # encryption) is an unreadable workbook, not a crash.
        fail(2, "cannot read %s: %s" % (name, str(exc) or type(exc).__name__))
    try:
        return ET.fromstring(data)
    except ET.ParseError as exc:
        fail(2, "cannot parse %s: %s" % (name, exc))


def soft_xml(zf, name):
    """(root, None), or (None, reason) for a missing or malformed part; never
    raises."""
    try:
        data = zf.read(name)
    except KeyError:
        return None, "member %s is missing" % name
    except Exception as exc:
        return None, "member %s cannot be read (%s)" % (name, type(exc).__name__)
    try:
        return ET.fromstring(data), None
    except Exception:
        return None, "cannot parse %s" % name


def resolve(part, target):
    """Package member a relationship target of part points at, or None."""
    if target.startswith("/"):
        resolved = posixpath.normpath(target[1:])
    else:
        resolved = posixpath.normpath(posixpath.join(posixpath.dirname(part), target))
    if resolved.startswith("../") or resolved in ("..", "."):
        return None
    return resolved


def rels_of(zf, part):
    """([(id, type, member or None, problem or None)], reason) from the
    relationship part of part; an absent relationship part is no
    relationship and no reason. An external target has member None and no
    problem; an internal target that is empty or points outside the package
    has member None and a problem naming it."""
    name = posixpath.join(posixpath.dirname(part), "_rels", posixpath.basename(part) + ".rels")
    try:
        zf.getinfo(name)
    except KeyError:
        return [], None
    root, reason = soft_xml(zf, name)
    if root is None:
        return [], reason
    result = []
    for rel in root.iter():
        if local(rel.tag) != "Relationship":
            continue
        rid = rel.get("Id", "")
        target = rel.get("Target", "")
        member = None
        problem = None
        if rel.get("TargetMode", "Internal") != "External":
            if target:
                member = resolve(part, target)
            if member is None:
                problem = "relationship %s target %s is outside the package" % (escape(rid) or "(no id)", escape(target) or "(empty)")
        result.append((rid, rel.get("Type", ""), member, problem))
    return result, None


def shared_strings(zf):
    root = read_xml(zf, "xl/sharedStrings.xml")
    if root is None:
        return []
    return [runs_of(si) for si in root.iter("{%s}si" % NS_MAIN)]


def style_sets(zf):
    """(cellXfs indexes whose number format is a date format, cellXfs
    indexes whose font strikes)."""
    root = read_xml(zf, "xl/styles.xml")
    if root is None:
        return set(), set()
    custom = {}
    for fmt in root.iter("{%s}numFmt" % NS_MAIN):
        try:
            custom[int(fmt.get("numFmtId", "-1"))] = fmt.get("formatCode", "")
        except ValueError:
            pass
    struck_fonts = set()
    fonts = root.find("{%s}fonts" % NS_MAIN)
    if fonts is not None:
        for index, font in enumerate(fonts.findall("{%s}font" % NS_MAIN)):
            mark = font.find("{%s}strike" % NS_MAIN)
            if mark is not None and flag_on(mark):
                struck_fonts.add(index)
    dates = set()
    strikes = set()
    xfs = root.find("{%s}cellXfs" % NS_MAIN)
    if xfs is None:
        return dates, strikes
    for index, xf in enumerate(xfs.findall("{%s}xf" % NS_MAIN)):
        try:
            if int(xf.get("fontId", "0")) in struck_fonts:
                strikes.add(index)
        except ValueError:
            pass
        try:
            fmt_id = int(xf.get("numFmtId", "0"))
        except ValueError:
            continue
        if fmt_id in BUILTIN_DATE_FORMATS:
            dates.add(index)
        elif fmt_id in custom:
            code = re.sub(r'"[^"]*"', "", custom[fmt_id])
            code = re.sub(r"\[[^\]]*\]", "", code)
            if DATE_FORMAT_RE.search(code) and "0" not in code.replace("0.", ""):
                dates.add(index)
    return dates, strikes


def sheets(zf):
    """[(name, member path, hidden)] in workbook order."""
    wb = read_xml(zf, "xl/workbook.xml")
    if wb is None:
        fail(2, "xl/workbook.xml is missing; not an .xlsx workbook")
    rels = read_xml(zf, "xl/_rels/workbook.xml.rels")
    targets = {}
    if rels is not None:
        for rel in rels.iter("{%s}Relationship" % NS_PKG):
            target = rel.get("Target", "")
            if target.startswith("/"):
                target = target[1:]
            elif not target.startswith("xl/"):
                target = "xl/" + target
            targets[rel.get("Id")] = target
    result = []
    for sheet in wb.iter("{%s}sheet" % NS_MAIN):
        rid = sheet.get("{%s}id" % NS_REL)
        member = targets.get(rid)
        if member is None:
            continue
        hidden = sheet.get("state", "visible") != "visible"
        result.append((sheet.get("name", "Sheet"), member, hidden))
    if not result:
        fail(2, "the workbook lists no worksheet")
    return result


def serial_to_text(value, date1904):
    try:
        serial = float(value)
    except ValueError:
        return value
    base = datetime.datetime(1904, 1, 1) if date1904 else datetime.datetime(1899, 12, 30)
    try:
        moment = base + datetime.timedelta(days=serial)
    except OverflowError:
        return value
    if abs(serial - round(serial)) < 1e-9:
        return moment.strftime("%Y-%m-%d")
    return moment.strftime("%Y-%m-%dT%H:%M:%S")


def cell_value(cell, strings, is_date, cell_strike, date1904):
    kind = cell.get("t", "n")
    if kind == "inlineStr":
        return render_runs(runs_of(cell), cell_strike)
    v = cell.find("{%s}v" % NS_MAIN)
    if v is None or v.text is None:
        return ""
    raw = v.text
    if kind == "s":
        try:
            return render_runs(strings[int(raw)], cell_strike)
        except (ValueError, IndexError):
            value = raw
    elif kind == "b":
        value = "TRUE" if raw.strip() == "1" else "FALSE"
    elif kind in ("str", "e"):
        value = raw
    elif is_date:
        value = serial_to_text(raw, date1904)
    else:
        try:
            number = float(raw)
        except ValueError:
            number = None
        if number is not None and number.is_integer() and "e" not in raw.lower():
            value = str(int(number))
        else:
            value = raw
    return struck(value) if cell_strike else value


def escape(value):
    value = value.replace("\\", "\\\\").replace("|", "\\|")
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    return "<br>".join(" ".join(line.split()) for line in value.split("\n"))


def merge_marker(c1, r1, c2, r2):
    parts = []
    if c1 != c2:
        parts.append("c%d-c%d" % (c1, c2))
    if r1 != r2:
        parts.append("rows %d-%d" % (r1, r2))
    return "[merged %s]" % " ".join(parts)


def anchor_text(anchor):
    kind = local(anchor.tag)
    if kind == "absoluteAnchor":
        return "at an absolute position"

    def point(name):
        node = child(anchor, name)
        try:
            return "c%d row %d" % (int(child(node, "col").text) + 1, int(child(node, "row").text) + 1)
        except (AttributeError, TypeError, ValueError):
            return None

    start = point("from")
    if start is None:
        return "at an unknown position"
    if kind == "twoCellAnchor":
        end = point("to")
        if end is not None:
            return "at %s to %s" % (start, end)
    return "at " + start


def content_children(node):
    """Children of node, with markup-compatibility wrappers replaced by the
    content of their first Choice (or their Fallback when no Choice)."""
    for item in node:
        if local(item.tag) == "AlternateContent":
            branch = child(item, "Choice")
            if branch is None:
                branch = child(item, "Fallback")
            if branch is not None:
                for inner in content_children(branch):
                    yield inner
        else:
            yield item


def shape_text(shape):
    body = child(shape, "txBody")
    if body is None:
        return ""
    paragraphs = []
    for para in body:
        if local(para.tag) != "p":
            continue
        parts = []
        for node in para.iter():
            name = local(node.tag)
            if name == "t":
                parts.append(node.text or "")
            elif name == "br":
                parts.append("\n")
        paragraphs.append("".join(parts).strip(" \t"))
    if not any(para.strip() for para in paragraphs):
        return ""
    return "\n".join(paragraphs)


def name_of(node, props_path):
    props = path(node, *props_path)
    return escape(props.get("name", "") if props is not None else "")


def slug(text):
    return SLUG_RE.sub("_", text)


class Context(object):
    """Workbook-wide state shared by every sheet."""

    def __init__(self, zf, limits, strings, dates, strikes, date1904):
        self.zf = zf
        self.limits = limits
        self.strings = strings
        self.dates = dates
        self.strikes = strikes
        self.date1904 = date1904
        self.persons = None
        self.person_errors = []
        self.extracted = {}
        self.taken = {}

    def person_names(self):
        """{person id: display name}; problems reading a persons part go to
        person_errors. A declared persons part that is missing or malformed
        is a problem; the default xl/persons/person.xml, used when none is
        declared, is a problem only when present but malformed."""
        if self.persons is not None:
            return self.persons
        self.persons = {}
        members = []
        declared = False
        rels, reason = rels_of(self.zf, "xl/workbook.xml")
        if reason is not None:
            self.person_errors.append("workbook relationships: " + reason)
        for _, kind, member, problem in rels:
            if not kind.endswith("/person"):
                continue
            declared = True
            if member is not None:
                members.append(member)
            elif problem is not None:
                self.person_errors.append("persons: " + problem)
        if not declared:
            members = ["xl/persons/person.xml"]
        for member in members:
            if not declared and member not in self.zf.namelist():
                continue
            root, reason = soft_xml(self.zf, member)
            if root is None:
                self.person_errors.append("persons: " + reason)
                continue
            for person in root.iter():
                if local(person.tag) == "person" and person.get("id") is not None:
                    self.persons[person.get("id")] = person.get("displayName", "")
        return self.persons

    def extract(self, sheet_name, member):
        """Write member under --extract-media once; return the line suffix."""
        directory = self.limits.extract_media
        key = (sheet_name, member)
        if key not in self.extracted:
            base = slug(posixpath.basename(member)) or "media"
            name = slug(sheet_name)[:40] + "-" + base
            stem, ext = os.path.splitext(name)
            n = 1
            while name in self.taken:
                n += 1
                name = "%s-%d%s" % (stem, n, ext)
            try:
                data = self.zf.read(member)
                os.makedirs(directory, exist_ok=True)
                with open(os.path.join(directory, name), "wb") as handle:
                    handle.write(data)
                self.taken[name] = member
                shown = directory.rstrip("/") or "/"
                self.extracted[key] = ", extracted to %s/%s" % (shown.rstrip("/"), name)
            except Exception as exc:
                reason = getattr(exc, "strerror", None) or type(exc).__name__
                self.extracted[key] = ", not extracted (%s)" % reason
        return self.extracted[key]


def sheet_notes(ctx, rels):
    """(lines, unreadable reasons) of the sheet's notes and comments."""
    zf = ctx.zf
    legacy = []
    threaded = []
    errors = []
    seq = 0
    for _, kind, member, problem in rels:
        if kind.endswith("/comments"):
            if member is None:
                if problem is not None:
                    errors.append("notes: " + problem)
                continue
            root, reason = soft_xml(zf, member)
            if root is None:
                errors.append("notes: " + reason)
                continue
            authors = [text_of(a) or (a.text or "") for a in root.iter() if local(a.tag) == "author"]
            for note in root.iter():
                if local(note.tag) != "comment":
                    continue
                seq += 1
                author = ""
                try:
                    idx = int(note.get("authorId", ""))
                except ValueError:
                    idx = -1
                if 0 <= idx < len(authors):
                    author = authors[idx]
                body = child(note, "text")
                legacy.append((note.get("ref", ""), author, text_of(body) if body is not None else "", seq))
        elif kind.endswith("/threadedComment"):
            if member is None:
                if problem is not None:
                    errors.append("threaded comments: " + problem)
                continue
            root, reason = soft_xml(zf, member)
            if root is None:
                errors.append("threaded comments: " + reason)
                continue
            persons = ctx.person_names()
            for issue in ctx.person_errors:
                if issue not in errors:
                    errors.append(issue)
            for note in root.iter():
                if local(note.tag) != "threadedComment":
                    continue
                seq += 1
                body = child(note, "text")
                threaded.append((note.get("ref", ""), persons.get(note.get("personId", ""), ""), (body.text or "") if body is not None else "", seq))
    threaded_refs = set(ref.strip().upper() for ref, _, _, _ in threaded)
    entries = [e for e in legacy if e[0].strip().upper() not in threaded_refs] + threaded
    keyed = []
    for ref, author, text, order in entries:
        pos = cell_ref(ref)
        if pos is None:
            keyed.append(((UNKNOWN_POS, UNKNOWN_POS, order), "- %s" % (escape(ref) or "(no address)"), author, text))
        else:
            keyed.append(((pos[1], pos[0], order), "- c%d row %d (%s)" % (pos[0], pos[1], ref.strip()), author, text))
    keyed.sort(key=lambda e: e[0])
    lines = []
    for _, head, author, text in keyed:
        if author.strip():
            head += ", " + escape(author)
        lines.append("%s: %s" % (head, escape(text) or "(no text)"))
    return lines, errors


def sheet_drawings(ctx, sheet_name, rels):
    """(shape lines, image lines, unreadable reasons) of the sheet's drawings."""
    zf = ctx.zf
    shapes = []
    images = []
    errors = []
    for _, kind, member, problem in rels:
        if not kind.endswith("/drawing"):
            continue
        if member is None:
            if problem is not None:
                errors.append("drawing: " + problem)
            continue
        root, reason = soft_xml(zf, member)
        if root is None:
            errors.append("drawing: " + reason)
            continue
        drels, reason = rels_of(zf, member)
        if reason is not None:
            errors.append("drawing relationships: " + reason)
        targets = {}
        for rid, _, target, problem in drels:
            targets.setdefault(rid, (target, problem))

        def picture(node, where):
            label = name_of(node, ("nvPicPr", "cNvPr"))
            rid = ""
            for item in node.iter():
                if local(item.tag) == "blip":
                    rid = item.get("{%s}embed" % NS_REL) or item.get("{%s}link" % NS_REL) or ""
                    break
            head = '- "%s" %s: ' % (label, where)
            if rid not in targets:
                return head + "[unreadable: image relationship %s not found]" % (escape(rid) or "(none)")
            media, problem = targets[rid]
            if media is None:
                if problem is not None:
                    return head + "[unreadable: image %s]" % problem
                return head + "(linked image; not read)"
            try:
                size = zf.getinfo(media).file_size
            except KeyError:
                return head + "[unreadable: media member %s is missing]" % escape(media)
            line = head + "%s (%d bytes)" % (escape(posixpath.basename(media)), size)
            if ctx.limits.extract_media:
                line += ctx.extract(sheet_name, media)
            return line

        def walk(node, where):
            name = local(node.tag)
            if name == "sp":
                text = escape(shape_text(node))
                shapes.append('- "%s" %s: %s' % (name_of(node, ("nvSpPr", "cNvPr")), where, text or "(no text)"))
            elif name == "grpSp":
                for inner in content_children(node):
                    walk(inner, where)
            elif name == "graphicFrame":
                label = name_of(node, ("nvGraphicFramePr", "cNvPr"))
                data = path(node, "graphic", "graphicData")
                uri = data.get("uri", "") if data is not None else ""
                if uri.rstrip("/").endswith("/chart"):
                    shapes.append('- chart "%s" %s: (chart; data not read)' % (label, where))
                else:
                    shapes.append('- graphic frame "%s" %s: (graphic frame; content not read)' % (label, where))
            elif name == "pic":
                images.append(picture(node, where))

        for anchor in content_children(root):
            if local(anchor.tag) not in ("twoCellAnchor", "oneCellAnchor", "absoluteAnchor"):
                continue
            where = anchor_text(anchor)
            for item in content_children(anchor):
                walk(item, where)
    return shapes, images, errors


def is_on(value):
    return (value or "0").strip().lower() in ("1", "true")


def dump_sheet(ctx, name, member, hidden, out):
    zf = ctx.zf
    limits = ctx.limits
    root = read_xml(zf, member)
    if root is None:
        out.append("## Sheet: %s\n\n[unreadable: member %s is missing]\n" % (name, member))
        return
    rows = []
    hidden_rows = set()
    max_col = 0
    rows_seen = 0
    last_row = 0
    for row in root.iter("{%s}row" % NS_MAIN):
        rows_seen += 1
        if rows_seen > limits.max_rows:
            break
        try:
            r = int(row.get("r", str(len(rows) + 1)))
        except ValueError:
            r = len(rows) + 1
        last_row = max(last_row, r)
        if is_on(row.get("hidden")):
            hidden_rows.add(r)
        cells = {}
        for cell in row.findall("{%s}c" % NS_MAIN):
            ref = cell.get("r", "")
            c = column_index(ref)
            if c == 0 or c > limits.max_cols:
                continue
            style = cell.get("s")
            is_date = False
            is_struck = False
            if style is not None:
                try:
                    is_date = int(style) in ctx.dates
                    is_struck = int(style) in ctx.strikes
                except ValueError:
                    pass
            value = cell_value(cell, ctx.strings, is_date, is_struck, ctx.date1904)
            if value != "":
                cells[c] = value
                max_col = max(max_col, c)
        if cells:
            rows.append((r, cells))
    truncated_rows = rows_seen > limits.max_rows

    # Merged ranges: a marker on each top-left cell inside the caps.
    markers = {}
    block_merge = False
    merge_beyond = False
    merges = root.find("{%s}mergeCells" % NS_MAIN)
    if merges is not None:
        for merge in merges.findall("{%s}mergeCell" % NS_MAIN):
            ends = (merge.get("ref") or "").split(":")
            if len(ends) != 2:
                continue
            a, b = cell_ref(ends[0]), cell_ref(ends[1])
            if a is None or b is None:
                continue
            c1, c2 = min(a[0], b[0]), max(a[0], b[0])
            r1, r2 = min(a[1], b[1]), max(a[1], b[1])
            if c1 > limits.max_cols:
                merge_beyond = True
                continue
            if (c1, r1) == (c2, r2) or (r1, c1) in markers:
                continue
            if truncated_rows and r1 > last_row:
                continue
            markers[(r1, c1)] = merge_marker(c1, r1, c2, r2)
            if r2 > r1 and c2 > c1:
                block_merge = True
    if markers:
        present = set(r for r, _ in rows)
        for (r1, c1) in sorted(markers):
            if r1 not in present:
                rows.append((r1, {}))
                present.add(r1)
            max_col = max(max_col, c1)
        rows.sort(key=lambda entry: entry[0])
    marked = {}
    for (r1, c1) in markers:
        marked.setdefault(r1, set()).add(c1)

    hidden_cols = set()
    cols = root.find("{%s}cols" % NS_MAIN)
    if cols is not None:
        for col in cols.findall("{%s}col" % NS_MAIN):
            if not is_on(col.get("hidden")):
                continue
            try:
                lo, hi = int(col.get("min", "0")), int(col.get("max", "0"))
            except ValueError:
                continue
            for c in range(max(lo, 1), min(hi, limits.max_cols) + 1):
                hidden_cols.add(c)

    width = max_col
    layout = limits.layout
    if layout == "auto":
        filled = sum(len(set(cells) | marked.get(r, set())) for r, cells in rows)
        sparse = width > 12 and filled * 10 < 3 * len(rows) * width
        layout = "cells" if (sparse or block_merge) else "table"

    out.append("## Sheet: %s%s%s\n\n" % (name, " (hidden)" if hidden else "", " (layout: cells)" if layout == "cells" else ""))
    if not rows:
        out.append("(empty sheet)\n")
    elif layout == "cells":
        for r, cells in rows:
            for c in sorted(set(cells) | marked.get(r, set())):
                line = "- r%d%s c%d%s" % (r, " (hidden)" if r in hidden_rows else "", c, " (hidden)" if c in hidden_cols else "")
                if (r, c) in markers:
                    line += " " + markers[(r, c)]
                text = escape(cells.get(c, ""))
                out.append(line + ":" + (" " + text if text else "") + "\n")
    else:
        out.append("| row | " + " | ".join("c%d%s" % (c, " (hidden)" if c in hidden_cols else "") for c in range(1, width + 1)) + " |\n")
        out.append("|---|" + "---|" * width + "\n")
        for r, cells in rows:
            shown = []
            for c in range(1, width + 1):
                value = cells.get(c, "")
                if (r, c) in markers:
                    value = markers[(r, c)] + (" " + value if value else "")
                shown.append(escape(value))
            out.append("| %d%s | " % (r, " (hidden)" if r in hidden_rows else "") + " | ".join(shown) + " |\n")
    if rows:
        if truncated_rows:
            out.append("\n[truncated: sheet %s has more than %d rows; only the first %d were read]\n" % (name, limits.max_rows, limits.max_rows))
        wide = merge_beyond or any(column_index(cell.get("r", "")) > limits.max_cols for row in root.iter("{%s}row" % NS_MAIN) for cell in row.findall("{%s}c" % NS_MAIN))
        if wide:
            out.append("\n[truncated: sheet %s has columns beyond c%d; they were not read]\n" % (name, limits.max_cols))

    rels, reason = rels_of(zf, member)
    if reason is not None:
        out.append("\n[unreadable: sheet relationships: %s]\n" % reason)
    else:
        # A drawing or legacy drawing the sheet declares must resolve through
        # its relationship part; a missing part or id would drop the sheet's
        # shapes, images or notes without a trace.
        known = set(rid for rid, _, _, _ in rels)
        for tag, label in (("drawing", "drawing relationship %s not found"), ("legacyDrawing", "legacy drawing relationship %s not found; the notes of the sheet may be missing")):
            for element in root.findall("{%s}%s" % (NS_MAIN, tag)):
                rid = element.get("{%s}id" % NS_REL) or ""
                if rid not in known:
                    out.append("\n[unreadable: %s]\n" % (label % (escape(rid) or "(no id)")))
    notes, note_errors = sheet_notes(ctx, rels)
    shapes, images, drawing_errors = sheet_drawings(ctx, name, rels)
    for problem in note_errors:
        out.append("\n[unreadable: %s]\n" % problem)
    if notes:
        out.append("\n### Notes\n" + "".join(line + "\n" for line in notes))
    for problem in drawing_errors:
        out.append("\n[unreadable: %s]\n" % problem)
    if shapes:
        out.append("\n### Shapes\n" + "".join(line + "\n" for line in shapes))
    if images:
        out.append("\n### Images\n" + "".join(line + "\n" for line in images))
    out.append("\n")


def main():
    parser = argparse.ArgumentParser(description="Dump an .xlsx workbook as Markdown text (stdlib only): one section per worksheet with its cells, notes, shapes and images.")
    parser.add_argument("workbook")
    parser.add_argument("--max-rows", type=int, default=2000, help="rows read per sheet (default 2000)")
    parser.add_argument("--max-cols", type=int, default=64, help="columns read per sheet (default 64)")
    parser.add_argument("--max-chars", type=int, default=200000, help="characters of output in total (default 200000)")
    parser.add_argument("--sheet", action="append", default=[], help="worksheet name to read (repeatable); default: every worksheet")
    parser.add_argument("--layout", choices=("table", "cells", "auto"), default="auto", help="table: a Markdown table per sheet; cells: one line per non-empty cell; auto (default): cells for a sheet wider than 12 columns that is less than 30 percent filled, or one with a merged range of at least 2 rows and 2 columns, table otherwise")
    parser.add_argument("--extract-media", metavar="DIR", default=None, help="write every image of a listed sheet to DIR/<sheet-slug>-<media name>, both parts with every character outside A-Z a-z 0-9 . _ - replaced by _ (DIR is created when needed); default: list the images only")
    limits = parser.parse_args()
    if limits.max_rows < 1 or limits.max_cols < 1 or limits.max_chars < 1:
        fail(2, "every --max-* value must be at least 1")
    if limits.extract_media is not None and not limits.extract_media:
        fail(2, "--extract-media needs a directory")
    try:
        zf = zipfile.ZipFile(limits.workbook)
    except (zipfile.BadZipFile, OSError) as exc:
        fail(2, "cannot open %s as a zip archive: %s" % (limits.workbook, exc))
    with zf:
        check_limits(zf)
        strings = shared_strings(zf)
        dates, strikes = style_sets(zf)
        wb = read_xml(zf, "xl/workbook.xml")
        date1904 = False
        if wb is not None:
            pr = wb.find("{%s}workbookPr" % NS_MAIN)
            if pr is not None and pr.get("date1904", "0") in ("1", "true"):
                date1904 = True
        out = ["# Workbook: %s\n\n" % limits.workbook.replace("\\", "/").split("/")[-1]]
        chosen = sheets(zf)
        if limits.sheet:
            names = [name for name, _, _ in chosen]
            missing = [want for want in limits.sheet if want not in names]
            if missing:
                fail(2, "sheet(s) not found: %s; the workbook has: %s" % (", ".join(missing), ", ".join(names)))
            chosen = [entry for entry in chosen if entry[0] in limits.sheet]
        ctx = Context(zf, limits, strings, dates, strikes, date1904)
        emitted = len(out[0])
        for name, member, hidden in chosen:
            # Past the cap nothing more would be printed, so the remaining
            # worksheets are neither parsed nor held in memory.
            if emitted > limits.max_chars:
                break
            before = len(out)
            dump_sheet(ctx, name, member, hidden, out)
            emitted += sum(len(piece) for piece in out[before:])
    text = "".join(out)
    if len(text) > limits.max_chars:
        notice = "\n[truncated: output exceeds %d characters; the rest of the workbook was not emitted]\n" % limits.max_chars
        text = text[: max(limits.max_chars - len(notice), 0)] + notice
    sys.stdout.write(text)


if __name__ == "__main__":
    main()
