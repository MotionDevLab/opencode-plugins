---
description: Snapshot the current session - timestamped JSON backup, no fork, no questions
---

# Snapshot current session

Routine checkpoint (milestone done, before compaction, end of day).
For emergencies on a dead session use the desktop Rescue shortcut instead.

Rules (follow exactly, no improvisation):
- You already know this session's ID from the conversation. Use it. Never run
  discovery commands (no env lookup, no directory listing first).
- Run exactly ONE shell block (below). Do not split it, do not preface it.
- The export command MUST include the session ID: `opencode export <ID>`.
  A bare `opencode export` with no ID is wrong.

Steps:

1. Fill SESSION with this session's ID and run this single block (PowerShell):

```powershell
$sid = "PUT-SESSION-ID-HERE"
$stamp = Get-Date -Format "yyyy-MM-ddTHH-mm-ss"
$dir = Join-Path $env:USERPROFILE ".local\share\opencode\backups"
New-Item -ItemType Directory -Path $dir -Force | Out-Null
Get-ChildItem $dir -Filter ("opencode-snapshot-session-" + $sid + "-*.json") | Sort-Object LastWriteTime -Descending | Select-Object -Skip 3 | ForEach-Object { Remove-Item $_.FullName -Force }
$out = Join-Path $dir ("opencode-snapshot-session-" + $sid + "-" + $stamp + ".json")
& "$env:APPDATA\npm\node_modules\opencode-ai\bin\opencode.exe" export $sid > $out 2>$null
$blines = Get-Content $out
$start = -1
for ($i = 0; $i -lt $blines.Count - 1; $i++) { if ($blines[$i] -match '^\s*\{\s*$' -and $blines[$i+1] -match '^\s*"info"') { $start = $i; break } }
if ($start -gt 0) { $blines[$start..($blines.Count-1)] | Set-Content $out -Encoding UTF8 }
try { Get-Content $out -Raw | ConvertFrom-Json | Out-Null; $v = "True" } catch { $v = "False" }
Write-Host ("SNAPSHOT path=" + $out + " bytes=" + (Get-Item $out).Length + " valid=" + $v)
```

2. Report one line: backup path, size, JSON valid true/false.
   Never print message contents.

3. End by telling the user: snapshot done — say `continue` to resume the
   interrupted task. The snapshot itself resumes nothing; the interrupted
   task waits for the user's next message.
