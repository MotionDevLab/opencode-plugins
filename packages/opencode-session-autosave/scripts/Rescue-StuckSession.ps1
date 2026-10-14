# Rescue-StuckSession.ps1 -- zero-model, zero-typing rescue for a throttled opencode session.
# Double-click (or: Rescue-StuckSession.ps1 -SessionId ses_xxx -Message "continue the work" [-Model qwencloud-2/kimi-k3]).
# 1) exports a JSON backup, 2) detects router vs native provider from the backup,
# 3) clears the router pin (router sessions) or skips it (native), 4) copies the best fork command to clipboard.
# NOTE: ASCII only in this file (PowerShell 5.1 misreads UTF-8 without BOM).
param(
  [string]$SessionId = "",
  [string]$Message = "continue the work",
  [string]$Model = ""
)

$ErrorActionPreference = "Stop"

# Direct exe bypasses the npm .ps1 shim, whose stderr rendering flashes red.
# Falls back to PATH `opencode` if the install layout ever changes.
$Exe = Join-Path $env:APPDATA "npm\node_modules\opencode-ai\bin\opencode.exe"
if (-not (Test-Path $Exe)) { $Exe = "opencode" }

function Safe-Run([scriptblock]$Block) {
  $prevPref = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try { & $Block } finally { $ErrorActionPreference = $prevPref }
}

# 1) Pick session: explicit arg first, else the last session that hit a
# stream error in the log (the rate-limited one), else most recent session.
if (-not $SessionId) {
  try {
    $logPath = Join-Path $env:USERPROFILE ".local\share\opencode\log\opencode.log"
    # small=false = real build turns only; title/small-agent failures (small=true)
    # from background sessions would otherwise misdirect the pick.
    $lastErr = Select-String -Path $logPath -Pattern 'level=ERROR.*stream error.*session\.id=(ses_[A-Za-z0-9]+).*small=false' | Select-Object -Last 1
    if ($lastErr -and ($lastErr.Line -match 'session\.id=(ses_[A-Za-z0-9]+)')) { $SessionId = $Matches[1] }
  } catch { $SessionId = "" }
  if ($SessionId) { Write-Host ("Picked last rate-limited session from log: " + $SessionId) }
}
if (-not $SessionId) {
  $list = Safe-Run { & $Exe session list 2>$null } | Where-Object { $_ -match 'ses_[A-Za-z0-9]+' }
  $first = $list | Select-Object -First 1
  if ($first -match '(ses_[A-Za-z0-9]+)') { $SessionId = $Matches[1] }
  if (-not $SessionId) { Write-Host "No sessions found. Pass -SessionId explicitly."; exit 1 }
  Write-Host ("Picked most recent session: " + $SessionId)
}
Write-Host ("Session: " + $SessionId)

# 2) Export backup (read-only; stdout JSON -> file).
# Backups live with opencode's own data (not Desktop -- multi-MB JSONs cause
# sync churn and clutter there). Desktop keeps only the Rescue shortcut.
$backupDir = Join-Path $env:USERPROFILE ".local\share\opencode\backups"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$stamp = Get-Date -Format "yyyy-MM-ddTHH-mm-ss"
$backup = Join-Path $backupDir ("opencode-rescue-" + $SessionId + "-" + $stamp + ".json")
$prevPref = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $Exe export $SessionId > $backup 2>$null
$code = $LASTEXITCODE
$ErrorActionPreference = $prevPref
if ($code -ne 0 -or -not (Test-Path $backup)) { Write-Host ("Export FAILED (exit " + $code + ")."); exit 1 }
# Strip plugin preamble (sentry status text opencode prints before the JSON body).
$blines = Get-Content $backup
$start = -1
for ($i = 0; $i -lt $blines.Count - 1; $i++) {
  if ($blines[$i] -match '^\s*\{\s*$' -and $blines[$i+1] -match '^\s*"info"\s*:') { $start = $i; break }
}
if ($start -gt 0) { $blines[$start..($blines.Count-1)] | Set-Content $backup -Encoding UTF8 }
try { Get-Content $backup -Raw | ConvertFrom-Json | Out-Null; $jsonOk = $true } catch { $jsonOk = $false }
# Retention: newest 3 backups per session, rest pruned.
$keep = Get-ChildItem $backupDir -Filter ("opencode-rescue-" + $SessionId + "-*.json") | Sort-Object LastWriteTime -Descending | Select-Object -Skip 3
foreach ($old in $keep) { Remove-Item $old.FullName -Force -ErrorAction SilentlyContinue }
Write-Host ("Backup: " + $backup + " (" + (Get-Item $backup).Length + " bytes, JSON valid: " + $jsonOk + ")")
if (-not $jsonOk) { Write-Host "WARNING: backup JSON did not validate - fork still works (history is in the DB), but treat import with care." }

# 3) Detect provider from the backup: last providerID/modelID wins (most recent message).
$raw = Get-Content $backup -Raw
$provMatches = [regex]::Matches($raw, '"providerID"\s*:\s*"([^"]+)"')
$modelMatches = [regex]::Matches($raw, '"modelID"\s*:\s*"([^"]+)"')
$provider = "unknown"
$oldModel = "unknown"
if ($provMatches.Count -gt 0) { $provider = $provMatches[$provMatches.Count - 1].Groups[1].Value }
if ($modelMatches.Count -gt 0) { $oldModel = $modelMatches[$modelMatches.Count - 1].Groups[1].Value }
Write-Host ("Detected: " + $provider + "/" + $oldModel)
$title = "unknown"
$dir = ""
if ($raw -match '"title"\s*:\s*"([^"]+)"') { $title = $Matches[1] }
if ($raw -match '"directory"\s*:\s*"([^"]+)"') { $dir = $Matches[1] }
Write-Host ("Title: " + $title)
if ($dir) { Write-Host ("Project dir: " + $dir) }
$isRouter = ($provider -eq "multi-auth-zen")

# 4) Router pin clear helps ONLY router sessions; native (zen-2/opencode/qwencloud) skips it.
if ($isRouter) {
  try {
    $clear = curl.exe -s -m 10 -X POST http://localhost:18904/api/sessions/clear -H "Content-Type: application/json" -d "{}"
    $health = curl.exe -s -m 10 http://localhost:18904/healthz
    Write-Host ("Router clear: " + $clear)
    Write-Host ("Router health: " + $health)
  } catch {
    Write-Host "Router unreachable (is the daemon running?). Backup above is still valid."
  }
} else {
  Write-Host ("Native provider (" + $provider + ") - no router pin to clear, skipping.")
}

# 5) Fork targets. Export/backup above works for EVERY provider (local DB read,
# no model call) -- native opencode, zen-2, multi-auth-zen, qwencloud all alike.
# Best next pool depends on where you are stuck:
#   multi-auth-zen -> pin cleared above, same-model fork usually suffices.
#   zen-2          -> other Zen account (built-in opencode) holds the same model IDs.
#   opencode       -> other Zen account (zen-2) holds the same model IDs.
#   anything else  -> Qwen fallback (unaffected pool per docs).
$q = [char]34
$Fallback = "qwencloud-2/kimi-k3"
$forkSame = "opencode -s " + $SessionId + " --fork " + $q + $Message + $q
$crossTarget = $Fallback
if ($provider -eq "zen-2" -and $oldModel -ne "unknown") { $crossTarget = "opencode/" + $oldModel }
if ($provider -eq "opencode" -and $oldModel -ne "unknown") { $crossTarget = "zen-2/" + $oldModel }
if ($Model) { $crossTarget = $Model }
$forkCross = "opencode -s " + $SessionId + " --fork -m " + $crossTarget + " " + $q + $Message + $q
if ($isRouter) {
  $best = $forkSame
  $bestWhy = "Router session: same-model fork usually suffices (pin cleared above)."
  $alt = $forkCross
} else {
  $best = $forkCross
  $bestWhy = "Native session (" + $provider + "): same pool is throttled - cross-pool fork recommended."
  $alt = $forkSame
}
Write-Host $bestWhy
Set-Clipboard -Value $best
Write-Host ""
Write-Host "RECOMMENDED (copied to clipboard, paste in a NEW terminal):"
Write-Host ("  " + $best)
Write-Host "Alternative:"
Write-Host ("  " + $alt)
Write-Host ("Old session is untouched (delete later: opencode session delete " + $SessionId + ")")
