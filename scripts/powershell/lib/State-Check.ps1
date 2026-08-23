#!/usr/bin/env pwsh
# lib/State-Check.ps1 — the tiered coherence gate (mirrors bash
# lib/state-check.sh). No-op unless the command is check; exits when it runs.
if ($Command -eq "check") {
  # Tiered: HARD (drift, dangling) blocks; SOFT (stale, unstamped, unmanaged) is advisory
  # unless --strict. Each issue carries a self-describing remedy + kind (see bash oracle).
  $issues = @()
  if ($unmanagedCount -gt 0) { $issues += [pscustomobject]@{ severity="soft"; type="unmanaged"; target=""; detail="$unmanagedCount section(s) not processed by the extension"; run="/speckit.blueprint-index.init"; kind="authored" } }
  foreach ($s in $drift) { $issues += [pscustomobject]@{ severity="hard"; type="drift"; target=$s; detail="built spec not in the map"; run="/speckit.blueprint-index.distill $s"; kind="authored" } }
  if (Test-Git) {
    foreach ($m in (Get-CodeMarkers)) {
      $cur = Get-CurSha $m.path
      if (-not $cur)             { $issues += [pscustomobject]@{ severity="hard"; type="dangling"; target=$m.path; detail="map points at code that no longer exists"; run="/speckit.blueprint-index.remap $($m.path)"; kind="authored" } }
      elseif ($m.sha -eq "NONE") { $issues += [pscustomobject]@{ severity="soft"; type="unstamped"; target=$m.path; detail="no git baseline recorded yet"; run="blueprint-state.ps1 restamp --path $($m.path)"; kind="deterministic" } }
      # abbreviate like git: a full 40-char pair is unreadable in a CI log line
      elseif ($cur -ne $m.sha)   { $short = { param($h) if ($h.Length -gt 8) { $h.Substring(0,8) } else { $h } }; $issues += [pscustomobject]@{ severity="soft"; type="stale"; target=$m.path; detail="code changed since mapped ($(& $short $m.sha) -> $(& $short $cur))"; run="/speckit.blueprint-index.remap $($m.path)"; kind="authored" } }
    }
    # unmapped code (coverage): every tracked file must be covered by a code
    # section, a context section, or an exclude pattern. The scan spans ALL
    # top-level directories — deriving scan roots from already-mapped paths (as
    # before) let a directory the on-ramp never touched stay invisible forever.
    # Root-level loose files are outside coverage by design; the blueprint doc
    # itself is always excluded. Reported at the shallowest uncovered directory.
    # Only runs when a blueprint exists — with no map at all, the actionable
    # signal is "run init", not one unmapped issue per directory.
    if ($Blueprint -and (Test-Path $Blueprint)) {
    $coveredPaths = @(Get-CodeMarkers | ForEach-Object { $_.path }) + @(Get-ContextMarkers)
    $excludes = @(Get-CoverageExcludes)
    $bpRel = if ($Blueprint) { $Blueprint.Replace("$Root/","").Replace("$Root\","") } else { "" }
    $uncovered = @()
    foreach ($f in (git -C $Root ls-files 2>$null)) {
      if ($f -notmatch '/') { continue }                                                    # root-level loose file
      if ($f -eq $bpRel) { continue }                                                       # the map itself
      $first = ($f -split '/')[0]
      $skip = $false
      foreach ($g in $excludes) {
        if ($g -match '/') { if ($f -like $g -or $f -like "$g/*") { $skip = $true; break } }
        else               { if ($first -like $g)                 { $skip = $true; break } }
      }
      if ($skip) { continue }
      if ($coveredPaths | Where-Object { $f -eq $_ -or $f.StartsWith("$_/") }) { continue }  # covered file
      $d = ($f -replace '/[^/]+$','')
      if ($coveredPaths | Where-Object { $_ -eq $d -or $_.StartsWith("$d/") }) { continue }  # covered-parent dir
      $uncovered += $d
    }
    # LC_ALL=C parity: Sort-Object is culture-aware; issue order must match bash
    $uSet = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($x in $uncovered) { [void]$uSet.Add([string]$x) }
    $uArr = [string[]]::new($uSet.Count); $uSet.CopyTo($uArr)
    [Array]::Sort($uArr, [System.StringComparer]::Ordinal)
    $uncovered = $uArr
    foreach ($d in $uncovered) {
      if ($uncovered | Where-Object { $_ -ne $d -and $d.StartsWith("$_/") }) { continue }   # keep shallowest
      $issues += [pscustomobject]@{ severity="soft"; type="unmapped"; target=$d; detail="tracked code no section maps"; run="/speckit.blueprint-index.init --from-code $d"; kind="authored" }
    }
    }
  } else { [Console]::Error.WriteLine("note: not a git repository — code-staleness/coverage checks skipped") }

  # relations (stage-2 architecture): validate the checkable half of every
  # agent-authored edge — endpoints are managed sections, evidence exists in git
  # (mirrors the bash oracle). SOFT; remedy re-runs the recovery agent.
  if ($Blueprint -and (Test-Path $Blueprint)) {
    $secIds = @(); $heading = ""
    foreach ($line in [System.IO.File]::ReadAllLines($Blueprint)) {
      if ($line -match '^## ') { $heading = ($line -replace '^##\s+','' -replace ' \(remainder\)$','') }
      elseif ($line -match '<!-- blueprint:section') { if ($heading) { $secIds += $heading }; $heading = "" }
    }
    $rels = Select-String -Path $Blueprint -Pattern '<!-- blueprint:relation from=(\S+) to=(\S+) kind=(\S+) evidence=(\S+) -->' -AllMatches |
      ForEach-Object { $_.Matches } | ForEach-Object { [pscustomobject]@{ from=$_.Groups[1].Value; to=$_.Groups[2].Value; ev=$_.Groups[4].Value } }
    foreach ($r in $rels) {
      foreach ($ep in @($r.from, $r.to)) {
        if ($secIds -notcontains $ep) { $issues += [pscustomobject]@{ severity="soft"; type="relation"; target="$($r.from)->$($r.to)"; detail="relation endpoint not on the map: $ep"; run="/speckit.blueprint-index.recover"; kind="authored" } }
      }
      $evPath = $r.ev.Split("#")[0]
      $evPat = if ($r.ev.Contains("#")) { $r.ev.Substring($r.ev.IndexOf("#") + 1) } else { "" }
      if (Test-Git) {
        if (-not (Get-CurSha $evPath)) { $issues += [pscustomobject]@{ severity="soft"; type="relation-evidence"; target="$($r.from)->$($r.to)"; detail="relation evidence path gone: $evPath"; run="/speckit.blueprint-index.recover"; kind="authored" } }
        else {
          if ($evPat -ne "") {
            $content = git -C $Root show "HEAD:$evPath" 2>$null
            $hit = $false
            foreach ($cl in @($content)) { if (([string]$cl).Contains($evPat)) { $hit = $true; break } }
            if (-not $hit) { $issues += [pscustomobject]@{ severity="soft"; type="relation-evidence"; target="$($r.from)->$($r.to)"; detail="evidence no longer demonstrates the edge: '$evPat' not in $evPath"; run="/speckit.blueprint-index.recover"; kind="authored" } }
          }
        }
      }
    }
  }

  # structure (decision D2, bash parity): intersection-domain marker-set diff
  if ($Blueprint -and (Test-Path $Blueprint) -and $Struct -and $Part) {
    $comp = [System.Collections.Generic.HashSet[string]]::new()
    $chead = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($s in $Part) { foreach ($m in $s.markers) { [void]$comp.Add("$($s.path)`u{1f}$m"); [void]$chead.Add($s.path) } }
    $doc = [System.Collections.Generic.HashSet[string]]::new()
    $dhead = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($dp in $DocPairs) { if ($dp.state -eq "code" -or $dp.state -eq "context") { [void]$doc.Add("$($dp.heading)`u{1f}$($dp.path)"); [void]$dhead.Add($dp.heading) } }
    $diff = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $comp) { $a = $k.Split("`u{1f}"); if ($dhead.Contains($a[0]) -and -not $doc.Contains($k)) { $diff.Add("missing`u{1f}$($a[0])`u{1f}$($a[1])") } }
    foreach ($k in $doc)  { $a = $k.Split("`u{1f}"); if ($chead.Contains($a[0]) -and -not $comp.Contains($k)) { $diff.Add("extra`u{1f}$($a[0])`u{1f}$($a[1])") } }
    $darr = [string[]]$diff.ToArray(); [Array]::Sort($darr, [System.StringComparer]::Ordinal)
    foreach ($d in $darr) {
      $a = $d.Split("`u{1f}")
      if ($a[0] -eq "missing") { $issues += [pscustomobject]@{ severity="soft"; type="structure"; target=$a[1]; detail="computed marker absent from the section: $($a[2])"; run="/speckit.blueprint-index.init --from-code $($a[1])"; kind="authored" } }
      else { $issues += [pscustomobject]@{ severity="soft"; type="structure"; target=$a[1]; detail="marker not computed for this section (moved/freehand): $($a[2])"; run="/speckit.blueprint-index.init --from-code $($a[1])"; kind="authored" } }
    }
  }

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

