target: references/shell-powershell.md
heading: (end of file)
mode: append
---
# PowerShell forms of the shell steps

## When this file applies

This file applies when Pre-computed Context recorded a `Shell: powershell <n>` line, such as `Shell: powershell 5` or `Shell: powershell 7` (SKILL.md, `## Pre-computed Context`): the host's shell tool runs Windows PowerShell 5.1 or PowerShell 7 or later. Then no POSIX form of this skill is ever run (SKILL.md Host notes, **Shell dialect**). Each shell step runs the PowerShell form listed below under its id instead. That form writes the files its POSIX form writes, plus, where general rule 8 applies, one file that holds the text it does not print. Every form is written to run unchanged on Windows PowerShell 5.1 and on PowerShell 7: it uses no syntax and no parameter that only one of them has. A shell step this file does not list is translated by the general rules below, never run in its POSIX form.

Each entry quotes the POSIX form it replaces as the other files print it, gives the PowerShell form in a fenced block, and names what the form prints and how each printed token maps onto the step's outcomes. A POSIX step reads an exit status. A PowerShell form prints a token for it instead (such as `exit=0`, `missing`, `present`), and the step takes the branch that token names. Placeholders (`{scratch}`, `{i}`, `<path>`, `VAR`, ...) are those of the POSIX text, replaced by plain text substitution before the command runs. Every value that replaces one has been checked first: a path, directory, sheet name or identifier by the character rule of SKILL.md Argument Parsing (**Character rule**); a URL by the URL rule of `references/destinations.md` (`api:` preflight steps 2 and 3); an `id_path=` or `source_content_path=` path, a `content_type=` value, a variable name, a slug and an option value (`<scheme>`, `render=`) by their own patterns; a `cli:` command by the `cli:` exemption of the character rule. The others (`{scratch}`, `<root>`, `{python}`, `{ts}`, `{NNN}`, `{i}`) are printed by the forms below or counted by the skill, and a search text follows general rule 4. A form marked "one statement" is a single cmdlet, .NET or `if` statement. A form marked "joined" is one script block, `& { ... }`, whose statements are joined with `;`.

The dialect probe of Pre-computed Context, `echo $PSVersionTable.PSVersion.Major`, runs before the dialect is known and is the same text in every shell. It has no PowerShell form of its own.

## General rules

1. **Syntax of both versions.** Never `&&`, `||`, the ternary `? :`, `??` or any other operator that only PowerShell 7 has. A condition is an `if (...) { ... } else { ... }` statement. A form of several statements is one script block, `& { ...; ... }`, so its variables live in a scope of their own and never meet those of an earlier command in a session the host keeps open. A form that calls a program sets `$ErrorActionPreference = 'Continue'` inside its block, so a caller's `Stop` cannot cut it short.
2. **No POSIX alias.** Under PowerShell `rm`, `rmdir`, `ls`, `cat`, `cp`, `mv`, `mkdir`, `echo`, `curl`, `sort` and `tee` name other commands with other parameters. `rmdir` on a directory that is not empty asks a question, and a host that answers it deletes the directory with all its content. Never write one of these names. The forms use full cmdlet names with `-LiteralPath`, or .NET calls, and they remove a directory only through the call that refuses one that is not empty (PS-DL-4), or through PS-DL-2 on the run's own scratch directory. A native program is called by its real name: `curl` is `curl.exe` (on PowerShell outside Windows, which has no `.exe` names, `curl`). So is a client: the first word of a client command (a `cli:` command, a client's status command or read probe) that is a bare name is written as the file name PS-AP-1 printed for it after `found: `, before the command runs, and printed that way. PowerShell runs a bare name as an alias, function, cmdlet or script of that name before it runs a program (Windows PowerShell 5.1 has an alias `sc`, and a client may install a `<name>.ps1` beside its `<name>.cmd`, which the execution policy refuses to run), while a name written with its extension (`<name>.exe`, `<name>.cmd`) runs that program file. Outside Windows the printed name is the bare name itself.
3. **Environment variables** are `$env:NAME`, tested with `[string]::IsNullOrEmpty($env:NAME)` and never printed. `$HOME` is the home directory, so a `~` path is written `"$HOME/<the part after ~/>"` as in a POSIX shell (SKILL.md Host notes, **`~` paths**). In a `cli:` command a `$NAME` or `${NAME}` reference, and one already written `$env:NAME`, is written `${env:NAME}` before the command runs, and printed that way. The braces end the name: without them a `:` or a name character right after it becomes part of the name, so `"$env:A:$env:B"` loses the value of `A` and the colon, while `"${env:A}:${env:B}"` keeps both.
4. **Quotes.** PowerShell reads the typographic quotes U+2018 to U+201E like `'` and `"`, so under PowerShell the character rule refuses a path, name or value that holds one, as it refuses `"`, and the URL rule refuses a URL that holds one. A value from the request is placed inside double quotes (`"<path>"`), never inside single quotes. Single quotes hold only text that cannot carry a quote of either kind: an option value of fixed spelling (`'<scheme>'`), a value whose pattern allows letters, digits and a few signs only (`'<path>'` of PS-SRC-9, `'<id_path>'` of PS-DST-20, `'{NNN}-'` of PS-DST-7), and a search text of this skill (`'<pattern>'` and `'<text>'` of PS-HN-1 and PS-HN-2), which must hold no `'` and no typographic quote: the skill searches only for its own fixed patterns, identifiers, and heading titles made of ASCII letters, digits, spaces, `-`, `.`, `,` and `:` (`references/destinations.md`, **Stored text check**).
5. **Files through .NET, UTF-8 without a byte order mark.** A text file is read and written through the .NET file API with an explicit `New-Object System.Text.UTF8Encoding($false)` encoding, which writes no byte order mark and skips one on reading; a line the form adds ends with a line feed only, and the line ends of text it copies stay as they are. Every path given to .NET is absolute: `$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("<path>")` turns a relative path into an absolute one, and also a drive or share path and a path that does not exist yet. It resolves a relative path against the current PowerShell location, while .NET alone would use the process directory. A relative path that holds a `:` is written with `./` in front (`"./<path>"`), for this idiom and for `Test-Path -LiteralPath` alike: PowerShell otherwise reads the text before the colon as a drive name and finds no such file. This matters only outside Windows, where a file name may hold a colon; the path is printed and recorded as typed. `>`, `>>`, `Out-File`, `Set-Content`, `Add-Content` and `Tee-Object` never write a file: Windows PowerShell 5.1 writes UTF-16 or the ANSI code page with them, and its `-Encoding UTF8` writes a byte order mark.
6. **Native programs.** A native program's output is never redirected with `>`. It writes its own file through its output option (`curl.exe -o`, the converter's `--out`), or the capture form PS-SRC-11 collects it. Before a native program runs the form sets `$global:LASTEXITCODE = $null`, runs the program inside `try { ... } catch { }` (a program that is not found raises an error that would otherwise stop a caller whose `$ErrorActionPreference` is `Stop`), reads `$LASTEXITCODE` on the next statement and prints it as `exit=<n>`; an empty value means the program did not start. `$?` is never read after a native program, and `exit` is never written: it would end a session the host keeps open. `--` is written `'--'`, because PowerShell may take a bare `--` for its own end-of-parameters marker. An argument that starts with `@` is one double-quoted string (`"@<path>"`): an unquoted `@` starts a splat or a here-string.
7. **No text on a command line.** The ticket text, a JSON body and any text that spans lines or holds quotes never appear in a command. They are files, passed by path.
8. **ASCII output.** A form prints ASCII tokens. Text that may hold other characters (a line of a file, a file name, a field of a JSON document) is written to the file the entry names, as UTF-8 with line feeds, and read back with the file-read tool. The shell tool receives what PowerShell itself prints in the console's code page, where such characters can become `?`. Five printed texts are not tokens and are printed as the console shows them, so they too can show `?`: the `<reason>` of a `failed (...)` or `not started (...)` token (the runtime's own message, which may name a path and is in the host's language), the program name of a `found:` line (PS-AP-1), the `<parent>/<entry>` of a `taken:` line (PS-DST-7), the directory names of PS-PC-2, and the identifier of an `id=` line (PS-DST-20 says how such an identifier is handled). A native program's own output line, such as a script's `Converted:` line, is not captured by the form and reaches the shell tool as the program wrote it.
9. **No script files.** Every form is typed as a command, and no form writes or runs a `.ps1` file, so the execution policy, which refuses script files, never applies to a form. Nor does it apply to a client command whose first word is a bare name: that word names the program file (rule 2), never a `.ps1` file the client installed beside it.
10. **Anything else.** A command this file does not list (a `cli:` command, a client's status command, a step added later) is written by these rules. A POSIX form is never run unchanged.

## SKILL.md

### PS-PC-1: UTC time

POSIX: `date -u +%Y-%m-%dT%H:%M:%SZ` (Pre-computed Context, also the `created` of `references/split-plan-schema.md`).

```powershell
[DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
```

Prints `2026-11-23T10:00:00Z`: the Gregorian UTC time whatever the host's culture or calendar. One statement.

### PS-PC-2: Skill-root listing

POSIX: `ls -1 <root>` (Pre-computed Context, `Available user skills:`).

```powershell
Get-ChildItem -LiteralPath "<root>" -Directory -Name -ErrorAction SilentlyContinue
```

Prints one directory name per line, and nothing for a root that does not exist. A `~` root is written `"$HOME/<rest>"`. One statement.

### PS-AP-1: Program on the PATH

POSIX: `command -v "<first word>"` (SKILL.md Argument Parsing, **Auth** (2); `references/sources.md` `## cli:<command>`; `references/destinations.md` `cli:` preflight step 1), `command -v curl` and `command -v jq` (`references/destinations.md` `api:` preflight step 1, `references/sources.md` `## api:<url>`).

```powershell
if (Get-Command -Name "<first word>" -CommandType Application -ErrorAction SilentlyContinue) { 'found: ' + @(Get-Command -Name "<first word>" -CommandType Application -ErrorAction SilentlyContinue)[0].Name } else { 'missing' }
```

Prints `found: <name>` (the POSIX exit status 0) or `missing`. `<name>` is the file name of the program PowerShell finds first on the PATH, on Windows with its extension (`<name>.exe`, `<name>.cmd`); general rule 2 says how a client command uses it. `-CommandType Application` keeps a PowerShell alias, function, cmdlet or script of the same name from counting as the program. `curl` is tested as `curl.exe`. `jq` is never tested under PowerShell: no form of this file needs it (PS-SRC-9, PS-DST-14 to PS-DST-17 and PS-DST-20 do its work). One statement.

### PS-AP-2: Status command of a signed-in client

POSIX: the client's status command, run as given (SKILL.md Argument Parsing, **Auth** (2)).

```powershell
& { $ErrorActionPreference = 'Continue'; $global:LASTEXITCODE = $null; try { <status command> } catch { 'not started (' + $_.Exception.Message + ')' }; "exit=$LASTEXITCODE" }
```

Prints the client's own output, then `exit=<n>`: `exit=0` means signed in, any other value or an empty one means not. An empty value comes after a `not started (<reason>)` line: the command did not start, and `<reason>` says why. `<status command>` follows general rules 2, 3 and 6, and a first word that is a quoted path gets `&` in front of it. Joined.

### PS-AP-3: Variable set or unset

POSIX: `[ -n "${VAR:-}" ] && echo set || echo unset` (SKILL.md Argument Parsing, **Auth** (4); `references/sources.md` `## api:<url>`; `references/destinations.md` `api:` preflight step 4 and `cli:` preflight step 5).

```powershell
if ([string]::IsNullOrEmpty($env:VAR)) { 'unset' } else { 'set' }
```

Prints `set` or `unset`, never the value; the variable's name stands in place of `VAR`. One statement.

### PS-AP-4: Characters a token may carry

POSIX: `case "${VAR:-}" in *\"*|*\\*|*[[:cntrl:]]*) echo bad;; *) echo ok;; esac` (`references/sources.md` `## api:<url>`, `references/destinations.md` `api:` preflight step 4).

```powershell
if ([string]$env:VAR -match '[^ -~]|["\\]') { 'bad' } else { 'ok' }
```

Prints `ok` or `bad`, never the value. Under PowerShell the header text reaches `curl.exe` through a pipe that carries ASCII only (PS-SRC-7), so a character outside printable ASCII is `bad` as well as a double quote, a backslash and a control character. For an `api:` destination `bad` raises the step's `ERROR:` line worded `ERROR: destination api: the token in <VAR> contains a character the curl config cannot carry (", \, a control character such as a line break, or a character outside printable ASCII)`, the line of `references/destinations.md` with the fourth case added. One statement.

### PS-AP-5: Scratch directory

POSIX: `mkdir -p .local/create-ticket-scratch`, then `mktemp -d .local/create-ticket-scratch/run.XXXXXX` (SKILL.md Argument Parsing). This one form does both.

```powershell
& { try { $p = $ExecutionContext.SessionState.Path; $b = $p.GetUnresolvedProviderPathFromPSPath('.local/create-ticket-scratch'); $null = [System.IO.Directory]::CreateDirectory($b); $n = ''; for ($k = 0; $k -lt 20 -and $n -eq ''; $k++) { $c = 'run.' + [System.IO.Path]::GetRandomFileName().Replace('.', '').Substring(0, 6); $f = [System.IO.Path]::Combine($b, $c); if (-not [System.IO.Directory]::Exists($f) -and -not [System.IO.File]::Exists($f)) { $null = [System.IO.Directory]::CreateDirectory($f); $n = $c } }; if ($n -eq '') { 'scratch: failed (no free name)' } else { '.local/create-ticket-scratch/' + $n } } catch { 'scratch: failed (' + $_.Exception.Message + ')' } }
```

Prints the new directory's path relative to the working directory, with forward slashes (`.local/create-ticket-scratch/run.k3qz9a`), which is `{scratch}`. Or it prints `scratch: failed (<reason>)`, which is the scratch `ERROR:` of Argument Parsing with that `<reason>`. Only a printed line that matches `^\.local/create-ticket-scratch/run\.[A-Za-z0-9]{6}$` is recorded as `{scratch}`. Joined.

### PS-AP-6: Repository root

POSIX: `git rev-parse --show-toplevel` (SKILL.md Argument Parsing; `references/destinations.md` `local:` Delivery step 4).

```powershell
& { $ErrorActionPreference = 'Continue'; $global:LASTEXITCODE = $null; $c = @(); try { $c = @(git rev-parse --show-cdup) } catch { }; if ($LASTEXITCODE -eq 0) { $r = ([string]($c -join '')).Trim().TrimEnd('/'); if ($r -eq '') { '.' } else { $r } } else { 'no-repo' } }
```

Prints `<root>` as a path relative to the working directory (`.`, `..`, `../..`), or `no-repo` outside a repository or without `git` (the POSIX non-zero exit: skip the `.gitignore` steps). The relative form needs no absolute path in any later command, and it is ASCII. Joined.

### PS-AP-7: The `**/.local/*` line of `.gitignore`

POSIX: `grep -qE '^\*\*/\.local/\*[[:space:]]*$' "<root>/.gitignore"`, then `[ -e "<root>/.gitignore" ]`, then `printf '\n%s\n' '**/.local/*' >> "<root>/.gitignore"` or `printf '%s\n' '**/.local/*' > "<root>/.gitignore"` (SKILL.md Argument Parsing). This one form does all four, with `<root>` as PS-AP-6 printed it.

```powershell
& { try { $u = New-Object System.Text.UTF8Encoding($false); $f = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("<root>/.gitignore"); $w = '**/.local/*'; $nl = [string][char]10; if ([System.IO.File]::Exists($f)) { $b = [System.IO.File]::ReadAllBytes($f); $hit = $false; foreach ($l in $u.GetString($b).Split([char]10)) { if ($l.Trim([char]0xFEFF).TrimEnd() -ceq $w) { $hit = $true } }; if ($hit) { 'present' } else { $pre = ''; if ($b.Length -gt 0 -and $b[$b.Length - 1] -ne 10) { $pre = $nl }; [System.IO.File]::AppendAllText($f, $pre + $w + $nl, $u); 'appended' } } else { $s = New-Object System.IO.FileStream($f, [System.IO.FileMode]::CreateNew); try { $d = $u.GetBytes($w + $nl); $s.Write($d, 0, $d.Length) } finally { $s.Dispose() }; 'created' } } catch { 'failed (' + $_.Exception.Message + ')' } }
```

Prints `present` when a line equals `**/.local/*` once trailing white space, a CR included, and a byte order mark are disregarded (nothing is written). It prints `appended` after it added the line to an existing file: the line feed that ends an unterminated last line first, then the line and a line feed, as UTF-8 with no byte order mark, also into a file with CR LF line ends. (The POSIX append always writes that first line feed, so after a complete last line it leaves an empty line, which this form does not.) It prints `created` after it created a missing file holding the line; it never replaces a file that appeared in the meantime. Otherwise it prints `failed (<reason>)`. It appends only, and never rewrites, reorders or removes a line. Joined.

### PS-IN-1: Directory creation

POSIX: `mkdir -p` (Intake I-1, on `"{scratch}/sources"`). The same form replaces `mkdir -p "{dir}/{parent-slug}"`, `mkdir -p "{ticket_dir_i}"` and `mkdir -p "{dir}/.rollback/{parent-slug}-{ts}"` of `references/destinations.md` (PS-DST-9).

```powershell
& { try { $null = [System.IO.Directory]::CreateDirectory($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("<directory>")); 'ok' } catch { 'failed (' + $_.Exception.Message + ')' } }
```

Prints `ok` once the directory and its parents exist (also when they existed already), else `failed (<reason>)`. Joined.

### PS-DL-1: File copy

POSIX: `command cp "<draft file>" "{scratch}/final-{i}.md"` (Phase 4 and Delivery Step DL-2). The same form replaces `command cp "{scratch}/final-{i}.md" "{scratch}/body-{i}.md"` and `command cp "{scratch}/final-{i}.md" "{ticket_dir_i}/ticket.md"` of `references/destinations.md` (PS-DST-10).

```powershell
& { try { $p = $ExecutionContext.SessionState.Path; [System.IO.File]::Copy($p.GetUnresolvedProviderPathFromPSPath("<draft file>"), $p.GetUnresolvedProviderPathFromPSPath("{scratch}/final-{i}.md"), $true); 'copied' } catch { 'failed (' + $_.Exception.Message + ')' } }
```

Prints `copied` after a byte-exact copy that creates the target or replaces it, else `failed (<reason>)`. Joined.

### PS-DL-2: Scratch removal

POSIX: `rm -rf "{scratch}"` (Delivery Step DL-5).

```powershell
& { $s = "{scratch}"; if ($s -cnotmatch '^\.local/create-ticket-scratch/run\.[A-Za-z0-9]{6}$') { 'refused (not the run scratch directory)' } elseif (-not (Test-Path -LiteralPath $s)) { 'removed' } else { try { Remove-Item -LiteralPath $s -Recurse -Force -Confirm:$false -ErrorAction Stop; 'removed' } catch { 'failed (' + $_.Exception.Message + ')' } } }
```

Prints `removed`, or `failed (<reason>)`, whose `<reason>` goes into the removal `WARNING:`. It refuses any path but a scratch directory of the form PS-AP-5 prints (`refused (...)`, handled like `failed`), and it never asks a question, whatever the session's confirmation setting. This is the only form of this file that deletes a directory that is not empty. Joined.

### PS-DL-3: Scratch directory still present

POSIX: `[ -d "{scratch}" ]` (Delivery Step DL-5).

```powershell
if (Test-Path -LiteralPath "{scratch}" -PathType Container) { 'present' } else { 'absent' }
```

Prints `present` (the POSIX exit status 0: the removal `WARNING:` with `still present` unless PS-DL-2 printed a reason) or `absent`. One statement.

### PS-DL-4: Empty parent removal

POSIX: `rmdir .local/create-ticket-scratch`, then `rmdir .local` (Delivery Step DL-5). Run the form once with `<directory>` = `.local/create-ticket-scratch`, then once with `<directory>` = `.local`.

```powershell
& { try { $d = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("<directory>"); if (([System.IO.File]::GetAttributes($d) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { 'kept' } else { [System.IO.Directory]::Delete($d, $false); 'removed' } } catch { 'kept' } }
```

Prints `removed`, or `kept` for a directory that still holds anything, is missing, or is a link or another reparse point (which may lead to a directory that still holds the tickets, and which `rmdir` refuses as not a directory); `kept` is expected and ignored. The .NET call with `$false` refuses a directory that is not empty and never asks a question. Joined.

### PS-HN-1: Lines that match a pattern

POSIX: `grep -nE '<pattern>' "<file>"` (Host notes, **Tool roles**: the searches of a host with no search tools).

```powershell
& { try { $u = New-Object System.Text.UTF8Encoding($false); $p = $ExecutionContext.SessionState.Path; $t = [System.IO.File]::ReadAllText($p.GetUnresolvedProviderPathFromPSPath("<file>"), $u); $r = New-Object System.Text.StringBuilder; $n = 0; $k = 0; foreach ($l in $t.Split([char]10)) { $n++; $l = $l.TrimEnd([char]13); if ([regex]::IsMatch($l, '<pattern>')) { $k++; $null = $r.Append([string]$n + ':' + $l + [char]10) } }; [System.IO.File]::WriteAllText($p.GetUnresolvedProviderPathFromPSPath("{scratch}/shell-result.txt"), $r.ToString(), $u); 'matches: ' + $k } catch { 'unreadable' } }
```

Writes `<line number>:<line>` for each matching line to `{scratch}/shell-result.txt`, a trailing CR left out, and replaces that file's previous content. Prints `matches: <k>` (read the lines with the file-read tool), or `unreadable`. The pattern is a .NET regular expression, which reads the patterns of this skill (`^#{2,4} `, `<kept id>([^0-9]|$)`, `Change rationale:`) as the POSIX extended syntax does. Joined.

### PS-HN-2: Lines that hold a fixed text

POSIX: `grep -nF -e '<text>' "<file>"` (Host notes, **Tool roles**).

```powershell
& { try { $u = New-Object System.Text.UTF8Encoding($false); $p = $ExecutionContext.SessionState.Path; $t = [System.IO.File]::ReadAllText($p.GetUnresolvedProviderPathFromPSPath("<file>"), $u); $r = New-Object System.Text.StringBuilder; $n = 0; $k = 0; foreach ($l in $t.Split([char]10)) { $n++; $l = $l.TrimEnd([char]13); if ($l.Contains('<text>')) { $k++; $null = $r.Append([string]$n + ':' + $l + [char]10) } }; [System.IO.File]::WriteAllText($p.GetUnresolvedProviderPathFromPSPath("{scratch}/shell-result.txt"), $r.ToString(), $u); 'matches: ' + $k } catch { 'unreadable' } }
```

As PS-HN-1, with `<text>` compared as a fixed, case-sensitive string. Joined.

### PS-HN-3: Directory listing

POSIX: `ls -1A "<dir>"` (Host notes, **Tool roles**). The same form, with `{scratch}/sources/shell-result.txt` in place of `{scratch}/shell-result.txt` (Intake writes only under `{scratch}/sources/`, which Intake I-1 creates before any `dir:` source is listed), replaces the `ls -1A` of a `dir:` source (`references/sources.md` `## dir:<path>`). Before `{scratch}` exists no directory is listed (Host notes, **Tool roles**).

```powershell
& { try { $u = New-Object System.Text.UTF8Encoding($false); $p = $ExecutionContext.SessionState.Path; $e = [System.IO.Directory]::GetFileSystemEntries($p.GetUnresolvedProviderPathFromPSPath("<dir>")); $names = New-Object 'System.Collections.Generic.List[string]'; foreach ($x in $e) { $names.Add([System.IO.Path]::GetFileName($x)) }; $names.Sort([System.StringComparer]::Ordinal); $r = New-Object System.Text.StringBuilder; foreach ($x in $names) { $null = $r.Append($x + [char]10) }; [System.IO.File]::WriteAllText($p.GetUnresolvedProviderPathFromPSPath("{scratch}/shell-result.txt"), $r.ToString(), $u); 'entries: ' + $names.Count } catch { 'unreadable' } }
```

Writes every entry name, names starting with `.` and hidden entries included, one per line in ordinal order, to `{scratch}/shell-result.txt`. Prints `entries: <k>` (read the names with the file-read tool), or `unreadable` for a directory that is missing or cannot be read. Joined.

## references/sources.md

### PS-SRC-1: Path exists

POSIX: `[ -e "<path>" ]` (`## Writing a source`).

```powershell
if (Test-Path -LiteralPath "<path>") { 'exists' } else { 'missing' }
```

Prints `exists` (the POSIX exit status 0) or `missing`. One statement.

### PS-SRC-2: Path is a directory

POSIX: `[ -d "<path>" ]` (`## Writing a source`).

```powershell
if (Test-Path -LiteralPath "<path>" -PathType Container) { 'directory' } else { 'not a directory' }
```

Prints `directory` (the POSIX exit status 0: `dir:`) or `not a directory`. One statement.

### PS-SRC-3: Text probe

POSIX: `dd if="<path>" bs=8000 count=1 2>/dev/null | od -An -c | grep -q '\\0' && echo binary || echo text` (`## file:<path>`).

```powershell
& { try { $s = [System.IO.File]::OpenRead($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("<path>")); $b = New-Object byte[] 8000; $n = 0; try { while ($n -lt 8000) { $k = $s.Read($b, $n, 8000 - $n); if ($k -le 0) { break }; $n += $k } } finally { $s.Dispose() }; if ([Array]::IndexOf($b, [byte]0, 0, $n) -ge 0) { 'binary' } else { 'text' } } catch { 'unreadable' } }
```

Prints `binary` (a NUL byte in the first 8,000 bytes) or `text`, as the POSIX form does. It prints `unreadable` for a file it cannot open, where the POSIX form prints `text`; handle it like `text`, and the file-read tool then reports the file. Joined.

### PS-SRC-4: Python interpreter

POSIX: `python3 --version`, then `python --version`, then `py -3 --version` (`## file:<path>`, **Python interpreter**). This one form runs them in that order.

```powershell
& { $ErrorActionPreference = 'Continue'; $pick = 'none'; foreach ($c in @('python3', 'python', 'py -3')) { $w = $c.Split(' '); if (Get-Command -Name $w[0] -CommandType Application -ErrorAction SilentlyContinue) { $exe = $w[0]; $rest = @($w | Select-Object -Skip 1); $v = ''; try { $v = [string](& $exe @rest --version 2>$null | Out-String) } catch { }; if ($v.TrimStart().StartsWith('Python 3.')) { $pick = $c; break } } }; 'python: ' + $pick }
```

Prints `python: python3`, `python: python` or `python: py -3`: the text after `python: ` is `{python}`, written unquoted at the start of every Python form below. A candidate that is missing, that cannot start, or that prints anything but `Python 3.` (an installer stub that only offers to install Python, a Python 2), is skipped. `python: none` means no Python 3: the no-Python behaviour of each feature. Joined.

### PS-SRC-5: Workbook converter

POSIX (`## file:<path>`):

```text
{python} -I "{skill_root}/scripts/xlsx_to_text.py" --max-rows 2000 --max-cols 64 --max-chars 60000 --extract-media "{scratch}/sources/S<n>-media" --out "{scratch}/sources/S<n>.md" [--sheet="<name>" ...] -- "<path>"
```

```powershell
& { $ErrorActionPreference = 'Continue'; $global:LASTEXITCODE = $null; try { {python} -I "{skill_root}/scripts/xlsx_to_text.py" --max-rows 2000 --max-cols 64 --max-chars 60000 --extract-media "{scratch}/sources/S<n>-media" --out "{scratch}/sources/S<n>.md" ["--sheet=<name>" ...] '--' "<path>" } catch { }; "exit=$LASTEXITCODE" }
```

`["--sheet=<name>" ...]` is one double-quoted `"--sheet=<name>"` argument per `?sheet=` value, or nothing. The form prints the converter's `Converted: <chars> characters, <lines> lines, truncated: yes|no` line, then `exit=<n>`, the exit status the step's `ERROR:` lines read. The converter writes `{scratch}/sources/S<n>.md` itself, as UTF-8 with line feeds. A re-conversion with `--max-chars <C>` changes only that number. Joined.

### PS-SRC-6: Sheet render

POSIX (`## file:<path>`, **Sheet rendering (optional)**):

```text
{python} -I "{skill_root}/scripts/xlsx_render.py" --chain <auto|excel|soffice> --only-if-structured "{scratch}/sources/S<n>.md" --out "{scratch}/sources/S<n>-render" [--sheet="<name>" ...] -- "<path>"
```

```powershell
& { $ErrorActionPreference = 'Continue'; $global:LASTEXITCODE = $null; try { {python} -I "{skill_root}/scripts/xlsx_render.py" --chain <auto|excel|soffice> --only-if-structured "{scratch}/sources/S<n>.md" --out "{scratch}/sources/S<n>-render" ["--sheet=<name>" ...] '--' "<path>" } catch { }; "exit=$LASTEXITCODE" }
```

`<auto|excel|soffice>` is the `render=` value. The form prints the script's one `Rendered:` line, then `exit=<n>`: a non-zero value, or no `Rendered:` line, is the `Rendered: no (render script failed)` case. Joined.

### PS-SRC-7: HTTP read with a token

POSIX (`## api:<url>`; `bearer`, then `basic`, then `basic-token`):

```text
printf 'header = "Authorization: Bearer %s"\n' "$VAR" | curl -sS -g --max-time 120 --connect-timeout 15 -K - \
  -o "{scratch}/sources/S<n>.body" -w '%{http_code}' "<url>"
```

```text
printf 'header = "Authorization: Basic %s"\n' "$(printf '%s' "$VAR" | base64 | tr -d '\n')" | curl -sS -g --max-time 120 --connect-timeout 15 -K - \
  -o "{scratch}/sources/S<n>.body" -w '%{http_code}' "<url>"
```

```text
printf 'header = "Authorization: Basic %s"\n' "$(printf ':%s' "$VAR" | base64 | tr -d '\n')" | curl -sS -g --max-time 120 --connect-timeout 15 -K - \
  -o "{scratch}/sources/S<n>.body" -w '%{http_code}' "<url>"
```

```powershell
& { $ErrorActionPreference = 'Continue'; $v = [string]$env:VAR; $m = '<scheme>'; if ($m -eq 'basic') { $h = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($v)) } elseif ($m -eq 'basic-token') { $h = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(':' + $v)) } else { $h = 'Bearer ' + $v }; $OutputEncoding = [System.Text.Encoding]::ASCII; $global:LASTEXITCODE = $null; try { ('header = "Authorization: ' + $h + '"') | curl.exe -sS -g --max-time 120 --connect-timeout 15 -K - -o "{scratch}/sources/S<n>.body" -w '%{http_code}\n' "<url>" } catch { }; "exit=$LASTEXITCODE" }
```

`<scheme>` is `bearer`, `basic` or `basic-token` (`source_auth_scheme=`, or `auth_scheme=` for a destination's read). The header travels only through the pipe into `curl.exe -K -`, never on a command line or in a file. `$OutputEncoding`, set inside the block, makes that pipe ASCII with no byte order mark. Prints the HTTP status (`200`), then `exit=<n>`, the `curl` exit status. The same form with `-o "{scratch}/stored-{i}.json"` is the read of the **Stored text check** (PS-DST-5), and with `-o "{scratch}/probe-response.json"` the read probe of a derived `api:` destination (PS-DST-16). Joined.

### PS-SRC-8: HTTP read without a token

POSIX: the commands of PS-SRC-7 without the `printf ... |` prefix and without `-K -` (`## api:<url>`).

```powershell
& { $ErrorActionPreference = 'Continue'; $global:LASTEXITCODE = $null; try { curl.exe -sS -g --max-time 120 --connect-timeout 15 -o "{scratch}/sources/S<n>.body" -w '%{http_code}\n' "<url>" } catch { }; "exit=$LASTEXITCODE" }
```

Prints the HTTP status, then `exit=<n>`. Its `-o` changes as in PS-SRC-7. Joined.

### PS-SRC-9: Content of one JSON field

POSIX: `jq -r '<path> // empty' "{scratch}/sources/S<n>.body"` (`## api:<url>` and `## cli:<command>`, `source_content_path=`).

```powershell
& { try { $u = New-Object System.Text.UTF8Encoding($false); $p = $ExecutionContext.SessionState.Path; $t = [System.IO.File]::ReadAllText($p.GetUnresolvedProviderPathFromPSPath("{scratch}/sources/S<n>.body"), $u); if ($t.Trim() -eq '') { throw 'empty' }; $v = ConvertFrom-Json -InputObject $t -ErrorAction Stop; if ($t.TrimStart().StartsWith('[')) { $v = $null }; foreach ($m in [regex]::Matches('<path>', '\.([A-Za-z_][A-Za-z0-9_]*)|\[([0-9]+)\]')) { if ($null -eq $v) { break }; if ($m.Groups[1].Success) { $q = $null; if ($v -is [System.Management.Automation.PSCustomObject]) { foreach ($x in $v.PSObject.Properties) { if ($x.Name -ceq $m.Groups[1].Value) { $q = $x } } }; if ($null -eq $q) { $v = $null } else { $v = $q.Value } } else { $k = [int]$m.Groups[2].Value; if ($v -is [System.Collections.IList] -and $k -lt $v.Count) { $v = $v[$k] } else { $v = $null } } }; $o = ''; if ($null -eq $v) { $o = '' } elseif ($v -is [bool]) { if ($v) { $o = 'true' } } elseif ($v -is [string]) { $o = $v } elseif ($v -is [DateTime]) { $o = $v.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture) } elseif ($v -is [System.Collections.IList] -or $v -is [System.Management.Automation.PSCustomObject]) { $o = ConvertTo-Json -InputObject $v -Depth 100 -Compress } else { $o = [System.Convert]::ToString($v, [System.Globalization.CultureInfo]::InvariantCulture) }; [System.IO.File]::WriteAllText($p.GetUnresolvedProviderPathFromPSPath("{scratch}/sources/S<n>.content.txt"), $o, $u); if ($o -eq '') { 'content: empty' } else { 'content: ' + $o.Length + ' characters' } } catch { 'content: not json' } }
```

`<path>` is the `source_content_path=` value, which matches the `id_path=` pattern (`.name` and `[index]` steps). Name steps compare case-sensitively. Writes the field's text to `{scratch}/sources/S<n>.content.txt`: a string as it is, `true`, a number, or the compact JSON of an object or array. A missing field, `null` and `false` write nothing. Prints `content: <k> characters` (read the file with the file-read tool), `content: empty` or `content: not json`; the last two are the `has no content at <path>` `ERROR:`. PowerShell 7 before 7.5 turns a string that holds an ISO date and time into a date, which this form writes back in the round-trip form `o`; that text may differ from the one the platform sent. A JSON document that holds an object with two keys that differ only in letter case, or with an empty key, cannot be read by PowerShell (`content: not json`), wherever that object sits. Joined.

### PS-SRC-10: Pretty-printed JSON body

POSIX: `jq .` (`## api:<url>` and `## cli:<command>`, a body read back without `source_content_path=`).

No PowerShell form: under PowerShell the body is read back verbatim with the file-read tool, the case the POSIX text gives for a host without `jq`.

### PS-SRC-11: Run a command-line client and capture its output

POSIX: `<command> >|"{scratch}/sources/S<n>.body" 2>|"{scratch}/sources/S<n>.err"` (`## cli:<command>`). The same form replaces `<command> >|"{scratch}/stored-{i}.txt" 2>|"{scratch}/stored-{i}.err"` (PS-DST-6) and `<command> >|"{scratch}/response-{i}.txt" 2>|"{scratch}/response-{i}.err"` (PS-DST-22), with the two file names changed.

```powershell
& { $ErrorActionPreference = 'Continue'; $u = New-Object System.Text.UTF8Encoding($false); $p = $ExecutionContext.SessionState.Path; $fo = $p.GetUnresolvedProviderPathFromPSPath("{scratch}/sources/S<n>.body"); $fe = $p.GetUnresolvedProviderPathFromPSPath("{scratch}/sources/S<n>.err"); $all = @(); $old = $null; try { $old = [Console]::OutputEncoding; [Console]::OutputEncoding = $u } catch { }; $global:LASTEXITCODE = $null; try { $all = @(<command> 2>&1) } catch { $all = @($_) } finally { if ($null -ne $old) { try { [Console]::OutputEncoding = $old } catch { } } }; $code = $LASTEXITCODE; $nl = [string][char]10; $so = New-Object System.Text.StringBuilder; $se = New-Object System.Text.StringBuilder; foreach ($x in $all) { if ($x -is [System.Management.Automation.ErrorRecord]) { $null = $se.Append($x.ToString() + $nl) } else { $null = $so.Append([string]$x + $nl) } }; [System.IO.File]::WriteAllText($fo, $so.ToString(), $u); [System.IO.File]::WriteAllText($fe, $se.ToString(), $u); "exit=$code" }
```

Writes the client's standard output and its error output to the two files as UTF-8 with line feeds, each created or replaced. The client's output is decoded as UTF-8 while it runs, and the console setting is restored afterwards. Prints `exit=<n>`: the exit status the step reads, empty when the command did not start (its error is then in the error file). `<command>` follows general rules 2, 3 and 6: a first word that is a bare name is the file name PS-AP-1 printed for it, a `$NAME` reference becomes `${env:NAME}`, a first word that is a quoted path gets `&` in front of it, and a placeholder of a `cli:` destination that the template writes right after `@` is substituted as `"@<path>"`. The other placeholders (`{title_file}`, `{body_file}`, `{request_file}`, `{parent}`) are double-quoted as in a POSIX shell. Joined.

## references/destinations.md

### PS-DST-1: Markdown with every angle bracket escaped

POSIX: `sed -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "{scratch}/body-{i}.md" >| "{scratch}/send-{i}.md"` (**Content-field markup**, `markdown-escaped`).

```powershell
& { try { $u = New-Object System.Text.UTF8Encoding($false); $p = $ExecutionContext.SessionState.Path; $t = [System.IO.File]::ReadAllText($p.GetUnresolvedProviderPathFromPSPath("{scratch}/body-{i}.md"), $u); [System.IO.File]::WriteAllText($p.GetUnresolvedProviderPathFromPSPath("{scratch}/send-{i}.md"), $t.Replace('<', '&lt;').Replace('>', '&gt;'), $u); 'converted' } catch { 'failed (' + $_.Exception.Message + ')' } }
```

Writes `{scratch}/send-{i}.md`, created or replaced: the text with every `<` written `&lt;` and every `>` written `&gt;`, line ends kept as they are, UTF-8 with no byte order mark. Prints `converted` or `failed (<reason>)`. Joined.

### PS-DST-2: HTML conversion with Python

POSIX: `{python} -I "{skill_root}/scripts/ticket_body.py" convert --to html --in "{scratch}/body-{i}.md" --out "{scratch}/send-{i}.html"` (**Content-field markup**, `html`).

```powershell
& { $ErrorActionPreference = 'Continue'; $global:LASTEXITCODE = $null; try { {python} -I "{skill_root}/scripts/ticket_body.py" convert --to html --in "{scratch}/body-{i}.md" --out "{scratch}/send-{i}.html" } catch { }; "exit=$LASTEXITCODE" }
```

Prints the script's `Converted:` line, then `exit=<n>`. A value other than `exit=0` is replaced by PS-DST-3, without the `NOTE:`. Joined.

### PS-DST-3: Preformatted HTML without Python

POSIX: `{ printf '<pre>'; sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "{scratch}/body-{i}.md"; printf '</pre>\n'; } >| "{scratch}/send-{i}.html"` (**Content-field markup**, `html`).

```powershell
& { try { $u = New-Object System.Text.UTF8Encoding($false); $p = $ExecutionContext.SessionState.Path; $t = [System.IO.File]::ReadAllText($p.GetUnresolvedProviderPathFromPSPath("{scratch}/body-{i}.md"), $u); [System.IO.File]::WriteAllText($p.GetUnresolvedProviderPathFromPSPath("{scratch}/send-{i}.html"), '<pre>' + $t.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') + '</pre>' + [char]10, $u); 'converted' } catch { 'failed (' + $_.Exception.Message + ')' } }
```

Writes `{scratch}/send-{i}.html`, created or replaced: `<pre>`, the text with `&`, `<` and `>` escaped in that order, `</pre>` and a line feed. These are the bytes of the POSIX form, except that a byte order mark at the start of the text is dropped, which the POSIX form keeps after `<pre>`. Prints `converted` or `failed (<reason>)`. Joined.

### PS-DST-4: Stored text check with Python

POSIX: `{python} -I "{skill_root}/scripts/ticket_body.py" check --sent "{scratch}/body-{i}.md" --stored "<file>"` (**Stored text check**, step 2).

```powershell
& { $ErrorActionPreference = 'Continue'; $global:LASTEXITCODE = $null; try { {python} -I "{skill_root}/scripts/ticket_body.py" check --sent "{scratch}/body-{i}.md" --stored "<file>" } catch { }; "exit=$LASTEXITCODE" }
```

Prints the script's one `Body check:` line, then `exit=<n>`. A value other than `exit=0` counts as `no content field`. Without Python, the heading lookup of that step runs through the search tools, or through PS-HN-2 on a host with none. Joined.

### PS-DST-5: Read back through the API

POSIX: the fetch command of `references/sources.md` `## api:<url>` with `-o "{scratch}/stored-{i}.json"` (**Stored text check**, step 1 (b)).

No form of its own: PS-SRC-7 (with a token) or PS-SRC-8 (without one), with `-o "{scratch}/stored-{i}.json"`.

### PS-DST-6: Read back through the client

POSIX: `<command> >|"{scratch}/stored-{i}.txt" 2>|"{scratch}/stored-{i}.err"` (**Stored text check**, step 1 (b)).

No form of its own: PS-SRC-11 with the files `{scratch}/stored-{i}.txt` and `{scratch}/stored-{i}.err`.

### PS-DST-7: Ticket number already taken

POSIX: `ls -d "{dir}"/*/{NNN}-* 2>/dev/null` (`## local:<dir>`, Delivery step 3).

```powershell
& { try { $d = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("{dir}"); $hits = New-Object 'System.Collections.Generic.List[string]'; if ([System.IO.Directory]::Exists($d)) { foreach ($a in [System.IO.Directory]::GetDirectories($d)) { $an = [System.IO.Path]::GetFileName($a); if (-not $an.StartsWith('.')) { $es = @(); try { $es = [System.IO.Directory]::GetFileSystemEntries($a) } catch { }; foreach ($e in $es) { $en = [System.IO.Path]::GetFileName($e); if ($en.StartsWith('{NNN}-', [System.StringComparison]::Ordinal)) { $hits.Add($an + '/' + $en) } } } } }; if ($hits.Count -eq 0) { 'free' } else { foreach ($h in $hits) { 'taken: ' + $h } } } catch { 'failed (' + $_.Exception.Message + ')' } }
```

Prints `free` (no match: the number is free), or one `taken: <parent>/<entry>` line per match, whose path under `{dir}` goes into the `already used by <path>` `ERROR:`. A directory whose name starts with `.` (`.rollback/`) is never looked into, and one that cannot be read is skipped, as the POSIX pattern skips it. `failed (<reason>)` means that `{dir}` itself cannot be listed, where the POSIX listing prints nothing: it counts as no match, as there. Joined.

### PS-DST-8: Keep the quarantine out of commits

POSIX: `git check-ignore -q "{dir}/.rollback/x"`, then `[ -e "<root>/.gitignore" ]`, then `printf '\n%s\n' "{rel}/.rollback/" >> "<root>/.gitignore"` or `printf '%s\n' "{rel}/.rollback/" > "<root>/.gitignore"` (`## local:<dir>`, Delivery step 4). This one form does the whole step, with `<root>` as PS-AP-6 printed it; it runs only when PS-AP-6 did not print `no-repo`.

```powershell
& { $ErrorActionPreference = 'Continue'; try { $u = New-Object System.Text.UTF8Encoding($false); $p = $ExecutionContext.SessionState.Path; $sep = [System.IO.Path]::DirectorySeparatorChar; $top = [System.IO.Path]::GetFullPath($p.GetUnresolvedProviderPathFromPSPath("<root>")).TrimEnd('\', '/'); $d = [System.IO.Path]::GetFullPath($p.GetUnresolvedProviderPathFromPSPath("{dir}")).TrimEnd('\', '/'); $cmp = [System.StringComparison]::Ordinal; if ($sep -eq '\') { $cmp = [System.StringComparison]::OrdinalIgnoreCase }; if (-not ($d.Equals($top, $cmp) -or $d.StartsWith($top + $sep, $cmp))) { 'outside' } else { $global:LASTEXITCODE = $null; git check-ignore -q "{dir}/.rollback/x"; $c = $LASTEXITCODE; if ($c -eq 0) { 'ignored' } elseif ($c -ne 1) { 'failed (git check-ignore exit ' + $c + ')' } else { $w = $d.Substring($top.Length).Replace('\', '/').TrimStart('/') + '/.rollback/'; $f = [System.IO.Path]::Combine($top, '.gitignore'); $nl = [string][char]10; if ([System.IO.File]::Exists($f)) { $b = [System.IO.File]::ReadAllBytes($f); $pre = ''; if ($b.Length -gt 0 -and $b[$b.Length - 1] -ne 10) { $pre = $nl }; [System.IO.File]::AppendAllText($f, $pre + $w + $nl, $u); 'appended' } else { $s = New-Object System.IO.FileStream($f, [System.IO.FileMode]::CreateNew); try { $x = $u.GetBytes($w + $nl); $s.Write($x, 0, $x.Length) } finally { $s.Dispose() }; 'created' } } } } catch { 'failed (' + $_.Exception.Message + ')' } }
```

Prints `outside` (`{dir}` is not inside the repository: skip the step), `ignored` (the POSIX exit status 0: nothing to add), `appended` or `created` (the line `{rel}/.rollback/` added as PS-AP-7 adds its line, where `{rel}` is `{dir}` relative to the root with forward slashes), or `failed (<reason>)`. Comparing paths ignores letter case on Windows. Joined.

### PS-DST-9: Ticket and quarantine directories

POSIX: `mkdir -p "{dir}/{parent-slug}"`, `mkdir -p "{ticket_dir_i}"` (`## local:<dir>`, Delivery step 5) and `mkdir -p "{dir}/.rollback/{parent-slug}-{ts}"` (the write-failure quarantine).

No form of its own: PS-IN-1 with `<directory>` = the quoted path.

### PS-DST-10: Copies of the final text

POSIX: `command cp "{scratch}/final-{i}.md" "{ticket_dir_i}/ticket.md"` (`## local:<dir>`, Delivery step 5 (3)) and `command cp "{scratch}/final-{i}.md" "{scratch}/body-{i}.md"` (`## api:<url>`, Delivery step 2, used by every remote adapter).

No form of its own: PS-DL-1 with the two paths of the POSIX form, in the same order.

### PS-DST-11: Quarantine time stamp

POSIX: `date -u +%Y%m%dT%H%M%SZ` (`## local:<dir>`, write failure).

```powershell
[DateTime]::UtcNow.ToString("yyyyMMdd'T'HHmmss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
```

Prints `20261123T100000Z`, which is `{ts}`. One statement.

### PS-DST-12: Quarantine move

POSIX: `command mv "<entry>" "{dir}/.rollback/{parent-slug}-{ts}/"` (`## local:<dir>`, write failure).

```powershell
& { try { $p = $ExecutionContext.SessionState.Path; $src = $p.GetUnresolvedProviderPathFromPSPath("<entry>").TrimEnd('\', '/'); $dst = [System.IO.Path]::Combine($p.GetUnresolvedProviderPathFromPSPath("{dir}/.rollback/{parent-slug}-{ts}"), [System.IO.Path]::GetFileName($src)); if ([System.IO.Directory]::Exists($src)) { [System.IO.Directory]::Move($src, $dst) } else { [System.IO.File]::Move($src, $dst) }; 'moved' } catch { 'failed (' + $_.Exception.Message + ')' } }
```

Moves the entry (a ticket directory, `{dir}/{parent-slug}` or `split-plan.md`) into the quarantine directory under its own name, and prints `moved` or `failed (<reason>)`. It never deletes, and it reads no character of either path as a wildcard. Joined.

### PS-DST-13: Programs of the `api:` adapter

POSIX: `command -v curl`, `command -v jq` and `jq -n 'walk(.)'` (`## api:<url>`, preflight step 1).

No form of its own: under PowerShell the step tests only `curl.exe`, with PS-AP-1, and `missing` raises the step's `ERROR:` line worded `ERROR: destination api: needs curl.exe on PATH`, without `jq`. `jq` is not needed, here or for the `{request_file}` and `id_path=` of a `cli:` destination, whose preflight step 3 then skips its `jq` test.

### PS-DST-14: Template placeholders `{title}` and `{body}`

POSIX: `jq -e '[.. | strings | select(. == "{title}")] | length > 0' "<path>"`, and the same for `{body}` (`## api:<url>`, preflight step 5).

```powershell
& { try { $t = [System.IO.File]::ReadAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("<path>"), (New-Object System.Text.UTF8Encoding($false))); $j = ConvertFrom-Json -InputObject $t -ErrorAction Stop; $hit = $false; $st = New-Object System.Collections.Stack; $st.Push($j); while ($st.Count -gt 0) { $o = $st.Pop(); if ($o -is [string]) { if ($o -ceq '{title}') { $hit = $true } } elseif ($o -is [System.Collections.IList]) { foreach ($e in $o) { $st.Push($e) } } elseif ($o -is [System.Management.Automation.PSCustomObject]) { foreach ($q in $o.PSObject.Properties) { $st.Push($q.Value) } } }; if ($hit -and $t.Contains('"{title}"')) { 'true' } else { 'false' } } catch { 'false' } }
```

Run once as written and once with `{body}` in place of both `{title}`. Prints `true` (the POSIX exit status 0) when the template is JSON, a string value somewhere in it equals the placeholder, and its text holds the quoted placeholder that PS-DST-17 fills. It prints `false` otherwise, a file that is not JSON included. PowerShell's JSON reader may accept text that `jq` refuses (PowerShell 7 accepts comments, a trailing comma and an unquoted key), so a template with one of them passes this test and the check of PS-DST-17: the platform then refuses the request at the first create, where the POSIX preflight would have stopped. Joined.

### PS-DST-15: Template placeholder `{parent}`

POSIX: `jq -e '[.. | strings | select(contains("{parent}"))] | length > 0' "<path>"` (`## api:<url>`, preflight step 7; `## cli:<command template>`, preflight steps 3 and 4).

```powershell
& { try { $t = [System.IO.File]::ReadAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("<path>"), (New-Object System.Text.UTF8Encoding($false))); $null = ConvertFrom-Json -InputObject $t -ErrorAction Stop; if ($t.Contains('{parent}')) { 'true' } else { 'false' } } catch { 'false' } }
```

Prints `true` (the POSIX exit status 0) when the template is JSON and its text holds `{parent}`, which PS-DST-17 replaces wherever it occurs. It prints `false` otherwise. Joined.

### PS-DST-16: Read probe of a derived `api:` destination

POSIX: the fetch command of `references/sources.md` `## api:<url>` with `-o "{scratch}/probe-response.json"`, then `jq empty` on that file (`## api:<url>`, preflight step 9).

The fetch is PS-SRC-7 or PS-SRC-8 with `-o "{scratch}/probe-response.json"`. The JSON test is:

```powershell
& { try { $t = [System.IO.File]::ReadAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("{scratch}/probe-response.json"), (New-Object System.Text.UTF8Encoding($false))); if ($t.Trim() -eq '') { 'json' } else { $null = ConvertFrom-Json -InputObject $t -ErrorAction Stop; 'json' } } catch { 'not json' } }
```

Prints `json` (the POSIX exit status 0) for a JSON document and for an empty or blank file, which `jq empty` accepts too, or `not json`. Joined.

### PS-DST-17: Request body

POSIX (`## api:<url>`, Delivery step 3; also `{request_file}` of `## cli:<command template>`):

```text
jq --rawfile title "{scratch}/title-{i}.txt" --rawfile body "<sent body>" --arg parent "<id>" \
  'walk(if . == "{title}" then ($title | rtrimstr("\n") | rtrimstr("\r")) elif . == "{body}" then $body elif type == "string" and contains("{parent}") then gsub("\\{parent\\}"; $parent) else . end)' \
  "<template>" >|"{scratch}/request-{i}.json"
```

```powershell
& { try { $u = New-Object System.Text.UTF8Encoding($false); $p = $ExecutionContext.SessionState.Path; $tpl = [System.IO.File]::ReadAllText($p.GetUnresolvedProviderPathFromPSPath("<template>"), $u); $title = [System.IO.File]::ReadAllText($p.GetUnresolvedProviderPathFromPSPath("{scratch}/title-{i}.txt"), $u); if ($title.EndsWith([string][char]10)) { $title = $title.Substring(0, $title.Length - 1) }; if ($title.EndsWith([string][char]13)) { $title = $title.Substring(0, $title.Length - 1) }; $body = [System.IO.File]::ReadAllText($p.GetUnresolvedProviderPathFromPSPath("<sent body>"), $u); $jt = ConvertTo-Json -InputObject $title -Compress; $jb = ConvertTo-Json -InputObject $body -Compress; $jp = ConvertTo-Json -InputObject "<id>" -Compress; $jp = $jp.Substring(1, $jp.Length - 2); $s1 = [guid]::NewGuid().ToString('N'); $s2 = [guid]::NewGuid().ToString('N'); $out = $tpl.Replace('"{title}"', $s1).Replace('"{body}"', $s2).Replace('{parent}', $jp).Replace($s1, $jt).Replace($s2, $jb); $null = ConvertFrom-Json -InputObject $out -ErrorAction Stop; [System.IO.File]::WriteAllText($p.GetUnresolvedProviderPathFromPSPath("{scratch}/request-{i}.json"), $out, $u); 'request: written' } catch { 'request: failed (' + $_.Exception.Message + ')' } }
```

Writes `{scratch}/request-{i}.json`, created or replaced, as UTF-8 with no byte order mark. The template is filled as text and never parsed and written again: each quoted `"{title}"` and `"{body}"` first becomes a sentinel no text can hold, then `{parent}` becomes the `parent=` value (written as JSON string content), and last each sentinel becomes the JSON string literal of the title (one trailing line feed and then one trailing CR removed) or of the sent body. So neither text is ever searched for a placeholder, the template's structure (a top-level array included) is kept, and the result is checked to parse as JSON, by the reader whose limit PS-DST-14 states. Prints `request: written` or `request: failed (<reason>)`. Joined.

### PS-DST-18: `POST` with a token

POSIX (`## api:<url>`, Delivery step 4; `bearer`, then `basic`, then `basic-token`):

```text
printf 'header = "Authorization: Bearer %s"\n' "$VAR" | curl -sS -g --max-time 120 --connect-timeout 15 -K - \
  -X POST "<url>" \
  -H "Content-Type: <content_type>" \
  --data-binary @"{scratch}/request-{i}.json" \
  -o "{scratch}/response-{i}.json" -w '%{http_code}'
```

```text
printf 'header = "Authorization: Basic %s"\n' "$(printf '%s' "$VAR" | base64 | tr -d '\n')" | curl -sS -g --max-time 120 --connect-timeout 15 -K - \
  -X POST "<url>" \
  -H "Content-Type: <content_type>" \
  --data-binary @"{scratch}/request-{i}.json" \
  -o "{scratch}/response-{i}.json" -w '%{http_code}'
```

```text
printf 'header = "Authorization: Basic %s"\n' "$(printf ':%s' "$VAR" | base64 | tr -d '\n')" | curl -sS -g --max-time 120 --connect-timeout 15 -K - \
  -X POST "<url>" \
  -H "Content-Type: <content_type>" \
  --data-binary @"{scratch}/request-{i}.json" \
  -o "{scratch}/response-{i}.json" -w '%{http_code}'
```

```powershell
& { $ErrorActionPreference = 'Continue'; $v = [string]$env:VAR; $m = '<scheme>'; if ($m -eq 'basic') { $h = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($v)) } elseif ($m -eq 'basic-token') { $h = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(':' + $v)) } else { $h = 'Bearer ' + $v }; $OutputEncoding = [System.Text.Encoding]::ASCII; $global:LASTEXITCODE = $null; try { ('header = "Authorization: ' + $h + '"') | curl.exe -sS -g --max-time 120 --connect-timeout 15 -K - -X POST "<url>" -H "Content-Type: <content_type>" --data-binary "@{scratch}/request-{i}.json" -o "{scratch}/response-{i}.json" -w '%{http_code}\n' } catch { }; "exit=$LASTEXITCODE" }
```

`<scheme>` is the `auth_scheme=` value. The request body is read by `curl.exe` from the file (`"@..."`, one quoted argument). Prints the HTTP status, then `exit=<n>`: success is `exit=0` with a `2xx` status. A `curl` timeout is `exit=28`. Joined.

### PS-DST-19: `POST` without a token

POSIX: the command of PS-DST-18 without the `printf ... |` prefix and without `-K -` (`## api:<url>`, Delivery step 4).

```powershell
& { $ErrorActionPreference = 'Continue'; $global:LASTEXITCODE = $null; try { curl.exe -sS -g --max-time 120 --connect-timeout 15 -X POST "<url>" -H "Content-Type: <content_type>" --data-binary "@{scratch}/request-{i}.json" -o "{scratch}/response-{i}.json" -w '%{http_code}\n' } catch { }; "exit=$LASTEXITCODE" }
```

Prints the HTTP status, then `exit=<n>`. Joined.

### PS-DST-20: Identifier from a JSON response

POSIX: `jq -r '<id_path> // empty' "{scratch}/response-{i}.json"` (`## api:<url>`, Delivery step 5) and `jq -r '<id_path> // empty' "{scratch}/response-{i}.txt"` (`## cli:<command template>`, Delivery step 4).

```powershell
& { try { $t = [System.IO.File]::ReadAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("{scratch}/response-{i}.json"), (New-Object System.Text.UTF8Encoding($false))); $v = ConvertFrom-Json -InputObject $t -ErrorAction Stop; if ($t.TrimStart().StartsWith('[')) { $v = $null }; foreach ($m in [regex]::Matches('<id_path>', '\.([A-Za-z_][A-Za-z0-9_]*)|\[([0-9]+)\]')) { if ($null -eq $v) { break }; if ($m.Groups[1].Success) { $q = $null; if ($v -is [System.Management.Automation.PSCustomObject]) { foreach ($x in $v.PSObject.Properties) { if ($x.Name -ceq $m.Groups[1].Value) { $q = $x } } }; if ($null -eq $q) { $v = $null } else { $v = $q.Value } } else { $k = [int]$m.Groups[2].Value; if ($v -is [System.Collections.IList] -and $k -lt $v.Count) { $v = $v[$k] } else { $v = $null } } }; $o = ''; if ($null -eq $v) { $o = '' } elseif ($v -is [bool]) { if ($v) { $o = 'true' } } elseif ($v -is [string]) { $o = $v } elseif ($v -is [DateTime]) { $o = $v.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture) } elseif ($v -is [System.Collections.IList] -or $v -is [System.Management.Automation.PSCustomObject]) { $o = ConvertTo-Json -InputObject $v -Depth 100 -Compress } else { $o = [System.Convert]::ToString($v, [System.Globalization.CultureInfo]::InvariantCulture) }; 'id=' + $o } catch { 'id=' } }
```

For the `cli:` response the path is `{scratch}/response-{i}.txt`. Prints `id=<identifier>`, the value of the field at `<id_path>` read as PS-SRC-9 reads a field. It prints `id=` with nothing after it for a missing field, `null`, `false` or a file that is not JSON: the empty `{id}` of the step. An identifier is ASCII on every platform this skill knows; one that is not may print as `?`, and the step then treats it as unusable. Joined.

### PS-DST-21: Read probe of a `cli:` destination

POSIX: `<probe command> >/dev/null` (`## cli:<command template>`, preflight step 2).

```powershell
& { $ErrorActionPreference = 'Continue'; $global:LASTEXITCODE = $null; try { $null = <probe command> } catch { 'not started (' + $_.Exception.Message + ')' }; "exit=$LASTEXITCODE" }
```

Discards the probe's standard output (its error output still reaches the terminal) and prints `exit=<n>`: `exit=0` is a passed probe, and any other value, or an empty one, is the `exit <n>` of the step's `Tried:` or `ERROR:` line. An empty value comes after a `not started (<reason>)` line (the command did not start), and that `exit <n>` is then written `not started (<reason>)`. `<probe command>` follows general rules 2, 3 and 6. Joined.

### PS-DST-22: Create through the client

POSIX: `<command> >|"{scratch}/response-{i}.txt" 2>|"{scratch}/response-{i}.err"` (`## cli:<command template>`, Delivery step 3).

No form of its own: PS-SRC-11 with the files `{scratch}/response-{i}.txt` and `{scratch}/response-{i}.err`, after the placeholders are substituted as that entry says. The ticket text still never goes on the command line: `{body_file}` and `{request_file}` are paths.

## Agent bodies

### PS-RO-1: Read-only inspection by the researcher and the planner

POSIX: the read-only commands of `references/agents/researcher.md` and `references/agents/planner.md` (**Side-effect ban**: `git log`, `git diff`, `git status`, `git branch`, `git show`, `find`, `grep`, `ls`, `cat` of repository files).

No form here: their spawn prompts carry the `Shell:` line, and their **Side-effect ban** names the cmdlets they use under PowerShell. The decomposer gets no `Shell:` line: it works from the content its spawn prompt inlines. The ticket-evaluator runs no shell command.
