#!/usr/bin/env pwsh
# lib/State-Restamp.ps1 — deterministic baseline refresh (mirrors bash
# lib/state-restamp.sh). No-op unless the command is restamp; exits when run.
if ($Command -eq "restamp") {
  if (-not (Test-Git)) { Write-Output "not a git repository — cannot restamp"; exit 1 }
  if (-not ($Blueprint -and (Test-Path $Blueprint))) { Write-Output "no blueprint"; exit 1 }
  $text = Get-Content -Raw $Blueprint; $updated = 0
  foreach ($m in (Get-CodeMarkers)) {
    if ($PathFilter -and $PathFilter -ne $m.path) { continue }
    $cur = Get-CurSha $m.path
    if (-not $cur) { Write-Output "skip (missing in git): $($m.path)"; continue }
    $old = "<!-- blueprint:code path=$($m.path) sha=$($m.sha) -->"
    $new = "<!-- blueprint:code path=$($m.path) sha=$cur -->"
    $text = $text.Replace($old, $new); Write-Output "stamped $($m.path) -> $cur"; $updated++
  }
  Set-Content -NoNewline -Path $Blueprint -Value $text
  Write-Output "restamped $updated marker(s)"; exit 0
}

