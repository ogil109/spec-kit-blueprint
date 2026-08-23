#!/usr/bin/env pwsh
# lib/State-Frontier.ps1 — the waterfall frontier: per-spec phase, section
# provenance (mirrors bash lib/state-frontier.sh gather half).
function Get-SpecPhase($dir) {
  if (-not (Test-Path (Join-Path $dir "spec.md"))) { return "specify" }
  if (Select-String -Path (Join-Path $dir "spec.md") -Pattern '\[NEEDS CLARIFICATION' -Quiet) { return "clarify" }
  if (-not (Test-Path (Join-Path $dir "plan.md")))  { return "plan" }
  if (-not (Test-Path (Join-Path $dir "tasks.md"))) { return "tasks" }
  if (Select-String -Path (Join-Path $dir "tasks.md") -Pattern '^\s*-\s*\[ \]' -Quiet) { return "implement" }
  return "built"
}
function Test-Distilled($slug) {
  if (-not ($Blueprint -and (Test-Path $Blueprint))) { return $false }
  return [bool](Select-String -Path $Blueprint -Pattern "specs/$slug" -Quiet)
}

$inflight = @(); $drift = @(); $builtCount = 0
if (Test-Path $specsDir) {
  foreach ($dir in (Get-ChildItem -Path $specsDir -Directory)) {
    $slug = $dir.Name
    if ($Skip -contains $slug) { continue }   # parked/excluded slice
    $phase = Get-SpecPhase $dir.FullName
    if ($phase -ne "built") { $inflight += [pscustomobject]@{ slug = $slug; phase = $phase } }
    else {
      $builtCount++
      # Distill drift = a BUILT slice not yet collapsed → distill is the slice's LAST
      # step (after implement), not the moment spec.md appears. In-flight = advance.
      if (-not (Test-Distilled $slug)) { $drift += $slug }
    }
  }
}

# section provenance: machine markers are authoritative; an unmarked ## heading is
# UNMANAGED (external / not yet run through init) and counts as pending backlog.
$detailedCount = 0; $settledCount = 0; $contextCount = 0; $unmanagedCount = 0
if ($Blueprint -and (Test-Path $Blueprint)) {
  $detailedCount = @(Select-String -Path $Blueprint -Pattern '<!-- blueprint:section state=detailed').Count
  $settledCount  = @(Select-String -Path $Blueprint -Pattern '<!-- blueprint:section state=(distilled|code)').Count
  $contextCount  = @(Select-String -Path $Blueprint -Pattern '<!-- blueprint:section state=context').Count
  $s=$false; $m=$false; $x=$false
  foreach ($line in [System.IO.File]::ReadAllLines($Blueprint)) {
    if ($line -match '^## ') {
      if ($s -and -not $m -and -not $x) { $unmanagedCount++ }
      $h = $line.ToLower(); $x = ($h -match 'table of contents' -or $h -match 'how this' -or $h -match 'changelog')
      $s = $true; $m = $false
    } elseif ($line -match '<!-- blueprint:section') { $m = $true }
  }
  if ($s -and -not $m -and -not $x) { $unmanagedCount++ }
}
$backlogCount = $detailedCount + $unmanagedCount

