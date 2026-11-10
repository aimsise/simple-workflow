target: scripts/xlsx_to_text.py
heading: (end of file)
mode: append
---
#!/usr/bin/env python3
"""Dump every worksheet of an .xlsx workbook as Markdown tables.

Standard library only (zipfile + xml.etree), so it runs wherever python3
runs; no third-party package is required. Run it as

    python3 -I xlsx_to_text.py WORKBOOK.xlsx [--max-rows N] [--max-cols N]
                                           [--max-chars N] [--sheet NAME ...]

Output (stdout): one "## Sheet: NAME" section per worksheet (every
worksheet, or only those named by --sheet, exact match; an unknown name
exits 2 and lists the names the workbook has), each a
Markdown table whose first column is the 1-based row number of the
worksheet, so every cell keeps its worksheet address (sheet name and row)
in the text that the skill reads and cites. Caps: --max-rows rows
per sheet (default 2000), --max-cols columns per sheet (default 64),
--max-chars characters of output in total (default 200000); a cap that is
hit is reported as a line starting with "[truncated:" at the point it
applies, never silently.

Cell values: shared and inline strings, numbers (a cell whose number format
is a date format is printed as an ISO date or date-time from its serial
value), booleans as TRUE / FALSE, cell errors as their text (#N/A, ...),
formulas as their cached value. Merged ranges are not expanded: the value
sits in the top-left cell and the other cells are blank. Hidden sheets are
included and marked. The date detection reads the cell's number format;
a custom elapsed-time format such as mm:ss is only approximated and may
print as a date-time near the epoch.

Exit status: 0 success (possibly with truncation markers), 2 the file is
not a readable .xlsx workbook, 3 the workbook exceeds the safety limits
(member count, uncompressed size) applied before anything is parsed.
"""
import argparse
import datetime
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


def text_of(node):
    """Concatenate the t elements below node (rich text runs included),
    skipping rPh phonetic-guide runs, which are reading aids and not part
    of the cell text."""
    parts = []
    for child in node:
        if child.tag == "{%s}rPh" % NS_MAIN:
            continue
        if child.tag == "{%s}t" % NS_MAIN:
            parts.append(child.text or "")
        else:
            parts.append(text_of(child))
    return "".join(parts)


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
    try:
        return ET.fromstring(data)
    except ET.ParseError as exc:
        fail(2, "cannot parse %s: %s" % (name, exc))


def shared_strings(zf):
    root = read_xml(zf, "xl/sharedStrings.xml")
    if root is None:
        return []
    return [text_of(si) for si in root.iter("{%s}si" % NS_MAIN)]


def date_styles(zf):
    """Set of cellXfs indexes whose number format is a date format."""
    root = read_xml(zf, "xl/styles.xml")
    if root is None:
        return set()
    custom = {}
    for fmt in root.iter("{%s}numFmt" % NS_MAIN):
        try:
            custom[int(fmt.get("numFmtId", "-1"))] = fmt.get("formatCode", "")
        except ValueError:
            pass
    result = set()
    xfs = root.find("{%s}cellXfs" % NS_MAIN)
    if xfs is None:
        return result
    for index, xf in enumerate(xfs.findall("{%s}xf" % NS_MAIN)):
        try:
            fmt_id = int(xf.get("numFmtId", "0"))
        except ValueError:
            continue
        if fmt_id in BUILTIN_DATE_FORMATS:
            result.add(index)
        elif fmt_id in custom:
            code = re.sub(r'"[^"]*"', "", custom[fmt_id])
            code = re.sub(r"\[[^\]]*\]", "", code)
            if DATE_FORMAT_RE.search(code) and "0" not in code.replace("0.", ""):
                result.add(index)
    return result


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


def cell_value(cell, strings, is_date, date1904):
    kind = cell.get("t", "n")
    if kind == "inlineStr":
        return text_of(cell)
    v = cell.find("{%s}v" % NS_MAIN)
    if v is None or v.text is None:
        return ""
    raw = v.text
    if kind == "s":
        try:
            return strings[int(raw)]
        except (ValueError, IndexError):
            return raw
    if kind == "b":
        return "TRUE" if raw.strip() == "1" else "FALSE"
    if kind in ("str", "e"):
        return raw
    if is_date:
        return serial_to_text(raw, date1904)
    try:
        number = float(raw)
    except ValueError:
        return raw
    if number.is_integer() and "e" not in raw.lower():
        return str(int(number))
    return raw


def escape(value):
    value = value.replace("\\", "\\\\").replace("|", "\\|")
    return " ".join(value.split())


def dump_sheet(zf, name, member, hidden, strings, dates, date1904, limits, out):
    root = read_xml(zf, member)
    if root is None:
        out.append("## Sheet: %s\n\n[unreadable: member %s is missing]\n" % (name, member))
        return
    rows = []
    max_col = 0
    rows_seen = 0
    for row in root.iter("{%s}row" % NS_MAIN):
        rows_seen += 1
        if rows_seen > limits.max_rows:
            break
        try:
            r = int(row.get("r", str(len(rows) + 1)))
        except ValueError:
            r = len(rows) + 1
        cells = {}
        for cell in row.findall("{%s}c" % NS_MAIN):
            ref = cell.get("r", "")
            c = column_index(ref)
            if c == 0 or c > limits.max_cols:
                continue
            style = cell.get("s")
            is_date = False
            if style is not None:
                try:
                    is_date = int(style) in dates
                except ValueError:
                    pass
            value = cell_value(cell, strings, is_date, date1904)
            if value != "":
                cells[c] = value
                max_col = max(max_col, c)
        if cells:
            rows.append((r, cells))
    header = "## Sheet: %s%s\n\n" % (name, " (hidden)" if hidden else "")
    out.append(header)
    if not rows:
        out.append("(empty sheet)\n\n")
        return
    width = max_col
    out.append("| row | " + " | ".join("c%d" % c for c in range(1, width + 1)) + " |\n")
    out.append("|---|" + "---|" * width + "\n")
    for r, cells in rows:
        out.append("| %d | " % r + " | ".join(escape(cells.get(c, "")) for c in range(1, width + 1)) + " |\n")
    if rows_seen > limits.max_rows:
        out.append("\n[truncated: sheet %s has more than %d rows; only the first %d were read]\n" % (name, limits.max_rows, limits.max_rows))
    wide = any(column_index(cell.get("r", "")) > limits.max_cols for row in root.iter("{%s}row" % NS_MAIN) for cell in row.findall("{%s}c" % NS_MAIN))
    if wide:
        out.append("\n[truncated: sheet %s has columns beyond c%d; they were not read]\n" % (name, limits.max_cols))
    out.append("\n")


def main():
    parser = argparse.ArgumentParser(description="Dump an .xlsx workbook as Markdown tables (stdlib only).")
    parser.add_argument("workbook")
    parser.add_argument("--max-rows", type=int, default=2000)
    parser.add_argument("--max-cols", type=int, default=64)
    parser.add_argument("--max-chars", type=int, default=200000)
    parser.add_argument("--sheet", action="append", default=[], help="worksheet name to read (repeatable); default: every worksheet")
    limits = parser.parse_args()
    if limits.max_rows < 1 or limits.max_cols < 1 or limits.max_chars < 1:
        fail(2, "every --max-* value must be at least 1")
    try:
        zf = zipfile.ZipFile(limits.workbook)
    except (zipfile.BadZipFile, OSError) as exc:
        fail(2, "cannot open %s as a zip archive: %s" % (limits.workbook, exc))
    with zf:
        check_limits(zf)
        strings = shared_strings(zf)
        dates = date_styles(zf)
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
        for name, member, hidden in chosen:
            dump_sheet(zf, name, member, hidden, strings, dates, date1904, limits, out)
    text = "".join(out)
    if len(text) > limits.max_chars:
        text = text[: limits.max_chars] + "\n[truncated: output exceeds %d characters; the rest of the workbook was not emitted]\n" % limits.max_chars
    sys.stdout.write(text)


if __name__ == "__main__":
    main()
