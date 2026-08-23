#!/usr/bin/env pwsh
# lib/Slice-Partition.ps1 — the deterministic partitioner: filter + partition
# (mirrors bash lib/slice-partition.sh). Sets: $Part, $RootFiles, …
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

