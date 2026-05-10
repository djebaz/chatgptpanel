
#Requires -PSEdition Core
#Requires -Version 7.0
param(
    [string] $AppName,
    [string] $ConfigPath,
    [string] $Version,
    [string] $TargetName,
    [switch] $DevBuild,
    [switch] $BuildDevVariant,
    [switch] $Strict,
    [switch] $NoZip
)

# Helper: Check if a path is excluded by folder, glob, or name pattern
function Test-IsExcluded {
    param(
        [string] $RelPath, # relative to srcRoot
        [string[]] $ExcludeFolders,
        [string[]] $ExcludeGlobs,
        [string[]] $ExcludeNamePatterns
    )
    # Folder exclusion (top-level or subfolder match)
    foreach ($folder in $ExcludeFolders) {
        if ($RelPath -eq $folder -or $RelPath.StartsWith("$folder/")) {
            return $true
        }
    }
    # Glob exclusion (PowerShell -like pattern)
    foreach ($glob in $ExcludeGlobs) {
        if ($RelPath -like $glob) {
            return $true
        }
    }
    # Name pattern exclusion (regex)
    foreach ($pat in $ExcludeNamePatterns) {
        if ($RelPath -match $pat) {
            return $true
        }
    }
    return $false
}

# ---------------- MAIN ----------------
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repoRoot

$cfgPathResolved = if ($ConfigPath) {
    $ConfigPath
}
else {
    (Join-Path $PSScriptRoot 'package-config.json')
}

if ($PSVersionTable.PSEdition -ne 'Core') {
    throw "ABORT(A0): Must run in PowerShell Core (pwsh), not Windows PowerShell (powershell.exe)"
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-Directory ([string] $Path) {
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Remove-IfExists ([string] $Path) {
    if (Test-Path $Path) {
        Remove-Item $Path -Recurse -Force
    }
}

function Import-Configuration ([string] $CfgPath) {
    if (-not (Test-Path $CfgPath)) {
        throw "ConfigPath not found: $CfgPath"
    }
    $raw = Get-Content $CfgPath -Raw
    $cfg = $raw | ConvertFrom-Json

    $hasSrcRoot = $cfg.PSObject.Properties.Name -contains 'srcRoot'
    if (-not $hasSrcRoot -or -not $cfg.srcRoot) {
        $cfg
        | Add-Member -NotePropertyName srcRoot -NotePropertyValue 'src' -Force
    }

    $hasDistRoot = $cfg.PSObject.Properties.Name -contains 'distRoot'
    if (-not $hasDistRoot -or -not $cfg.distRoot) {
        $cfg
        | Add-Member -NotePropertyName distRoot -NotePropertyValue 'dist' -Force
    }

    $hasManifestPath = $cfg.PSObject.Properties.Name -contains 'manifestPath'
    if (-not $hasManifestPath -or -not $cfg.manifestPath) {
        $cfg
        | Add-Member -NotePropertyName manifestPath -NotePropertyValue (
            Join-Path $cfg.srcRoot 'manifest.json'
        ) -Force
    }

    if (-not $cfg.allowlist -or $cfg.allowlist.Count -eq 0) {
        throw "Config must define non-empty 'allowlist' (array of relative paths under srcRoot)."
    }

    if (-not ($cfg.PSObject.Properties.Name -contains 'excludeFolders')) {
        $cfg
        | Add-Member -NotePropertyName excludeFolders -NotePropertyValue @() -Force
    }
    if (-not ($cfg.PSObject.Properties.Name -contains 'excludeGlobs')) {
        $cfg
        | Add-Member -NotePropertyName excludeGlobs -NotePropertyValue @() -Force
    }
    if (-not ($cfg.PSObject.Properties.Name -contains 'excludeNamePatterns')) {
        $cfg
        | Add-Member -NotePropertyName excludeNamePatterns -NotePropertyValue @(
            '\.map$',
            '\.bak$',
            '\.log$',
            '\.tmp$',
            '\.DS_Store$'
        ) -Force
    }

    $hasManifestRelPath = $cfg.PSObject.Properties.Name -contains 'manifestRelPath'
    if (-not $hasManifestRelPath -or -not $cfg.manifestRelPath) {
        $cfg
        | Add-Member -NotePropertyName manifestRelPath -NotePropertyValue 'manifest.json' -Force
    }

    return $cfg
}


function Read-ManifestVersion ([string] $ManifestAbsPath) {
    if (-not (Test-Path $ManifestAbsPath)) {
        throw "manifest.json not found at: $ManifestAbsPath"
    }
    $m = Get-Content $ManifestAbsPath -Raw | ConvertFrom-Json
    if (-not $m.version) {
        throw "manifest.json has no 'version' field"
    }
    return [string] $m.version
}

function Copy-Allowlist (
    [string] $SrcRootAbs,
    [string] $StageDir,
    $Cfg,
    [switch] $StrictMode
) {
    $excludeFolders = $Cfg.excludeFolders
    $excludeGlobs = $Cfg.excludeGlobs
    $excludeNamePatterns = $Cfg.excludeNamePatterns
    foreach ($item in $Cfg.allowlist) {
        if (Test-IsExcluded -RelPath $item -ExcludeFolders $excludeFolders -ExcludeGlobs $excludeGlobs -ExcludeNamePatterns $excludeNamePatterns) {
            continue
        }
        $srcPath = Join-Path $SrcRootAbs $item
        if (-not (Test-Path $srcPath)) {
            $msg = "Missing allowlisted item: $item"
            if ($StrictMode) {
                throw $msg
            }
            else {
                Write-Warning $msg
                continue
            }
        }
        $destPath = Join-Path $StageDir $item
        Initialize-Directory (Split-Path $destPath -Parent)
        if (Test-Path $srcPath -PathType Container) {
            # Recursively copy, but filter exclusions
            $allFiles = Get-ChildItem -Path $srcPath -Recurse -File | ForEach-Object {
                $rel = Join-Path $item ($_.FullName.Substring($srcPath.Length).TrimStart('\', '/'))
                if (-not (Test-IsExcluded -RelPath $rel -ExcludeFolders $excludeFolders -ExcludeGlobs $excludeGlobs -ExcludeNamePatterns $excludeNamePatterns)) {
                    $_
                }
            }
            foreach ($f in $allFiles) {
                $rel = Join-Path $item ($f.FullName.Substring($srcPath.Length).TrimStart('\', '/'))
                $dst = Join-Path $StageDir $rel
                Initialize-Directory (Split-Path $dst -Parent)
                Copy-Item -Path $f.FullName -Destination $dst -Force
            }
        }
        else {
            Copy-Item -Path $srcPath -Destination $destPath -Force
        }
    }
}

function Remove-ExcludedFolders ( [string] $StageDir, $Cfg ) {
    foreach ($folder in $Cfg.excludeFolders) {
        $p = Join-Path $StageDir $folder
        if (Test-Path $p) {
            Write-Host "Removing excluded folder from staged bundle: $folder"
            Remove-Item $p -Recurse -Force
        }
    }
}

function Remove-ExcludedByNamePatterns (
    [string] $StageDir,
    [string[]] $Patterns
) {
    if (-not $Patterns -or $Patterns.Count -eq 0) {
        return
    }
    $files = Get-ChildItem -Path $StageDir -Recurse -Force -File
    foreach ($f in $files) {
        foreach ($pat in $Patterns) {
            if ($f.Name -match $pat) {
                Remove-Item $f.FullName -Force
                break
            }
        }
    }
}

function Remove-ExcludedByGlobs ( [string] $StageDir, [string[]] $Globs ) {
    if (-not $Globs -or $Globs.Count -eq 0) {
        return
    }
    foreach ($glob in $Globs) {
        $matchedFiles = Get-ChildItem -Path $StageDir -Recurse -Force -File
        | Where-Object {
            $_.FullName -like (Join-Path $StageDir $glob)
        }
        foreach ($m in $matchedFiles) {
            Write-Host "Removing excluded file (glob): $($m.FullName)"
            Remove-Item $m.FullName -Force
        }
    }
}

function Set-ManifestDevVersionName (
    [string] $StagedManifestAbsPath,
    [string] $Version,
    [bool] $IsDev
) {
    if (-not (Test-Path $StagedManifestAbsPath)) {
        throw "Staged manifest not found: $StagedManifestAbsPath"
    }

    $m = Get-Content $StagedManifestAbsPath -Raw | ConvertFrom-Json

    $effectiveVersion = if ($m.version) {
        [string] $m.version
    }
    else {
        [string] $Version
    }
    if (-not $effectiveVersion) {
        throw "manifest.json missing 'version' and no override provided."
    }

    if ($m.PSObject.Properties.Name -notcontains 'version_name') {
        $m | Add-Member -NotePropertyName version_name -NotePropertyValue ''
    }
    $m.version_name = if ($IsDev) {
        "{0}-dev" -f $effectiveVersion
    }
    else {
        $effectiveVersion
    }

    $json = $m | ConvertTo-Json -Depth 64
    Set-Content -Path $StagedManifestAbsPath -Value $json -Encoding utf8
}

function Resolve-AppName (
    [string] $AppNameParam,
    $Cfg,
    [string] $ManifestAbsPath
) {
    if ($AppNameParam) {
        return $AppNameParam
    }
    if (
        $Cfg -and (
            $Cfg.PSObject.Properties.Name -contains 'appName'
        ) -and $Cfg.appName
    ) {
        return [string] $Cfg.appName
    }

    if (Test-Path $ManifestAbsPath) {
        $m = Get-Content $ManifestAbsPath -Raw | ConvertFrom-Json
        if ($m.name) {
            $sanitized = ( $m.name -replace '\s+', '' ).Trim()
            if ($sanitized) {
                return $sanitized
            }
        }
    }

    throw "AppName is required. Pass -AppName or set 'appName' in package-config.json (or ensure manifest.json has a non-empty name)."
}

function Invoke-StagingAndZip (
    [string] $RepoRoot,
    [string] $SrcRootAbs,
    [string] $DistRootAbs,
    [string] $StageName,
    $Cfg,
    [switch] $StrictMode,
    [switch] $DevFlag,
    [string] $VersionOverride
) {
    $stageDir = Join-Path $DistRootAbs $StageName
    Write-Host ""
    Write-Host "Staging to: $stageDir" -ForegroundColor Cyan
    Remove-IfExists $stageDir
    Initialize-Directory $stageDir

    Write-Host "Copy allowlist from: $SrcRootAbs"
    Copy-Allowlist -SrcRootAbs $SrcRootAbs -StageDir $stageDir -Cfg $Cfg -StrictMode:$StrictMode

    Remove-ExcludedFolders $stageDir $Cfg
    Remove-ExcludedByGlobs $stageDir $Cfg.excludeGlobs
    Remove-ExcludedByNamePatterns $stageDir $Cfg.excludeNamePatterns

    $manifestRel = if ($Cfg.manifestRelPath) {
        $Cfg.manifestRelPath
    }
    else {
        'manifest.json'
    }
    $stagedManifest = Join-Path $stageDir $manifestRel

    if (-not (Test-Path $stagedManifest)) {
        throw "Staged manifest not found: $stagedManifest (check allowlist and manifestRelPath in package-config.json)"
    }

    Set-ManifestDevVersionName -StagedManifestAbsPath $stagedManifest -Version $VersionOverride -IsDev:$DevFlag

    Write-Host ""
    if (-not ($NoZip)) {
        $zipPath = Join-Path $DistRootAbs ("$StageName.zip")
        Write-Host "Creating zip: $zipPath" -ForegroundColor Cyan
        Remove-IfExists $zipPath

        # Zip staged contents (flat zip root)
        Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath -Force
        Write-Host ""
        Write-Host "ZIP ready:" -ForegroundColor Green
        Write-Host "  $zipPath"
    }
    else {
        Write-Host "Nozip for testing" -ForegroundColor Green
    }
}
$cfgAbs = if ([System.IO.Path]::IsPathRooted($cfgPathResolved)) {
    $cfgPathResolved
}
else {
    (Join-Path $repoRoot $cfgPathResolved)
}
$cfg = Import-Configuration -CfgPath $cfgAbs

$srcRootAbs = Join-Path $repoRoot $cfg.srcRoot
$distRootAbs = Join-Path $repoRoot $cfg.distRoot
Initialize-Directory $distRootAbs

$manifestAbs = if ([System.IO.Path]::IsPathRooted($cfg.manifestPath)) {
    $cfg.manifestPath
}
else {
    (Join-Path $repoRoot $cfg.manifestPath)
}
$AppName = Resolve-AppName -AppNameParam $AppName -Cfg $cfg -ManifestAbsPath $manifestAbs
if (-not $Version) {
    $Version = Read-ManifestVersion -ManifestAbsPath $manifestAbs

}

$defaultName = "{0}-{1}" -f $AppName, $Version
if ($DevBuild -and -not $TargetName) {
    $defaultName = "{0}-dev" -f $defaultName
}
$stageName = if ($TargetName) {
    $TargetName
}
else {
    $defaultName
}
$devFlag = [bool] $DevBuild

Invoke-StagingAndZip -RepoRoot $repoRoot -SrcRootAbs $srcRootAbs -DistRootAbs $distRootAbs -StageName $stageName -Cfg $cfg -StrictMode:$Strict -DevFlag:$devFlag -VersionOverride $Version

if ($BuildDevVariant) {
    $devName = if ($stageName.ToLower().EndsWith('-dev')) {
        $stageName
    }
    else {
        "{0}-dev" -f $stageName
    }
    Invoke-StagingAndZip -RepoRoot $repoRoot -SrcRootAbs $srcRootAbs -DistRootAbs $distRootAbs -StageName $devName -Cfg $cfg -StrictMode:$Strict -DevFlag:$true -VersionOverride $Version
}


