param(
    [Parameter(Mandatory = $true)]
    [string] $BaselineDist,
    [Parameter(Mandatory = $true)]
    [string] $CandidateDist,
    [Parameter(Mandatory = $true)]
    [string] $StartUrl,
    [Parameter(Mandatory = $true)]
    [string] $NextUrl,
    [Parameter(Mandatory = $true)]
    [string] $ThirdUrl,
    [int] $Runs = 3,
    [int] $SettleMs = 2000,
    [int] $PopupActionDelayMs = 700,
    [int] $ViewportWidth = 1440,
    [int] $ViewportHeight = 2200,
    [string] $BrowserChannel = 'chromium',
    [string] $OutDir = '',
    [string] $BaselineLabel = 'baseline',
    [string] $CandidateLabel = 'candidate',
    [switch] $DebugMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$nodeCommand = Get-Command node -ErrorAction Stop
$scriptPath = Join-Path $repoRoot 'test\perf\compare-real-page.js'

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Perf harness not found: $scriptPath"
}

$baselineDistPath = (Resolve-Path -LiteralPath $BaselineDist).Path
$candidateDistPath = (Resolve-Path -LiteralPath $CandidateDist).Path

$argumentList = @(
    $scriptPath,
    '--baseline-dist',
    $baselineDistPath,
    '--candidate-dist',
    $candidateDistPath,
    '--start-url',
    $StartUrl,
    '--next-url',
    $NextUrl,
    '--third-url',
    $ThirdUrl,
    '--runs',
    $Runs.ToString(),
    '--settle-ms',
    $SettleMs.ToString(),
    '--popup-action-delay-ms',
    $PopupActionDelayMs.ToString(),
    '--viewport-width',
    $ViewportWidth.ToString(),
    '--viewport-height',
    $ViewportHeight.ToString(),
    '--browser-channel',
    $BrowserChannel,
    '--baseline-label',
    $BaselineLabel,
    '--candidate-label',
    $CandidateLabel
)

if ($OutDir) {
    $argumentList += @( '--out-dir', $OutDir )
}

if ($DebugMode) {
    $argumentList += '--debug'
}

& $nodeCommand.Source $argumentList
if ($LASTEXITCODE -ne 0) {
    throw "Perf compare failed with exit code $LASTEXITCODE"
}
