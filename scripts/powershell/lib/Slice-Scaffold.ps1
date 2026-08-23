#!/usr/bin/env pwsh
# lib/Slice-Scaffold.ps1 — `scaffold`: machine-written map skeleton /
# additive blocks (mirrors bash lib/slice-scaffold.sh). No-op unless the
# command is scaffold; exits when it runs.
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

