#!/usr/bin/env pwsh
# lib/Slice-Render.ps1 — `render`: facts -> validated prose + merged relations
# (mirrors bash lib/slice-render.sh). No-op unless the command is render;
# exits when it runs.
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
  # evidence may be <path> or <path>#<pattern> (fixed string that must be
  # present in the file at HEAD — makes the claim falsifiable; bash parity)
  function Validate-Ev($who, $ev, $juris) {
    $evPath = $ev.Split("#")[0]
    $evPat = if ($ev.Contains("#")) { $ev.Substring($ev.IndexOf("#") + 1) } else { "" }
    if (-not (Get-Sha $evPath)) { $script:errs.Add("$who evidence not tracked in git: $evPath"); return }
    if ($juris -and -not (CoveredBy $evPath $juris)) { $script:errs.Add("$who evidence outside '$juris' markers: $evPath") }
    if ($evPat -ne "") {
      $content = git -C $Root show "HEAD:$evPath" 2>$null
      $hit = $false
      foreach ($cl in @($content)) { if (([string]$cl).Contains($evPat)) { $hit = $true; break } }
      if (-not $hit) { $script:errs.Add("$who evidence pattern not found in ${evPath}: '$evPat'") }
    }
  }

  # parse facts + validate
  $errs = [System.Collections.Generic.List[string]]::new()
  $blocks = [System.Collections.Generic.List[pscustomobject]]::new()   # ordered
  $edges = [System.Collections.Generic.List[string]]::new()            # from US kind US to US why US ev
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
      if (($blocks | Where-Object { $_.name -eq $nm }).Count -gt 0) { $errs.Add("duplicate block for '$nm' — a facts file declares each section once") }
      $st = if ($headState.ContainsKey($nm)) { $headState[$nm] } else { "" }
      if ($st -eq "code" -or $st -eq "context") { $sectionCount++ }
      elseif ($st -eq "") { $errs.Add("section '$nm' is not on the map (scaffold first; check the heading)"); $st = "code" }
      else { $errs.Add("section '$nm' is $st-owned — render only writes code/context sections") }
      $cur = [pscustomobject]@{ name = $nm; state = $st; role = ""; facets = [System.Collections.Generic.List[string]]::new(); notes = [System.Collections.Generic.List[string]]::new() }
      continue
    }
    if ($line -match '^concern ') {
      $errs.Add("facts line ${lineNo}: the concern directive was removed — model cross-cutting facilities as sections with crosscuts edges")
      continue
    }
    if ($line -match '^role (.*)$') { if (-not $cur) { $errs.Add("role before any section"); continue }; $cur.role = $Matches[1]; continue }
    if ($line -match '^note (.*)$') { if (-not $cur) { $errs.Add("note before any section"); continue }; $cur.notes.Add($Matches[1]); continue }
    if ($line -match '^facet (.*)$') {
      if (-not $cur) { $errs.Add("facet before any section"); continue }
      $parts = $Matches[1] -split ' \| '
      if ($parts.Count -ne 3) { $errs.Add("facts line ${lineNo}: facet needs: <Label> | <text> | <evidence>"); continue }
      $ev = $parts[2]
      Validate-Ev "'$($cur.name)' facet" $ev $cur.name
      $cur.facets.Add("$($parts[0])`u{1f}$($parts[1])`u{1f}$ev")
      continue
    }
    if ($line -match '^neighbor (.*)$') {
      if (-not $cur) { $errs.Add("neighbor before any section"); continue }
      $parts = $Matches[1] -split ' \| '
      if ($parts.Count -ne 4) { $errs.Add("facts line ${lineNo}: neighbor needs: <kind> | <to> | <why> | <evidence>"); continue }
      $kind = $parts[0]; $to = $parts[1]; $why = $parts[2]; $ev = $parts[3]
      if (@("uses", "crosscuts") -notcontains $kind) { $errs.Add("'$($cur.name)' neighbor kind must be uses|crosscuts: $kind"); continue }
      $tost = if ($headState.ContainsKey($to)) { $headState[$to] } else { "" }
      if ($tost -eq "") { $errs.Add("'$($cur.name)' neighbor endpoint not on the map: $to") }
      $juris = $cur.name
      if ($kind -eq "crosscuts") { $juris = if ($tost -ne "") { $to } else { "" } }
      Validate-Ev "'$($cur.name)' $kind-edge" $ev $juris
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

  # Edge repair is per-block and INTERNAL (bash parity): a facts block owns its
  # section's outgoing edges; edges from unnamed sections are preserved by
  # round-tripping the machine-written relations home; preserved edges with
  # endpoints gone from the map are dropped.
  $owned = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($b in $blocks) { [void]$owned.Add($b.name) }
  $dropped = 0
  $inRel = $false; $whyMap = @{}
  $exEdges = [System.Collections.Generic.List[string]]::new()
  foreach ($line in [System.IO.File]::ReadAllLines($Blueprint)) {
    if ($line -match '^## ') { $inRel = ($line -eq "## Architecture — subsystem relations"); continue }
    if ($inRel -and $line -match '^\| ' -and $line -notmatch '^\| from \|' -and $line -notmatch '^\|---') {
      $row = $line -replace '^\| ', '' -replace ' \|$', ''
      $f = $row -split ' \| '
      if ($f.Count -eq 4) { $whyMap["$($f[0])`u{1f}$($f[1])`u{1f}$($f[2])"] = $f[3] }
      continue
    }
    if ($inRel -and $line -match '<!-- blueprint:relation from=(\S+) to=(\S+) kind=(\S+) evidence=(\S+) -->') {
      $k = "$($Matches[1])`u{1f}$($Matches[3])`u{1f}$($Matches[2])"
      $w = if ($whyMap.ContainsKey($k)) { $whyMap[$k] } else { "" }
      $exEdges.Add("$($Matches[1])`u{1f}$($Matches[3])`u{1f}$($Matches[2])`u{1f}$w`u{1f}$($Matches[4])")
    }
  }
  foreach ($ex in $exEdges) {
    $f = $ex.Split("`u{1f}")
    if ($owned.Contains($f[0])) { continue }
    $fromOk = $headState.ContainsKey($f[0])
    $toOk = $headState.ContainsKey($f[2])
    if (-not ($fromOk -and $toOk)) { $dropped++; continue }
    $edges.Add($ex)
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
  $inToc = $false; $tocSeen = $false; $tocFlushed = $false
  $tocPresent = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($line in [System.IO.File]::ReadAllLines($Blueprint)) {
    if ($line -match '^- `([^`]+)`') {
      $pth = $Matches[1]
      $tocSeen = $true; [void]$tocPresent.Add($pth)
      if ($byName.ContainsKey($pth)) {
        $rem = if ($line -match ' \(remainder\)') { " (remainder)" } else { "" }
        $status = if ($byName[$pth].state -eq "context") { "**context**" } else { "**code-owned**" }
        [void]$sb.Append("- ``$pth``$rem — $(First-Sentence $byName[$pth].role); $status`n")
        continue
      }
    }
    if ($inToc -and $tocSeen -and -not $tocFlushed -and $line -match '^\s*$') {
      foreach ($b in $blocks) {
        if (-not $tocPresent.Contains($b.name)) {
          $status = if ($b.state -eq "context") { "**context**" } else { "**code-owned**" }
          [void]$sb.Append("- ``$($b.name)`` — $(First-Sentence $b.role); $status`n")
        }
      }
      $tocFlushed = $true
    }
    if ($line -match '^## ') {
      $h = ($line -replace '^##\s+', '' -replace ' \(remainder\)$', '')
      $inToc = ($line -eq "## Table of Contents")
      if ($mode -eq "skiprel") { $mode = "copy" }
      if ($h -eq $relHead -and $rtext -ne "") { [void]$sb.Append($rtext); $mode = "skiprel"; continue }
      if ($byName.ContainsKey($h)) { [void]$sb.Append($line + "`n"); $mode = "header"; $curh = $h; continue }
      [void]$sb.Append($line + "`n"); $mode = "copy"; continue
    }
    if ($mode -eq "skiprel") { continue }
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
  # append the relations section when it did not exist yet
  $orig = [System.IO.File]::ReadAllText($Blueprint)
  if ($rtext -ne "" -and $orig -notmatch "(?m)^## Architecture — subsystem relations$") { [void]$sb.Append($rtext) }
  [System.IO.File]::WriteAllText($Blueprint, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
  $rel = $Blueprint.Replace("$Root/", "").Replace("$Root\", "")
  $dropnote = if ($dropped -gt 0) { " (dropped $dropped dangling edge(s))" } else { "" }
  WL "rendered $sectionCount section(s), $($relLines.Count) relation(s)$dropnote → $rel"
  WL "next: restamp, then verify + check"
  Flush
  exit 0
}

