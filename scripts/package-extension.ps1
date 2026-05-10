param(
    [string] $AppName = '', # Path to per-repo packaging config (JSON). Example: scripts/package-config.json
    [string] $ConfigPath = '', # Optional: override version used in dist folder/zip naming only; does NOT mutate src manifest.
    [string] $Version = '', # Optional custom folder name inside dist/. Default: <AppName>-<Version>
    [string] $TargetName = '', # Optional: skip zip creation and keep only the staged folder under dist/.
    [switch] $NoZip, # Marks the staged manifest as a dev build by setting version_name = "<version>-dev".
    [switch] $DevBuild, # Optional: build an extra dev variant folder/zip with suffix "-dev".
    [switch] $BuildDevVariant, # Optional: fail if any allowlisted item is missing (default: warn + continue).
    [switch] $Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-Dir ([string] $Path) {
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Remove-IfExist ([string] $Path) {
    if (Test-Path $Path) {
        Remove-Item $Path -Recurse -Force
    }
}

function Load-Config ([string] $CfgPath) {
    if (-not (Test-Path $CfgPath)) {
        throw "ConfigPath not found: $CfgPath"
    }
    $raw = Get-Content $CfgPath -Raw
    $cfg = $raw | ConvertFrom-Json

    $hasSrcRoot = $cfg.PSObject.Properties.Name -contains 'srcRoot'
    if (-not $hasSrcRoot -or -not $cfg.srcRoot) {
        $cfg | Add-Member -NotePropertyName srcRoot -NotePropertyValue 'src' -Force
    }

    $hasDistRoot = $cfg.PSObject.Properties.Name -contains 'distRoot'
    if (-not $hasDistRoot -or -not $cfg.distRoot) {
        $cfg | Add-Member -NotePropertyName distRoot -NotePropertyValue 'dist' -Force
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
        $cfg | Add-Member -NotePropertyName excludeFolders -NotePropertyValue @() -Force
    }
    if (-not ($cfg.PSObject.Properties.Name -contains 'excludeGlobs')) {
        $cfg | Add-Member -NotePropertyName excludeGlobs -NotePropertyValue @() -Force
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
        $cfg | Add-Member -NotePropertyName manifestRelPath -NotePropertyValue 'manifest.json' -Force
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
    foreach ($item in $Cfg.allowlist) {
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
        Ensure-Dir (Split-Path $destPath -Parent)
        Copy-Item -Path $srcPath -Destination $destPath -Recurse -Force
    }
}

function Remove-ExcludedFolder ( [string] $StageDir, $Cfg ) {
    foreach ($folder in $Cfg.excludeFolders) {
        $p = Join-Path $StageDir $folder
        if (Test-Path $p) {
            Write-Host "Removing excluded folder from staged bundle: $folder"
            Remove-Item $p -Recurse -Force
        }
    }
}

function Remove-ExcludedByNamePattern (
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

function Remove-ExcludedByGlob ( [string] $StageDir, [string[]] $Globs ) {
    if (-not $Globs -or $Globs.Count -eq 0) {
        return
    }
    foreach ($glob in $Globs) {
        $matches = Get-ChildItem -Path $StageDir -Recurse -Force -File
        | Where-Object {
            $_.FullName -like (Join-Path $StageDir $glob)
        }
        foreach ($m in $matches) {
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

function Stage-And-Zip (
    [string] $RepoRoot,
    [string] $SrcRootAbs,
    [string] $DistRootAbs,
    [string] $StageName,
    $Cfg,
    [switch] $StrictMode,
    [switch] $DevFlag,
    [string] $VersionOverride,
    [switch] $SkipZip
) {
    $stageDir = Join-Path $DistRootAbs $StageName
    $zipPath = Join-Path $DistRootAbs("{0}.zip" -f $StageName)

    Write-Host ""
    Write-Host "Staging to: $stageDir" -ForegroundColor Cyan
    Remove-IfExist $stageDir
    Ensure-Dir $stageDir

    Write-Host "Copy allowlist from: $SrcRootAbs"
    Copy-Allowlist -SrcRootAbs $SrcRootAbs -StageDir $stageDir -Cfg $Cfg -StrictMode:$StrictMode

    Remove-ExcludedFolder -StageDir $stageDir -Cfg $Cfg
    Remove-ExcludedByGlob -StageDir $stageDir -Globs $Cfg.excludeGlobs
    Remove-ExcludedByNamePattern -StageDir $stageDir -Patterns $Cfg.excludeNamePatterns

    # Set dev marker in staged manifest only
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

    Write-Host "Load unpacked from:" -ForegroundColor Green
    Write-Host "  $stageDir"

    if ($SkipZip) {
        Write-Host ""
        Write-Host "ZIP skipped due to -NoZip." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Creating zip: $zipPath" -ForegroundColor Cyan
    Remove-IfExist $zipPath

    # Zip staged contents (flat zip root)
    Compress-Archive -Path (
        Join-Path $stageDir '*'
    ) -DestinationPath $zipPath -Force

    Write-Host ""
    Write-Host "ZIP ready:" -ForegroundColor Green
    Write-Host "  $zipPath"
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
$cfgAbs = if ([System.IO.Path]::IsPathRooted($cfgPathResolved)) {
    $cfgPathResolved
}
else {
    (Join-Path $repoRoot $cfgPathResolved)
}
$cfg = Load-Config -CfgPath $cfgAbs

$srcRootAbs = Join-Path $repoRoot $cfg.srcRoot
$distRootAbs = Join-Path $repoRoot $cfg.distRoot
Ensure-Dir $distRootAbs

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

Stage-And-Zip -RepoRoot $repoRoot -SrcRootAbs $srcRootAbs -DistRootAbs $distRootAbs -StageName $stageName -Cfg $cfg -StrictMode:$Strict -DevFlag:$devFlag -VersionOverride $Version -SkipZip:$NoZip

if ($BuildDevVariant) {
    $devName = if ($stageName.ToLower().EndsWith('-dev')) {
        $stageName
    }
    else {
        "{0}-dev" -f $stageName
    }
    Stage-And-Zip -RepoRoot $repoRoot -SrcRootAbs $srcRootAbs -DistRootAbs $distRootAbs -StageName $devName -Cfg $cfg -StrictMode:$Strict -DevFlag:$true -VersionOverride $Version -SkipZip:$NoZip
}
