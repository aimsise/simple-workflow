target: scripts/xlsx_render.py
heading: (end of file)
mode: append
---
#!/usr/bin/env python3
"""Render an .xlsx workbook to PDF through renderers installed on the host.

Standard library only. The render is optional: when no renderer is
available the script says so on one line and exits 0. Run it as

    python3 -I xlsx_render.py [--chain auto|excel|soffice] [--sheet NAME ...]
                              [--timeout SECONDS] [--soffice PATH]
                              [--excel-cmd PATH] [--only-if-structured FILE]
                              --out DIR -- WORKBOOK

Chain (--chain auto, the default): try each renderer that applies to the
platform, in this order, and stop at the first one that produces a PDF.

1. excel: the spreadsheet application (Microsoft Excel) through its
   automation interface. The script writes an automation script into its
   private temporary directory and runs

       macOS and every other non-Windows platform:
           osascript <tmp>/render.applescript <workbook copy> <tmp>/excel.pdf
       Windows (sys.platform win32):
           powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass
               -File <tmp>/render.ps1 <workbook copy> <tmp>/excel.pdf

   The AppleScript (on run argv) tests whether the application is running
   before it talks to it, sets its visible property to false and its
   display alerts to false before opening anything, opens the workbook with
   read only true, saves it (or each selected worksheet) with the PDF file
   format, closes it saving no, restores display alerts, and quits the
   application only when the script launched it (an application that was
   already running gets its visible property back). The PowerShell text
   (param($wb, $out)) creates the Excel.Application COM object with
   Visible, DisplayAlerts and ScreenUpdating false, opens the workbook with
   Workbooks.Open($wb, 0, $true) (read-only), calls
   ExportAsFixedFormat(0, $out), closes with Close($false), calls Quit()
   and releases every COM object in a finally block. The excel renderer
   applies on macOS when osascript and the application bundle
   (Microsoft Excel.app under /Applications or the user's Applications
   folder) exist, and on Windows when powershell.exe and the registered
   Excel.Application COM class exist; otherwise it fails with "not
   installed". On any other platform it is skipped with "no spreadsheet
   application on this platform".
2. soffice: LibreOffice, run as

       soffice -env:UserInstallation=file://<tmp>/profile --headless
           --norestore --convert-to pdf --outdir <tmp>/soffice <workbook copy>

   The private profile keeps a LibreOffice instance that is already running
   from taking the call. soffice is looked up on the PATH (soffice,
   soffice.exe, libreoffice), then at the usual install locations:
   /Applications/LibreOffice.app/Contents/MacOS/soffice (macOS),
   %ProgramFiles%\\LibreOffice\\program\\soffice.exe and the
   %ProgramFiles(x86)% variant (Windows), /usr/bin/soffice,
   /usr/lib/libreoffice/program/soffice and /snap/bin/libreoffice (Linux).
3. Nothing produced a PDF: the "Rendered: no" line below, exit 0.

--chain excel or --chain soffice tries only that renderer.

Guarantees: the workbook is never modified. It is copied into the private
temporary directory and only the copy is given to a renderer; excel opens
the copy read-only and closes it without saving, soffice only converts
it. No window is shown (visible false, --headless), nothing prompts (stdin
is closed, alerts are off), and nothing is written outside --out DIR and
the temporary directory, which is created inside DIR and removed before
the script exits.

Sheets: --sheet NAME (repeatable, exact names) restricts the excel render.
Each selected worksheet, in the order given, is exported to its own PDF;
the first selected sheet's PDF becomes the output (concatenating PDFs is
out of scope), and a name the workbook lacks makes the excel renderer fail
with "sheet not found: NAME". soffice has no sheet selection and always
renders every sheet. The workbook is never changed to select a sheet.

Timeout: --timeout SECONDS (default 120) is the wall-clock limit of each
renderer. On expiry the renderer's whole process group is killed (the
process tree on Windows) and the renderer fails with "timed out after N s";
for excel, a spreadsheet application that was not running before the
renderer started and is running after it is asked to quit, then killed.

Overrides (for tests and unusual installs): --soffice PATH replaces the
soffice program. --excel-cmd PATH replaces only the interpreter of the
excel renderer (osascript, or powershell.exe on Windows); the script still
generates the automation script and passes it with the same arguments, so
the output PDF path is always the LAST argument. A fake interpreter that
writes a file starting with %PDF to its last argument therefore serves
both shapes. A renderer given an override is tried on every platform.

Structured-only gate: --only-if-structured FILE reads FILE (the converter
output) and, when it holds no "### Shapes" or "### Images" line, no
"(layout: cells)" and no "[merged " marker, prints "Rendered: no (not
structured)" and exits 0 without trying a renderer. A FILE that cannot be
read prints "Rendered: no (structure file not readable)". With --chain
excel or --chain soffice the gate is ignored.

Output: the PDF is DIR/<slug>.pdf, where the slug is the workbook's base
name without its extension with every character outside A-Z a-z 0-9 . _ -
replaced by _, cut to 40 characters; an existing file is overwritten. Only
a non-empty file that starts with %PDF counts as a PDF. One line on stdout,
exit 0:

    Rendered: DIR/<slug>.pdf (by excel|soffice, <size> bytes, all sheets)
    Rendered: DIR/<slug>.pdf (by excel, <size> bytes, sheet NAME)
        (with "; other selected sheets not rendered" before the closing
        parenthesis when more than one sheet was selected)
    Rendered: no (<renderer>: <reason>; <renderer>: <reason>)

Reasons: not installed, no spreadsheet application on this platform,
timed out after N s, exit status N (followed by ": " and the first line of
the renderer's error output, cut to 120 characters, when there is one),
no PDF produced, sheet not found: NAME. Error output is otherwise
discarded; the home directory prefix in it is written as ~.

Exit status 2, with one line on stderr: a missing or unreadable workbook,
an empty --out or one that cannot be created, a bad --chain or --timeout
value, an empty --sheet name or one holding a control character.
"""
import argparse
import os
import pathlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

SLUG_RE = re.compile(r"[^A-Za-z0-9._-]")
STRUCTURE_RE = re.compile(r"^### (Shapes|Images)$|\(layout: cells\)|\[merged ", re.MULTILINE)
MISSING_RE = re.compile(r"xlsx-render: sheet-missing ([0-9]+)")
CONTROL_RE = re.compile(r"[\x00-\x1f\x7f]")
EXCEL_APP = "Microsoft Excel"
QUIT_WAIT = 10


def fail(message):
    sys.stderr.write("xlsx_render: " + message + "\n")
    sys.exit(2)


class Parser(argparse.ArgumentParser):
    def error(self, message):
        fail(message)


def emit(line):
    out = getattr(sys.stdout, "buffer", None)
    if out is None:
        sys.stdout.write(line + "\n")
    else:
        out.write((line + "\n").encode("utf-8", "replace"))
    sys.stdout.flush()


def clean(text, limit):
    text = CONTROL_RE.sub("", text)
    text = "".join(ch if ch < "\x7f" else "?" for ch in text).strip()
    return text[:limit]


def slug_of(workbook):
    stem = os.path.splitext(os.path.basename(workbook))[0]
    return SLUG_RE.sub("_", stem)[:40] or "workbook"


def as_applescript(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def as_powershell(text):
    for quote in ("'", "\u2018", "\u2019", "\u201a", "\u201b"):
        text = text.replace(quote, quote + quote)
    return "'" + text + "'"


def applescript_text(sheets):
    """The AppleScript the excel renderer runs as: osascript FILE WORKBOOK OUT."""
    names = "{" + ", ".join(as_applescript(name) for name in sheets) + "}"
    return "\n".join([
        "on run argv",
        "    set wbFile to (POSIX file (item 1 of argv)) as text",
        "    set outPath to item 2 of argv",
        "    set sheetNames to " + names,
        "    set pdfFiles to {}",
        "    repeat with i from 1 to count of sheetNames",
        "        if i is 1 then",
        "            set pdfPath to outPath",
        "        else",
        "            set pdfPath to (text 1 thru -5 of outPath) & \"-\" & i & \".pdf\"",
        "        end if",
        "        set end of pdfFiles to (POSIX file pdfPath) as text",
        "    end repeat",
        "    set outFile to (POSIX file outPath) as text",
        "    set wasRunning to application \"" + EXCEL_APP + "\" is running",
        "    set failure to \"\"",
        "    set wb to missing value",
        "    tell application \"" + EXCEL_APP + "\"",
        "        set oldVisible to visible",
        "        set visible to false",
        "        set oldAlerts to display alerts",
        "        set display alerts to false",
        "        try",
        "            open workbook workbook file name wbFile update links do not update links read only true",
        "            set wb to active workbook",
        "            if (count of sheetNames) is 0 then",
        "                save workbook as wb filename outFile file format PDF file format",
        "            else",
        "                repeat with i from 1 to count of sheetNames",
        "                    set sheetName to item i of sheetNames",
        "                    if not (exists worksheet sheetName of wb) then error \"xlsx-render: sheet-missing \" & i",
        "                    save as worksheet sheetName of wb filename (item i of pdfFiles) file format PDF file format",
        "                end repeat",
        "            end if",
        "        on error errMsg",
        "            set failure to errMsg",
        "        end try",
        "        if wb is not missing value then",
        "            try",
        "                close wb saving no",
        "            end try",
        "        end if",
        "        set display alerts to oldAlerts",
        "        if wasRunning then",
        "            set visible to oldVisible",
        "        else",
        "            quit saving no",
        "        end if",
        "    end tell",
        "    if failure is not \"\" then error failure",
        "end run",
        "",
    ])


def powershell_text(sheets):
    """The PowerShell script the excel renderer runs as: powershell.exe ... -File FILE WORKBOOK OUT."""
    names = "@(" + ", ".join(as_powershell(name) for name in sheets) + ")"
    release = "[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject"
    return "\r\n".join([
        "param($wb, $out)",
        "$ErrorActionPreference = 'Stop'",
        "$sheets = " + names,
        "$app = $null",
        "$book = $null",
        "$sheet = $null",
        "$code = 0",
        "try {",
        "    $app = New-Object -ComObject Excel.Application",
        "    $app.Visible = $false",
        "    $app.DisplayAlerts = $false",
        "    $app.ScreenUpdating = $false",
        "    $book = $app.Workbooks.Open($wb, 0, $true)",
        "    if ($sheets.Count -eq 0) {",
        "        $book.ExportAsFixedFormat(0, $out)",
        "    } else {",
        "        for ($i = 1; $i -le $sheets.Count; $i++) {",
        "            if ($i -eq 1) { $path = $out } else { $path = ($out -replace '\\.pdf$', '') + '-' + $i + '.pdf' }",
        "            try { $sheet = $book.Worksheets.Item($sheets[$i - 1]) } catch { $sheet = $null }",
        "            if ($null -eq $sheet) {",
        "                [Console]::Error.WriteLine('xlsx-render: sheet-missing ' + $i)",
        "                $code = 4",
        "                break",
        "            }",
        "            $sheet.ExportAsFixedFormat(0, $path)",
        "            " + release + "($sheet)",
        "            $sheet = $null",
        "        }",
        "    }",
        "} catch {",
        "    [Console]::Error.WriteLine($_.Exception.Message)",
        "    $code = 1",
        "} finally {",
        "    if ($null -ne $sheet) { try { " + release + "($sheet) } catch { } }",
        "    if ($null -ne $book) {",
        "        try { $book.Close($false) } catch { }",
        "        try { " + release + "($book) } catch { }",
        "    }",
        "    if ($null -ne $app) {",
        "        try { $app.Quit() } catch { }",
        "        try { " + release + "($app) } catch { }",
        "    }",
        "    [GC]::Collect()",
        "    [GC]::WaitForPendingFinalizers()",
        "}",
        "exit $code",
        "",
    ])


def quiet(argv, timeout):
    """Run a helper command, never raising; return its exit status or None."""
    try:
        return subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=timeout).returncode
    except (OSError, subprocess.SubprocessError):
        return None


def excel_pids():
    """Process ids of the spreadsheet application, or None when unknown."""
    if sys.platform == "darwin":
        if not shutil.which("pgrep"):
            return None
        try:
            out = subprocess.run(["pgrep", "-x", EXCEL_APP], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10).stdout
        except (OSError, subprocess.SubprocessError):
            return None
        return set(out.decode("ascii", "replace").split())
    if sys.platform == "win32":
        try:
            out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq EXCEL.EXE", "/FO", "CSV", "/NH"],
                                 stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, timeout=10).stdout
        except (OSError, subprocess.SubprocessError):
            return None
        pids = set()
        for line in out.decode("ascii", "replace").splitlines():
            fields = [f.strip('"') for f in line.split('","')]
            if len(fields) > 1 and fields[1].isdigit():
                pids.add(fields[1])
        return pids
    return None


def quit_launched_excel(before):
    """Ask a spreadsheet application this run started to quit, then kill it."""
    after = excel_pids()
    if before is None or not after:
        return
    started = sorted(after - before)
    if not started:
        return
    if sys.platform == "darwin":
        if not before:
            quiet(["osascript", "-e", 'tell application "%s" to quit saving no' % EXCEL_APP], QUIT_WAIT)
        for pid in started:
            if pid in (excel_pids() or set()):
                quiet(["kill", "-9", pid], QUIT_WAIT)
    else:
        for pid in started:
            quiet(["taskkill", "/PID", pid], QUIT_WAIT)
        time.sleep(2)
        for pid in started:
            if pid in (excel_pids() or set()):
                quiet(["taskkill", "/F", "/PID", pid], QUIT_WAIT)


def run_renderer(argv, timeout, errfile, app_cleanup):
    """Run one renderer; return None on exit status 0, else a reason."""
    before = excel_pids() if app_cleanup else None
    with open(errfile, "wb") as err:
        kwargs = {"stdin": subprocess.DEVNULL, "stdout": subprocess.DEVNULL, "stderr": err}
        if sys.platform == "win32":
            kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
        else:
            kwargs["start_new_session"] = True
        try:
            proc = subprocess.Popen(argv, **kwargs)
        except OSError:
            return "not installed"
        try:
            code = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            if sys.platform == "win32":
                quiet(["taskkill", "/T", "/F", "/PID", str(proc.pid)], QUIT_WAIT)
            else:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except OSError:
                    pass
            try:
                proc.kill()
            except OSError:
                pass
            proc.wait()
            if app_cleanup:
                quit_launched_excel(before)
            return "timed out after %d s" % timeout
    if code == 0:
        return None
    return "exit status %d" % code


def error_line(errfile, tmp):
    try:
        with open(errfile, "rb") as handle:
            text = handle.read().decode("utf-8", "replace")
    except OSError:
        return ""
    text = text.replace(tmp, "<tmp>")
    home = os.path.expanduser("~")
    if home and home != "~" and home != os.sep:
        text = text.replace(home, "~")
    for line in text.splitlines():
        line = clean(line, 120)
        if line:
            return line
    return ""


def missing_sheet(errfile, sheets):
    try:
        with open(errfile, "rb") as handle:
            match = MISSING_RE.search(handle.read().decode("utf-8", "replace"))
    except OSError:
        return None
    if match and 1 <= int(match.group(1)) <= len(sheets):
        return sheets[int(match.group(1)) - 1]
    return None


def is_pdf(path):
    try:
        with open(path, "rb") as handle:
            return handle.read(4) == b"%PDF"
    except OSError:
        return False


def find_soffice(override):
    if override:
        return shutil.which(override)
    for name in ("soffice", "soffice.exe", "libreoffice"):
        found = shutil.which(name)
        if found:
            return found
    places = []
    if sys.platform == "darwin":
        places.append("/Applications/LibreOffice.app/Contents/MacOS/soffice")
    elif sys.platform == "win32":
        for var in ("ProgramFiles", "ProgramFiles(x86)"):
            base = os.environ.get(var)
            if base:
                places.append(os.path.join(base, "LibreOffice", "program", "soffice.exe"))
    else:
        places.extend(["/usr/bin/soffice", "/usr/lib/libreoffice/program/soffice", "/snap/bin/libreoffice"])
    for place in places:
        if os.path.isfile(place) and os.access(place, os.X_OK):
            return place
    return None


def excel_installed():
    """Whether the spreadsheet application exists, checked without starting it."""
    if sys.platform == "darwin":
        bundle = EXCEL_APP + ".app"
        return any(os.path.isdir(os.path.join(root, bundle))
                   for root in ("/Applications", os.path.expanduser("~/Applications")))
    if sys.platform == "win32":
        try:
            import winreg
            winreg.CloseKey(winreg.OpenKey(winreg.HKEY_CLASSES_ROOT, "Excel.Application"))
            return True
        except OSError:
            return False
    return False


def render_excel(args, copy, tmp):
    """Return (pdf path, None) or (None, reason)."""
    if args.excel_cmd:
        interpreter = shutil.which(args.excel_cmd)
    elif sys.platform == "darwin":
        interpreter = shutil.which("osascript") if excel_installed() else None
    elif sys.platform == "win32":
        interpreter = None
        if excel_installed():
            interpreter = shutil.which("powershell.exe") or shutil.which("powershell")
    else:
        return None, "no spreadsheet application on this platform"
    if not interpreter:
        return None, "not installed"
    out = os.path.join(tmp, "excel.pdf")
    if sys.platform == "win32":
        script = os.path.join(tmp, "render.ps1")
        with open(script, "w", encoding="utf-8-sig", newline="") as handle:
            handle.write(powershell_text(args.sheet))
        argv = [interpreter, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script, copy, out]
    else:
        script = os.path.join(tmp, "render.applescript")
        with open(script, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(applescript_text(args.sheet))
        argv = [interpreter, script, copy, out]
    errfile = os.path.join(tmp, "excel.err")
    reason = run_renderer(argv, args.timeout, errfile, sys.platform in ("darwin", "win32"))
    if reason and reason.startswith("exit status"):
        name = missing_sheet(errfile, args.sheet)
        if name is not None:
            return None, "sheet not found: " + name
        line = error_line(errfile, tmp)
        return None, reason + (": " + line if line else "")
    if reason:
        return None, reason
    if not is_pdf(out):
        return None, "no PDF produced"
    return out, None


def render_soffice(args, copy, tmp):
    """Return (pdf path, None) or (None, reason)."""
    program = find_soffice(args.soffice)
    if not program:
        return None, "not installed"
    outdir = os.path.join(tmp, "soffice")
    os.mkdir(outdir)
    profile = pathlib.Path(tmp, "profile").resolve().as_uri()
    argv = [program, "-env:UserInstallation=" + profile, "--headless", "--norestore",
            "--convert-to", "pdf", "--outdir", outdir, copy]
    errfile = os.path.join(tmp, "soffice.err")
    reason = run_renderer(argv, args.timeout, errfile, False)
    if reason and reason.startswith("exit status"):
        line = error_line(errfile, tmp)
        return None, reason + (": " + line if line else "")
    if reason:
        return None, reason
    out = os.path.join(outdir, os.path.splitext(os.path.basename(copy))[0] + ".pdf")
    if not is_pdf(out):
        return None, "no PDF produced"
    return out, None


def main():
    parser = Parser(usage="%(prog)s [--chain auto|excel|soffice] [--sheet NAME ...] [--timeout SECONDS] [--soffice PATH] [--excel-cmd PATH] [--only-if-structured FILE] --out DIR -- WORKBOOK", description="Render an .xlsx workbook to PDF through a spreadsheet application or LibreOffice installed on the host, when one is; optional, never required.")
    parser.add_argument("workbook", metavar="WORKBOOK", help="the .xlsx workbook (never modified)")
    parser.add_argument("--chain", choices=("auto", "excel", "soffice"), default="auto", metavar="auto|excel|soffice", help="auto (default): excel, then soffice; or only the one named")
    parser.add_argument("--sheet", metavar="NAME", action="append", default=[], help="worksheet to render with excel (repeatable; the first one becomes the output); soffice renders every sheet")
    parser.add_argument("--timeout", metavar="SECONDS", type=int, default=120, help="wall-clock seconds per renderer (default 120)")
    parser.add_argument("--soffice", metavar="PATH", default=None, help="the soffice program to use (tried on every platform)")
    parser.add_argument("--excel-cmd", metavar="PATH", default=None, help="the interpreter of the excel renderer, in place of osascript or powershell.exe (tried on every platform); it receives the output PDF path as its last argument")
    parser.add_argument("--only-if-structured", metavar="FILE", default=None, help="with --chain auto, render only when FILE (the converter output) holds a ### Shapes or ### Images line, (layout: cells) or a [merged marker")
    parser.add_argument("--out", metavar="DIR", required=True, help="directory the PDF is written to (created when needed)")
    args = parser.parse_args()
    if args.timeout < 1:
        fail("--timeout must be at least 1")
    if not args.out.strip():
        fail("--out needs a directory")
    for name in args.sheet:
        if not name or CONTROL_RE.search(name):
            fail("--sheet needs a name without control characters")
    if not os.path.isfile(args.workbook):
        fail("workbook not found: " + args.workbook)
    try:
        with open(args.workbook, "rb") as handle:
            handle.read(1)
    except OSError as exc:
        fail("cannot read the workbook: %s" % exc)
    if args.chain == "auto" and args.only_if_structured is not None:
        try:
            with open(args.only_if_structured, "r", encoding="utf-8", errors="replace") as handle:
                structured = STRUCTURE_RE.search(handle.read()) is not None
        except OSError:
            emit("Rendered: no (structure file not readable)")
            return
        if not structured:
            emit("Rendered: no (not structured)")
            return
    try:
        os.makedirs(args.out, exist_ok=True)
    except OSError as exc:
        fail("cannot create the output directory: %s" % exc)
    slug = slug_of(args.workbook)
    final = os.path.join(args.out, slug + ".pdf")
    tmp = tempfile.mkdtemp(prefix=".render-", dir=args.out)
    try:
        tmp = os.path.realpath(tmp)
        src = os.path.join(tmp, "src")
        os.mkdir(src)
        ext = os.path.splitext(args.workbook)[1].lower() or ".xlsx"
        copy = os.path.join(src, slug + ext)
        shutil.copyfile(args.workbook, copy)
        renderers = [("excel", render_excel), ("soffice", render_soffice)]
        if args.chain != "auto":
            renderers = [entry for entry in renderers if entry[0] == args.chain]
        reasons = []
        for name, render in renderers:
            pdf, reason = render(args, copy, tmp)
            if pdf is None:
                reasons.append("%s: %s" % (name, reason))
                continue
            os.replace(pdf, final)
            size = os.path.getsize(final)
            if name == "excel" and args.sheet:
                cover = "sheet " + args.sheet[0]
                if len(args.sheet) > 1:
                    cover += "; other selected sheets not rendered"
            else:
                cover = "all sheets"
            emit("Rendered: %s (by %s, %d bytes, %s)" % (final, name, size, cover))
            return
        emit("Rendered: no (%s)" % "; ".join(reasons))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
