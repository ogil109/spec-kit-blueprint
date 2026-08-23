#!/usr/bin/env pwsh
# lib/Slice-Covered.ps1 — DOCPAIRS parse, covered-path set, holes (mirrors
# bash lib/slice-covered.sh).
# ── verify: parse the map's actual structure (state, heading, kind, marker) ───
$DocPairs = @()
if ($Command -eq "verify") {
  if (-not ($Blueprint -and (Test-Path $Blueprint))) { [Console]::Error.WriteLine("verify: no blueprint found"); exit 1 }
  $heading = ""; $state = ""
  foreach ($line in [System.IO.File]::ReadAllLines($Blueprint)) {
    if ($line -match '^## ') { $heading = ($line -replace '^##\s+', '' -replace ' \(remainder\)$', ''); $state = ""; continue }
    if ($line -match '<!-- blueprint:section state=(\S+)') { $state = ($Matches[1] -replace '-->.*', ''); continue }
    if ($line -match '<!-- blueprint:code path=(\S+) ')    { $DocPairs += [pscustomobject]@{ state = $state; heading = $heading; kind = "code";    path = $Matches[1] }; continue }
    if ($line -match '<!-- blueprint:context path=(\S+) ') { $DocPairs += [pscustomobject]@{ state = $state; heading = $heading; kind = "context"; path = $Matches[1] }; continue }
  }
}

# ── existing coverage (subtracted unless --all; verify: spec-owned only) ──────
$covered = @()
if ($Command -eq "verify") {
  $covered = Sort-OrdinalUnique @($DocPairs | Where-Object { ($_.state -eq "distilled" -or $_.state -eq "detailed") -and $_.kind -eq "code" } |
    ForEach-Object { $_.path })
} elseif (-not $All -and $Blueprint -and (Test-Path $Blueprint)) {
  $covered = Sort-OrdinalUnique @(Select-String -Path $Blueprint -Pattern '<!-- blueprint:(code|context) path=(\S+)' -AllMatches |
    ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[2].Value })
}
$BpRel = ""
if ($Blueprint) { $BpRel = $Blueprint.Replace("$Root/", "").Replace("$Root\", "") }

