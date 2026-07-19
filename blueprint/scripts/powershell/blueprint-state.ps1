#!/usr/bin/env pwsh
# blueprint-state — deterministic state oracle + coherence gate for the blueprint (PowerShell port).
# Mirrors scripts/bash/blueprint-state.sh.
#
# Usage:
#   blueprint-state.ps1 status
#   blueprint-state.ps1 next [--json]
#   [--root <dir>] [--blueprint <path>]
[CmdletBinding()]
param(
  [Parameter(Position = 0)] [string]$Command = "status",
  [Parameter(ValueFromRemainingArguments = $true)] [string[]]$Rest
)
$ErrorActionPreference = "Stop"

$Json = $false; $Root = ""; $Blueprint = ""; $Skip = @(); $PathFilter = ""; $Strict = $false; $Human = $false
for ($i = 0; $i -lt $Rest.Count; $i++) {
  switch ($Rest[$i]) {
    "--json"      { $Json = $true }
    "--root"      { $i++; $Root = $Rest[$i] }
    "--blueprint" { $i++; $Blueprint = $Rest[$i] }
    "--skip"      { $i++; $Skip += $Rest[$i] }   # exclude a slug (e.g. a parked slice); repeatable
    "--path"      { $i++; $PathFilter = $Rest[$i] }  # restamp: limit to one code path
    "--strict"    { $Strict = $true }            # check: make advisory (soft) issues blocking too
    "--human"     { $Human = $true }             # force human-readable output
  }
}
# Output format: explicit flag wins; else JSON when piped, human on a TTY (git/ls convention).
if ($Json) { $Fmt = "json" } elseif ($Human) { $Fmt = "human" }
elseif ([Environment]::UserInteractive -and -not [Console]::IsOutputRedirected) { $Fmt = "human" } else { $Fmt = "json" }

# locate repo root
if (-not $Root) {
  $d = (Get-Location).Path
  while ($d -and (Split-Path $d -Parent)) {
    if (Test-Path (Join-Path $d ".specify")) { $Root = $d; break }
    $d = Split-Path $d -Parent
  }
  if (-not $Root) { $Root = (Get-Location).Path }
}

# locate blueprint
if (-not $Blueprint) {
  $cfg = Join-Path $Root ".specify/extensions/blueprint/blueprint-config.yml"
  if (Test-Path $cfg) {
    $m = Select-String -Path $cfg -Pattern '^\s*path:\s*"?([^"]*)"?\s*$' | Select-Object -First 1
    if ($m) { $Blueprint = Join-Path $Root $m.Matches[0].Groups[1].Value }
  }
}
if (-not $Blueprint -or -not (Test-Path $Blueprint)) {
  foreach ($c in @("docs/blueprint.md", "docs/overview.md", ".specify/memory/blueprint.md")) {
    if (Test-Path (Join-Path $Root $c)) { $Blueprint = Join-Path $Root $c; break }
  }
}

$specsDir = Join-Path $Root "specs"

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

# code-staleness support (mirrors the bash oracle): a code-owned section carries
#   <!-- blueprint:code path=src/area sha=<git-sha> -->  recording the code baseline.
function Test-Git    { git -C $Root rev-parse --git-dir 2>$null | Out-Null; return $LASTEXITCODE -eq 0 }
function Get-CurSha($p) { $s = git -C $Root rev-parse --verify --quiet "HEAD:$p" 2>$null; if ($LASTEXITCODE -eq 0) { return $s.Trim() } else { return "" } }
function Get-CodeMarkers {
  if (-not ($Blueprint -and (Test-Path $Blueprint))) { return @() }
  Select-String -Path $Blueprint -Pattern '<!-- blueprint:code path=(\S+) sha=(\S+) -->' -AllMatches |
    ForEach-Object { $_.Matches } | ForEach-Object { [pscustomobject]@{ path = $_.Groups[1].Value; sha = $_.Groups[2].Value } }
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

if ($Command -eq "check") {
  # Tiered: HARD (drift, dangling) blocks; SOFT (stale, unstamped, unmanaged) is advisory
  # unless --strict. Each issue carries a self-describing remedy + kind (see bash oracle).
  $issues = @()
  if ($unmanagedCount -gt 0) { $issues += [pscustomobject]@{ severity="soft"; type="unmanaged"; target=""; detail="$unmanagedCount section(s) not processed by the extension"; run="/speckit.blueprint.init"; kind="authored" } }
  foreach ($s in $drift) { $issues += [pscustomobject]@{ severity="hard"; type="drift"; target=$s; detail="built spec not in the map"; run="/speckit.blueprint.distill $s"; kind="authored" } }
  if (Test-Git) {
    foreach ($m in (Get-CodeMarkers)) {
      $cur = Get-CurSha $m.path
      if (-not $cur)             { $issues += [pscustomobject]@{ severity="hard"; type="dangling"; target=$m.path; detail="map points at code that no longer exists"; run="/speckit.blueprint.remap $($m.path)"; kind="authored" } }
      elseif ($m.sha -eq "NONE") { $issues += [pscustomobject]@{ severity="soft"; type="unstamped"; target=$m.path; detail="no git baseline recorded yet"; run="blueprint-state.ps1 restamp --path $($m.path)"; kind="deterministic" } }
      elseif ($cur -ne $m.sha)   { $issues += [pscustomobject]@{ severity="soft"; type="stale"; target=$m.path; detail="code changed since mapped ($($m.sha) -> $cur)"; run="/speckit.blueprint.remap $($m.path)"; kind="authored" } }
    }
  } else { [Console]::Error.WriteLine("note: not a git repository — code-staleness checks skipped") }

  $hardN = @($issues | Where-Object { $_.severity -eq "hard" }).Count
  $softN = @($issues | Where-Object { $_.severity -eq "soft" }).Count
  $inSync = ($issues.Count -eq 0)
  $rc = 0; if ($hardN -gt 0 -or ($Strict -and $softN -gt 0)) { $rc = 1 }
  $rel = if ($Blueprint) { $Blueprint.Replace("$Root/","").Replace("$Root\","") } else { "" }

  if ($Fmt -eq "json") {
    $obj = [ordered]@{ blueprint_schema="1"; command="check"; blueprint=$rel; in_sync=$inSync; blocking=$hardN; advisory=$softN; strict=$Strict;
      issues=@($issues | ForEach-Object { [ordered]@{ severity=$_.severity; type=$_.type; target=$_.target; detail=$_.detail; remedy=[ordered]@{ run=$_.run; kind=$_.kind } } }) }
    Write-Output ($obj | ConvertTo-Json -Depth 6 -Compress)
    exit $rc
  }
  if ($inSync) { Write-Output "blueprint in sync"; exit 0 }
  if ($hardN -gt 0) { Write-Output "HARD - the map contradicts reality (blocks merge):"; $issues | Where-Object { $_.severity -eq "hard" } | ForEach-Object { Write-Output ("  {0} {1} {2}   -> {3}" -f $_.type.ToUpper(), $_.target, $_.detail, $_.run) } }
  if ($softN -gt 0) { if ($hardN -gt 0) { Write-Output "" }; Write-Output "SOFT - the map may be behind (advisory):"; $issues | Where-Object { $_.severity -eq "soft" } | ForEach-Object { Write-Output ("  {0} {1} {2}   -> {3}" -f $_.type.ToUpper(), $_.target, $_.detail, $_.run) } }
  Write-Output ""; Write-Output "$hardN blocking, $softN advisory"
  exit $rc
}

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

$nextPhase = "done"; $nextSlug = ""; $reason = "backlog empty — nothing in specs/, nothing in flight"
if ($drift.Count -gt 0) {
  $nextPhase = "distill"; $nextSlug = $drift[0]; $reason = "spec exists but blueprint still holds its detail"
} elseif ($inflight.Count -gt 0) {
  $nextPhase = $inflight[0].phase; $nextSlug = $inflight[0].slug; $reason = "in-flight slice; next build phase by artifact frontier"
} elseif (($Blueprint -and (Test-Path $Blueprint)) -and $detailedCount -eq 0 -and $settledCount -eq 0 -and $unmanagedCount -gt 0) {
  $nextPhase = "init"; $reason = "blueprint not yet processed by the extension — run /speckit.blueprint.init ($unmanagedCount unmanaged section(s))"
} elseif (($Blueprint -and (Test-Path $Blueprint)) -and $backlogCount -gt 0) {
  $nextPhase = "specify"; $reason = "no in-flight work; specify the next detailed subsystem from the blueprint"
} elseif (($Blueprint -and (Test-Path $Blueprint)) -and $settledCount -gt 0) {
  $reason = "all sections settled (owned by a spec or by code) — no pending design (run /speckit.specify to start a slice, then distill it)"
} elseif ($Blueprint -and (Test-Path $Blueprint)) {
  $nextPhase = "specify"; $reason = "blueprint has no subsystem sections yet — add some, or run /speckit.blueprint.init"
}
$hasNext = ($nextPhase -ne "done")

if ($Command -eq "next") {
  if ($Json) {
    $rel = if ($Blueprint) { $Blueprint.Replace("$Root/", "").Replace("$Root\", "") } else { "" }
    '{{"has_next": {0}, "phase": "{1}", "slug": "{2}", "reason": "{3}", "blueprint": "{4}"}}' -f `
      $hasNext.ToString().ToLower(), $nextPhase, $nextSlug, $reason, $rel
  } else {
    "next: $nextPhase $(if($nextSlug){"($nextSlug)"}) — $reason"
  }
  exit 0
}

Write-Output "Blueprint waterfall — state"
Write-Output "  root:      $Root"
Write-Output "  blueprint: $(if($Blueprint){$Blueprint}else{'<none — run blueprint.init>'}) ($builtCount built, $($inflight.Count) in-flight)"
if ($Blueprint -and (Test-Path $Blueprint)) { Write-Output "  sections:  $detailedCount detailed, $settledCount settled, $contextCount context, $unmanagedCount unmanaged (not yet processed by init)" }
Write-Output ""
Write-Output "In-flight (spec exists, build not complete):"
if ($inflight.Count -eq 0) { Write-Output "  (none)" } else { $inflight | ForEach-Object { Write-Output "  - $($_.slug)  → next: $($_.phase)" } }
Write-Output ""
Write-Output "Distill drift (spec exists, blueprint not yet collapsed):"
if ($drift.Count -eq 0) { Write-Output "  (none — blueprint in sync)" } else { $drift | ForEach-Object { Write-Output "  - $_  → /speckit.blueprint.distill $_" } }
Write-Output ""
Write-Output "Next action: $nextPhase $(if($nextSlug){"($nextSlug)"})"
Write-Output "  ($reason)"
