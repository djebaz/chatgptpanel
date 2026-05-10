param(
  [Parameter(Mandatory = $true)]
  [string]$BaseRef,
  [string]$HeadRef = 'HEAD',
  [string]$eventPath = $env:GITHUB_EVENT_PATH,
  [string]$OutputPath = $env:GITHUB_OUTPUT,
  [string]$SummaryPath = $env:GITHUB_STEP_SUMMARY,
  [string]$ConfigPath = (Join-Path $PSScriptRoot 'release-signal-config.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$innerOutputPath = Join-Path ([System.IO.Path]::GetTempPath()) ("release-signal-output-{0}.txt" -f ([System.Guid]::NewGuid().ToString('N')))
$innerSummaryPath = $SummaryPath
$scriptPath = Join-Path $PSScriptRoot 'check-release-signal.ps1'

function Add-OutputValue {
  param(
    [Parameter(Mandatory = $true)]
    [string] $Name,
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string] $Value
  )

  if ($OutputPath) {
    Add-Content -LiteralPath $OutputPath -Value "$Name=$Value"
  }
}

function Copy-InnerOutput {
  if ($OutputPath -and (Test-Path -LiteralPath $innerOutputPath)) {
    Get-Content -LiteralPath $innerOutputPath | Add-Content -LiteralPath $OutputPath
  }
}

function Invoke-GitText {
  param(
    [Parameter(Mandatory = $true)]
    [string[]] $Args
  )

  $result = & git @Args 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "git $($Args -join ' ') failed ($exitCode): $($result -join [Environment]::NewLine)"
  }

  return ($result -join "`n")
}

function Get-ReleaseAuditMetadata {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string] $Text
  )

  $prsMatch = [regex]::Match($Text, '(?m)^- PRs:\s*(.+?)\r?$')
  $scopeMatch = [regex]::Match($Text, '(?m)^- Scope:\s*(.*)\r?$')

  return @{
    HasParsablePrs = $prsMatch.Success
    Prs            = @([regex]::Matches($prsMatch.Groups[1].Value, '#\d+') | ForEach-Object { $_.Value }) | Sort-Object -Unique
    Scope          = if ($scopeMatch.Success) { $scopeMatch.Groups[1].Value.Trim() } else { '' }
  }
}

function Get-CurrentPrNumber {
  if (-not $eventPath -or -not (Test-Path -LiteralPath $eventPath)) {
    return $null
  }

  $eventData = Get-Content -Raw -LiteralPath $eventPath | ConvertFrom-Json
  if ($eventData.PSObject.Properties['pull_request'] -and $eventData.pull_request.PSObject.Properties['number']) {
    return [int]$eventData.pull_request.number
  }

  return $null
}

function Test-ReleaseRolloverAudit {
  param(
    [Parameter(Mandatory = $true)]
    [string] $Base,
    [Parameter(Mandatory = $true)]
    [string] $Head
  )

  $currentPrNumber = Get-CurrentPrNumber
  if ($null -eq $currentPrNumber) {
    return $false
  }

  $changedFilesRaw = Invoke-GitText -Args @('diff', '--name-only', '--diff-filter=ACMR', "$Base...$Head")
  $changedFiles = @($changedFilesRaw -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })

  $unreleasedFile = 'devdocs/releases/unreleased.md'
  if ($changedFiles -notcontains $unreleasedFile) {
    return $false
  }

  $releaseFiles = @($changedFiles | Where-Object { $_ -match '^devdocs/releases/\d+\.\d+\.\d+\.md$' })
  if (@($releaseFiles).Count -ne 1) {
    return $false
  }

  $unreleasedText = Get-Content -Raw -LiteralPath $unreleasedFile
  $unreleasedAudit = Get-ReleaseAuditMetadata -Text $unreleasedText
  $currentPrToken = "#$currentPrNumber"

  if (-not $unreleasedAudit.HasParsablePrs) {
    return $false
  }
  if (@($unreleasedAudit.Prs) -notcontains $currentPrToken) {
    return $false
  }
  if ([string]::IsNullOrWhiteSpace($unreleasedAudit.Scope)) {
    return $false
  }

  $releaseText = Get-Content -Raw -LiteralPath $releaseFiles[0]
  $releaseAudit = Get-ReleaseAuditMetadata -Text $releaseText
  if (-not $releaseAudit.HasParsablePrs) {
    return $false
  }
  if ([string]::IsNullOrWhiteSpace($releaseAudit.Scope)) {
    return $false
  }

  $baseUnreleasedText = Invoke-GitText -Args @('show', "$Base`:$unreleasedFile")
  $baseAudit = Get-ReleaseAuditMetadata -Text $baseUnreleasedText
  if (-not $baseAudit.HasParsablePrs) {
    return $false
  }

  foreach ($pr in @($baseAudit.Prs)) {
    if (@($releaseAudit.Prs) -notcontains $pr) {
      return $false
    }
  }

  return $true
}

try {
  & $scriptPath -BaseRef $BaseRef -HeadRef $HeadRef -eventPath $eventPath -OutputPath $innerOutputPath -SummaryPath $innerSummaryPath -ConfigPath $ConfigPath
  Copy-InnerOutput
  exit 0
}
catch {
  $innerError = $_
  if (Test-ReleaseRolloverAudit -Base $BaseRef -Head $HeadRef) {
    Copy-InnerOutput
    Add-OutputValue -Name 'error_count' -Value '0'
    Add-OutputValue -Name 'errors_joined' -Value ''

    $message = 'Release rollover detected: unreleased.md was reset for the current release PR and the cumulative Release audit metadata was copied to the versioned release notes file.'
    Add-OutputValue -Name 'warnings_joined' -Value $message
    Write-Warning $message
    exit 0
  }

  Copy-InnerOutput
  throw $innerError
}
finally {
  if (Test-Path -LiteralPath $innerOutputPath) {
    Remove-Item -LiteralPath $innerOutputPath -Force
  }
}
