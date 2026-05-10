#Requires -PSEdition Core
#Requires -Version 7.0

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $PlaywrightArgs
)

if ($PSVersionTable.PSEdition -ne 'Core') {
    throw "ABORT(A0): Must run in PowerShell Core (pwsh), not Windows PowerShell (powershell.exe)"
}
$ErrorActionPreference = 'Stop'

./scripts/package-extension.ps1 -DevBuild -Version 99 -NoZip
$env:EXTENSION_PATH = (Resolve-Path './dist/ChatPTPanel-99-dev').Path

if ($null -eq $PlaywrightArgs) {
    $PlaywrightArgs = @()
}
Write-Host "Starting Playwright test..."

# Start background job to adjust priority
$job = Start-Job -ScriptBlock {
    $timeout = 60
    $elapsed = 0
    $changed = $false

    while ($elapsed -lt $timeout) {
        # Get all Chrome processes
        $allChrome = Get-Process -Name chrome -ErrorAction SilentlyContinue

        if ($allChrome) {
            # Filter: Select ONLY processes where PriorityClass is higher than Normal
            $targetProcesses = $allChrome | Where-Object { $_.PriorityClass -gt [System.Diagnostics.ProcessPriorityClass]::Normal }

            if ($targetProcesses) {
                try {
                    # Set them to Normal (or BelowNormal if you prefer to lower them)
                    # Based on your request: "different than normal" -> set to Normal
                    $targetProcesses | ForEach-Object { $_.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal }


                    $msg = @(
                    "==================== ACP PRIORITY FIX ====================",
                    "[$(Get-Date -Format 'HH:mm:ss')]",
                    "Fixed $($targetProcesses.Count) Chrome process with non-Normal priority.",
                    "Priority changed from higher-than-Normal to Normal.",
                    "========================================================="
                    ) -join "`n"
                    Write-Host $msg -ForegroundColor Yellow

                    # CRITICAL: Stop immediately after the first change as requested
                    $changed = $true
                    break
                } catch {
                    Write-Warning "Failed to set priority: $_"
                }
            } else {
                # All Chrome processes are already Normal, nothing to do
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] All Chrome processes are already at Normal priority." -ForegroundColor Cyan
                # We can still break if you only care about fixing "wrong" priorities
                # Or keep waiting to see if a new worker spawns with wrong priority
                # Assuming you want to stop if nothing needs fixing:
                # break
            }
        }

        Start-Sleep -Seconds 1
        $elapsed++
    }

    if (-not $changed) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] No Chrome processes found with non-Normal priority within timeout."
    }
}

# Run Playwright
npx playwright test tests/e2e/all-in-one-substep.spec.js `
  --retries=0 `
  --config=playwright.config.js `
  @PlaywrightArgs

$playwrightExitCode = $LASTEXITCODE

# Cleanup
Write-Host "Playwright test finished. Stopping background job..."
Stop-Job -Job $job
$jobOutput = Receive-Job -Job $job
if ($jobOutput) { Write-Host $jobOutput }
Remove-Job -Job $job

exit $playwrightExitCode
