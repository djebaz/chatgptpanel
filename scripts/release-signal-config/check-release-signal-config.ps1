#Requires -PSEdition Core
<#
.SYNOPSIS
Validates release-signal-config.json and audits rule consistency.

.DESCRIPTION
Repo-aware version.

This script can live either inside the repository or inside an external Codex skill/helper
directory. It resolves the repository root first, then defaults config paths to:

  <repo>/scripts/release-signal-config.json
  <repo>/scripts/release-signal-config.schema.json

It intentionally contains no project-specific release classification policy.
#>
[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$ConfigPath = '',
  [string]$SchemaPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:passCount = 0
$script:failCount = 0
$script:warnCount = 0
$script:failMessages = New-Object System.Collections.Generic.List[string]
$script:warnMessages = New-Object System.Collections.Generic.List[string]

function Test-VerboseOutput {
  return $VerbosePreference -ne 'SilentlyContinue'
}

function Write-Detail {
  param([string]$Message = '')

  if (Test-VerboseOutput) {
    Write-Host $Message
  }
}

function Write-FinalSummary {
  Write-Host ''
  Write-Host '╔════════════════════════════════════════╗'
  Write-Host '║  FINAL SUMMARY                         ║'
  Write-Host '╚════════════════════════════════════════╝'
  Write-Host ''
  Write-Host "  Passed:   $script:passCount"
  Write-Host "  Warnings: $script:warnCount"
  Write-Host "  Failed:   $script:failCount"

  if ($script:failMessages.Count -gt 0) {
    Write-Host ''
    Write-Host 'Failures:'
    foreach ($message in $script:failMessages) {
      Write-Host "  - $message"
    }
  }

  if ($script:warnMessages.Count -gt 0) {
    Write-Host ''
    Write-Host 'Warnings:'
    foreach ($message in $script:warnMessages) {
      Write-Host "  - $message"
    }
  }

  Write-Host ''
}

function Resolve-FullPathFromBase {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BasePath,

    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if ([System.IO.Path]::IsPathFullyQualified($Path)) {
    return $Path
  }

  return (Join-Path $BasePath $Path)
}

function Resolve-RepositoryRoot {
  param([string]$RequestedRepoRoot = '')

  if (-not [string]::IsNullOrWhiteSpace($RequestedRepoRoot)) {
    $resolved = Resolve-Path -LiteralPath $RequestedRepoRoot -ErrorAction Stop
    return $resolved.Path
  }

  $cwd = (Get-Location).Path

  try {
    $gitRoot = (& git -C $cwd rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitRoot)) {
      return [string]$gitRoot
    }
  }
  catch {
    # Fall through to upward search.
  }

  $dir = Get-Item -LiteralPath $cwd -ErrorAction Stop
  while ($null -ne $dir) {
    $configCandidate = Join-Path $dir.FullName 'scripts/release-signal-config.json'
    $schemaCandidate = Join-Path $dir.FullName 'scripts/release-signal-config.schema.json'

    if ((Test-Path -LiteralPath $configCandidate) -and (Test-Path -LiteralPath $schemaCandidate)) {
      return $dir.FullName
    }

    $dir = $dir.Parent
  }

  throw "Could not resolve repository root from current directory: $cwd. Run from inside the repo or pass -RepoRoot."
}

$repoRootResolved = Resolve-RepositoryRoot -RequestedRepoRoot $RepoRoot

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  $ConfigPath = Join-Path $repoRootResolved 'scripts/release-signal-config.json'
}
else {
  $ConfigPath = Resolve-FullPathFromBase -BasePath $repoRootResolved -Path $ConfigPath
}

if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
  $SchemaPath = Join-Path $repoRootResolved 'scripts/release-signal-config.schema.json'
}
else {
  $SchemaPath = Resolve-FullPathFromBase -BasePath $repoRootResolved -Path $SchemaPath
}

function Resolve-RepoPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if ([System.IO.Path]::IsPathFullyQualified($Path)) {
    return $Path
  }

  return (Join-Path $repoRootResolved $Path)
}

function Add-Pass {
  param([Parameter(Mandatory = $true)][string]$Message)
  $script:passCount++
  Write-Detail "  ✓ $Message"
}

function Add-Fail {
  param([Parameter(Mandatory = $true)][string]$Message)
  $script:failCount++
  $script:failMessages.Add($Message) | Out-Null
  Write-Detail "  ✗ $Message"
}

function Add-Warn {
  param([Parameter(Mandatory = $true)][string]$Message)
  $script:warnCount++
  $script:warnMessages.Add($Message) | Out-Null
  Write-Detail "  ⚠ $Message"
}

function Test-Check {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [scriptblock]$Test
  )

  try {
    if (& $Test) {
      Add-Pass $Name
      return $true
    }

    Add-Fail $Name
    return $false
  }
  catch {
    Add-Fail "$Name — $_"
    return $false
  }
}

function Get-ConfigValue {
  param(
    [Parameter(Mandatory = $false)]
    [AllowNull()]
    [object]$Object,
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $false)]
    [AllowNull()]
    [object]$Default = $null
  )

  if ($null -eq $Object) {
    return $Default
  }

  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) {
    return $Default
  }

  return $property.Value
}

function Get-ConfigArray {
  param(
    [Parameter(Mandatory = $false)]
    [AllowNull()]
    [object]$Value
  )

  if ($null -eq $Value) {
    return @()
  }

  return @($Value)
}

function Get-HighSignalExactFiles {
  param([Parameter(Mandatory = $true)][object]$Config)

  $files = New-Object System.Collections.Generic.List[string]
  foreach ($rule in (Get-ConfigArray (Get-ConfigValue $Config 'highSignal'))) {
    $file = Get-ConfigValue $rule 'file'
    if ($file) {
      $files.Add([string]$file) | Out-Null
    }
    foreach ($item in (Get-ConfigArray (Get-ConfigValue $rule 'files'))) {
      $files.Add([string]$item) | Out-Null
    }
  }
  return @($files)
}

function Get-HighSignalPathPrefixes {
  param([Parameter(Mandatory = $true)][object]$Config)

  $prefixes = New-Object System.Collections.Generic.List[string]
  foreach ($rule in (Get-ConfigArray (Get-ConfigValue $Config 'highSignal'))) {
    foreach ($prefix in (Get-ConfigArray (Get-ConfigValue $rule 'pathPrefixes'))) {
      $prefixes.Add([string]$prefix) | Out-Null
    }
  }
  return @($prefixes)
}

function Test-AnyPrefixCovers {
  param(
    [Parameter(Mandatory = $true)][string]$RequiredPrefix,
    [Parameter(Mandatory = $true)][string[]]$ActualPrefixes
  )

  foreach ($prefix in $ActualPrefixes) {
    if ($RequiredPrefix.StartsWith($prefix, [StringComparison]::Ordinal) -or
      $prefix.StartsWith($RequiredPrefix, [StringComparison]::Ordinal)) {
      return $true
    }
  }

  return $false
}

function Invoke-GitOptional {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Args
  )

  $result = & git -C $repoRootResolved @Args 2>&1
  return @{
    ExitCode = $LASTEXITCODE
    Output   = @($result)
  }
}

function Test-GitTrackedExactFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  $result = Invoke-GitOptional -Args @('ls-files', '--error-unmatch', '--', $Path)
  return $result.ExitCode -eq 0
}

function Test-GitTrackedPrefix {
  param([Parameter(Mandatory = $true)][string]$Prefix)

  $result = Invoke-GitOptional -Args @('ls-files', '--', "$Prefix*")
  return $result.ExitCode -eq 0 -and @($result.Output | Where-Object { $_ }).Count -gt 0
}

function Test-JsonSchemaIfAvailable {
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$SchemaPath
  )

  $command = Get-Command Test-Json -ErrorAction SilentlyContinue
  if (-not $command) {
    Add-Warn 'Test-Json is not available; schema validation skipped'
    return
  }

  $jsonText = Get-Content -Raw -LiteralPath $ConfigPath

  try {
    if ($command.Parameters.ContainsKey('SchemaFile')) {
      $ok = $jsonText | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop
      if ($ok) {
        Add-Pass 'Config validates against JSON Schema'
      }
      else {
        Add-Fail 'Config validates against JSON Schema'
      }
      return
    }

    $schemaText = Get-Content -Raw -LiteralPath $SchemaPath
    if ($command.Parameters.ContainsKey('Schema')) {
      $ok = $jsonText | Test-Json -Schema $schemaText -ErrorAction Stop
      if ($ok) {
        Add-Pass 'Config validates against JSON Schema'
      }
      else {
        Add-Fail 'Config validates against JSON Schema'
      }
      return
    }

    Add-Warn 'Test-Json exists but does not expose Schema/SchemaFile; schema validation skipped'
  }
  catch {
    Add-Fail "Config validates against JSON Schema — $_"
  }
}

Write-Detail '╔════════════════════════════════════════╗'
Write-Detail '║  Release Signal Config Check           ║'
Write-Detail '╚════════════════════════════════════════╝'
Write-Detail ''
Write-Detail "Repository root: $repoRootResolved"
Write-Detail "Config path:     $ConfigPath"
Write-Detail "Schema path:     $SchemaPath"
Write-Detail ''

Write-Detail '1. CONFIG AND SCHEMA'
Write-Detail ''

$configExists = Test-Check 'Config file exists' { Test-Path -LiteralPath $ConfigPath }
$schemaExists = Test-Check 'Schema file exists' { Test-Path -LiteralPath $SchemaPath }

if (-not $configExists -or -not $schemaExists) {
  Write-Detail ''
  Add-Fail 'Cannot continue without config and schema files'
  Write-FinalSummary
  exit 1
}

$config = $null
$schema = $null

Test-Check 'Config parses as JSON' {
  $script:config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
  $null -ne $script:config
} | Out-Null

Test-Check 'Schema parses as JSON' {
  $script:schema = Get-Content -Raw -LiteralPath $SchemaPath | ConvertFrom-Json
  $null -ne $script:schema
} | Out-Null

Test-JsonSchemaIfAvailable -ConfigPath $ConfigPath -SchemaPath $SchemaPath

Write-Detail ''
Write-Detail '2. REQUIRED SECTIONS'
Write-Detail ''

foreach ($section in @('version', 'project', 'lowSignal', 'nonTrivialLines', 'highSignal', 'conditionalFiles', 'labels', 'docsPolicy')) {
  Test-Check "$section section present" {
    $null -ne $script:config.PSObject.Properties[$section]
  } | Out-Null
}

Write-Detail ''
Write-Detail '3. FILE AND PREFIX EXISTENCE'
Write-Detail ''

$lowSignal = Get-ConfigValue $script:config 'lowSignal'
$lowExactFiles = Get-ConfigArray (Get-ConfigValue $lowSignal 'exactFiles')
$lowPrefixes = Get-ConfigArray (Get-ConfigValue $lowSignal 'pathPrefixes')
$highFiles = Get-HighSignalExactFiles -Config $script:config
$highPrefixes = Get-HighSignalPathPrefixes -Config $script:config
$conditionalFiles = @(
  foreach ($rule in (Get-ConfigArray (Get-ConfigValue $script:config 'conditionalFiles'))) {
    $file = Get-ConfigValue $rule 'file'
    if ($file) { [string]$file }
  }
)

foreach ($file in @($lowExactFiles + $highFiles + $conditionalFiles | Sort-Object -Unique)) {
  Test-Check "Configured file path exists: $file" { Test-Path -LiteralPath (Resolve-RepoPath $file) } | Out-Null
}

foreach ($prefix in @($lowPrefixes + $highPrefixes | Sort-Object -Unique)) {
  $trimmed = ([string]$prefix).TrimEnd('/')
  Test-Check "Configured path prefix exists: $prefix" { Test-Path -LiteralPath (Resolve-RepoPath $trimmed) } | Out-Null
}

$docsPolicy = Get-ConfigValue $script:config 'docsPolicy'
foreach ($field in @('unreleasedFile', 'readmeFile', 'changelogFile', 'agentsFile')) {
  $path = [string](Get-ConfigValue $docsPolicy $field)
  if ($path) {
    Test-Check "Docs policy file exists: $path" { Test-Path -LiteralPath (Resolve-RepoPath $path) } | Out-Null
  }
}

Write-Detail ''
Write-Detail '4. RULE CONSISTENCY'
Write-Detail ''

$allExactAssignments = @()
foreach ($file in $lowExactFiles) { $allExactAssignments += [pscustomobject]@{ File = [string]$file; Bucket = 'lowSignal.exactFiles' } }
foreach ($file in $highFiles) { $allExactAssignments += [pscustomobject]@{ File = [string]$file; Bucket = 'highSignal' } }
foreach ($file in $conditionalFiles) { $allExactAssignments += [pscustomobject]@{ File = [string]$file; Bucket = 'conditionalFiles' } }

$duplicatedFiles = @(
  $allExactAssignments |
  Group-Object File |
  Where-Object { @($_.Group | Select-Object -ExpandProperty Bucket -Unique).Count -gt 1 }
)

if ($duplicatedFiles.Count -gt 0) {
  foreach ($dup in $duplicatedFiles) {
    $buckets = @($dup.Group | Select-Object -ExpandProperty Bucket -Unique) -join ', '
    Add-Fail "File appears in multiple rule buckets: $($dup.Name) ($buckets)"
  }
}
else {
  Add-Pass 'No exact file is assigned to multiple rule buckets'
}

$labelConfig = Get-ConfigValue $script:config 'labels'
Test-Check 'releaseNeeded and releaseNone labels differ' {
  [string](Get-ConfigValue $labelConfig 'releaseNeeded') -ne [string](Get-ConfigValue $labelConfig 'releaseNone')
} | Out-Null

Write-Detail ''
Write-Detail '5. OPTIONAL COVERAGE AUDIT'
Write-Detail ''

$coverageAudit = Get-ConfigValue $script:config 'coverageAudit'
if ($null -eq $coverageAudit) {
  Add-Warn 'No coverageAudit section found; shipped-code coverage audit skipped'
}
else {
  # For coverage audit, "covered" means highSignal OR conditionalFiles.
  $releaseSignalFilesForAudit = @($highFiles + @(
      foreach ($rule in (Get-ConfigArray (Get-ConfigValue $script:config 'conditionalFiles'))) {
        $file = Get-ConfigValue $rule 'file'
        if ($file) { [string]$file }

        foreach ($item in (Get-ConfigArray (Get-ConfigValue $rule 'files'))) {
          [string]$item
        }
      }
    )) | Sort-Object -Unique

  $releaseSignalPrefixesForAudit = @($highPrefixes + @(
      foreach ($rule in (Get-ConfigArray (Get-ConfigValue $script:config 'conditionalFiles'))) {
        foreach ($prefix in (Get-ConfigArray (Get-ConfigValue $rule 'pathPrefixes'))) {
          [string]$prefix
        }
      }
    )) | Sort-Object -Unique

  $requiredFiles = Get-ConfigArray (Get-ConfigValue $coverageAudit 'requiredReleaseSignalFiles')
  foreach ($file in $requiredFiles) {
    Test-Check "Required release-signal file covered: $file" {
      $releaseSignalFilesForAudit -contains [string]$file
    } | Out-Null
  }

  $requiredPrefixes = Get-ConfigArray (Get-ConfigValue $coverageAudit 'requiredReleaseSignalPathPrefixes')
  foreach ($prefix in $requiredPrefixes) {
    Test-Check "Required release-signal prefix covered: $prefix" {
      Test-AnyPrefixCovers -RequiredPrefix ([string]$prefix) -ActualPrefixes @($releaseSignalPrefixesForAudit)
    } | Out-Null
  }
}

Write-Detail ''
Write-Detail '6. TRACKED-FILE ALIGNMENT'
Write-Detail ''

$gitAvailable = $false
try {
  $gitProbe = Invoke-GitOptional -Args @('rev-parse', '--is-inside-work-tree')
  $gitAvailable = $gitProbe.ExitCode -eq 0
}
catch {
  $gitAvailable = $false
}

if (-not $gitAvailable) {
  Add-Warn 'Not inside a git work tree or git unavailable; tracked-file alignment skipped'
}
else {
  foreach ($file in @($lowExactFiles + $highFiles + $conditionalFiles | Sort-Object -Unique)) {
    Test-Check "Git tracks configured file: $file" { Test-GitTrackedExactFile -Path ([string]$file) } | Out-Null
  }

  foreach ($prefix in @($lowPrefixes + $highPrefixes | Sort-Object -Unique)) {
    Test-Check "Git tracks at least one file under prefix: $prefix" { Test-GitTrackedPrefix -Prefix ([string]$prefix) } | Out-Null
  }
}

Write-FinalSummary

if ($script:failCount -gt 0) {
  Write-Host "✗ $script:failCount check(s) failed"
  exit 1
}

Write-Host '✓ All required checks passed'
exit 0
