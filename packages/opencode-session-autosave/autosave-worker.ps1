# autosave-worker.ps1 -- background session backup for the opencode-session-autosave plugin.
# Launched via spawn (no console, no model call, no quota). Never throws to the caller.
# Usage: autosave-worker.ps1 -SessionId ses_xxx -Kind auto|emergency|precompact|postcompact|snapshot-session|rescue
# Retention (delete-after-write, enforced here, no scheduler):
#   auto: keep last 3 per session id + delete anything older than 7 days.
#   emergency: keep last 2 per session id + delete anything older than 7 days.
#   Scope is whole-kind: every save converges ALL sessions of that kind, so
#   dead sessions shrink to nothing instead of lingering at the per-session cap.
#   precompact/postcompact/snapshot-session/rescue: uncapped (rare, small, precious).
#   Never deletes the file just written. Dir unreachable -> log and skip.
# Backups + autosave.log: %USERPROFILE%\.local\share\opencode\backups\ (disk files, not RAM).
# NOTE: ASCII only in this file (PowerShell 5.1 misreads UTF-8 without BOM).
param(
  [string]$SessionId = "",
  [string]$Kind = "auto"
)

$ErrorActionPreference = "Continue"

function Log-Line([string]$Msg) {
  try {
    $logDir = Join-Path $env:USERPROFILE ".local\share\opencode\backups"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $ts = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    ($ts + " [" + $Kind + "] " + $SessionId + " " + $Msg) | Out-File (Join-Path $logDir "autosave.log") -Append -Encoding UTF8
  } catch { }
}

if (-not $SessionId) { Log-Line "SKIP empty-session-id"; exit 0 }
Log-Line "START"

$backupDir = Join-Path $env:USERPROFILE ".local\share\opencode\backups"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$stamp = Get-Date -Format "yyyy-MM-ddTHH-mm-ss"
$prefix = "opencode-auto-"
$keep = 3
$retentionDays = 7
$retentionOn = $true
if ($Kind -eq "emergency") { $prefix = "opencode-emergency-"; $keep = 2 }
if ($Kind -eq "precompact") { $prefix = "opencode-precompact-"; $retentionOn = $false }
if ($Kind -eq "postcompact") { $prefix = "opencode-postcompact-"; $retentionOn = $false }
if ($Kind -eq "snapshot-session") { $prefix = "opencode-snapshot-session-"; $retentionOn = $false }
if ($Kind -eq "rescue") { $prefix = "opencode-rescue-"; $retentionOn = $false }

function Ordinal([int]$n) {
  $suffix = "th"
  $m = $n % 100
  if ($m -lt 11 -or $m -gt 13) {
    $r = $n % 10
    if ($r -eq 1) { $suffix = "st" }
    elseif ($r -eq 2) { $suffix = "nd" }
    elseif ($r -eq 3) { $suffix = "rd" }
  }
  return ("" + $n + $suffix)
}
$backup = Join-Path $backupDir ($prefix + $SessionId + "-" + $stamp + ".json")

$Exe = Join-Path $env:APPDATA "npm\node_modules\opencode-ai\bin\opencode.exe"
if (-not (Test-Path $Exe)) { $Exe = "opencode" }

try {
  & $Exe export $SessionId > $backup 2>$null
  $code = $LASTEXITCODE
} catch {
  $code = 1
}
if ($code -ne 0 -or -not (Test-Path $backup)) { Log-Line ("EXPORT-FAIL exit=" + $code); exit 0 }

$blines = Get-Content $backup
$start = -1
for ($i = 0; $i -lt $blines.Count - 1; $i++) {
  if ($blines[$i] -match '^\s*\{\s*$' -and $blines[$i+1] -match '^\s*"info"\s*:') { $start = $i; break }
}
if ($start -gt 0) { $blines[$start..($blines.Count-1)] | Set-Content $backup -Encoding UTF8 }
$valid = $false
try { Get-Content $backup -Raw | ConvertFrom-Json | Out-Null; $valid = $true } catch { $valid = $false }
if (-not $valid) { Remove-Item $backup -Force -ErrorAction SilentlyContinue; Log-Line "INVALID-JSON deleted"; exit 0 }

$bytes = 0
try { $bytes = (Get-Item $backup).Length } catch { $bytes = 0 }
$retentionDeleted = 0
if ($retentionOn) {
  try {
    $justWritten = (Get-Item $backup).FullName
    $cutoff = (Get-Date).AddDays(0 - $retentionDays)
    $all = Get-ChildItem $backupDir -Filter ($prefix + "*.json") | Sort-Object LastWriteTime -Descending
    $perSession = @{}
    foreach ($f in $all) {
      $sid = ""
      if ($f.Name -match ("^" + [regex]::Escape($prefix) + "(.+)-(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2})\.json$")) { $sid = $Matches[1] } else { continue }
      if (-not $perSession.ContainsKey($sid)) { $perSession[$sid] = 0 }
      $perSession[$sid]++
      if ($f.FullName -eq $justWritten) { continue }
      $reason = ""
      if ($perSession[$sid] -gt $keep) { $reason = (Ordinal $perSession[$sid]) + " newest for session (keep " + $keep + ")" }
      elseif ($f.LastWriteTime -lt $cutoff) { $reason = "older than " + $retentionDays + "d" }
      if ($reason -ne "") {
        try {
          Remove-Item $f.FullName -Force -ErrorAction Stop
          $retentionDeleted++
          Log-Line ("[retention] deleted " + $f.Name + " (" + $reason + ")")
        } catch {
          Log-Line ("[retention] FAILED " + $f.Name + " : " + $_.Exception.Message)
        }
      }
    }
  } catch {
    Log-Line ("[retention] SKIP dir unreachable: " + $_.Exception.Message)
  }
}
Log-Line ("OK bytes=" + $bytes + " retention_deleted=" + $retentionDeleted)
exit 0
