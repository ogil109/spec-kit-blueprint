#!/usr/bin/env pwsh
# blueprint-slice — deterministic brownfield partitioner (PowerShell port).
# Mirrors scripts/bash/blueprint-slice.sh at OUTPUT PARITY: for the same repo
# state + config, slice --json, scaffold, and verify emit byte-identical text
# to the bash oracle (tests/ps_parity_test.sh diffs them in CI).
#
# Usage:
#   blueprint-slice.ps1 [slice] [--json|--human]
#     [--root <dir>] [--blueprint <path>] [--scope <dir>] [--all]
#   blueprint-slice.ps1 verify   [--json|--human] [--root <dir>] [--blueprint <path>]
#   blueprint-slice.ps1 scaffold [--root <dir>] [--blueprint <path>] [--scope <dir>]
#   blueprint-slice.ps1 render --facts <file> [--root <dir>] [--blueprint <path>]
[CmdletBinding()]
param(
  [Parameter(Position = 0)] [string]$Command = "slice",
  [Parameter(ValueFromRemainingArguments = $true)] [string[]]$Rest
)
$ErrorActionPreference = "Stop"

$Json = $false; $Human = $false; $Root = ""; $Blueprint = ""; $Scope = ""; $All = $false; $Facts = ""
for ($i = 0; $i -lt $Rest.Count; $i++) {
  switch ($Rest[$i]) {
    "--json"      { $Json = $true }
    "--human"     { $Human = $true }
    "--root"      { $i++; $Root = $Rest[$i] }
    "--blueprint" { $i++; $Blueprint = $Rest[$i] }
    "--scope"     { $i++; $Scope = $Rest[$i].TrimEnd('/') }
    "--facts"     { $i++; $Facts = $Rest[$i] }
    "--all"       { $All = $true }
  }
}
if ($Json) { $Fmt = "json" } elseif ($Human) { $Fmt = "human" }
elseif ([Environment]::UserInteractive -and -not [Console]::IsOutputRedirected) { $Fmt = "human" } else { $Fmt = "json" }
if (@("slice", "verify", "scaffold", "render") -notcontains $Command) {
  [Console]::Error.WriteLine("unknown command: $Command (only: slice, verify, scaffold, render)"); exit 2
}
$Out = [System.Text.StringBuilder]::new()
function W([string]$s)  { [void]$Out.Append($s) }
function WL([string]$s) { [void]$Out.Append($s + "`n") }
function Flush { [Console]::Out.Write($Out.ToString()) }
# LC_ALL=C parity: native-command output elements are not guaranteed to be
# System.String in PS 7.5+, and both Sort-Object and comparer fallbacks then
# go culture-aware. Force real strings + ordinal everywhere order is emitted.
function Sort-Ordinal([object[]]$a) {
  $s = [string[]]$a; [Array]::Sort($s, [System.StringComparer]::Ordinal); return $s
}
function Sort-OrdinalUnique([object[]]$a) {
  $set = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($x in $a) { [void]$set.Add([string]$x) }
  $s = [string[]]::new($set.Count); $set.CopyTo($s)
  [Array]::Sort($s, [System.StringComparer]::Ordinal); return $s
}

# ── locate repo root (same rule as the bash port) ─────────────────────────────
if (-not $Root) {
  $d = (Get-Location).Path
  while ($d -and (Split-Path $d -Parent)) {
    if (Test-Path (Join-Path $d ".specify")) { $Root = $d; break }
    $d = Split-Path $d -Parent
  }
  if (-not $Root) { $Root = (Get-Location).Path }
}
git -C $Root rev-parse --git-dir 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("not a git repository: $Root"); exit 1 }

$Cfg = Join-Path $Root ".specify/extensions/blueprint-index/blueprint-config.yml"

# ── locate the blueprint doc ──────────────────────────────────────────────────
if (-not $Blueprint -and (Test-Path $Cfg)) {
  $m = Select-String -Path $Cfg -Pattern '^\s*path:\s*"?([^"]*)"?\s*$' | Select-Object -First 1
  if ($m) {
    $p = $m.Matches[0].Groups[1].Value
    if ($p -and (Test-Path (Join-Path $Root $p))) { $Blueprint = Join-Path $Root $p }
  }
}
if (-not $Blueprint -or -not (Test-Path $Blueprint)) {
  foreach ($c in @(".specify/memory/blueprint.md", "docs/blueprint.md", "docs/overview.md")) {
    if (Test-Path (Join-Path $Root $c)) { $Blueprint = Join-Path $Root $c; break }
  }
}

# ── config (YAML subset: two levels, scalars + string lists) ──────────────────
function Cfg-Val([string]$top, [string]$key) {
  if (-not (Test-Path $Cfg)) { return "" }
  $inTop = $false
  foreach ($line in [System.IO.File]::ReadAllLines($Cfg)) {
    if ($line -match '^[^\s#]') { $inTop = ($line -match "^$top`:\s*$") ; continue }
    if ($inTop -and $line -match "^\s+$key`:\s*(.*)$") {
      $v = $Matches[1] -replace '\s+#.*$', '' -replace '"', ''
      return $v.Trim()
    }
  }
  return ""
}
function Cfg-List([string]$top, [string]$key) {
  $items = @()
  if (-not (Test-Path $Cfg)) { return $items }
  $inTop = $false; $inList = $false
  foreach ($line in [System.IO.File]::ReadAllLines($Cfg)) {
    if ($line -match '^[^\s#]') { $inTop = ($line -match "^$top`:\s*$"); $inList = $false; continue }
    if ($inTop -and $line -match "^\s+$key`:\s*$") { $inList = $true; continue }
    if ($inTop -and $inList) {
      if ($line -match '^\s+-\s+(.*)$') { $items += ($Matches[1] -replace '\s+#.*$', '' -replace '"', '').Trim() }
      elseif ($line -match '^\s*(#|$)') { } else { $inList = $false }
    }
  }
  return $items
}

$MaxFiles = Cfg-Val "slice" "max_files"; if (-not $MaxFiles) { $MaxFiles = 400 } else { $MaxFiles = [int]$MaxFiles }
$MinFiles = Cfg-Val "slice" "min_files"; if (-not $MinFiles) { $MinFiles = 3 } else { $MinFiles = [int]$MinFiles }
$Boundary = @(Cfg-List "slice" "boundary_files")
if ($Boundary.Count -eq 0) {
  $Boundary = @("pyproject.toml", "setup.py", "package.json", "Cargo.toml", "go.mod",
                "pom.xml", "build.gradle", "CMakeLists.txt", "composer.json", "Gemfile")
}
$ContextDirs = @(Cfg-List "slice" "context_dirs")
if ($ContextDirs.Count -eq 0) { $ContextDirs = @("docs", "doc", "documentation") }
$PinDirs = @()
foreach ($pd in @(Cfg-List "slice" "pin_dirs")) { if ($pd) { $PinDirs += ([string]$pd).TrimEnd('/') } }
$Excludes = @(Cfg-List "coverage" "exclude")
if ($Excludes.Count -eq 0) { $Excludes = @(".*", "specs") }

# ── render: deterministic prose + relations from a validated FACTS file ───────
# Mirrors the bash renderer at byte parity. See the bash header for the format.
if ($Command -eq "render") {
  if (-not $Facts -or -not (Test-Path $Facts)) { [Console]::Error.WriteLine("render: --facts <file> required"); exit 2 }
  if (-not ($Blueprint -and (Test-Path $Blueprint))) { [Console]::Error.WriteLine("render: no blueprint found (scaffold first)"); exit 1 }
  function Get-Sha($p) { $s = git -C $Root rev-parse --verify --quiet "HEAD:$p" 2>$null; if ($LASTEXITCODE -eq 0 -and $s) { return ([string]$s).Trim() } else { return "" } }

  # map structure: heading -> state, heading -> markers
  $headState = @{}; $headMarkers = @{}
  $hh = ""
  foreach ($line in [System.IO.File]::ReadAllLines($Blueprint)) {
    if ($line -match '^## ') { $hh = ($line -replace '^##\s+', '' -replace ' \(remainder\)$', ''); continue }
    if ($line -match '<!-- blueprint:section state=(\S+)') { $s = ($Matches[1] -replace '-->.*', ''); if ($hh) { $headState[$hh] = $s }; continue }
    if ($line -match '<!-- blueprint:(code|context) path=(\S+)') {
      if (-not $headMarkers.ContainsKey($hh)) { $headMarkers[$hh] = [System.Collections.Generic.List[string]]::new() }
      $headMarkers[$hh].Add($Matches[2]); continue
    }
  }
  function CoveredBy($ev, $h) {
    if (-not $headMarkers.ContainsKey($h)) { return $false }
    foreach ($m in $headMarkers[$h]) { if ($ev -eq $m -or $ev.StartsWith("$m/")) { return $true } }
    return $false
  }

  # parse facts + validate
  $errs = [System.Collections.Generic.List[string]]::new()
  $blocks = [System.Collections.Generic.List[pscustomobject]]::new()   # ordered
  $edges = [System.Collections.Generic.List[string]]::new()            # from US kind US to US why US ev
  $concernNames = [System.Collections.Generic.List[string]]::new()
  $sectionCount = 0
  $cur = $null
  function Flush-Cur { if ($script:cur) { if (-not $script:cur.role) { $script:errs.Add("'$($script:cur.name)': role is required") }; $script:blocks.Add($script:cur); $script:cur = $null } }
  $lineNo = 0
  foreach ($line in [System.IO.File]::ReadAllLines($Facts)) {
    $lineNo++
    if ($lineNo -eq 1) { if ($line -ne "blueprint-facts 1") { $errs.Add("facts line 1: first line must be: blueprint-facts 1") }; continue }
    if ($line -match '^\s*(#|$)') { continue }
    if ($line -match '^section (.*)$') {
      Flush-Cur
      $nm = $Matches[1]
      $st = if ($headState.ContainsKey($nm)) { $headState[$nm] } else { "" }
      if ($st -eq "code" -or $st -eq "context") { $sectionCount++ }
      elseif ($st -eq "") { $errs.Add("section '$nm' is not on the map (scaffold first; check the heading)"); $st = "code" }
      else { $errs.Add("section '$nm' is $st-owned — render only writes code/context sections") }
      $cur = [pscustomobject]@{ name = $nm; kind = "section"; state = $st; role = ""; facets = [System.Collections.Generic.List[string]]::new(); notes = [System.Collections.Generic.List[string]]::new() }
      continue
    }
    if ($line -match '^concern (.*)$') {
      Flush-Cur
      $nm = $Matches[1]
      if ($nm.Contains(" ")) { $errs.Add("concern '$nm' must be a space-free name") } else { $concernNames.Add($nm) }
      $cur = [pscustomobject]@{ name = $nm; kind = "concern"; state = "context"; role = ""; facets = [System.Collections.Generic.List[string]]::new(); notes = [System.Collections.Generic.List[string]]::new() }
      continue
    }
    if ($line -match '^role (.*)$') { if (-not $cur) { $errs.Add("role before any section/concern"); continue }; $cur.role = $Matches[1]; continue }
    if ($line -match '^note (.*)$') { if (-not $cur) { $errs.Add("note before any section/concern"); continue }; $cur.notes.Add($Matches[1]); continue }
    if ($line -match '^facet (.*)$') {
      if (-not $cur) { $errs.Add("facet before any section/concern"); continue }
      $parts = $Matches[1] -split ' \| '
      if ($parts.Count -ne 3) { $errs.Add("facts line ${lineNo}: facet needs: <Label> | <text> | <evidence>"); continue }
      $ev = $parts[2]
      if (-not (Get-Sha $ev)) { $errs.Add("'$($cur.name)' facet evidence not tracked in git: $ev") }
      if ($cur.kind -eq "section" -and -not (CoveredBy $ev $cur.name)) { $errs.Add("'$($cur.name)' facet evidence outside the section's own markers: $ev") }
      $cur.facets.Add("$($parts[0])`u{1f}$($parts[1])`u{1f}$ev")
      continue
    }
    if ($line -match '^neighbor (.*)$') {
      if (-not $cur) { $errs.Add("neighbor before any section/concern"); continue }
      $parts = $Matches[1] -split ' \| '
      if ($parts.Count -ne 4) { $errs.Add("facts line ${lineNo}: neighbor needs: <kind> | <to> | <why> | <evidence>"); continue }
      $kind = $parts[0]; $to = $parts[1]; $why = $parts[2]; $ev = $parts[3]
      if (@("uses", "crosscuts") -notcontains $kind) { $errs.Add("'$($cur.name)' neighbor kind must be uses|crosscuts: $kind"); continue }
      $tost = if ($headState.ContainsKey($to)) { $headState[$to] } else { "" }
      $tok = ($tost -ne "") -or ($concernNames -contains $to)
      if (-not $tok) { $errs.Add("'$($cur.name)' neighbor endpoint not on the map: $to") }
      if (-not (Get-Sha $ev)) { $errs.Add("'$($cur.name)' neighbor evidence not tracked in git: $ev") }
      if ($kind -eq "uses" -and $cur.kind -eq "section" -and -not (CoveredBy $ev $cur.name)) { $errs.Add("'$($cur.name)' uses-edge evidence must sit under '$($cur.name)' markers: $ev") }
      if ($kind -eq "crosscuts" -and $tost -ne "" -and -not (CoveredBy $ev $to)) { $errs.Add("'$($cur.name)' crosscuts-edge evidence must sit under '$to' markers: $ev") }
      $edges.Add("$($cur.name)`u{1f}$kind`u{1f}$to`u{1f}$why`u{1f}$ev")
      continue
    }
    $errs.Add("facts line ${lineNo}: unrecognized line: $line")
  }
  Flush-Cur

  if ($errs.Count -gt 0) {
    [Console]::Error.WriteLine("render: $($errs.Count) validation error(s) — nothing written:")
    foreach ($e in $errs) { [Console]::Error.WriteLine("  - $e") }
    exit 1
  }

  # relations: full-line ordinal sort, dedupe by from|kind|to keeping first
  $relLines = @()
  if ($edges.Count -gt 0) {
    $sorted = [string[]]$edges.ToArray(); [Array]::Sort($sorted, [System.StringComparer]::Ordinal)
    $seenKeys = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($e in $sorted) { $f = $e.Split("`u{1f}"); if ($seenKeys.Add("$($f[0])|$($f[1])|$($f[2])")) { $relLines += , $e } }
  }

  $byName = @{}
  foreach ($b in $blocks) { $byName[$b.name] = $b }
  function First-Sentence($r) { $i = $r.IndexOf(". "); if ($i -ge 0) { return $r.Substring(0, $i) } else { return ($r -replace '\.$', '') } }
  function Render-Body($h) {
    $b = $byName[$h]
    $o = "`n" + $b.role + $(if ($b.facets.Count -gt 0) { " At a glance:" } else { "" }) + "`n"
    if ($b.facets.Count -gt 0) {
      $o += "`n"
      foreach ($fc in $b.facets) { $pp = $fc.Split("`u{1f}"); $o += "- **" + $pp[0] + "** — " + $pp[1] + "`n" }
    }
    if ($b.notes.Count -gt 0) { $o += "`n"; foreach ($nt in $b.notes) { $o += $nt + "`n" } }
    if ($b.state -eq "code") { $o += "`nFor exact behavior, read the code under ``" + $h + "/``. Do not restate it here.`n" }
    return $o
  }
  $relHead = "Architecture — subsystem relations"
  $rtext = ""
  if ($relLines.Count -gt 0) {
    $rtext = "## $relHead`n<!-- blueprint:section state=context -->`n`n"
    $rtext += "Rendered from the recovery facts; every edge below is machine-validated by`n"
    $rtext += "the check gate (endpoints on the map, evidence tracked in git).`n`n"
    $rtext += "| from | kind | to | why |`n|---|---|---|---|`n"
    foreach ($e in $relLines) { $f = $e.Split("`u{1f}"); $rtext += "| $($f[0]) | $($f[1]) | $($f[2]) | $($f[3]) |`n" }
    $rtext += "`n"
    foreach ($e in $relLines) { $f = $e.Split("`u{1f}"); $rtext += "<!-- blueprint:relation from=$($f[0]) to=$($f[2]) kind=$($f[1]) evidence=$($f[4]) -->`n" }
  }

  $sb = [System.Text.StringBuilder]::new()
  $mode = "copy"; $curh = ""
  foreach ($line in [System.IO.File]::ReadAllLines($Blueprint)) {
    if ($line -match '^- `([^`]+)`') {
      $pth = $Matches[1]
      if ($byName.ContainsKey($pth) -and $byName[$pth].kind -eq "section") {
        $rem = if ($line -match ' \(remainder\)') { " (remainder)" } else { "" }
        $status = if ($byName[$pth].state -eq "context") { "**context**" } else { "**code-owned**" }
        [void]$sb.Append("- ``$pth``$rem — $(First-Sentence $byName[$pth].role); $status`n")
        continue
      }
    }
    if ($line -match '^## ') {
      $h = ($line -replace '^##\s+', '' -replace ' \(remainder\)$', '')
      if ($mode -eq "skiprel" -or $mode -eq "skipconcern") { $mode = "copy" }
      if ($h -eq $relHead -and $rtext -ne "") { [void]$sb.Append($rtext); $mode = "skiprel"; continue }
      if ($byName.ContainsKey($h) -and $byName[$h].kind -eq "concern") {
        [void]$sb.Append("## $h`n<!-- blueprint:section state=context -->`n" + (Render-Body $h) + "`n---`n`n"); $mode = "skipconcern"; continue
      }
      if ($byName.ContainsKey($h) -and $byName[$h].kind -eq "section") { [void]$sb.Append($line + "`n"); $mode = "header"; $curh = $h; continue }
      [void]$sb.Append($line + "`n"); $mode = "copy"; continue
    }
    if ($mode -eq "skiprel" -or $mode -eq "skipconcern") { continue }
    if ($mode -eq "header") {
      if ($line -match '^<!-- blueprint:' -or $line -match '^> ') { [void]$sb.Append($line + "`n"); continue }
      $mode = "prose"
    }
    if ($mode -eq "prose") {
      if ($line -eq "---") { [void]$sb.Append((Render-Body $curh)); [void]$sb.Append("---`n"); $mode = "copy" }
      continue
    }
    [void]$sb.Append($line + "`n")
  }
  if ($mode -eq "prose") { [void]$sb.Append((Render-Body $curh)) }
  # append concerns/relations that did not exist yet
  $orig = [System.IO.File]::ReadAllText($Blueprint)
  foreach ($c in $concernNames) {
    if ($orig -notmatch "(?m)^## $([regex]::Escape($c))( |$)") {
      [void]$sb.Append("## $c`n<!-- blueprint:section state=context -->`n" + (Render-Body $c) + "`n---`n`n")
    }
  }
  if ($rtext -ne "" -and $orig -notmatch "(?m)^## Architecture — subsystem relations$") { [void]$sb.Append($rtext) }
  [System.IO.File]::WriteAllText($Blueprint, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
  $rel = $Blueprint.Replace("$Root/", "").Replace("$Root\", "")
  WL "rendered $sectionCount section(s), $($concernNames.Count) concern(s), $($relLines.Count) relation(s) → $rel"
  WL "next: restamp, then verify + check"
  Flush
  exit 0
}

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

# ── the file stream: filter, then partition ───────────────────────────────────
$RootFiles = [System.Collections.Generic.List[string]]::new()
$ExcludedRecs = [System.Collections.Generic.List[string]]::new()   # "path`u{1f}pattern"
$Subtracted = 0
$Feed = [System.Collections.Generic.List[string]]::new()

$allFiles = Sort-Ordinal @(git -C $Root ls-files 2>$null | Where-Object { $_ })
foreach ($f in $allFiles) {
  if (-not $f) { continue }
  if ($f.Contains(" ")) { $ExcludedRecs.Add("$f`u{1f}unsupported-space"); continue }
  if (-not $f.Contains("/")) { $RootFiles.Add($f); continue }
  if ($f -eq $BpRel) { continue }
  $first = $f.Split("/")[0]
  $skip = $false
  foreach ($g in $Excludes) {
    if (-not $g) { continue }
    if ($g.Contains("/")) { if ($f -like $g -or $f -like "$g/*") { $ExcludedRecs.Add("$($g.Split('/')[0])`u{1f}$g"); $skip = $true; break } }
    else                  { if ($first -like $g)                 { $ExcludedRecs.Add("$first`u{1f}$g"); $skip = $true; break } }
  }
  if ($skip) { continue }
  foreach ($p in $covered) {
    if ($f -eq $p -or $f.StartsWith("$p/")) { $Subtracted++; $skip = $true; break }
  }
  if ($skip) { continue }
  if ($Scope) { if (-not $f.StartsWith("$Scope/")) { continue } }
  $Feed.Add($f)
}

# ── partition (ports the awk exactly; input sorted → emitted order sorted) ────
$cnt = @{}; $childdirs = @{}; $dfiles = @{}; $seen = @{}; $tops = [System.Collections.Generic.List[string]]::new()
$boundaryAt = @{}; $nested = @{}
$bset = @{}; foreach ($b in $Boundary) { if ($b) { $bset[$b] = $true } }
$cset = @{}; foreach ($c in $ContextDirs) { if ($c) { $cset[$c] = $true } }
$pset = @{}; $pnested = @{}
foreach ($pin in $PinDirs) {
  $pset[$pin] = $true
  $parts = $pin.Split("/"); $q = ""
  for ($j = 0; $j -lt $parts.Count - 1; $j++) { $q = if ($q) { "$q/$($parts[$j])" } else { $parts[$j] }; $pnested[$q] = $true }
}
$hnested = @{}
foreach ($hole in $covered) {
  $parts = $hole.Split("/"); $q = ""
  for ($j = 0; $j -lt $parts.Count - 1; $j++) { $q = if ($q) { "$q/$($parts[$j])" } else { $parts[$j] }; $hnested[$q] = $true }
}

foreach ($f in $Feed) {
  $parts = $f.Split("/"); $n = $parts.Count
  $path = ""
  for ($i = 0; $i -lt $n - 1; $i++) {
    $parent = $path
    $path = if ($path) { "$path/$($parts[$i])" } else { $parts[$i] }
    if (-not $seen.ContainsKey($path)) {
      $seen[$path] = $true
      if (-not $parent) { $tops.Add($path) }
      else {
        if (-not $childdirs.ContainsKey($parent)) { $childdirs[$parent] = [System.Collections.Generic.List[string]]::new() }
        $childdirs[$parent].Add($path)
      }
    }
    if ($cnt.ContainsKey($path)) { $cnt[$path]++ } else { $cnt[$path] = 1 }
  }
  $dir = if ($n -gt 1) { $f.Substring(0, $f.Length - $parts[$n - 1].Length - 1) } else { "" }
  if (-not $dfiles.ContainsKey($dir)) { $dfiles[$dir] = [System.Collections.Generic.List[string]]::new() }
  $dfiles[$dir].Add($f)
  if ($bset.ContainsKey($parts[$n - 1]) -and $dir) {
    $boundaryAt[$dir] = $true
    $q = ""
    for ($i = 0; $i -lt $n - 2; $i++) { $q = if ($q) { "$q/$($parts[$i])" } else { $parts[$i] }; $nested[$q] = $true }
  }
}

$Part = [System.Collections.Generic.List[pscustomobject]]::new()
function Emit([string]$kind, [string]$path, [int]$rem, [string]$rule, [int]$count, [string[]]$markers) {
  $script:Part.Add([pscustomobject]@{ kind = $kind; path = $path; rem = $rem; rule = $rule; count = $count; markers = $markers })
}
function Partition([string]$d) {
  $n = $cnt[$d]; $mod = $boundaryAt.ContainsKey($d)
  if ($pset.ContainsKey($d) -and -not $hnested.ContainsKey($d))            { Emit "code" $d 0 "pinned" $n @($d); return }
  if ($mod -and $n -le $MaxFiles -and -not $pnested.ContainsKey($d) -and -not $hnested.ContainsKey($d)) { Emit "code" $d 0 "module" $n @($d); return }
  if (-not $mod -and -not $nested.ContainsKey($d) -and -not $pnested.ContainsKey($d) -and -not $hnested.ContainsKey($d) -and $n -le $MaxFiles) { Emit "code" $d 0 "fits" $n @($d); return }
  $kids = if ($childdirs.ContainsKey($d)) { $childdirs[$d] } else { @() }
  if ($kids.Count -eq 0 -and $n -gt $MaxFiles -and -not $hnested.ContainsKey($d)) { Emit "code" $d 0 "flat" $n @($d); return }
  $remm = [System.Collections.Generic.List[string]]::new(); $remc = 0
  foreach ($c in $kids) {
    if ($pset.ContainsKey($c) -or $pnested.ContainsKey($c) -or $boundaryAt.ContainsKey($c) -or $nested.ContainsKey($c) -or $hnested.ContainsKey($c) -or $cnt[$c] -ge $MinFiles) { Partition $c }
    else { $remm.Add($c); $remc += $cnt[$c] }
  }
  if ($dfiles.ContainsKey($d)) { foreach ($df in $dfiles[$d]) { $remm.Add($df); $remc++ } }
  if ($remm.Count -gt 0) { Emit "code" $d 1 "remainder" $remc $remm.ToArray() }
}
if ($Scope) {
  if ($seen.ContainsKey($Scope)) { Partition $Scope }
} else {
  foreach ($t in $tops) {
    if ($cset.ContainsKey($t)) { Emit "context" $t 0 "context-dir" $cnt[$t] @($t) }
    else { Partition $t }
  }
}

function JEsc([string]$s) { return $s.Replace('\', '\\').Replace('"', '\"') }

# ── verify: diff the computed structure against the map's actual structure ────
if ($Command -eq "verify") {
  $expected = [System.Collections.Generic.List[string]]::new()
  foreach ($s in $Part) { foreach ($m in $s.markers) { $expected.Add("$($s.path)`u{1f}$($s.kind)`u{1f}$m") } }
  $exp = Sort-Ordinal $expected.ToArray()
  $act = Sort-OrdinalUnique @($DocPairs | Where-Object { $_.state -eq "code" -or $_.state -eq "context" } |
    ForEach-Object { "$($_.heading)`u{1f}$($_.kind)`u{1f}$($_.path)" })
  $expSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$exp)
  $actSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$act)
  $missing = @($exp | Where-Object { -not $actSet.Contains($_) })
  $unexpected = @($act | Where-Object { -not $expSet.Contains($_) })
  $ok = ($missing.Count -eq 0 -and $unexpected.Count -eq 0)
  $rel = $BpRel
  if ($Fmt -eq "json") {
    W ('{"blueprint_slice_schema":"1","command":"verify","blueprint":"' + (JEsc $rel) + '","structure_ok":' + $(if ($ok) { "true" } else { "false" }) + ',"missing":[')
    $first = $true
    foreach ($r in $missing) {
      $sec, $kind, $m = $r.Split("`u{1f}")
      if (-not $first) { W ',' }; $first = $false
      W ('{"section":"' + (JEsc $sec) + '","kind":"' + $kind + '","marker":"' + (JEsc $m) + '"}')
    }
    W '],"unexpected":['
    $first = $true
    foreach ($r in $unexpected) {
      $sec, $kind, $m = $r.Split("`u{1f}")
      if (-not $first) { W ',' }; $first = $false
      W ('{"section":"' + (JEsc $sec) + '","kind":"' + $kind + '","marker":"' + (JEsc $m) + '"}')
    }
    WL ']}'
  } else {
    WL "blueprint-slice verify — map structure vs computed partition"
    if ($ok) {
      WL "  structure conforms ✓ ($($exp.Count) marker(s) exactly as computed)"
    } else {
      if ($missing.Count -gt 0) {
        WL "  MISSING — computed by the partition, absent from the map:"
        foreach ($r in $missing) { $sec, $kind, $m = $r.Split("`u{1f}"); WL ("    {0,-8} {1,-40} marker: {2}" -f $kind, $sec, $m) }
      }
      if ($unexpected.Count -gt 0) {
        WL "  UNEXPECTED — in the map, not computed (freehand / merged / renamed):"
        foreach ($r in $unexpected) { $sec, $kind, $m = $r.Split("`u{1f}"); WL ("    {0,-8} {1,-40} marker: {2}" -f $kind, $sec, $m) }
      }
      WL "  fix: restore the computed structure, or change blueprint-config.yml and re-run the slicer"
    }
  }
  Flush
  if ($ok) { exit 0 } else { exit 1 }
}

# ── scaffold: emit the map (or the missing blocks) — structure by machine ─────
if ($Command -eq "scaffold") {
  function Emit-Section([pscustomobject]$s) {
    WL ("## {0}{1}" -f $s.path, $(if ($s.rem -eq 1) { ' (remainder)' } else { '' }))
    if ($s.kind -eq "code") {
      WL '<!-- blueprint:section state=code -->'
      WL ('> **Distilled — owned by code at `{0}/`.** (no spec yet) The implementation' -f $s.path)
      WL '> is the source of truth; this section maps it. To change it, `/speckit.specify`'
      WL '> the area as usual and `distill` it when the spec ships.'
      foreach ($m in $s.markers) { WL ('<!-- blueprint:code path={0} sha=NONE -->' -f $m) }
    } else {
      WL '<!-- blueprint:section state=context -->'
      WL '> Framing / documentation tree — on the map, not a buildable slice.'
      foreach ($m in $s.markers) { WL ('<!-- blueprint:context path={0} -->' -f $m) }
    }
    WL ''
    WL ('TODO(prose): pending render — emit a facts entry for `{0}` (see the' -f $s.path)
    WL 'recover command) and run blueprint-slice render; do not edit by hand.'
    WL ''
    WL '---'
    WL ''
  }
  $hasMap = ($BpRel -and (Test-Path $Blueprint) -and ((Get-Item $Blueprint).Length -gt 0))
  if (-not $hasMap) {
    $proj = ""
    $origin = git -C $Root remote get-url origin 2>$null
    if ($LASTEXITCODE -eq 0 -and $origin) {
      $proj = ($origin.TrimEnd('/') -replace '\.git$', '') -replace '.*[/:]', ''
    }
    if (-not $proj) { $proj = Split-Path $Root -Leaf }
    WL ("# {0} Blueprint" -f $proj)
    WL ''
    WL '**Status**: Living document — the authoritative backlog + architecture map for this project.'
    WL ''
    WL '<!--'
    WL '  HOW THIS DOCUMENT WORKS'
    WL '  ======================='
    WL '  Decreasing-detail map. Sections are DETAILED (backlog: design pending), SETTLED'
    WL '  (digest + pointer; owner is a feature spec specs/<slug> or the CODE itself —'
    WL '  brownfield), or CONTEXT (framing; never backlog). Ground truth is the filesystem;'
    WL '  the machine-readable provenance markers under each heading are what the oracle'
    WL '  reads — banners and prose are cosmetic. To change a code-owned slice:'
    WL '  /speckit.specify it as usual; distill collapses its section when the spec ships.'
    WL '  STRUCTURE IS COMPUTED (blueprint-slice.sh scaffold), never improvised: to change'
    WL '  the cut, edit blueprint-config.yml and re-derive; blueprint-slice.sh verify'
    WL '  machine-checks conformance.'
    WL '-->'
    WL ''
    WL '## Table of Contents'
    WL ''
    foreach ($s in $Part) {
      $status = if ($s.kind -eq "context") { "**context**" } else { "**code-owned**" }
      WL ('- `{0}`{1} — TODO(prose): one line; {2}' -f $s.path, $(if ($s.rem -eq 1) { ' (remainder)' } else { '' }), $status)
    }
    WL ''
    WL '---'
    WL ''
  }
  $emitted = 0
  foreach ($s in $Part) { Emit-Section $s; $emitted++ }
  if ($emitted -eq 0) { [Console]::Error.WriteLine("note: nothing to scaffold — every tracked path is already covered") }
  Flush
  exit 0
}

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
