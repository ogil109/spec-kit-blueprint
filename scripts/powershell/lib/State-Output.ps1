#!/usr/bin/env pwsh
# lib/State-Output.ps1 — next-action computation and next/status presentation
# (mirrors the bash frontier next block + lib/state-output.sh).
$nextPhase = "done"; $nextSlug = ""; $reason = "backlog empty — nothing in specs/, nothing in flight"
if ($drift.Count -gt 0) {
  $nextPhase = "distill"; $nextSlug = $drift[0]; $reason = "spec exists but blueprint still holds its detail"
} elseif ($inflight.Count -gt 0) {
  $nextPhase = $inflight[0].phase; $nextSlug = $inflight[0].slug; $reason = "in-flight slice; next build phase by artifact frontier"
} elseif (($Blueprint -and (Test-Path $Blueprint)) -and $detailedCount -eq 0 -and $settledCount -eq 0 -and $unmanagedCount -gt 0) {
  $nextPhase = "init"; $reason = "blueprint not yet processed by the extension — run /speckit.blueprint-index.init ($unmanagedCount unmanaged section(s))"
} elseif (($Blueprint -and (Test-Path $Blueprint)) -and $backlogCount -gt 0) {
  $nextPhase = "specify"; $reason = "no in-flight work; specify the next detailed subsystem from the blueprint"
} elseif (($Blueprint -and (Test-Path $Blueprint)) -and $settledCount -gt 0) {
  $reason = "all sections settled (owned by a spec or by code) — no pending design (run /speckit.specify to start a slice, then distill it)"
} elseif ($Blueprint -and (Test-Path $Blueprint)) {
  $nextPhase = "specify"; $reason = "blueprint has no subsystem sections yet — add some, or run /speckit.blueprint-index.init"
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
if ($drift.Count -eq 0) { Write-Output "  (none — blueprint in sync)" } else { $drift | ForEach-Object { Write-Output "  - $_  → /speckit.blueprint-index.distill $_" } }
Write-Output ""
Write-Output "Next action: $nextPhase $(if($nextSlug){"($nextSlug)"})"
Write-Output "  ($reason)"
