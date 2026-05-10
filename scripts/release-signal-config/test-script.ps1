#Requires -PSEdition Core
<#
.SYNOPSIS
Tests the release-signal script against current branch.

.DESCRIPTION
Executes check-release-signal.ps1 and reports:
- Release likelihood
- Number of candidates
- Classification results
- Any warnings or errors

.PARAMETER BaseRef
Base reference for git diff (default: origin/main)

.PARAMETER HeadRef
Head reference for git diff (default: HEAD)

.PARAMETER ScriptPath
Path to check-release-signal.ps1 (default: scripts/check-release-signal.ps1)

.EXAMPLE
.\test-script.ps1
Tests current branch against origin/main

.EXAMPLE
.\test-script.ps1 -BaseRef "v2.0.0" -HeadRef "HEAD"
Tests against a specific tag
#>
param(
  [string]$BaseRef = "origin/main",
  [string]$HeadRef = "HEAD",
  [string]$ScriptPath = "scripts/check-release-signal.ps1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ScriptPath)) {
  Write-Host "✗ Release signal script not found at: $ScriptPath"
  exit 1
}

Write-Host "╔════════════════════════════════════════╗"
Write-Host "║  Release Signal Script Test            ║"
Write-Host "╚════════════════════════════════════════╝"
Write-Host ""
Write-Host "Testing: $BaseRef...$HeadRef"
Write-Host ""

try {
  $output = & pwsh -NoProfile -File $ScriptPath -BaseRef $BaseRef -HeadRef $HeadRef 2>&1

  if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Script failed with exit code $LASTEXITCODE"
    Write-Host ""
    Write-Host "Output:"
    $output | ForEach-Object { Write-Host "  $_" }
    exit 1
  }

  # Parse output
  $releaseLikely = $output | Select-String "release_likely=(.+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }
  $candidates = $output | Select-String "release_signal_candidates=(\d+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }
  $reason = $output | Select-String "release_reason=(.+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }

  Write-Host "Results:"
  Write-Host "  Release likely: $releaseLikely"
  Write-Host "  Candidates: $candidates"
  Write-Host "  Reason: $reason"
  Write-Host ""

  # Check for warnings/errors
  $warnings = @($output | Select-String "^::")
  if ($warnings.Count -gt 0) {
    Write-Host "Warnings/Errors ($($warnings.Count)):"
    $warnings | ForEach-Object { Write-Host "  $_" }
  } else {
    Write-Host "No CI warnings or errors"
  }

  Write-Host ""
  Write-Host "═══════════════════════════════════════"
  Write-Host "✓ Script executed successfully"
  Write-Host "═══════════════════════════════════════"

} catch {
  Write-Host "✗ Error: $_"
  exit 1
}
