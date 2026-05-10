param(
    [string]$PrTitle,
    [int]$DelaySeconds = 45
)

#Requires -PSEdition Core
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        [Parameter(Mandatory = $true)]
        [string[]]$Args
    )

    $result = & $CommandName @Args 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Warning "$CommandName $($Args -join ' ') failed ($exitCode): $($result -join [Environment]::NewLine)"
        return $null
    }

    return ($result -join "`n")
}

$actions = New-Object System.Collections.Generic.List[string]

$branch = Invoke-NativeChecked -CommandName 'git' -Args @('rev-parse', '--abbrev-ref', 'HEAD')
if (-not $branch) {
    Write-Warning "Unable to resolve current branch. Stopping unreleased.md audit update."
    return $actions
}
if ($branch -eq 'HEAD') {
    throw "Detached HEAD detected. Checkout a feature branch first."
}

if ($DelaySeconds -gt 0) {
    Write-Host "[INFO] DelaySeconds=$DelaySeconds is ignored; checking for an existing PR immediately."
}

# Check if PR already exists for this branch
$pr = $null
try {
    $existingPrJson = Invoke-NativeChecked -CommandName 'gh' -Args @('pr', 'list', '--state', 'open', '--head', "$branch", '--json', 'number', '--limit', '1')
    if ($existingPrJson) {
        $parsed = $existingPrJson | ConvertFrom-Json
        if ($parsed.Count -gt 0 -and $parsed[0].number) {
            $pr = $parsed[0].number
            Write-Host "✓ Found manual PR #$pr for branch '$branch' — using that"
        }
    }
}
catch {
    Write-Host "⚠️  Unable to check for existing PRs, will attempt auto-creation"
}

# If no manual PR found, create auto PR
if (-not $pr) {
    if (-not $PrTitle -or $PrTitle -eq '') {
        $PrTitle = $branch -replace '[^a-zA-Z0-9_-]', '-'
    }
    Write-Host "ℹ️  No manual PR found, creating auto-PR with title: $PrTitle"
    $null = Invoke-NativeChecked -CommandName 'gh' -Args @('pr', 'create', '--base', 'main', '--title', "$PrTitle", '--fill')
    $pr = Invoke-NativeChecked -CommandName 'gh' -Args @('pr', 'view', '--json', 'number', '--jq', '.number')
    if (-not $pr) {
        Write-Warning "Auto-PR creation did not return a PR number. Skipping unreleased.md audit update."
        return $actions
    }
    Write-Host "✓ Auto-created PR #$pr 🚀"
    $actions.Add("Auto-created PR #$pr 🚀") | Out-Null
}

Write-Host "[INFO] Using PR #$pr for unreleased.md audit"
$content = Get-Content devdocs/releases/unreleased.md
$sanitizedBranch = ($branch -replace '^fix:|^feat:|^docs:|^chore:', '')
$sanitizedBranch = ($sanitizedBranch -replace '[^a-zA-Z0-9]', ' ').Trim()
while ($sanitizedBranch -match '  ') { $sanitizedBranch = $sanitizedBranch -replace '  ', ' ' }

Write-Host "[DEBUG] Branch: $branch, Sanitized: $sanitizedBranch"
for ($i = 0; $i -lt $content.Length; $i++) {
    if ($content[$i] -match '^\s*-?\s*PRs:\s*(.*)$') {
        Write-Host "[DEBUG] Original PRs line: $($content[$i])"
        $prs = ($matches[1] -split ', *' | ForEach-Object { $_.Trim().TrimEnd(',') } | Where-Object { $_ })
        if ($prs -notcontains ("#$pr")) { $prs += "#$pr" }
        $prs = $prs | Sort-Object -Unique
        $content[$i] = ('- PRs: ' + ($prs -join ', '))
    }
    
    if ($content[$i] -match '^-?\s*Scope:\s*(.*)$') {
        $scope = $matches[1]
        
        # Determine if the scope line has already grown compared to the base branch
        $baseBranch = 'origin/main'
        $scopeAlreadyGrown = $false
        try {
            $baseContent = Invoke-NativeChecked -CommandName 'git' -Args @('show', "${baseBranch}:devdocs/releases/unreleased.md")
            if ($baseContent -match '^-?\s*Scope:\s*(.*)$') {
                $baseScope = $matches[1]
                if ($scope.Length -gt $baseScope.Length) {
                    $scopeAlreadyGrown = $true
                }
            }
        } catch { }

        if (-not $scopeAlreadyGrown) {
            $cleanScope = $scope.Trim().TrimEnd(';').TrimEnd('.').Trim()
            if ([string]::IsNullOrWhiteSpace($cleanScope)) {
                $content[$i] = ('- Scope: ' + $sanitizedBranch)
            }
            else {
                $content[$i] = ('- Scope: ' + $cleanScope + '; ' + $sanitizedBranch)
            }
            Write-Host "[DEBUG] Updated Scope line: $($content[$i])"
        }
    }
}

$hasChanges = $false
$oldContent = if (Test-Path -LiteralPath '.\devdocs\releases\unreleased.md') {
    Get-Content -Raw -LiteralPath '.\devdocs\releases\unreleased.md'
}
else {
    $null
}

Set-Content devdocs/releases/unreleased.md $content
$newContent = Get-Content -Raw -LiteralPath '.\devdocs\releases\unreleased.md'

if ($oldContent -ne $newContent) {
    $hasChanges = $true
}

if ($hasChanges) {
    $null = Invoke-NativeChecked -CommandName 'git' -Args @('add', 'devdocs/releases/unreleased.md')
    $commitResult = Invoke-NativeChecked -CommandName 'git' -Args @('commit', '-m', 'Add PR number and branch to unreleased.md audit')
    if ($commitResult) {
        $null = Invoke-NativeChecked -CommandName 'git' -Args @('push')
        Write-Host "✓ Synced PR #$pr to Release audit 📜"
        $actions.Add("Synced PR #$pr to ``Release audit`` 📜") | Out-Null
    }
    else {
        Write-Warning "Skipping push because git commit did not succeed."
    }
}
else {
    Write-Host "[INFO] No changes to unreleased.md audit"
}

return @($actions)
