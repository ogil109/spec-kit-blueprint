#!/usr/bin/env pwsh
# lib/Slice-Output.ps1 — oversize advisories, excluded roster, and the slice
# JSON/human emission (mirrors bash lib/slice-output.sh).
# ── advisories: existing code sections that outgrew the thresholds ────────────
$Advisories = @()
if (-not $All -and $Blueprint -and (Test-Path $Blueprint)) {
  $advPaths = Sort-OrdinalUnique @(Select-String -Path $Blueprint -Pattern '<!-- blueprint:code path=(\S+)' -AllMatches |
    ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value })
  foreach ($p in $advPaths) {
    $n = @(git -C $Root ls-files -- $p 2>$null).Count
    if ($n -gt $MaxFiles) { $Advisories += [pscustomobject]@{ path = $p; files = $n } }
  }
}

$exclU = Sort-OrdinalUnique @($ExcludedRecs | Where-Object { $_ })

# ── output ────────────────────────────────────────────────────────────────────
if ($Fmt -eq "json") {
  W ('{"blueprint_slice_schema":"1","command":"slice","root":"' + (JEsc $Root) + '","config":{"max_files":' + $MaxFiles + ',"min_files":' + $MinFiles + '},"scope":"' + (JEsc $Scope) + '","respect_existing":' + $(if (-not $All) { "true" } else { "false" }) + ',"subtracted_files":' + $Subtracted + ',"sections":[')
  $first = $true
  foreach ($s in $Part) {
    if (-not $first) { W ',' }; $first = $false
    W ('{"kind":"' + $s.kind + '","path":"' + (JEsc $s.path) + '","remainder":' + $(if ($s.rem -eq 1) { "true" } else { "false" }) + ',"rule":"' + $s.rule + '","files":' + $s.count + ',"markers":[')
    $mfirst = $true
    foreach ($m in $s.markers) { if (-not $mfirst) { W ',' }; $mfirst = $false; W ('"' + (JEsc $m) + '"') }
    W ']}'
  }
  W '],"root_files":['
  $first = $true
  foreach ($f in $RootFiles) { if (-not $first) { W ',' }; $first = $false; W ('"' + (JEsc $f) + '"') }
  W '],"excluded":['
  $first = $true
  foreach ($r in $exclU) {
    $pth, $pat = $r.Split("`u{1f}")
    if (-not $first) { W ',' }; $first = $false
    W ('{"path":"' + (JEsc $pth) + '","pattern":"' + (JEsc $pat) + '"}')
  }
  W '],"advisories":['
  $first = $true
  foreach ($a in $Advisories) {
    if (-not $first) { W ',' }; $first = $false
    W ('{"type":"oversize","path":"' + (JEsc $a.path) + '","files":' + $a.files + ',"max_files":' + $MaxFiles + '}')
  }
  WL ']}'
  Flush
  exit 0
}

# human
WL "blueprint-slice — deterministic partition (max_files=$MaxFiles, min_files=$MinFiles)"
if ($Scope) { WL "  scope: $Scope" }
if (-not $All -and $Subtracted -gt 0) { WL "  (subtracted $Subtracted file(s) already covered by existing markers)" }
WL ''
foreach ($s in $Part) {
  $label = $s.path
  if ($s.rem -eq 1) { $label = "$($s.path) (remainder, $($s.markers.Count) markers)" }
  WL ("  {0,-8} {1,-52} {2,6} files  [{3}]" -f $s.kind.ToUpper(), $label, $s.count, $s.rule)
}
if ($RootFiles.Count -gt 0) {
  WL ''
  WL "  root-level files (outside coverage by design): $($RootFiles.Count)"
}
if ($exclU.Count -gt 0) {
  WL "  excluded:"
  foreach ($r in $exclU) { $pth, $pat = $r.Split("`u{1f}"); WL ("    {0,-20} (pattern: {1})" -f $pth, $pat) }
}
foreach ($a in $Advisories) {
  WL "  advisory: existing section $($a.path) now spans $($a.files) files (> max_files=$MaxFiles) — consider splitting"
}
Flush
