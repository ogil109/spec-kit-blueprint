#!/usr/bin/env pwsh
# lib/Slice-Verify.ps1 — `verify`: structure conformance diff (mirrors bash
# lib/slice-verify.sh). No-op unless the command is verify; exits when run.
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

