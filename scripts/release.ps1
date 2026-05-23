#Requires -PSEdition Core
#Requires -Version 7.0
param(
    [string] $Version,
    [string] $Branch = 'main',
    [string] $Remote = 'origin',
    [string] $ArtifactPath,
    [switch] $SkipPull,
    [switch] $SkipTests,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repoRoot

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,
        [Parameter(Mandatory = $false)]
        [string[]] $Arguments = @()
    )

    Write-Host "> $FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $FilePath $($Arguments -join ' ')"
    }
}

function Get-JsonFileVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Version file not found: $Path"
    }

    $json = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    if (-not $json.version) {
        throw "No version field found in $Path"
    }

    return [string] $json.version
}

function Assert-CommandAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found on PATH: $Name"
    }
}

Assert-CommandAvailable -Name 'git'
Assert-CommandAvailable -Name 'gh'
Assert-CommandAvailable -Name 'npm'

$currentBranch = (& git branch --show-current).Trim()
if ($currentBranch -ne $Branch) {
    throw "Release must run from '$Branch'. Current branch: '$currentBranch'"
}

if (-not $SkipPull) {
    Invoke-LoggedCommand -FilePath 'git' -Arguments @('pull', $Remote, $Branch, '--ff-only')
}

$status = (& git status --short)
if ($status) {
    throw "Working tree is not clean. Commit or stash changes before release.`n$status"
}

if (-not $Version) {
    $Version = Get-JsonFileVersion -Path (Join-Path $repoRoot 'src/manifest.json')
}

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Version must be semver x.y.z. Got: $Version"
}

$packageVersion = Get-JsonFileVersion -Path (Join-Path $repoRoot 'package.json')
$manifestVersion = Get-JsonFileVersion -Path (Join-Path $repoRoot 'src/manifest.json')
if ($packageVersion -ne $Version) {
    throw "package.json version '$packageVersion' does not match requested version '$Version'."
}
if ($manifestVersion -ne $Version) {
    throw "src/manifest.json version '$manifestVersion' does not match requested version '$Version'."
}

$releaseNotesPath = Join-Path $repoRoot "devdocs/releases/$Version.md"
if (-not (Test-Path -LiteralPath $releaseNotesPath)) {
    throw "Release notes not found: $releaseNotesPath"
}

$releaseNotes = Get-Content -Raw -LiteralPath $releaseNotesPath
$escapedVersion = [regex]::Escape($Version)
if ($releaseNotes -notmatch "(?m)^## v$escapedVersion\s*$") {
    throw "Release notes must contain header: ## v$Version"
}

$tagName = "v$Version"
$existingTag = @(& git tag --list $tagName) -join ''
if ($existingTag -and -not $Force) {
    throw "Tag already exists locally: $tagName. Use -Force only after verifying the existing release state."
}

$remoteTagExists = $false
& git ls-remote --exit-code --tags $Remote $tagName *> $null
if ($LASTEXITCODE -eq 0) {
    $remoteTagExists = $true
}
elseif ($LASTEXITCODE -ne 2) {
    throw "Failed to query remote tag $tagName. git ls-remote exit code: $LASTEXITCODE"
}

if ($remoteTagExists -and -not $Force) {
    throw "Tag already exists on ${Remote}: $tagName. Use -Force only after verifying the existing release state."
}

if (-not $SkipTests) {
    Invoke-LoggedCommand -FilePath 'npm' -Arguments @('run', 'format')
    Invoke-LoggedCommand -FilePath 'npm' -Arguments @('run', 'lint')
    Invoke-LoggedCommand -FilePath 'npm' -Arguments @('run', 'test:unit')
}

Invoke-LoggedCommand -FilePath 'pwsh' -Arguments @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    './scripts/package-extension.ps1',
    '-Version',
    $Version
)

if (-not $ArtifactPath) {
    $ArtifactPath = Join-Path $repoRoot "dist/ChatPTPanel-$Version.zip"
}

if (-not (Test-Path -LiteralPath $ArtifactPath)) {
    throw "Expected release artifact not found: $ArtifactPath"
}

$artifact = Get-Item -LiteralPath $ArtifactPath
if ($artifact.Length -le 0) {
    throw "Release artifact is empty: $ArtifactPath"
}

$existingRelease = $null
try {
    $existingRelease = gh release view $tagName --json tagName,name,isDraft,isPrerelease,assets 2>$null | ConvertFrom-Json
}
catch {
    $existingRelease = $null
}

if ($existingRelease -and -not $Force) {
    throw "GitHub release already exists for $tagName. Use -Force only after verifying the existing release state."
}

if (-not $remoteTagExists) {
    if (-not $existingTag) {
        Invoke-LoggedCommand -FilePath 'git' -Arguments @('tag', $tagName)
    }
    Invoke-LoggedCommand -FilePath 'git' -Arguments @('push', $Remote, $tagName)
}

if (-not $existingRelease) {
    Invoke-LoggedCommand -FilePath 'gh' -Arguments @(
        'release',
        'create',
        $tagName,
        $ArtifactPath,
        '--title',
        $tagName,
        '--notes-file',
        $releaseNotesPath
    )
}
elseif ($Force) {
    Invoke-LoggedCommand -FilePath 'gh' -Arguments @(
        'release',
        'upload',
        $tagName,
        $ArtifactPath,
        '--clobber'
    )
}

$release = gh release view $tagName --json tagName,name,isDraft,isPrerelease,assets | ConvertFrom-Json
if ($release.tagName -ne $tagName) {
    throw "Release verification failed: expected tagName $tagName, got $($release.tagName)"
}
if ($release.isDraft) {
    throw "Release verification failed: $tagName is still a draft."
}
if ($release.isPrerelease) {
    throw "Release verification failed: $tagName is marked as prerelease."
}

$artifactName = Split-Path -Leaf $ArtifactPath
$asset = @($release.assets | Where-Object { $_.name -eq $artifactName }) | Select-Object -First 1
if (-not $asset) {
    throw "Release verification failed: asset not found on release: $artifactName"
}

Write-Host ""
Write-Host "Release published successfully." -ForegroundColor Green
Write-Host "  Tag:     $tagName"
Write-Host "  Asset:   $($asset.name)"
Write-Host "  Size:    $($asset.size) bytes"
Write-Host "  URL:     $($asset.url)"
