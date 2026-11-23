# Behaviour test of references/shell-powershell.md in the generated create-ticket skill.
#
# Every fenced PowerShell form is taken from the built tree by its id, its
# placeholders are filled with fixture values (a placeholder left over fails the
# test), and it runs in a temporary working directory whose path differs from
# the process directory, so a form that hands a relative path to .NET writes in
# the wrong place and fails. The forms run under the harshest caller settings,
# Set-StrictMode -Version Latest and $ErrorActionPreference = 'Stop'.
#
# Runs on Windows PowerShell 5.1 and PowerShell 7 (ASCII-only source). Parts
# that need a program the host lacks (git, Python 3, curl.exe) print SKIP;
# with -RequireAll (the Windows CI job) every SKIP counts as a failure.
#
# Usage:
#   powershell -NoProfile -File tests/test-standalone-skill-powershell.ps1 -SkillDir <out>/create-ticket [-RequireAll]
#   pwsh -NoProfile -File tests/test-standalone-skill-powershell.ps1 -SkillDir <out>/create-ticket [-RequireAll]
param([Parameter(Mandatory = $true)][string]$SkillDir, [switch]$RequireAll)

$ErrorActionPreference = 'Continue'
Set-StrictMode -Off

$script:Pass = 0
$script:Fail = 0
$script:Skip = 0

# An error in the test's own code (a file that is missing, a method called on
# $null) is a failure: without this trap the statement would be skipped and the
# check after it could still pass. The forms run inside Run-Form's try/catch,
# so their own errors never reach it.
trap {
  $script:Fail++
  [Console]::Out.WriteLine('  FAIL test code error: ' + $_.Exception.Message + ' (line ' + $_.InvocationInfo.ScriptLineNumber + ')')
  continue
}
$script:Forms = @{}
$script:Ran = @{}
$script:Skipped = @{}
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:IsWin = ([System.IO.Path]::DirectorySeparatorChar -eq '\')
$script:LF = [string][char]10
$script:CR = [string][char]13
$script:JA = [string][char]0x898B + [char]0x7A4D + [char]0x3082 + [char]0x308A
$script:JA2 = [string][char]0x8981 + [char]0x4EF6

# The console starts in a code page that is not UTF-8 (ISO 8859-1), so only a
# form's own switch to UTF-8 (PS-SRC-11) can keep a client's non-ASCII output.
# The test itself prints ASCII only. The setting is restored at the end.
$script:ConsoleBefore = $null
try { $script:ConsoleBefore = [Console]::OutputEncoding; [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(28591) } catch { [Console]::Out.WriteLine('  NOTE the console code page could not be set (' + $_.Exception.Message + ')') }

function Write-Line([string]$Text) { [Console]::Out.WriteLine($Text) }

function Check([string]$Name, [string]$Detail) {
  if ([string]::IsNullOrEmpty($Detail)) {
    $script:Pass++
    Write-Line ('  PASS ' + $Name)
  } else {
    $script:Fail++
    Write-Line ('  FAIL ' + $Name)
    foreach ($l in $Detail.Split([char]10)) { Write-Line ('       ' + $l) }
    foreach ($fm in [regex]::Matches($Name, 'PS-[A-Z]+-[0-9]+')) {
      if ($script:Ran.ContainsKey($fm.Value)) { Write-Line ('       last filled ' + $fm.Value + ': ' + $script:Ran[$fm.Value]) }
    }
  }
}

function Skip([string]$Name, [string]$Why) {
  if ($RequireAll) {
    $script:Fail++
    Write-Line ('  FAIL ' + $Name + ': skipped under -RequireAll (' + $Why + ')')
  } else {
    $script:Skip++
    Write-Line ('  SKIP ' + $Name + ': ' + $Why)
  }
  foreach ($fm in [regex]::Matches($Name, 'PS-[A-Z]+-[0-9]+')) { $script:Skipped[$fm.Value] = $true }
}

function Show-Bytes([byte[]]$B) {
  if ($null -eq $B) { return '(missing)' }
  $n = [Math]::Min($B.Length, 120)
  $s = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $n; $i++) { $null = $s.Append($B[$i].ToString('x2')) }
  return $s.ToString() + ' (' + $B.Length + ' bytes)'
}

function Same-Bytes([byte[]]$A, [byte[]]$B) {
  if ($null -eq $A -or $null -eq $B) { return $false }
  if ($A.Length -ne $B.Length) { return $false }
  for ($i = 0; $i -lt $A.Length; $i++) { if ($A[$i] -ne $B[$i]) { return $false } }
  return $true
}

function Read-Bytes([string]$Path) {
  if (-not [System.IO.File]::Exists($Path)) { return $null }
  return ,([System.IO.File]::ReadAllBytes($Path))
}

# The UTF-8 text of a file, or $null when the file is missing.
function Read-Text([string]$Path) {
  if (-not [System.IO.File]::Exists($Path)) { return $null }
  return [System.IO.File]::ReadAllText($Path, $script:Utf8)
}

function Put-Bytes([string]$Path, [byte[]]$Bytes) {
  $d = [System.IO.Path]::GetDirectoryName($Path)
  if ($d -and -not [System.IO.Directory]::Exists($d)) { $null = [System.IO.Directory]::CreateDirectory($d) }
  [System.IO.File]::WriteAllBytes($Path, $Bytes)
}

function Put-Text([string]$Path, [string]$Text) { Put-Bytes $Path $script:Utf8.GetBytes($Text) }

function U8([string]$Text) { return ,($script:Utf8.GetBytes($Text)) }

function Join-Bytes([byte[]]$A, [byte[]]$B) {
  $r = New-Object byte[] ($A.Length + $B.Length)
  [Array]::Copy($A, 0, $r, 0, $A.Length)
  [Array]::Copy($B, 0, $r, $A.Length, $B.Length)
  return ,$r
}

function Has-Program([string]$Name) {
  return [bool](Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue)
}

# --- forms ---------------------------------------------------------------------
$MdPath = [System.IO.Path]::Combine((Resolve-Path -LiteralPath $SkillDir).ProviderPath, 'references', 'shell-powershell.md')
if (-not [System.IO.File]::Exists($MdPath)) {
  Write-Line ('FAIL: no references/shell-powershell.md under ' + $SkillDir)
  Write-Line 'PASS 0 / FAIL 1'
  exit 1
}
$MdText = [System.IO.File]::ReadAllText($MdPath, $script:Utf8).Replace($script:CR + $script:LF, $script:LF)
$cur = $null
$inBlock = $false
$buf = $null
foreach ($line in $MdText.Split([char]10)) {
  $m = [regex]::Match($line, '^### (PS-[A-Z]+-[0-9]+): ')
  if ($m.Success) { $cur = $m.Groups[1].Value; continue }
  if (-not $inBlock -and $line -ceq ('`' * 3 + 'powershell')) { $inBlock = $true; $buf = New-Object System.Text.StringBuilder; continue }
  if ($inBlock -and $line -ceq ('`' * 3)) {
    $inBlock = $false
    if ($null -ne $cur) { $script:Forms[$cur] = $buf.ToString().TrimEnd() }
    continue
  }
  if ($inBlock) { $null = $buf.Append($line + $script:LF) }
}
Check 'the forms of references/shell-powershell.md are found by their ids' $(if ($script:Forms.Count -ge 30) { '' } else { 'only ' + $script:Forms.Count + ' forms found' })

# Placeholder names used in the forms; the literal template tokens and the
# curl write-out variable are not placeholders.
$Literal = @('{title}', '{body}', '{parent}', '{http_code}', '<pre>', '</pre>')
$AllPlaceholders = @{}
foreach ($k in $script:Forms.Keys) {
  foreach ($mm in [regex]::Matches($script:Forms[$k], '\{[A-Za-z_][A-Za-z0-9_-]*\}|<[A-Za-z][A-Za-z0-9 _|-]*>|\["--sheet=<name>" \.\.\.\] ')) {
    if ($Literal -notcontains $mm.Value) { $AllPlaceholders[$mm.Value] = $true }
  }
}

function Fill([string]$Id, [hashtable]$Map) {
  if (-not $script:Forms.ContainsKey($Id)) { throw ('no form ' + $Id) }
  $t = $script:Forms[$Id]
  $keys = @($Map.Keys | Sort-Object -Property Length -Descending)
  foreach ($k in $keys) { $t = $t.Replace([string]$k, [string]$Map[$k]) }
  foreach ($k in $AllPlaceholders.Keys) {
    if ($t.Contains($k)) { throw ($Id + ': placeholder ' + $k + ' left in the filled form') }
  }
  $script:Ran[$Id] = $t
  return $t
}

# Run a filled form the way a shell tool would run one command, under the
# harshest caller settings (a confirmation asked for every cmdlet that can
# ask one, too), and return its output as strings.
function Run-Form([string]$Id, [hashtable]$Map, [string]$Dir) {
  $text = Fill $Id $Map
  $sb = [scriptblock]::Create($text)
  Push-Location -LiteralPath $Dir
  try {
    $out = @(& { Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'; $ConfirmPreference = 'Low'; & $sb } 2>&1 | ForEach-Object { [string]$_ })
  } catch {
    $out = @('THROWN: ' + $_.Exception.Message)
  } finally {
    Pop-Location
  }
  return ,$out
}

function Out-Text($Out) { return (@($Out) -join ' | ') }

# --- work area -------------------------------------------------------------------
$Root = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'sw-ps-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = [System.IO.Directory]::CreateDirectory($Root)
$ProcDir = [System.IO.Path]::Combine($Root, 'process-dir')
$null = [System.IO.Directory]::CreateDirectory($ProcDir)
[System.Environment]::CurrentDirectory = $ProcDir
$W = [System.IO.Path]::Combine($Root, 'work')
$null = [System.IO.Directory]::CreateDirectory($W)
function WP([string]$Rel) { return [System.IO.Path]::Combine($W, $Rel.Replace('/', [string][System.IO.Path]::DirectorySeparatorChar)) }
function Stray([string]$Rel) { return [System.IO.File]::Exists([System.IO.Path]::Combine($ProcDir, $Rel)) -or [System.IO.Directory]::Exists([System.IO.Path]::Combine($ProcDir, $Rel)) }

$PsExe = (Get-Process -Id $PID).Path
function Child-Command([string]$Script) {
  $b64 = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Script))
  return '& "' + $PsExe + '" -NoProfile -NonInteractive -EncodedCommand ' + $b64
}
function Exit-Command([int]$Code) {
  if ($script:IsWin) { return 'cmd.exe /d /c exit ' + $Code }
  return "sh -c 'exit " + $Code + "'"
}

Write-Line ('=== PowerShell forms of the standalone create-ticket skill (PowerShell ' + $PSVersionTable.PSVersion.ToString() + ') ===')

# --- general rule: the absolute-path idiom ------------------------------------------
Push-Location -LiteralPath $W
$abs = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('sub/new-file.txt')
Pop-Location
$d = ''
if ($abs -ne [System.IO.Path]::Combine($W, 'sub', 'new-file.txt')) { $d = 'relative path resolved to ' + $abs }
if ($script:IsWin) {
  $dr = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('C:/work/spec.md')
  if ($dr -ne 'C:\work\spec.md') { $d += ' drive path resolved to ' + $dr }
  $un = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('\\server\share\x.md')
  if ($un -ne '\\server\share\x.md') { $d += ' share path resolved to ' + $un }
  # The spelling every form receives: backslashes read as / (SKILL.md, Character rule).
  # The forms hand the result to .NET, so the property is where .NET takes it.
  $uf = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('//server/share/x.md')
  if ([System.IO.Path]::GetFullPath($uf) -ne '\\server\share\x.md') { $d += ' share path //server/share/x.md resolved to ' + $uf }
}
if ($MdText.IndexOf('$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("<path>")', [System.StringComparison]::Ordinal) -lt 0) { $d += ' the general rules do not state the idiom' }
Check ('the absolute-path idiom resolves a relative path against the PowerShell location, not the process directory' + $(if ($script:IsWin) { ', and keeps drive and share paths' } else { '' })) $d

# --- PS-PC-1 / PS-DST-11: UTC time --------------------------------------------------
$o = Run-Form 'PS-PC-1' @{} $W
$d = ''
if ((Out-Text $o) -notmatch '^(19|20|21)\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ$') { $d = 'printed ' + (Out-Text $o) }
$ts = Run-Form 'PS-DST-11' @{} $W
if ((Out-Text $ts) -notmatch '^(19|20|21)\d{6}T\d{6}Z$') { $d += ' timestamp printed ' + (Out-Text $ts) }
$culture = $null
try { $culture = New-Object System.Globalization.CultureInfo('th-TH') } catch { }
if ($null -ne $culture -and $culture.Calendar.GetType().Name -ne 'GregorianCalendar') {
  $old = [System.Threading.Thread]::CurrentThread.CurrentCulture
  try {
    [System.Threading.Thread]::CurrentThread.CurrentCulture = $culture
    $sb = [scriptblock]::Create((Fill 'PS-PC-1' @{}))
    $ot = [string](& $sb)
  } finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $old }
  if ($ot -notmatch '^(19|20|21)\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ$') { $d += ' under a non-Gregorian culture it printed ' + $ot }
}
Check 'PS-PC-1 / PS-DST-11: UTC time and quarantine time stamp in the documented shapes (Gregorian, colons kept, Z)' $d

# --- PS-PC-2: skill-root listing ---------------------------------------------------
foreach ($x in @('roots/skills/alpha', 'roots/skills/beta')) { $null = [System.IO.Directory]::CreateDirectory((WP $x)) }
Put-Text (WP 'roots/skills/file.txt') 'x'
$o = Run-Form 'PS-PC-2' @{ '<root>' = 'roots/skills' } $W
$o2 = Run-Form 'PS-PC-2' @{ '<root>' = 'roots/missing' } $W
$d = ''
if ((@($o | Sort-Object) -join ',') -ne 'alpha,beta') { $d = 'listed ' + (Out-Text $o) }
if (@($o2).Count -ne 0) { $d += ' missing root printed ' + (Out-Text $o2) }
Check 'PS-PC-2: a skill root lists its directory names only; a missing root prints nothing' $d

# --- PS-AP-1: program presence -------------------------------------------------------
$self = [System.IO.Path]::GetFileNameWithoutExtension($PsExe)
Set-Alias -Name sw-fake-alias -Value Get-Date -Scope Global
function global:sw-fake-function { 'x' }
$a = Run-Form 'PS-AP-1' @{ '<first word>' = $self } $W
$b = Run-Form 'PS-AP-1' @{ '<first word>' = 'sw-no-such-program-x1' } $W
$c = Run-Form 'PS-AP-1' @{ '<first word>' = 'sw-fake-alias' } $W
$e = Run-Form 'PS-AP-1' @{ '<first word>' = 'sw-fake-function' } $W
$d = ''
# The printed name is the program's file name: with its extension on Windows.
if ((Out-Text $a) -notmatch ('^found: ' + [regex]::Escape($self) + $(if ($script:IsWin) { '\.exe$' } else { '$' }))) { $d += ' own executable: ' + (Out-Text $a) }
if ((Out-Text $b) -ne 'missing') { $d += ' missing program: ' + (Out-Text $b) }
if ((Out-Text $c) -ne 'missing') { $d += ' alias: ' + (Out-Text $c) }
if ((Out-Text $e) -ne 'missing') { $d += ' function: ' + (Out-Text $e) }
if ($MdText.IndexOf('is written as the file name PS-AP-1 printed for it after `found: `', [System.StringComparison]::Ordinal) -lt 0) { $d += ' general rule 2 does not name the printed file name' }
Check 'PS-AP-1: found: <file name> for a program on the PATH, missing for an absent one, an alias or a function of that name' $d

# General rule 2: a client's first word is the file name PS-AP-1 printed. On
# Windows that name carries its extension, so an alias of the bare name (one
# that Windows PowerShell 5.1 ships, such as sc) is not what runs.
if ($script:IsWin) {
  $shadow = [System.IO.Path]::Combine($Root, 'shadow-bin')
  $null = [System.IO.Directory]::CreateDirectory($shadow)
  Put-Text ([System.IO.Path]::Combine($shadow, 'sw-shadow.cmd')) ('@exit /b 0' + $script:CR + $script:LF)
  Set-Alias -Name sw-shadow -Value Get-Date -Scope Global
  $pathBefore = $env:PATH
  $env:PATH = $shadow + [System.IO.Path]::PathSeparator + $pathBefore
  try {
    $sf = Run-Form 'PS-AP-1' @{ '<first word>' = 'sw-shadow' } $W
    $sn = (Out-Text $sf).Replace('found: ', '')
    $sx = Run-Form 'PS-AP-2' @{ '<status command>' = $sn } $W
  } finally { $env:PATH = $pathBefore }
  $d = ''
  if ((Out-Text $sf) -ne 'found: sw-shadow.cmd') { $d += ' lookup: ' + (Out-Text $sf) }
  if ((Out-Text $sx) -ne 'exit=0') { $d += ' run as ' + $sn + ': ' + (Out-Text $sx) }
  Check 'PS-AP-1 / PS-AP-2: a client whose bare name is also an alias runs as the program when its first word is the printed file name (sw-shadow.cmd)' $d
}

# --- PS-AP-2 / PS-DST-21: status and read probes ----------------------------------------
$d = ''
foreach ($pair in @(@('PS-AP-2', '<status command>'), @('PS-DST-21', '<probe command>'))) {
  $x0 = Run-Form $pair[0] @{ ($pair[1]) = (Exit-Command 0) } $W
  $x3 = Run-Form $pair[0] @{ ($pair[1]) = (Exit-Command 3) } $W
  $xn = Run-Form $pair[0] @{ ($pair[1]) = 'sw-no-such-program-x1 --status' } $W
  if (@($x0)[-1] -ne 'exit=0') { $d += ' ' + $pair[0] + ' exit 0: ' + (Out-Text $x0) }
  if (@($x3)[-1] -ne 'exit=3') { $d += ' ' + $pair[0] + ' exit 3: ' + (Out-Text $x3) }
  if (@($xn)[-1] -ne 'exit=') { $d += ' ' + $pair[0] + ' not found: ' + (Out-Text $xn) }
  elseif (@($xn).Count -lt 2 -or @($xn)[-2] -notmatch '(?s)^not started \(.*sw-no-such-program-x1.*\)$') { $d += ' ' + $pair[0] + ' not found, no reason printed: ' + (Out-Text $xn) }
}
Check 'PS-AP-2 / PS-DST-21: exit=0, exit=3, and for a command that does not start a not started (<reason>) line and an empty exit= (no stale status)' $d

# General rule 3: a variable reference of a cli: command is written ${env:NAME},
# so a ':' or a name character right after it stays text ($env:A:$env:B
# would lose A and the colon). A stand-in client echoes its arguments.
$env:SWPS_A = 'user'
$env:SWPS_B = 'pw'
$env:SWPS_T = 'tok'
$refs = '-u "${env:SWPS_A}:${env:SWPS_B}" "X-Token: ${env:SWPS_T}suffix" "${env:SWPS_T}_x" ${env:SWPS_A}:${env:SWPS_B}'
$echoCmd = $(if ($script:IsWin) { 'cmd.exe /d /c echo ' + $refs } else { "sh -c 'echo `"`$*`"' sh " + $refs })
$x = Run-Form 'PS-AP-2' @{ '<status command>' = $echoCmd } $W
$d = ''
if ($MdText.IndexOf('is written `${env:NAME}` before the command runs', [System.StringComparison]::Ordinal) -lt 0) { $d += ' general rule 3 does not write ${env:NAME}' }
$xt = Out-Text $x
foreach ($want in @('-u user:pw', 'X-Token: toksuffix', 'tok_x', 'tok_x user:pw')) {
  if (-not $xt.Contains($want)) { $d += ' missing [' + $want + ']' }
}
if (@($x)[-1] -ne 'exit=0') { $d += ' status ' + @($x)[-1] }
if ($d -ne '') { $d += ' output: ' + $xt }
foreach ($v in @('SWPS_A', 'SWPS_B', 'SWPS_T')) { Remove-Item -LiteralPath ('Env:' + $v) -ErrorAction SilentlyContinue }
Check 'PS-AP-2 with a cli: command written by general rule 3: ${env:NAME} keeps a following colon, name characters and text (the arguments reach the client whole)' $d

# --- PS-AP-3 / PS-AP-4: variable probes ------------------------------------------------
$env:SWPS_SET = 'secret-value-123'
Remove-Item -LiteralPath 'Env:SWPS_UNSET' -ErrorAction SilentlyContinue
$s1 = Run-Form 'PS-AP-3' @{ 'VAR' = 'SWPS_SET' } $W
$s2 = Run-Form 'PS-AP-3' @{ 'VAR' = 'SWPS_UNSET' } $W
$d = ''
if ((Out-Text $s1) -ne 'set') { $d += ' set: ' + (Out-Text $s1) }
if ((Out-Text $s2) -ne 'unset') { $d += ' unset: ' + (Out-Text $s2) }
$cases = @(
  @('abc.DEF-123_xyz==', 'ok'),
  @('a"b', 'bad'),
  @('a\b', 'bad'),
  @(('a' + $script:LF + 'b'), 'bad'),
  @(('a' + [char]9 + 'b'), 'bad'),
  @(('a' + $script:CR), 'bad'),
  @(('caf' + [char]0xE9), 'bad')
)
$k = 0
foreach ($cs in $cases) {
  $k++
  $env:SWPS_PROBE = $cs[0]
  $r = Run-Form 'PS-AP-4' @{ 'VAR' = 'SWPS_PROBE' } $W
  if ((Out-Text $r) -ne $cs[1]) { $d += ' case ' + $k + ': ' + (Out-Text $r) + ' (want ' + $cs[1] + ')' }
  if ((Out-Text $r).Contains($cs[0])) { $d += ' case ' + $k + ' leaked the value' }
}
if ((Out-Text $s1).Contains('secret')) { $d += ' the set probe leaked the value' }
Remove-Item -LiteralPath 'Env:SWPS_PROBE' -ErrorAction SilentlyContinue
Check 'PS-AP-3 / PS-AP-4: set/unset and ok/bad without printing the value (quote, backslash, LF, tab, CR and non-ASCII are bad)' $d

# --- PS-AP-5: scratch creation --------------------------------------------------------
$r1 = Run-Form 'PS-AP-5' @{} $W
$r2 = Run-Form 'PS-AP-5' @{} $W
$d = ''
$pat = '^\.local/create-ticket-scratch/run\.[A-Za-z0-9]{6}$'
foreach ($r in @($r1, $r2)) {
  if ((Out-Text $r) -cnotmatch $pat) { $d += ' printed ' + (Out-Text $r) }
  elseif (-not [System.IO.Directory]::Exists((WP (Out-Text $r)))) { $d += ' ' + (Out-Text $r) + ' does not exist under the working directory' }
}
if ((Out-Text $r1) -eq (Out-Text $r2)) { $d += ' two runs printed the same directory' }
if (Stray '.local') { $d += ' a .local directory appeared in the process directory' }
Check 'PS-AP-5: scratch creation prints a new relative run.XXXXXX path with forward slashes that exists under the PowerShell location' $d
$Scratch = Out-Text $r1
$Other = Out-Text $r2

# --- PS-AP-6: repository root ------------------------------------------------------------
if (Has-Program 'git') {
  $repo = [System.IO.Path]::Combine($Root, 'repo')
  $null = [System.IO.Directory]::CreateDirectory([System.IO.Path]::Combine($repo, 'sub', 'dir'))
  $env:GIT_CEILING_DIRECTORIES = $Root
  Push-Location -LiteralPath $repo
  $null = & git init -q 2>&1
  Pop-Location
  $outside = [System.IO.Path]::Combine($Root, 'outside')
  $null = [System.IO.Directory]::CreateDirectory($outside)
  $g1 = Run-Form 'PS-AP-6' @{} $repo
  $g2 = Run-Form 'PS-AP-6' @{} ([System.IO.Path]::Combine($repo, 'sub', 'dir'))
  $g3 = Run-Form 'PS-AP-6' @{} $outside
  $d = ''
  if ((Out-Text $g1) -ne '.') { $d += ' root: ' + (Out-Text $g1) }
  if ((Out-Text $g2) -ne '../..') { $d += ' sub/dir: ' + (Out-Text $g2) }
  if (@($g3)[-1] -ne 'no-repo') { $d += ' outside: ' + (Out-Text $g3) }
  Check 'PS-AP-6: the repository root as a relative path (. at the root, ../.. two levels down), no-repo outside' $d
} else {
  $savedPath = $env:PATH
  $g3 = Run-Form 'PS-AP-6' @{} $W
  Check 'PS-AP-6: no-repo when git is not installed (no stale exit status)' $(if (@($g3)[-1] -eq 'no-repo') { '' } else { 'printed ' + (Out-Text $g3) })
  Skip 'PS-AP-6 inside a repository' 'git is not installed'
}

# --- PS-AP-7: the **/.local/* line ----------------------------------------------------------
$line = '**/.local/*'
$fx = [ordered]@{
  'gi-missing' = $null
  'gi-nofinal' = (U8 ('a' + $script:CR + $script:LF + 'b'))
  'gi-crlf' = (U8 ('x' + $script:CR + $script:LF + $line + $script:CR + $script:LF))
  'gi-bom' = (Join-Bytes ([byte[]](0xEF, 0xBB, 0xBF)) (U8 ($line + $script:LF)))
  'gi-final' = (U8 ('x' + $script:LF))
  'gi-empty' = (New-Object byte[] 0)
  'gi-trail' = (U8 ($line + ' ' + [char]9 + $script:LF))
  'gi-other' = (U8 ('foo/' + $line + $script:LF))
}
$want = @{
  'gi-missing' = @('created', (U8 ($line + $script:LF)))
  'gi-nofinal' = @('appended', (U8 ('a' + $script:CR + $script:LF + 'b' + $script:LF + $line + $script:LF)))
  'gi-crlf' = @('present', $fx['gi-crlf'])
  'gi-bom' = @('present', $fx['gi-bom'])
  'gi-final' = @('appended', (U8 ('x' + $script:LF + $line + $script:LF)))
  'gi-empty' = @('appended', (U8 ($line + $script:LF)))
  'gi-trail' = @('present', $fx['gi-trail'])
  'gi-other' = @('appended', (U8 ('foo/' + $line + $script:LF + $line + $script:LF)))
}
$d = ''
foreach ($g in $fx.Keys) {
  $null = [System.IO.Directory]::CreateDirectory((WP $g))
  if ($null -ne $fx[$g]) { Put-Bytes (WP ($g + '/.gitignore')) $fx[$g] }
  $r = Run-Form 'PS-AP-7' @{ '<root>' = $g } $W
  $r2 = Run-Form 'PS-AP-7' @{ '<root>' = $g } $W
  if ((Out-Text $r) -ne $want[$g][0]) { $d += ' ' + $g + ': printed ' + (Out-Text $r) + ' (want ' + $want[$g][0] + ')' }
  if ((Out-Text $r2) -ne 'present') { $d += ' ' + $g + ': second run printed ' + (Out-Text $r2) }
  $got = Read-Bytes (WP ($g + '/.gitignore'))
  if (-not (Same-Bytes $got $want[$g][1])) { $d += ' ' + $g + ': file is ' + (Show-Bytes $got) + ' want ' + (Show-Bytes $want[$g][1]) }
}
if (Stray 'gi-missing') { $d += ' wrote into the process directory' }
Check 'PS-AP-7: .gitignore line test, append and create (missing file, no final newline, CR LF, byte order mark, trailing blanks, empty file), second run present, bytes exact' $d

# --- PS-IN-1: directory creation ---------------------------------------------------------
$m1 = Run-Form 'PS-IN-1' @{ '<directory>' = ($Scratch + '/sources') } $W
$m2 = Run-Form 'PS-IN-1' @{ '<directory>' = ($Scratch + '/sources') } $W
$m3 = Run-Form 'PS-IN-1' @{ '<directory>' = 'mk/a [x]/b/c' } $W
Put-Text (WP 'mk/file') 'x'
$m4 = Run-Form 'PS-IN-1' @{ '<directory>' = 'mk/file/sub' } $W
$d = ''
if ((Out-Text $m1) -ne 'ok' -or (Out-Text $m2) -ne 'ok') { $d += ' sources: ' + (Out-Text $m1) + ' / ' + (Out-Text $m2) }
if ((Out-Text $m3) -ne 'ok' -or -not [System.IO.Directory]::Exists((WP 'mk/a [x]/b/c'))) { $d += ' nested: ' + (Out-Text $m3) }
if ((Out-Text $m4) -notmatch '^failed \(') { $d += ' under a file: ' + (Out-Text $m4) }
Check 'PS-IN-1: creates a directory and its parents, ok again when it exists, failed (...) under a file' $d

# --- PS-DL-1: copy --------------------------------------------------------------------
$src = Join-Bytes ([byte[]](0xEF, 0xBB, 0xBF)) (U8 ('## T: ' + $script:JA + $script:CR + $script:LF + 'a' + [char]0 + 'b' + $script:LF))
Put-Bytes (WP 'draft [1].md') $src
$c1 = Run-Form 'PS-DL-1' @{ '<draft file>' = 'draft [1].md'; '{scratch}' = $Scratch; '{i}' = '0' } $W
$src2 = Join-Bytes $src (U8 ('second' + $script:LF))
Put-Bytes (WP 'draft [1].md') $src2
$c2 = Run-Form 'PS-DL-1' @{ '<draft file>' = 'draft [1].md'; '{scratch}' = $Scratch; '{i}' = '0' } $W
$d = ''
if ((Out-Text $c1) -ne 'copied' -or (Out-Text $c2) -ne 'copied') { $d += ' printed ' + (Out-Text $c1) + ' / ' + (Out-Text $c2) }
$got = Read-Bytes (WP ($Scratch + '/final-0.md'))
if (-not (Same-Bytes $got $src2)) { $d += ' copy is ' + (Show-Bytes $got) }
Check 'PS-DL-1: byte-exact copy (byte order mark, CR LF, NUL, non-ASCII), replaced on the second run, wildcard characters in the name taken literally' $d

# --- PS-HN-1 / PS-HN-2 / PS-HN-3: searches and listing -------------------------------------
$ticket = '## T-1: ' + $script:JA + $script:CR + $script:LF + $script:CR + $script:LF + '### ' + $script:JA2 + $script:CR + $script:LF + 'Change rationale: x' + $script:LF + '#### Sub' + $script:LF + '##### deep' + $script:LF + 'text' + $script:LF
Put-Text (WP 'search/ticket.md') $ticket
$h1 = Run-Form 'PS-HN-1' @{ '<file>' = 'search/ticket.md'; '<pattern>' = '^#{2,4} '; '{scratch}' = $Scratch } $W
$res1 = Read-Bytes (WP ($Scratch + '/shell-result.txt'))
$h2 = Run-Form 'PS-HN-2' @{ '<file>' = 'search/ticket.md'; '<text>' = 'Change rationale:'; '{scratch}' = $Scratch } $W
$res2 = Read-Bytes (WP ($Scratch + '/shell-result.txt'))
$h3 = Run-Form 'PS-HN-1' @{ '<file>' = 'search/none.md'; '<pattern>' = '^#'; '{scratch}' = $Scratch } $W
$h4 = Run-Form 'PS-HN-2' @{ '<file>' = 'search/ticket.md'; '<text>' = 'change rationale:'; '{scratch}' = $Scratch } $W
$res4 = Read-Bytes (WP ($Scratch + '/shell-result.txt'))
$d = ''
if ((Out-Text $h1) -ne 'matches: 3') { $d += ' pattern: ' + (Out-Text $h1) }
$w1 = U8 ('1:## T-1: ' + $script:JA + $script:LF + '3:### ' + $script:JA2 + $script:LF + '5:#### Sub' + $script:LF)
if (-not (Same-Bytes $res1 $w1)) { $d += ' pattern result ' + (Show-Bytes $res1) }
if ((Out-Text $h2) -ne 'matches: 1' -or -not (Same-Bytes $res2 (U8 ('4:Change rationale: x' + $script:LF)))) { $d += ' fixed: ' + (Out-Text $h2) + ' ' + (Show-Bytes $res2) }
if ((Out-Text $h3) -ne 'unreadable') { $d += ' missing file: ' + (Out-Text $h3) }
if ((Out-Text $h4) -ne 'matches: 0' -or $null -eq $res4 -or $res4.Length -ne 0) { $d += ' fixed text in another letter case: ' + (Out-Text $h4) + ' ' + (Show-Bytes $res4) }
Check 'PS-HN-1 / PS-HN-2: matching lines with their numbers written as UTF-8 to {scratch}/shell-result.txt (non-ASCII kept, CR dropped), an ASCII count printed, the fixed text compared case-sensitively, unreadable for a missing file' $d

# Zeta.txt and alpha.txt order differently by ordinal and by a culture or
# case-insensitive comparer, so the listing order tells them apart.
foreach ($x in @('list/b.txt', 'list/A.txt', 'list/alpha.txt', 'list/Zeta.txt', 'list/.hidden', ('list/' + $script:JA + '.md'))) { Put-Text (WP $x) 'x' }
$null = [System.IO.Directory]::CreateDirectory((WP 'list/sub'))
$l1 = Run-Form 'PS-HN-3' @{ '<dir>' = 'list'; '{scratch}' = $Scratch } $W
$lres = Read-Bytes (WP ($Scratch + '/shell-result.txt'))
$l2 = Run-Form 'PS-HN-3' @{ '<dir>' = 'list-missing'; '{scratch}' = $Scratch } $W
$names = @('.hidden', 'A.txt', 'Zeta.txt', 'alpha.txt', 'b.txt', 'sub', ($script:JA + '.md'))
$d = ''
if ((Out-Text $l1) -ne 'entries: 7') { $d += ' printed ' + (Out-Text $l1) }
if (-not (Same-Bytes $lres (U8 (($names -join $script:LF) + $script:LF)))) { $d += ' listing ' + (Show-Bytes $lres) }
if ((Out-Text $l2) -ne 'unreadable') { $d += ' missing dir: ' + (Out-Text $l2) }
# The listing of a dir: source writes {scratch}/sources/shell-result.txt instead.
$l3 = Run-Form 'PS-HN-3' @{ '<dir>' = 'list'; '{scratch}/shell-result.txt' = ($Scratch + '/sources/shell-result.txt') } $W
if ((Out-Text $l3) -ne 'entries: 7' -or -not (Same-Bytes (Read-Bytes (WP ($Scratch + '/sources/shell-result.txt'))) $lres)) { $d += ' dir: source result file: ' + (Out-Text $l3) }
Check 'PS-HN-3: every entry name, dot-files included, in ordinal order, written as UTF-8 to the result file ({scratch}/sources/shell-result.txt for a dir: source); unreadable for a missing directory' $d

# --- PS-SRC-1 / PS-SRC-2: existence tests -------------------------------------------------
Put-Text (WP 'ex/a [1].md') 'x'
$d = ''
$t1 = Run-Form 'PS-SRC-1' @{ '<path>' = 'ex/a [1].md' } $W
$t2 = Run-Form 'PS-SRC-1' @{ '<path>' = 'ex/missing.md' } $W
$t3 = Run-Form 'PS-SRC-2' @{ '<path>' = 'ex' } $W
$t4 = Run-Form 'PS-SRC-2' @{ '<path>' = 'ex/a [1].md' } $W
if ((Out-Text $t1) -ne 'exists') { $d += ' file: ' + (Out-Text $t1) }
if ((Out-Text $t2) -ne 'missing') { $d += ' missing: ' + (Out-Text $t2) }
if ((Out-Text $t3) -ne 'directory') { $d += ' dir: ' + (Out-Text $t3) }
if ((Out-Text $t4) -ne 'not a directory') { $d += ' file as dir: ' + (Out-Text $t4) }
Check 'PS-SRC-1 / PS-SRC-2: exists, missing, directory, not a directory (wildcard characters taken literally)' $d

# --- PS-SRC-3: text probe ---------------------------------------------------------------
$big1 = New-Object byte[] 9000
for ($i = 0; $i -lt 9000; $i++) { $big1[$i] = 65 }
$big2 = [byte[]]$big1.Clone()
$big1[8500] = 0
$big2[7999] = 0
Put-Bytes (WP 'probe/ja.txt') (U8 ($script:JA + $script:LF + 'line'))
Put-Bytes (WP 'probe/bin.dat') ([byte[]](0x61, 0x62, 0x00, 0x63))
Put-Bytes (WP 'probe/empty') (New-Object byte[] 0)
Put-Bytes (WP 'probe/late-nul') $big1
Put-Bytes (WP 'probe/edge-nul') $big2
$d = ''
foreach ($pc in @(@('probe/ja.txt', 'text'), @('probe/bin.dat', 'binary'), @('probe/empty', 'text'), @('probe/late-nul', 'text'), @('probe/edge-nul', 'binary'), @('probe/missing', 'unreadable'))) {
  $r = Run-Form 'PS-SRC-3' @{ '<path>' = $pc[0] } $W
  if ((Out-Text $r) -ne $pc[1]) { $d += ' ' + $pc[0] + ': ' + (Out-Text $r) + ' (want ' + $pc[1] + ')' }
}
Check 'PS-SRC-3: text probe reads the first 8,000 bytes only (Japanese text, NUL, empty file, NUL after and at the limit, missing file)' $d

# General rule 5: outside Windows a file name may hold a colon, and a relative
# path that holds one is written with ./ in front.
if (-not $script:IsWin) {
  Put-Text (WP 'col/spec:v2.md') 'x'
  $d = ''
  if ($MdText.IndexOf('A relative path that holds a `:` is written with `./` in front', [System.StringComparison]::Ordinal) -lt 0) { $d += ' general rule 5 does not state the ./ prefix' }
  $k1 = Run-Form 'PS-SRC-1' @{ '<path>' = './col/spec:v2.md' } $W
  $k2 = Run-Form 'PS-SRC-3' @{ '<path>' = './col/spec:v2.md' } $W
  $k3 = Run-Form 'PS-HN-2' @{ '<file>' = './col/spec:v2.md'; '<text>' = 'x'; '{scratch}' = $Scratch } $W
  if ((Out-Text $k1) -ne 'exists' -or (Out-Text $k2) -ne 'text' -or (Out-Text $k3) -ne 'matches: 1') { $d += ' printed ' + (Out-Text $k1) + ' / ' + (Out-Text $k2) + ' / ' + (Out-Text $k3) }
  Check 'general rule 5: a relative path that holds a colon, written with ./ in front, is found by Test-Path and by the .NET idiom' $d
}

# --- PS-SRC-4: Python choice --------------------------------------------------------------
$py = Run-Form 'PS-SRC-4' @{} $W
$expect = 'none'
foreach ($cand in @('python3', 'python', 'py -3')) {
  $cw = $cand.Split(' ')
  if (Has-Program $cw[0]) {
    $cexe = $cw[0]
    $rest = @($cw | Select-Object -Skip 1)
    $v = [string](& $cexe @rest --version 2>$null | Out-String)
    if ($v.TrimStart().StartsWith('Python 3.')) { $expect = $cand; break }
  }
}
Check ('PS-SRC-4: the interpreter choice agrees with the same probe written in the test (python: ' + $expect + ')') $(if ((Out-Text $py) -eq ('python: ' + $expect)) { '' } else { 'printed ' + (Out-Text $py) })
$stub = [System.IO.Path]::Combine($Root, 'stub-bin')
$null = [System.IO.Directory]::CreateDirectory($stub)
$savedPath = $env:PATH
$stubOk = $true
if ($script:IsWin) {
  Put-Text ([System.IO.Path]::Combine($stub, 'python3.cmd')) ('@echo Python was not found; run without arguments to install' + $script:CR + $script:LF + '@exit /b 9009' + $script:CR + $script:LF)
  Put-Text ([System.IO.Path]::Combine($stub, 'python.cmd')) ('@echo Python 3.11.4' + $script:CR + $script:LF)
} else {
  Put-Text ([System.IO.Path]::Combine($stub, 'python3')) ('#!/bin/sh' + $script:LF + 'echo "Python 2.7.18"' + $script:LF)
  Put-Text ([System.IO.Path]::Combine($stub, 'python')) ('#!/bin/sh' + $script:LF + 'echo "Python 3.11.4"' + $script:LF)
  $null = & chmod 755 ([System.IO.Path]::Combine($stub, 'python3')) ([System.IO.Path]::Combine($stub, 'python')) 2>&1
  if ($LASTEXITCODE -ne 0) { $stubOk = $false }
}
if ($stubOk) {
  $env:PATH = $stub + [System.IO.Path]::PathSeparator + $savedPath
  try { $pys = Run-Form 'PS-SRC-4' @{} $W } finally { $env:PATH = $savedPath }
  Check 'PS-SRC-4 with stand-in programs first on the PATH: a python3 that is not Python 3 is skipped, the next one that prints Python 3. is chosen' $(if ((Out-Text $pys) -eq 'python: python') { '' } else { 'printed ' + (Out-Text $pys) })
  # Neither python3 nor python is Python 3; a py launcher answers for -3.
  $stub2 = [System.IO.Path]::Combine($Root, 'stub-bin-2')
  $null = [System.IO.Directory]::CreateDirectory($stub2)
  if ($script:IsWin) {
    Put-Text ([System.IO.Path]::Combine($stub2, 'python3.cmd')) ('@echo Python was not found; run without arguments to install' + $script:CR + $script:LF + '@exit /b 9009' + $script:CR + $script:LF)
    Put-Text ([System.IO.Path]::Combine($stub2, 'python.cmd')) ('@echo Python 2.7.18' + $script:CR + $script:LF)
    Put-Text ([System.IO.Path]::Combine($stub2, 'py.cmd')) ('@if "%1"=="-3" if "%2"=="--version" echo Python 3.12.1' + $script:CR + $script:LF)
  } else {
    Put-Text ([System.IO.Path]::Combine($stub2, 'python3')) ('#!/bin/sh' + $script:LF + 'echo "Python 2.7.18"' + $script:LF)
    Put-Text ([System.IO.Path]::Combine($stub2, 'python')) ('#!/bin/sh' + $script:LF + 'echo "Python 2.7.18"' + $script:LF)
    Put-Text ([System.IO.Path]::Combine($stub2, 'py')) ('#!/bin/sh' + $script:LF + 'if [ "$1" = "-3" ] && [ "$2" = "--version" ]; then echo "Python 3.12.1"; fi' + $script:LF)
    $null = & chmod 755 ([System.IO.Path]::Combine($stub2, 'python3')) ([System.IO.Path]::Combine($stub2, 'python')) ([System.IO.Path]::Combine($stub2, 'py')) 2>&1
  }
  $env:PATH = $stub2 + [System.IO.Path]::PathSeparator + $savedPath
  try { $pyl = Run-Form 'PS-SRC-4' @{} $W } finally { $env:PATH = $savedPath }
  Check 'PS-SRC-4 with stand-in programs: neither python3 nor python is Python 3, py -3 is chosen as two words' $(if ((Out-Text $pyl) -eq 'python: py -3') { '' } else { 'printed ' + (Out-Text $pyl) })
  # A python3 on the PATH that cannot start (an executable that is not a
  # program for this system; outside Windows, one whose interpreter line names
  # no file) is skipped under the caller's Stop as well.
  $stub3 = [System.IO.Path]::Combine($Root, 'stub-bin-3')
  $null = [System.IO.Directory]::CreateDirectory($stub3)
  if ($script:IsWin) {
    Put-Bytes ([System.IO.Path]::Combine($stub3, 'python3.exe')) ([byte[]](0x6E, 0x6F, 0x74, 0x20, 0x61, 0x20, 0x70, 0x72, 0x6F, 0x67, 0x72, 0x61, 0x6D))
    Put-Text ([System.IO.Path]::Combine($stub3, 'python.cmd')) ('@echo Python 3.11.4' + $script:CR + $script:LF)
  } else {
    Put-Text ([System.IO.Path]::Combine($stub3, 'python3')) ('#!/sw-no-such-dir/interpreter' + $script:LF + 'echo "Python 3.11.4"' + $script:LF)
    Put-Text ([System.IO.Path]::Combine($stub3, 'python')) ('#!/bin/sh' + $script:LF + 'echo "Python 3.11.4"' + $script:LF)
    $null = & chmod 755 ([System.IO.Path]::Combine($stub3, 'python3')) ([System.IO.Path]::Combine($stub3, 'python')) 2>&1
  }
  $env:PATH = $stub3 + [System.IO.Path]::PathSeparator + $savedPath
  try { $pyx = Run-Form 'PS-SRC-4' @{} $W } finally { $env:PATH = $savedPath }
  Check 'PS-SRC-4 with stand-in programs: a python3 that cannot start is skipped (no error ends the form), the next one that prints Python 3. is chosen' $(if ((Out-Text $pyx) -eq 'python: python') { '' } else { 'printed ' + (Out-Text $pyx) })
} else {
  Skip 'PS-SRC-4 with stand-in programs' 'chmod failed'
}

# --- PS-SRC-9 / PS-DST-20: JSON fields without jq --------------------------------------------
$body = '{"data":{"items":[{"key":"A-1","number":7},{"key":"B-2","text":"' + $script:JA + '\nline 2 \"q\" \\ end"}]},"n":12,"t":true,"f":false,"z":null,"id":"T-42"}'
$null = [System.IO.Directory]::CreateDirectory((WP ($Scratch + '/sources')))
Put-Text (WP ($Scratch + '/sources/S1.body')) $body
Put-Text (WP ($Scratch + '/sources/S2.body')) '<html>sign in</html>'
Put-Text (WP ($Scratch + '/sources/S3.body')) '[{"a":"x"}]'
$d = ''
$want = @(
  @('S1', '.data.items[1].text', ('content: ' + ($script:JA + $script:LF + 'line 2 "q" \ end').Length + ' characters'), ($script:JA + $script:LF + 'line 2 "q" \ end')),
  @('S1', '.n', 'content: 2 characters', '12'),
  @('S1', '.t', 'content: 4 characters', 'true'),
  @('S1', '.f', 'content: empty', ''),
  @('S1', '.z', 'content: empty', ''),
  @('S1', '.missing', 'content: empty', ''),
  @('S1', '.Data', 'content: empty', ''),
  @('S1', '.data.items[5]', 'content: empty', ''),
  @('S2', '.a', 'content: not json', $null),
  @('S3', '.a', 'content: empty', '')
)
foreach ($cw in $want) {
  $r = Run-Form 'PS-SRC-9' @{ '{scratch}' = $Scratch; 'S<n>' = $cw[0]; '<path>' = $cw[1] } $W
  if ((Out-Text $r) -ne $cw[2]) { $d += ' ' + $cw[0] + $cw[1] + ': ' + (Out-Text $r) + ' (want ' + $cw[2] + ')' }
  elseif ($null -ne $cw[3]) {
    $got = Read-Bytes (WP ($Scratch + '/sources/' + $cw[0] + '.content.txt'))
    if (-not (Same-Bytes $got (U8 $cw[3]))) { $d += ' ' + $cw[0] + $cw[1] + ' file ' + (Show-Bytes $got) }
  }
}
$r = Run-Form 'PS-SRC-9' @{ '{scratch}' = $Scratch; 'S<n>' = 'S1'; '<path>' = '.data.items[0]' } $W
$got = Read-Text (WP ($Scratch + '/sources/S1.content.txt'))
if ($null -eq $got) { $d += ' object: no content file' } elseif ($got.Replace(' ', '') -ne '{"key":"A-1","number":7}') { $d += ' object: ' + $got }
Check 'PS-SRC-9: a JSON field without jq (nested path, array index, number, true, false, null, missing, wrong letter case, object, not JSON, top-level array), the text written as UTF-8 to S<n>.content.txt' $d

Put-Text (WP ($Scratch + '/response-0.json')) $body
Put-Text (WP ($Scratch + '/response-1.json')) '{"data":{"items":[{"number":12345}]}}'
Put-Text (WP ($Scratch + '/response-2.json')) 'not json'
$d = ''
foreach ($iw in @(@('0', '.id', 'id=T-42'), @('1', '.data.items[0].number', 'id=12345'), @('0', '.nothing', 'id='), @('0', '.ID', 'id='), @('2', '.id', 'id='))) {
  $r = Run-Form 'PS-DST-20' @{ '{scratch}' = $Scratch; '{i}' = $iw[0]; '<id_path>' = $iw[1] } $W
  if ((Out-Text $r) -ne $iw[2]) { $d += ' ' + $iw[1] + ': ' + (Out-Text $r) + ' (want ' + $iw[2] + ')' }
}
Check 'PS-DST-20: identifier at id_path=.id and at a nested path, empty for a missing field, a key in another letter case and a body that is not JSON' $d

# --- PS-SRC-11: capture a client's output -------------------------------------------------
$childOut = 'ID-1' + $script:LF + $script:JA + $script:LF
$childScript = '$o = [Console]::OpenStandardOutput(); $b = [Convert]::FromBase64String(''' + [Convert]::ToBase64String((U8 $childOut)) + '''); $o.Write($b, 0, $b.Length); $o.Flush(); $e = [Console]::OpenStandardError(); $c = [Convert]::FromBase64String(''' + [Convert]::ToBase64String((U8 ('warn' + $script:LF))) + '''); $e.Write($c, 0, $c.Length); $e.Flush(); exit 3'
$cmd = Child-Command $childScript
$d = ''
foreach ($run in 1, 2) {
  # Before the second run both files hold other text, which the form must replace.
  if ($run -eq 2) { Put-Text (WP ($Scratch + '/sources/S4.body')) 'stale'; Put-Text (WP ($Scratch + '/sources/S4.err')) 'stale' }
  $r = Run-Form 'PS-SRC-11' @{ '{scratch}' = $Scratch; 'S<n>' = 'S4'; '<command>' = $cmd } $W
  if (@($r)[-1] -ne 'exit=3') { $d += ' run ' + $run + ': ' + (Out-Text $r) }
  $gotO = Read-Bytes (WP ($Scratch + '/sources/S4.body'))
  $gotE = Read-Text (WP ($Scratch + '/sources/S4.err'))
  if (-not (Same-Bytes $gotO (U8 $childOut))) { $d += ' run ' + $run + ' stdout ' + (Show-Bytes $gotO) }
  if ($null -eq $gotE) { $d += ' run ' + $run + ': no error file' } elseif (-not $gotE.Contains('warn') -or $gotE.Contains('stale')) { $d += ' run ' + $run + ' stderr: ' + $gotE }
}
$r = Run-Form 'PS-SRC-11' @{ '{scratch}' = $Scratch; 'S<n>' = 'S5'; '<command>' = 'sw-no-such-program-x1 view 1' } $W
if (@($r)[-1] -ne 'exit=') { $d += ' not found: ' + (Out-Text $r) }
$gotO = Read-Bytes (WP ($Scratch + '/sources/S5.body'))
$gotE = Read-Text (WP ($Scratch + '/sources/S5.err'))
if ($null -eq $gotO -or $gotO.Length -ne 0) { $d += ' not found: stdout file missing or not empty' }
if ($null -eq $gotE -or $gotE.Length -eq 0) { $d += ' not found: no error text' }
Check 'PS-SRC-11: client output captured as UTF-8 (non-ASCII kept) into the body and error files, both replaced on a second run, exit=3; exit= and an error text for a command that does not start' $d

# --- PS-DST-1 / PS-DST-3: content-field conversions ----------------------------------------------
$md = '## T: ' + $script:JA + $script:CR + $script:LF + $script:LF + '| a \| b | count<limit -> x >= 3 & y |' + $script:LF + '<surface name> and `<code>`' + $script:LF + '<!-- comment -->' + $script:LF + '```' + $script:LF + '<tag> & </tag>' + $script:LF + '```' + $script:LF
foreach ($bom in @($false, $true)) {
  if ($bom) { Put-Bytes (WP ($Scratch + '/body-0.md')) (Join-Bytes ([byte[]](0xEF, 0xBB, 0xBF)) (U8 $md)) } else { Put-Text (WP ($Scratch + '/body-0.md')) $md }
  $d = ''
  $c1 = Run-Form 'PS-DST-1' @{ '{scratch}' = $Scratch; '{i}' = '0' } $W
  $c2 = Run-Form 'PS-DST-3' @{ '{scratch}' = $Scratch; '{i}' = '0' } $W
  if ((Out-Text $c1) -ne 'converted' -or (Out-Text $c2) -ne 'converted') { $d += ' printed ' + (Out-Text $c1) + ' / ' + (Out-Text $c2) }
  $e1 = U8 ($md.Replace('<', '&lt;').Replace('>', '&gt;'))
  $e2 = U8 ('<pre>' + $md.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') + '</pre>' + $script:LF)
  $g1 = Read-Bytes (WP ($Scratch + '/send-0.md'))
  $g2 = Read-Bytes (WP ($Scratch + '/send-0.html'))
  if (-not (Same-Bytes $g1 $e1)) { $d += ' markdown-escaped ' + (Show-Bytes $g1) }
  if (-not (Same-Bytes $g2 $e2)) { $d += ' pre ' + (Show-Bytes $g2) }
  Check ('PS-DST-1 / PS-DST-3: markdown-escaped and the preformatted HTML on a Japanese ticket' + $(if ($bom) { ' with a byte order mark' } else { '' }) + ' (UTF-8 without byte order mark out, CR LF kept, every < escaped)') $d
}

# --- PS-DST-7: ticket number collision -------------------------------------------------------
# tk/.rollback/002-y sits where the form looks ({dir}/<child>/{NNN}-*), so
# only the exclusion of dot directories keeps 002 free.
foreach ($x in @('tk/p/001-x', 'tk/.rollback/q-T1/002-y', 'tk/.rollback/002-y', 'tk/q/003-z')) { $null = [System.IO.Directory]::CreateDirectory((WP $x)) }
Put-Text (WP 'tk/note.txt') 'x'
Put-Text (WP 'tk/q/004-file.md') 'x'
$d = ''
foreach ($nc in @(@('001', 'taken: p/001-x'), @('002', 'free'), @('003', 'taken: q/003-z'), @('004', 'taken: q/004-file.md'), @('005', 'free'))) {
  $r = Run-Form 'PS-DST-7' @{ '{dir}' = 'tk'; '{NNN}' = $nc[0] } $W
  if ((Out-Text $r) -ne $nc[1]) { $d += ' ' + $nc[0] + ': ' + (Out-Text $r) + ' (want ' + $nc[1] + ')' }
}
$r = Run-Form 'PS-DST-7' @{ '{dir}' = 'tk-missing'; '{NNN}' = '001' } $W
if ((Out-Text $r) -ne 'free') { $d += ' missing dir: ' + (Out-Text $r) }
Check 'PS-DST-7: a taken number names <parent>/<entry>, a free one prints free, .rollback/ is never looked into' $d

# A sibling directory that cannot be read is skipped, as the POSIX pattern
# skips it, and a match in another one is still reported. Only where chmod can
# make a directory unreadable for this process (not as root, not on Windows).
if (-not $script:IsWin) {
  foreach ($x in @('tk2/a-parent/001-x', 'tk2/b-parent/007-taken')) { $null = [System.IO.Directory]::CreateDirectory((WP $x)) }
  $null = & chmod 000 (WP 'tk2/a-parent') 2>&1
  $readable = $true
  try { $null = [System.IO.Directory]::GetFileSystemEntries((WP 'tk2/a-parent')) } catch { $readable = $false }
  if ($readable) {
    Write-Line '  NOTE PS-DST-7 unreadable-sibling case not run: this process can read a directory with mode 000'
  } else {
    $r = Run-Form 'PS-DST-7' @{ '{dir}' = 'tk2'; '{NNN}' = '007' } $W
    Check 'PS-DST-7: an unreadable sibling directory is skipped and a match in another parent is still taken' $(if ((Out-Text $r) -eq 'taken: b-parent/007-taken') { '' } else { 'printed ' + (Out-Text $r) })
  }
  $null = & chmod 755 (WP 'tk2/a-parent') 2>&1
}

# --- PS-DST-8: keep the quarantine out of commits -----------------------------------------------
if (Has-Program 'git') {
  $repo2 = [System.IO.Path]::Combine($Root, 'repo2')
  $null = [System.IO.Directory]::CreateDirectory([System.IO.Path]::Combine($repo2, 'tickets'))
  $env:GIT_CEILING_DIRECTORIES = $Root
  Push-Location -LiteralPath $repo2
  $null = & git init -q 2>&1
  Pop-Location
  Put-Bytes ([System.IO.Path]::Combine($repo2, '.gitignore')) (U8 'build.log')
  $q1 = Run-Form 'PS-DST-8' @{ '<root>' = '.'; '{dir}' = 'tickets' } $repo2
  $q2 = Run-Form 'PS-DST-8' @{ '<root>' = '.'; '{dir}' = 'tickets' } $repo2
  $q3 = Run-Form 'PS-DST-8' @{ '<root>' = '.'; '{dir}' = '../outside' } $repo2
  $d = ''
  if ((Out-Text $q1) -ne 'appended') { $d += ' first: ' + (Out-Text $q1) }
  if ((Out-Text $q2) -ne 'ignored') { $d += ' second: ' + (Out-Text $q2) }
  if ((Out-Text $q3) -ne 'outside') { $d += ' outside: ' + (Out-Text $q3) }
  $gi = Read-Bytes ([System.IO.Path]::Combine($repo2, '.gitignore'))
  if (-not (Same-Bytes $gi (U8 ('build.log' + $script:LF + 'tickets/.rollback/' + $script:LF)))) { $d += ' .gitignore ' + (Show-Bytes $gi) }
  Check 'PS-DST-8: the quarantine line is appended once (then git reports it ignored), and a directory outside the repository is left alone' $d
} else {
  Skip 'PS-DST-8' 'git is not installed'
}

# --- PS-DST-12: quarantine move ------------------------------------------------------------------
foreach ($x in @('qd [1]/p/001-x/ticket.md', 'qd [1]/p/split-plan.md')) { Put-Text (WP $x) ('content of ' + $x) }
$t1 = Out-Text (Run-Form 'PS-DST-11' @{} $W)
$mk = Run-Form 'PS-IN-1' @{ '<directory>' = ('qd [1]/.rollback/p-' + $t1) } $W
$mv1 = Run-Form 'PS-DST-12' @{ '<entry>' = 'qd [1]/p/001-x'; '{dir}' = 'qd [1]'; '{parent-slug}' = 'p'; '{ts}' = $t1 } $W
$mv2 = Run-Form 'PS-DST-12' @{ '<entry>' = 'qd [1]/p/split-plan.md'; '{dir}' = 'qd [1]'; '{parent-slug}' = 'p'; '{ts}' = $t1 } $W
$d = ''
if ((Out-Text $mk) -ne 'ok' -or (Out-Text $mv1) -ne 'moved' -or (Out-Text $mv2) -ne 'moved') { $d += ' printed ' + (Out-Text $mk) + ' / ' + (Out-Text $mv1) + ' / ' + (Out-Text $mv2) }
$qt = Read-Text (WP ('qd [1]/.rollback/p-' + $t1 + '/001-x/ticket.md'))
if ($qt -ne 'content of qd [1]/p/001-x/ticket.md') { $d += ' moved ticket holds ' + $qt }
if (-not [System.IO.File]::Exists((WP ('qd [1]/.rollback/p-' + $t1 + '/split-plan.md')))) { $d += ' split-plan.md not moved' }
if ([System.IO.Directory]::Exists((WP 'qd [1]/p/001-x'))) { $d += ' source directory still there' }
Check 'PS-DST-12: a ticket directory and split-plan.md move into the quarantine under their own names, wildcard characters in {dir} taken literally' $d

# --- PS-DST-14 / PS-DST-15 / PS-DST-16: template and probe JSON tests ----------------------------
Put-Text (WP 'tpl/array.json') ('[{"fields": {"summary": "{title}", "description": "{body}", "parent": {"key": "{parent}"}, "link": "https://x.example/browse/{parent}"}}]' + $script:LF)
Put-Text (WP 'tpl/nobody.json') '{"title": "{title}", "description": "text"}'
Put-Text (WP 'tpl/keyonly.json') '{"{title}": "x", "description": "{body}"}'
Put-Text (WP 'tpl/inner.json') '{"title": "x\"{title}", "description": "{body}"}'
Put-Text (WP 'tpl/broken.json') '{"title": "{title}", "description": "{body}"'
Put-Text (WP 'tpl/default.json') '{"title": "{title}", "description": "{body}"}'
$d = ''
foreach ($tc in @(@('array', 'true', 'true', 'true'), @('nobody', 'true', 'false', 'false'), @('keyonly', 'false', 'true', 'false'), @('inner', 'false', 'true', 'false'), @('broken', 'false', 'false', 'false'), @('default', 'true', 'true', 'false'))) {
  $p = 'tpl/' + $tc[0] + '.json'
  $rt = Run-Form 'PS-DST-14' @{ '<path>' = $p } $W
  $rb = Run-Form 'PS-DST-14' @{ '<path>' = $p; '{title}' = '{body}' } $W
  $rp = Run-Form 'PS-DST-15' @{ '<path>' = $p } $W
  if ((Out-Text $rt) -ne $tc[1]) { $d += ' ' + $tc[0] + ' title: ' + (Out-Text $rt) }
  if ((Out-Text $rb) -ne $tc[2]) { $d += ' ' + $tc[0] + ' body: ' + (Out-Text $rb) }
  if ((Out-Text $rp) -ne $tc[3]) { $d += ' ' + $tc[0] + ' parent: ' + (Out-Text $rp) }
}
Put-Text (WP ($Scratch + '/probe-response.json')) '{"fields": {}}'
$j1 = Run-Form 'PS-DST-16' @{ '{scratch}' = $Scratch } $W
Put-Text (WP ($Scratch + '/probe-response.json')) '<!doctype html><title>Sign in</title>'
$j2 = Run-Form 'PS-DST-16' @{ '{scratch}' = $Scratch } $W
Put-Text (WP ($Scratch + '/probe-response.json')) ''
$j3 = Run-Form 'PS-DST-16' @{ '{scratch}' = $Scratch } $W
Put-Text (WP ($Scratch + '/probe-response.json')) (' ' + $script:LF)
$j4 = Run-Form 'PS-DST-16' @{ '{scratch}' = $Scratch } $W
# jq empty accepts an empty or blank file, and so does the form.
if ((Out-Text $j1) -ne 'json' -or (Out-Text $j2) -ne 'not json' -or (Out-Text $j3) -ne 'json' -or (Out-Text $j4) -ne 'json') { $d += ' probe body: ' + (Out-Text $j1) + ' / ' + (Out-Text $j2) + ' / ' + (Out-Text $j3) + ' / ' + (Out-Text $j4) }
Check 'PS-DST-14 / PS-DST-15 / PS-DST-16: template placeholder tests (array template, missing body, key only, inside a longer string, not JSON) and the probe-body JSON test (an empty or blank body is JSON, as for jq empty), all without jq' $d

# --- PS-DST-17: request body without jq --------------------------------------------------------
$title = 'Title "q" \ {body} {parent} ' + $script:JA
$bodyText = '## ' + $script:JA + $script:LF + 'quotes "x" and \back\slashes' + $script:CR + $script:LF + '{body} {title} {parent} "{body}"' + $script:LF + 'tab' + [char]9 + 'end' + $script:LF
Put-Text (WP ($Scratch + '/title-0.txt')) ($title + $script:CR + $script:LF)
Put-Text (WP ($Scratch + '/sent-0.md')) $bodyText
Put-Text (WP ($Scratch + '/title-1.txt')) ('{body}' + $script:LF)
$d = ''
foreach ($run in 1, 2) {
  $r = Run-Form 'PS-DST-17' @{ '{scratch}' = $Scratch; '{i}' = '0'; '<template>' = 'tpl/array.json'; '<sent body>' = ($Scratch + '/sent-0.md'); '<id>' = 'P-1' } $W
  if ((Out-Text $r) -ne 'request: written') { $d += ' run ' + $run + ': ' + (Out-Text $r) }
}
$raw = Read-Bytes (WP ($Scratch + '/request-0.json'))
if ($null -ne $raw -and $raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB) { $d += ' byte order mark written' }
$txt = $script:Utf8.GetString($raw)
if (-not $txt.TrimStart().StartsWith('[')) { $d += ' not an array any more' }
try {
  $j = @(ConvertFrom-Json -InputObject $txt)
  $f = $j[0].fields
  if ($j.Count -ne 1) { $d += ' array of ' + $j.Count }
  if ($f.summary -cne $title) { $d += ' title is [' + $f.summary + ']' }
  if ($f.description -cne $bodyText) { $d += ' body differs' }
  if ($f.parent.key -cne 'P-1') { $d += ' parent key ' + $f.parent.key }
  if ($f.link -cne 'https://x.example/browse/P-1') { $d += ' link ' + $f.link }
} catch { $d += ' not JSON: ' + $_.Exception.Message }
$r = Run-Form 'PS-DST-17' @{ '{scratch}' = $Scratch; '{i}' = '1'; '<template>' = 'tpl/default.json'; '<sent body>' = ($Scratch + '/sent-0.md'); '<id>' = '' } $W
try {
  $j = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText((WP ($Scratch + '/request-1.json')), $script:Utf8))
  if ($j.title -cne '{body}') { $d += ' a title that is {body} became [' + $j.title + ']' }
  if ($j.description -cne $bodyText) { $d += ' body differs after a {body} title' }
} catch { $d += ' second request not JSON: ' + (Out-Text $r) }
$r = Run-Form 'PS-DST-17' @{ '{scratch}' = $Scratch; '{i}' = '0'; '<template>' = 'tpl/broken.json'; '<sent body>' = ($Scratch + '/sent-0.md'); '<id>' = '' } $W
if ((Out-Text $r) -notmatch '^request: failed \(') { $d += ' broken template: ' + (Out-Text $r) }
Check 'PS-DST-17: request built without jq from a one-element array template (quotes, backslashes, placeholders and Japanese in title and body, CR LF title end) parses, stays an array, holds the exact texts; a {body} title is not re-filled; a broken template fails' $d

# --- PS-DL-2 / PS-DL-3 / PS-DL-4: scratch removal --------------------------------------------------
$null = [System.IO.Directory]::CreateDirectory((WP ($Scratch + '/sources/S1-media/deep')))
Put-Text (WP ($Scratch + '/sources/S1-media/deep/f.txt')) 'x'
$ro = WP ($Scratch + '/read-only.txt')
Put-Text $ro 'x'
[System.IO.File]::SetAttributes($ro, [System.IO.FileAttributes]::ReadOnly)
Put-Text (WP ($Other + '/keep.txt')) 'keep'
$null = [System.IO.Directory]::CreateDirectory((WP '.local/tickets'))
Put-Text (WP '.local/tickets/keep.md') 'keep'
$d = ''
$x = Run-Form 'PS-DL-2' @{ '{scratch}' = '.local' } $W
if ((Out-Text $x) -notmatch '^refused' -or -not [System.IO.Directory]::Exists((WP '.local/tickets'))) { $d += ' .local: ' + (Out-Text $x) }
$x = Run-Form 'PS-DL-2' @{ '{scratch}' = ($Scratch + '/..') } $W
if ((Out-Text $x) -notmatch '^refused') { $d += ' parent path: ' + (Out-Text $x) }
$x = Run-Form 'PS-DL-2' @{ '{scratch}' = $Scratch } $W
if ((Out-Text $x) -ne 'removed' -or [System.IO.Directory]::Exists((WP $Scratch))) { $d += ' scratch: ' + (Out-Text $x) }
$x = Run-Form 'PS-DL-3' @{ '{scratch}' = $Scratch } $W
if ((Out-Text $x) -ne 'absent') { $d += ' existence after removal: ' + (Out-Text $x) }
$x = Run-Form 'PS-DL-3' @{ '{scratch}' = $Other } $W
if ((Out-Text $x) -ne 'present') { $d += ' existence of the other run: ' + (Out-Text $x) }
$x = Run-Form 'PS-DL-2' @{ '{scratch}' = $Scratch } $W
if ((Out-Text $x) -ne 'removed') { $d += ' second removal: ' + (Out-Text $x) }
$x1 = Run-Form 'PS-DL-4' @{ '<directory>' = '.local/create-ticket-scratch' } $W
$x2 = Run-Form 'PS-DL-4' @{ '<directory>' = '.local' } $W
if ((Out-Text $x1) -ne 'kept' -or (Out-Text $x2) -ne 'kept') { $d += ' parents: ' + (Out-Text $x1) + ' / ' + (Out-Text $x2) }
if ((Read-Text (WP ($Other + '/keep.txt'))) -ne 'keep') { $d += ' the other run was touched' }
if ((Read-Text (WP '.local/tickets/keep.md')) -ne 'keep') { $d += ' the tickets were touched' }
[System.IO.File]::Delete((WP ($Other + '/keep.txt')))
[System.IO.Directory]::Delete((WP $Other))
$x1 = Run-Form 'PS-DL-4' @{ '<directory>' = '.local/create-ticket-scratch' } $W
$x2 = Run-Form 'PS-DL-4' @{ '<directory>' = '.local' } $W
if ((Out-Text $x1) -ne 'removed' -or (Out-Text $x2) -ne 'kept' -or -not [System.IO.Directory]::Exists((WP '.local/tickets'))) { $d += ' after the other run: ' + (Out-Text $x1) + ' / ' + (Out-Text $x2) }
[System.IO.File]::Delete((WP '.local/tickets/keep.md'))
[System.IO.Directory]::Delete((WP '.local/tickets'))
$x2 = Run-Form 'PS-DL-4' @{ '<directory>' = '.local' } $W
if ((Out-Text $x2) -ne 'removed' -or [System.IO.Directory]::Exists((WP '.local'))) { $d += ' empty .local: ' + (Out-Text $x2) }
Check 'PS-DL-2 / PS-DL-3 / PS-DL-4: the scratch directory goes (read-only file and nested directories included), a non-scratch path is refused, a parent that holds another run or the tickets stays untouched, an empty parent is removed' $d

# A .local that is a link (a junction on Windows) to a directory that still
# holds the tickets: rmdir refuses it, and so does PS-DL-4.
$lw = [System.IO.Path]::Combine($Root, 'linkcase', 'w')
$lt = [System.IO.Path]::Combine($Root, 'linkcase', 'target')
$null = [System.IO.Directory]::CreateDirectory([System.IO.Path]::Combine($lt, 'tickets'))
$null = [System.IO.Directory]::CreateDirectory([System.IO.Path]::Combine($lt, 'create-ticket-scratch'))
$null = [System.IO.Directory]::CreateDirectory($lw)
Put-Text ([System.IO.Path]::Combine($lt, 'tickets', 'keep.md')) 'keep'
$link = [System.IO.Path]::Combine($lw, '.local')
$linkMade = $false
try {
  $kind = $(if ($script:IsWin) { 'Junction' } else { 'SymbolicLink' })
  $null = New-Item -ItemType $kind -Path $link -Target $lt -ErrorAction Stop
  $linkMade = $true
} catch { Write-Line ('  NOTE PS-DL-4 link case not run: the link could not be created (' + $_.Exception.Message + ')') }
if ($linkMade) {
  $y1 = Run-Form 'PS-DL-4' @{ '<directory>' = '.local/create-ticket-scratch' } $lw
  $y2 = Run-Form 'PS-DL-4' @{ '<directory>' = '.local' } $lw
  $d = ''
  if ((Out-Text $y1) -ne 'removed') { $d += ' empty scratch parent behind the link: ' + (Out-Text $y1) }
  if ((Out-Text $y2) -ne 'kept') { $d += ' the link: ' + (Out-Text $y2) }
  if (-not [System.IO.Directory]::Exists($link)) { $d += ' the link is gone' }
  if (-not [System.IO.File]::Exists([System.IO.Path]::Combine($lt, 'tickets', 'keep.md'))) { $d += ' the tickets behind the link are gone' }
  Check ('PS-DL-4: a .local that is a ' + $(if ($script:IsWin) { 'junction' } else { 'symbolic link' }) + ' to a directory holding the tickets is kept, as rmdir keeps it') $d
  try { [System.IO.Directory]::Delete($link, $false) } catch { }
}

# --- programs: Python scripts -----------------------------------------------------------------
$pyChoice = (Out-Text $py)
if ($pyChoice -eq 'python: none') {
  Skip 'PS-SRC-5 / PS-SRC-6 / PS-DST-2 / PS-DST-4 (the Python scripts on a Japanese workbook and ticket)' 'no Python 3 on this host'
} else {
  $python = $pyChoice.Substring(8)
  $skillAbs = (Resolve-Path -LiteralPath $SkillDir).ProviderPath
  $null = [System.IO.Directory]::CreateDirectory((WP 'py/.local/s/sources'))
  Add-Type -AssemblyName System.IO.Compression
  $zipPath = WP ('py/' + $script:JA + ' book.xlsx')
  $fs = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::Create)
  try {
    $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    $sml = 'application/vnd.openxmlformats-officedocument.spreadsheetml.'
    $parts = [ordered]@{
      '[Content_Types].xml' = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="' + $sml + 'sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="' + $sml + 'worksheet+xml"/></Types>'
      '_rels/.rels' = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
      'xl/workbook.xml' = '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="' + $script:JA2 + '" sheetId="1" r:id="rId1"/></sheets></workbook>'
      'xl/_rels/workbook.xml.rels' = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'
      'xl/worksheets/sheet1.xml' = '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>' + $script:JA + '</t></is></c><c r="B1" t="inlineStr"><is><t>two</t></is></c></row><row r="2"><c r="A2" t="inlineStr"><is><t>' + $script:JA2 + ' &lt;x&gt;</t></is></c></row></sheetData></worksheet>'
    }
    foreach ($pn in $parts.Keys) {
      $en = $zip.CreateEntry($pn)
      $es = $en.Open()
      try { $bb = U8 $parts[$pn]; $es.Write($bb, 0, $bb.Length) } finally { $es.Dispose() }
    }
    $zip.Dispose()
  } finally { $fs.Dispose() }
  $map = @{ '{python}' = $python; '{skill_root}' = $skillAbs; '{scratch}' = 'py/.local/s'; 'S<n>' = 'S1'; '["--sheet=<name>" ...] ' = ''; '<path>' = ('py/' + $script:JA + ' book.xlsx') }
  $cv = Run-Form 'PS-SRC-5' $map $W
  $conv = Read-Bytes (WP 'py/.local/s/sources/S1.md')
  $d = ''
  if (@($cv)[-1] -ne 'exit=0' -or (Out-Text $cv) -notmatch 'Converted: \d+ characters, \d+ lines, truncated: no') { $d += ' printed ' + (Out-Text $cv) }
  if ($null -eq $conv) { $d += ' no --out file' } else {
    $ct = $script:Utf8.GetString($conv)
    if ([Array]::IndexOf($conv, [byte]13) -ge 0) { $d += ' CR in the output file' }
    if ($conv.Length -ge 3 -and $conv[0] -eq 0xEF -and $conv[1] -eq 0xBB) { $d += ' byte order mark in the output file' }
    if (-not $ct.Contains($script:JA) -or -not $ct.Contains($script:JA2)) { $d += ' Japanese cell text missing' }
    $m = [regex]::Match((Out-Text $cv), 'Converted: (\d+) characters')
    if ($m.Success -and [int]$m.Groups[1].Value -ne $ct.Length) { $d += ' Converted: says ' + $m.Groups[1].Value + ' characters, the file has ' + $ct.Length }
  }
  Check ('PS-SRC-5: the converter writes the Japanese workbook to --out as UTF-8 with LF only and prints its Converted: line and exit=0 (' + $python + ')') $d
  $map['<auto|excel|soffice>'] = 'auto'
  $rv = Run-Form 'PS-SRC-6' $map $W
  Check 'PS-SRC-6: the render prints one Rendered: line (a plain workbook is not structured) and exit=0' $(if ((Out-Text $rv) -eq 'Rendered: no (not structured) | exit=0') { '' } else { 'printed ' + (Out-Text $rv) })
  $tkt = '## T: ' + $script:JA + $script:LF + $script:LF + '### Scope' + $script:LF + $script:LF + '<surface name> and count<limit -> x >= 3' + $script:LF + $script:LF + '| a | b |' + $script:LF + '|---|---|' + $script:LF + '| ' + $script:JA2 + ' | c \| d |' + $script:LF
  Put-Text (WP 'py/.local/s/body-0.md') $tkt
  $cm = @{ '{python}' = $python; '{skill_root}' = $skillAbs; '{scratch}' = 'py/.local/s'; '{i}' = '0' }
  $hv = Run-Form 'PS-DST-2' $cm $W
  $html = Read-Bytes (WP 'py/.local/s/send-0.html')
  $d = ''
  if (@($hv)[-1] -ne 'exit=0' -or (Out-Text $hv) -notmatch '^Converted: html \(\d+ characters\)') { $d += ' printed ' + (Out-Text $hv) }
  if ($null -eq $html) { $d += ' no HTML file' } else {
    $ht = $script:Utf8.GetString($html)
    if ([Array]::IndexOf($html, [byte]13) -ge 0) { $d += ' CR in the HTML file' }
    if ($html.Length -ge 3 -and $html[0] -eq 0xEF -and $html[1] -eq 0xBB) { $d += ' byte order mark in the HTML file' }
    if ($ht.Contains('<surface') -or -not $ht.Contains('&lt;surface name&gt;')) { $d += ' <surface name> not escaped' }
    if (-not $ht.Contains($script:JA)) { $d += ' Japanese text missing' }
  }
  Check 'PS-DST-2: ticket_body.py convert writes the HTML with LF only, no byte order mark, every < escaped, and prints Converted: and exit=0' $d
  $cm['<file>'] = 'py/.local/s/send-0.html'
  $kv = Run-Form 'PS-DST-4' $cm $W
  Check 'PS-DST-4: ticket_body.py check of the converted body prints Body check: complete and exit=0' $(if ((Out-Text $kv) -eq 'Body check: complete | exit=0') { '' } else { 'printed ' + (Out-Text $kv) })
}

# --- programs: curl.exe against a local listener -------------------------------------------------
$curlName = $null
if (Has-Program 'curl.exe') { $curlName = 'curl.exe' }
if ($null -eq $curlName) {
  Skip 'PS-SRC-7 / PS-SRC-8 / PS-DST-18 / PS-DST-19 (curl.exe against a local HTTP listener)' 'curl.exe is not installed'
} else {
  $tcp = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
  $tcp.Start()
  $port = ([System.Net.IPEndPoint]$tcp.LocalEndpoint).Port
  $tcp.Stop()
  $listener = New-Object System.Net.HttpListener
  $listener.Prefixes.Add('http://localhost:' + $port + '/')
  $listener.Start()
  $log = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
  $ps = [PowerShell]::Create()
  $null = $ps.AddScript({
    param($l, $log)
    while ($l.IsListening) {
      try { $ctx = $l.GetContext() } catch { break }
      $rq = $ctx.Request
      $ms = New-Object System.IO.MemoryStream
      $rq.InputStream.CopyTo($ms)
      $null = $log.Add(@{ Method = $rq.HttpMethod; Path = $rq.Url.AbsolutePath; Auth = [string]$rq.Headers['Authorization']; Type = [string]$rq.ContentType; Body = $ms.ToArray() })
      $status = 200
      $resp = '{"ok":true}'
      if ($rq.HttpMethod -eq 'POST') { $status = 201; $resp = '{"id":"T-9"}' }
      if ($rq.Url.AbsolutePath -eq '/missing') { $status = 404; $resp = '{"error":"no"}' }
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($resp)
      $ctx.Response.StatusCode = $status
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
      $ctx.Response.Close()
    }
  }).AddArgument($listener).AddArgument($log)
  $handle = $ps.BeginInvoke()
  $savedOut = $OutputEncoding
  $OutputEncoding = [System.Text.Encoding]::UTF8
  $env:SWPS_TOKEN = 'tok.EN-123_x=='
  $base = 'http://localhost:' + $port
  $null = [System.IO.Directory]::CreateDirectory((WP 'http/.local/s/sources'))
  $d = ''
  $expectAuth = @{
    'bearer' = 'Bearer tok.EN-123_x=='
    'basic' = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('tok.EN-123_x=='))
    'basic-token' = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(':tok.EN-123_x=='))
  }
  $n = 0
  foreach ($scheme in @('bearer', 'basic', 'basic-token')) {
    $n++
    $log.Clear()
    $r = Run-Form 'PS-SRC-7' @{ 'VAR' = 'SWPS_TOKEN'; '<scheme>' = $scheme; '{scratch}' = 'http/.local/s'; 'S<n>' = ('S' + $n); '<url>' = ($base + '/item?x=1&y=2') } $W
    if ((Out-Text $r) -ne '200 | exit=0') { $d += ' GET ' + $scheme + ': ' + (Out-Text $r) }
    if ($log.Count -ne 1 -or $log[0].Auth -cne $expectAuth[$scheme]) { $d += ' GET ' + $scheme + ' header [' + $(if ($log.Count -gt 0) { $log[0].Auth } else { 'none' }) + ']' }
    if ((Out-Text $r).Contains('tok.EN')) { $d += ' the token was printed' }
    $gb = Read-Text (WP ('http/.local/s/sources/S' + $n + '.body'))
    if ($gb -ne '{"ok":true}') { $d += ' GET ' + $scheme + ' body file: ' + $gb }
  }
  $log.Clear()
  $r = Run-Form 'PS-SRC-8' @{ '{scratch}' = 'http/.local/s'; 'S<n>' = 'S9'; '<url>' = ($base + '/missing') } $W
  if ((Out-Text $r) -ne '404 | exit=0') { $d += ' GET without token: ' + (Out-Text $r) }
  if ($log.Count -ne 1 -or $log[0].Auth -ne '') { $d += ' GET without token sent a header' }
  # The pipe into curl.exe is ASCII whatever the caller's $OutputEncoding (UTF-8
  # here): a character outside ASCII arrives as ?, never as UTF-8 bytes.
  $env:SWPS_TOKEN = 'caf' + [char]0xE9
  $log.Clear()
  $r = Run-Form 'PS-SRC-7' @{ 'VAR' = 'SWPS_TOKEN'; '<scheme>' = 'bearer'; '{scratch}' = 'http/.local/s'; 'S<n>' = 'S7'; '<url>' = ($base + '/item') } $W
  if ($log.Count -ne 1 -or $log[0].Auth -cne 'Bearer caf?') { $d += ' non-ASCII token header [' + $(if ($log.Count -gt 0) { $log[0].Auth } else { 'none' }) + '] (want Bearer caf?)' }
  $env:SWPS_TOKEN = 'tok.EN-123_x=='
  Put-Text (WP 'http/.local/s/request-0.json') ('{"title":"' + $script:JA + '","description":"a\nb"}')
  $reqBytes = Read-Bytes (WP 'http/.local/s/request-0.json')
  foreach ($scheme in @('bearer', 'basic', 'basic-token')) {
    $log.Clear()
    [System.IO.File]::Delete((WP 'http/.local/s/response-0.json'))
    $r = Run-Form 'PS-DST-18' @{ 'VAR' = 'SWPS_TOKEN'; '<scheme>' = $scheme; '{scratch}' = 'http/.local/s'; '{i}' = '0'; '<url>' = ($base + '/create'); '<content_type>' = 'application/json' } $W
    if ((Out-Text $r) -ne '201 | exit=0') { $d += ' POST ' + $scheme + ': ' + (Out-Text $r) }
    if ($log.Count -ne 1) { $d += ' POST ' + $scheme + ': ' + $log.Count + ' requests' } else {
      if ($log[0].Method -ne 'POST' -or $log[0].Auth -cne $expectAuth[$scheme]) { $d += ' POST ' + $scheme + ' header [' + $log[0].Auth + ']' }
      if (-not (Same-Bytes $log[0].Body $reqBytes)) { $d += ' POST ' + $scheme + ' body ' + (Show-Bytes $log[0].Body) }
      if ($log[0].Type -ne 'application/json') { $d += ' POST content type ' + $log[0].Type }
    }
    $rb = Read-Text (WP 'http/.local/s/response-0.json')
    if ($rb -ne '{"id":"T-9"}') { $d += ' response file: ' + $rb }
  }
  $log.Clear()
  $r = Run-Form 'PS-DST-19' @{ '{scratch}' = 'http/.local/s'; '{i}' = '0'; '<url>' = ($base + '/create'); '<content_type>' = 'application/json' } $W
  if ((Out-Text $r) -ne '201 | exit=0' -or $log.Count -ne 1 -or $log[0].Auth -ne '') { $d += ' POST without token: ' + (Out-Text $r) }
  $r = Run-Form 'PS-SRC-8' @{ '{scratch}' = 'http/.local/s'; 'S<n>' = 'S8'; '<url>' = 'http://localhost:1/nothing' } $W
  if (@($r)[-1] -notmatch '^exit=[1-9]') { $d += ' unreachable host: ' + (Out-Text $r) }
  $OutputEncoding = $savedOut
  Remove-Item -LiteralPath 'Env:SWPS_TOKEN' -ErrorAction SilentlyContinue
  $listener.Stop()
  $null = $handle.AsyncWaitHandle.WaitOne(5000)
  $ps.Dispose()
  Check 'PS-SRC-7 / PS-SRC-8 / PS-DST-18 / PS-DST-19: GET and POST through curl.exe with the bearer, basic and basic-token header read from stdin (pipe pinned to ASCII under a UTF-8 caller $OutputEncoding: a non-ASCII token character arrives as ?), the status and exit= printed, the token never printed, files written by curl itself' $d
}

# --- agent bodies: the read-only inspection forms of the researcher and the planner -----------------
$agentText = @{}
foreach ($an in @('researcher', 'planner')) {
  $ap = [System.IO.Path]::Combine((Resolve-Path -LiteralPath $SkillDir).ProviderPath, 'references', 'agents', $an + '.md')
  $agentText[$an] = $(if ([System.IO.File]::Exists($ap)) { [System.IO.File]::ReadAllText($ap, $script:Utf8) } else { '' })
}
$spans = @([regex]::Matches($agentText['researcher'], '`((Get-ChildItem|Select-String) [^`]+)`') | ForEach-Object { $_.Groups[1].Value })
$d = ''
if ($spans.Count -ne 3) { $d += ' found ' + $spans.Count + ' forms in researcher.md' }
foreach ($sp in $spans) { if (-not $agentText['planner'].Contains('`' + $sp + '`')) { $d += ' planner.md lacks ' + $sp } }
if ($spans.Count -eq 3) {
  $script:Forms['AGENT-LS'] = $spans[0]
  $script:Forms['AGENT-FIND'] = $spans[1]
  $script:Forms['AGENT-GREP'] = $spans[2]
  Put-Text (WP 'agent/a.md') ('# ' + $script:JA + $script:LF + 'TODO: ' + $script:JA2 + ' estimate' + $script:LF + 'done' + $script:LF)
  Put-Text (WP 'agent/.hidden') 'x'
  Put-Text (WP 'agent/sub/b.txt') 'x'
  $a1 = Run-Form 'AGENT-LS' @{ '<dir>' = 'agent' } $W
  $a2 = Run-Form 'AGENT-FIND' @{ '<dir>' = 'agent' } $W
  $a3 = Run-Form 'AGENT-GREP' @{ '<file>' = 'agent/a.md'; '<pattern>' = 'TODO|estimate' } $W
  if ((@($a1 | Sort-Object) -join ',') -ne '.hidden,a.md,sub') { $d += ' ls form: ' + (Out-Text $a1) }
  if ((@($a2 | ForEach-Object { $_.Replace('\', '/') } | Sort-Object) -join ',') -ne '.hidden,a.md,sub/b.txt') { $d += ' find form: ' + (Out-Text $a2) }
  if ((Out-Text $a3) -cne ('2:TODO: ' + $script:JA2 + ' estimate')) { $d += ' grep form: ' + (Out-Text $a3) }
  if ((Out-Text $a3).IndexOf([char]27) -ge 0) { $d += ' grep form printed an escape sequence' }
}
Check 'agent bodies: the ls, find and grep forms of researcher.md and planner.md list names (dot-files included) and print <line number>:<line> without emphasis codes' $d

# --- passthrough: a form's output as the host receives it ----------------------------------------
$formText = Fill 'PS-AP-2' @{ '<status command>' = $(if ($script:IsWin) { 'cmd.exe /d /c echo signed-in' } else { "sh -c 'echo signed-in'" }) }
$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName = $PsExe
$pinfo.Arguments = '-NoProfile -NonInteractive -EncodedCommand ' + [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($formText))
$pinfo.UseShellExecute = $false
$pinfo.RedirectStandardOutput = $true
$pinfo.RedirectStandardError = $true
$pinfo.WorkingDirectory = $W
$proc = [System.Diagnostics.Process]::Start($pinfo)
$ms = New-Object System.IO.MemoryStream
$proc.StandardOutput.BaseStream.CopyTo($ms)
$null = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()
$outText = [System.Text.Encoding]::ASCII.GetString($ms.ToArray()).Replace($script:CR, '')
Check 'PS-AP-2 as a host runs it (a child PowerShell with its output in a pipe): the client line comes before exit=0' $(if ($outText -match '^signed-in\s*\nexit=0\s*$') { '' } else { 'output: ' + $outText.Replace($script:LF, '\n') })

# --- every form was run or skipped --------------------------------------------------------------
$never = @($script:Forms.Keys | Where-Object { -not $script:Ran.ContainsKey($_) -and -not $script:Skipped.ContainsKey($_) } | Sort-Object)
Check 'every fenced form of references/shell-powershell.md was run (or skipped for a missing program)' $(if ($never.Count -eq 0) { '' } else { 'never run: ' + ($never -join ', ') })

# --- end -------------------------------------------------------------------------------------
[System.Environment]::CurrentDirectory = [System.IO.Path]::GetTempPath()
try { Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction Stop } catch { Write-Line ('  NOTE could not remove ' + $Root) }
if ($null -ne $script:ConsoleBefore) { try { [Console]::OutputEncoding = $script:ConsoleBefore } catch { } }
Write-Line ''
Write-Line ('PASS ' + $script:Pass + ' / FAIL ' + $script:Fail + ' / SKIP ' + $script:Skip)
if ($script:Fail -gt 0) { exit 1 }
exit 0
