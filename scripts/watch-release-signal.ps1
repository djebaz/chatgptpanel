param(
  [string]$Repository,
  [ValidateSet('current-pr', 'workflow-runs')]
  [string]$Mode = 'current-pr',
  [string]$Branch,
  [string]$Workflow = 'release-signal.yml',
  [int]$PollSeconds = 30,
  [int]$PerPage = 10,
  [switch]$Apply,
  [string]$StatusContext = 'local/release-signal',
  [string]$UnreleasedPath = 'devdocs/releases/unreleased.md',
  [switch]$Once
)


Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# (Removed early exit to allow persistent polling across branch switches)

function Write-Status {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  $ts = Get-Date -Format 'HH:mm:ss'
  $icon = "  "
  $color = "White"

  if ($Message -match 'success|PASSED|Synced|✓|Auto-apply committed|🚀') {
    $icon = "✅ "
    $color = "Green"
  }
  elseif ($Message -match '\berror\b|\bfailure\b|\bFAILED\b|⭕') {
    if ($Message -match 'errors=0') {
      # This is a summary line with zero errors, treat as neutral/info
      $icon = "✅ "
      $color = "Green"
    } else {
      $icon = "❌ "
      $color = "Red"
    }
  }
  elseif ($Message -match '\bwarning\b|⚠️') {
    if ($Message -match 'warnings=0') {
      # This is a summary line with zero warnings, treat as neutral/info
      $icon = "✅ "
      $color = "Green"
    } else {
      $icon = "⚠️  "
      $color = "Yellow"
    }
  }
  elseif ($Message -match 'Trigger|Watching|Evaluating|ℹ️|Running update|📝|Polling') {
    $icon = "ℹ️  "
    $color = "Cyan"
  }
  elseif ($Message -match 'Evaluate') {
    $icon = "🔍 "
    $color = "Magenta"
  }

  Write-Host "[$ts] " -NoNewline -ForegroundColor Gray
  Write-Host "$icon$Message" -ForegroundColor $color
}

function Invoke-GhJson {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Args
  )

  $raw = & gh @Args 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "gh $($Args -join ' ') failed ($exitCode): $($raw -join [Environment]::NewLine)"
  }

  return (($raw -join "`n") | ConvertFrom-Json)
}
function Invoke-Git {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Args
  )

  $raw = & git @Args 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "git $($Args -join ' ') failed ($exitCode): $($raw -join [Environment]::NewLine)"
  }

  return ($raw -join "`n")
}

function Set-CommitStatus {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoName,
    [Parameter(Mandatory = $true)]
    [string]$Sha,
    [Parameter(Mandatory = $true)]
    [ValidateSet('pending', 'success', 'failure', 'error')]
    [string]$State,
    [Parameter(Mandatory = $true)]
    [string]$Context,
    [Parameter(Mandatory = $true)]
    [string]$Description,
    [AllowEmptyString()]
    [string]$TargetUrl = ''
  )

  $statusArgs = @(
    'api',
    '--method',
    'POST',
    "repos/$RepoName/statuses/$Sha",
    '-f',
    "state=$State",
    '-f',
    "context=$Context",
    '-f',
    "description=$Description"
  )
  if ($TargetUrl) {
    $statusArgs += @('-f', "target_url=$TargetUrl")
  }

  [void](Invoke-GhJson -Args $statusArgs)
}

function Update-ReleaseSignalStatusSafe {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoName,
    [Parameter(Mandatory = $true)]
    [string]$Sha,
    [Parameter(Mandatory = $true)]
    [ValidateSet('pending', 'success', 'failure', 'error')]
    [string]$State,
    [Parameter(Mandatory = $true)]
    [string]$Description
  )

  try {
    Set-CommitStatus -RepoName $RepoName -Sha $Sha -State $State -Context $StatusContext -Description $Description
    Write-Status "Commit status '$StatusContext' -> $State on $Sha"
  }
  catch {
    Write-Status "Commit status update failed for '$StatusContext' on ${Sha}: $($_.Exception.Message)"
  }
}

function Get-ReleaseAuditFooter {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Text
  )

  $footerPattern = '(?s)^(?<prefix>.*?)(?:\r?\n)?## Release audit\r?\n\r?\n- PRs:\s*(?<prs>[^\r\n]+)\r?\n- Scope:\s*(?<scope>[^\r\n]*)'
  $match = [regex]::Match($Text, $footerPattern)
  if (-not $match.Success) {
    return $null
  }

  return @{
    Prefix    = $match.Groups['prefix'].Value.TrimEnd()
    PrLine    = $match.Groups['prs'].Value.Trim()
    ScopeLine = $match.Groups['scope'].Value.Trim()
    PrTokens  = @([regex]::Matches($match.Groups['prs'].Value, '#\d+') | ForEach-Object { $_.Value }) | Sort-Object -Unique
  }
}

function Update-UnreleasedReleaseAudit {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [int]$PrNumber,
    [Parameter(Mandatory = $true)]
    [string]$PrTitle,
    [object[]]$Labels,
    [object[]]$RemediationActions = @(),
    [string]$BaseRef = ""
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Status "Auto-apply skipped file sync; missing '$Path'."
    return $false
  }

  $text = Get-Content -Raw -LiteralPath $Path
  $footer = Get-ReleaseAuditFooter -Text $text
  if (-not $footer) {
    Write-Status "Auto-apply skipped file sync; '$Path' does not end with a parseable 'Release audit' footer."
    return $false
  }

  $prToken = "#$PrNumber"
  $prAlreadyListed = $footer.PrTokens -contains $prToken

  # Determine if the scope line has already grown compared to the base branch
  $scopeAlreadyGrown = $false
  try {
    $repoName = Get-RepositoryName -Repo $Repository
    $baseBranch = if ($BaseRef) { $BaseRef } else { Get-DefaultBaseBranch -RepoName $repoName }
    $baseRefPath = if ($BaseRef) { "$BaseRef`:$Path" } else { "origin/$baseBranch`:$Path" }
    $baseUnreleasedText = Invoke-Git -Args @('show', $baseRefPath)
    $baseFooter = Get-ReleaseAuditFooter -Text $baseUnreleasedText
    if ($baseFooter -and $footer.ScopeLine.Length -gt $baseFooter.ScopeLine.Length) {
      $scopeAlreadyGrown = $true
      Write-Status "Scope already grown ($($footer.ScopeLine.Length) > $($baseFooter.ScopeLine.Length)). Skipping auto-append."
    }
  }
  catch {
    Write-Status "Unable to compare with base branch scope: $($_.Exception.Message)"
  }

  if ($prAlreadyListed -and $scopeAlreadyGrown) {
    return $false
  }

  $cleanPrLine = $footer.PrLine.Trim().TrimEnd(',').Trim()
  $newPrLine = if ($prAlreadyListed) {
    $footer.PrLine
  }
  elseif ([string]::IsNullOrWhiteSpace($cleanPrLine)) {
    $prToken
  }
  else {
    "$cleanPrLine, $prToken"
  }

  $currentBranchName = Get-CurrentBranchName
  $sanitizedBranch = Get-SanitizedBranchName -BranchName $currentBranchName
  $scopeSuffix = if ($sanitizedBranch) { $sanitizedBranch } else { $PrTitle.Trim() }

  $newScopeLine = if ($scopeAlreadyGrown) {
    $footer.ScopeLine
  }
  else {
    $cleanScope = $footer.ScopeLine.Trim().TrimEnd(';').TrimEnd('.').Trim()
    if ([string]::IsNullOrWhiteSpace($cleanScope)) {
      $scopeSuffix
    }
    else {
      "$cleanScope; $scopeSuffix"
    }
  }
  $newText = @(
    $footer.Prefix
    ''
    '## Release audit'
    ''
    "- PRs: $newPrLine"
    "- Scope: $newScopeLine"
  ) -join "`n"

  Set-Content -LiteralPath $Path -Value $newText -Encoding UTF8

  # Commit and push the auto-audit update
  try {
    [void](Invoke-Git -Args @('add', $Path))
    [void](Invoke-Git -Args @('commit', '-m', "docs: auto-audit sync $prToken in unreleased.md [skip ci]"))
    [void](Invoke-Git -Args @('push'))
    Write-Status "Auto-apply committed and pushed '$Path' update for $prToken."
  }
  catch {
    Write-Status "Auto-apply failed to commit/push '$Path' update: $($_.Exception.Message)"
  }

  Write-Status "Auto-apply updated '$Path' Release audit footer with $prToken."
  $changeType = if (-not $prAlreadyListed -and -not $scopeAlreadyGrown) { 'Both' } elseif (-not $prAlreadyListed) { 'List' } else { 'Scope' }
  return $changeType
}


function Invoke-UpdateUnreleasedAudit {
  param(
    [Parameter(Mandatory = $true)]
    [int]$PrNumber,
    [Parameter(Mandatory = $true)]
    [string]$PrTitle
  )

  Write-Status "Running update-unreleased-audit for PR #$PrNumber..."
  try {
    $auditActions = & pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/update-unreleased-audit.ps1 `
      -PrTitle $PrTitle 2>&1 | Where-Object { $_ }

    # Extract JSON-serialized action array from output
    $actionLines = @($auditActions | Where-Object { $_ -match '^\[.*\]$' })
    if ($actionLines.Count -gt 0) {
      return ($actionLines[-1] | ConvertFrom-Json)
    }
  }
  catch {
    Write-Status "update-unreleased-audit failed: $($_.Exception.Message)"
  }

  return @()
}

function Invoke-AutoRemediation {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoName,
    [Parameter(Mandatory = $true)]
    [int]$PrNumber,
    [Parameter(Mandatory = $true)]
    [string]$PrTitle,
    [Parameter(Mandatory = $true)]
    [hashtable]$Outputs,
    [Parameter(Mandatory = $true)]
    [string]$BaseSha,
    [Parameter(Mandatory = $true)]
    [string]$HeadSha
  )

  $actions = New-Object System.Collections.Generic.List[string]

  $hasReleaseLabel = $false
  if ($Outputs.ContainsKey('has_release_label')) {
    $hasReleaseLabel = $Outputs['has_release_label'].ToLowerInvariant() -eq 'true'
  }

  if (-not $hasReleaseLabel) {
    $recommendedLabel = if ($Outputs.ContainsKey('recommended_release_label') -and $Outputs['recommended_release_label']) {
      $Outputs['recommended_release_label']
    }
    else {
      $null
    }

    if ($recommendedLabel) {
      [void](Invoke-GhJson -Args @(
          'api',
          '--method',
          'POST',
          "repos/$RepoName/issues/$PrNumber/labels",
          '-f',
          "labels[]=$recommendedLabel"
        ))
      Write-Status "Auto-apply added label '$recommendedLabel' to PR #$PrNumber."
      $actions.Add("Added label ``$recommendedLabel`` 🏷️") | Out-Null
    }
  }

  $errorsJoined = if ($Outputs.ContainsKey('errors_joined')) { $Outputs['errors_joined'] } else { '' }

  $missingAuditPrError = $errorsJoined -and
    $errorsJoined.Contains('must list the current PR number') -and
    ($errorsJoined -match "#$PrNumber\b")

  $scopeMismatchError = $errorsJoined -and
    ($errorsJoined -match 'Scope:.*summary')

  if ($missingAuditPrError -or $scopeMismatchError) {
    Write-Status "Audit remediation detected (MissingPR=$missingAuditPrError, ScopeMismatch=$scopeMismatchError). Waiting 10s for manual fix..."
    Start-Sleep -Seconds 10

    # Re-fetch the PR state to see if it was fixed manually during the wait
    $pr = Invoke-GhJson -Args @('api', "repos/$RepoName/pulls/$PrNumber")
    # Re-evaluate locally to see if the file was fixed
    $evaluation = Invoke-ReleaseSignalEvaluation -SourceId "re-check" -Trigger "post-grace-period re-check" -PrNumber $PrNumber -BaseSha $BaseSha -HeadSha $HeadSha -PrBody ([string]$pr.body) -Labels @($pr.labels)

    $reCheckErrors = if ($evaluation['Outputs'].ContainsKey('errors_joined')) { $evaluation['Outputs']['errors_joined'] } else { '' }
    if ($reCheckErrors -notmatch 'Scope|summary|line did not grow|must list the current PR') {
      Write-Status "✅ Audit fixed manually during grace period. Skipping auto-remediation."
      return @()
    }

    Write-Status "ℹ️ Grace period over. Proceeding with auto-remediation..."
    $baseRef = if ($evaluation['Outputs'].ContainsKey('base_ref')) { $evaluation['Outputs']['base_ref'] } else { "" }
    $result = Update-UnreleasedReleaseAudit -Path $UnreleasedPath -PrNumber $PrNumber -PrTitle $PrTitle -BaseRef $baseRef
    if ($result) {
      if ($result -eq 'List' -or $result -eq 'Both') {
        $actions.Add("Synced PR #$PrNumber to `Release audit` list 📜") | Out-Null
      }
      if ($result -eq 'Scope' -or $result -eq 'Both') {
        $actions.Add("Synced PR #$PrNumber to `Release audit` Scope 📜") | Out-Null
      }
    }
  }

  if ($errorsJoined.Contains('PR body contains literal `\n` sequences')) {
    $pr = Invoke-GhJson -Args @('api', "repos/$RepoName/pulls/$PrNumber")
    $body = [string]$pr.body
    if ($body.Contains('\')) {
      # 1. Replace literal \n with real newline (collapsing any extra backslashes)
      $newBody = $body -replace '\\+n', "`n"
      # 2. Remove backslashes before characters that often get over-escaped (', `, ", etc.)
      $newBody = $newBody -replace '\\+([''`"\[\]()`])', '$1'
      [void](Invoke-GhJson -Args @(
        'api',
        '--method',
        'PATCH',
        "repos/$RepoName/pulls/$PrNumber",
        '-f',
        "body=$newBody"
      ))
      Write-Status "Auto-apply fixed literal '\n' in PR body for #$PrNumber."
      $actions.Add("Fixed literal ``\n`` sequences in PR body ✍️") | Out-Null
    }
  }

  return @($actions)
}

function Get-RepositoryName {
  param(
    [AllowEmptyString()]
    [string]$Repo
  )

  if ($Repo) {
    return $Repo
  }

  $result = & gh repo view --json nameWithOwner -q .nameWithOwner 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0 -or -not $result) {
    throw "Unable to resolve repository. Pass -Repository <owner/repo>. gh error: $($result -join [Environment]::NewLine)"
  }

  return ($result -join '').Trim()
}

function Get-CurrentBranchName {
  $result = & git branch --show-current 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0 -or -not $result) {
    throw "Unable to resolve current git branch: $($result -join [Environment]::NewLine)"
  }

  return ($result -join '').Trim()
}

function Get-SanitizedBranchName {
  param(
    [AllowEmptyString()]
    [string]$BranchName
  )

  if (-not $BranchName) {
    return ''
  }

  $clean = ($BranchName -replace '^(fix|feat|docs|chore)[:\-]', '')
  $clean = ($clean -replace '[^a-zA-Z0-9]', ' ').Trim()
  while ($clean -match '  ') { $clean = $clean -replace '  ', ' ' }
  return $clean
}

function Get-OutputMap {
  param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
  )

  $map = @{}
  if (-not (Test-Path -LiteralPath $OutputPath)) {
    return $map
  }

  foreach ($line in (Get-Content -LiteralPath $OutputPath)) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    $split = $line.Split('=', 2)
    if ($split.Count -ne 2) {
      continue
    }
    $map[$split[0].Trim()] = $split[1].Trim()
  }

  return $map
}

function Invoke-ReleaseSignalEvaluation {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceId,
    [string]$Trigger = 'unspecified',
    [Parameter(Mandatory = $true)]
    [int]$PrNumber,
    [Parameter(Mandatory = $true)]
    [string]$BaseSha,
    [Parameter(Mandatory = $true)]
    [string]$HeadSha,
    [AllowEmptyString()]
    [string]$PrBody = '',
    [AllowEmptyCollection()]
    [object[]]$Labels = @(),
    [object[]]$Actions = @()
  )

  $eventPayload = @{
    pull_request = @{
      number = $PrNumber
      labels = @($Labels | ForEach-Object { @{ name = $_.name } })
      body   = $PrBody
    }
  } | ConvertTo-Json -Depth 5

  $tempRoot = [System.IO.Path]::GetTempPath()
  $eventPath = Join-Path $tempRoot "release-signal-event-$SourceId.json"
  $outputPath = Join-Path $tempRoot "release-signal-output-$SourceId.txt"
  $summaryPath = Join-Path $tempRoot "release-signal-summary-$SourceId.md"

  Set-Content -LiteralPath $eventPath -Value $eventPayload -Encoding UTF8
  if (Test-Path -LiteralPath $outputPath) {
    Remove-Item -LiteralPath $outputPath -Force
  }
  if (Test-Path -LiteralPath $summaryPath) {
    Remove-Item -LiteralPath $summaryPath -Force
  }

  Write-Status "Evaluate $SourceId for PR #$PrNumber ($BaseSha...$HeadSha)"
  Write-Status "Trigger: $Trigger"

  $failed = $false
  $checkOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/check-release-signal.ps1 `
    -BaseRef $BaseSha `
    -HeadRef $HeadSha `
    -EventPath $eventPath `
    -OutputPath $outputPath `
    -SummaryPath $summaryPath 2>&1
  $checkExit = $LASTEXITCODE
  foreach ($line in @($checkOutput)) {
    $lineStr = [string]$line
    if ($lineStr -match 'release_signal_candidates=|release_signal_progress=|docs_required=') {
      continue
    }
    if ($lineStr -match 'release_likely=(True|False)') {
      $icon = if ($matches[1] -eq 'True') { "🚀" } else { "💤" }
      Write-Status "$icon Release Likely: $($matches[1])"
      continue
    }
    if ($lineStr -match 'release_reason=(.*)') {
      Write-Status "📝 Reason: $($matches[1])"
      continue
    }

    # Clean up standard status lines from the check script
    if ($lineStr -match '^[⭕⚠️ℹ️✅ ]') {
      Write-Status $lineStr
    }
    else {
      Write-Host $line
    }
  }
  if ($checkExit -ne 0) {
    $failed = $true
  }

  $outputs = Get-OutputMap -OutputPath $outputPath
  $releaseLikely = if ($outputs.ContainsKey('release_likely')) { $outputs['release_likely'] } else { 'unknown' }
  $warningCount = if ($outputs.ContainsKey('warning_count')) { $outputs['warning_count'] } else { 'unknown' }
  $errorCount = if ($outputs.ContainsKey('error_count')) { $outputs['error_count'] } else { 'unknown' }
  $recommendedLabel = if ($outputs.ContainsKey('recommended_release_label')) { $outputs['recommended_release_label'] } else { '(none)' }
  $reason = if ($outputs.ContainsKey('release_reason')) { $outputs['release_reason'] } else { '(missing)' }

  $summaryIcon = if ($releaseLikely -eq 'True') { "🚀" } else { "💤" }
  Write-Status "$summaryIcon Result for PR #$PrNumber release_likely=$releaseLikely warnings=$warningCount errors=$errorCount recommended_label=$recommendedLabel"
  if ($reason -and $reason -ne '(missing)') {
    Write-Status "📝 Reason: $reason"
  }

  if ($outputs.ContainsKey('warnings_joined') -and $outputs['warnings_joined']) {
    $items = @($outputs['warnings_joined'] -split ' \|\| ' | Where-Object { $_ })
    foreach ($item in $items) {
      Write-Status "⚠️ $item"
    }
  }

  if ($outputs.ContainsKey('errors_joined') -and $outputs['errors_joined']) {
    $items = @($outputs['errors_joined'] -split ' \|\| ' | Where-Object { $_ })
    foreach ($item in $items) {
      Write-Status "⭕ $item"
    }
  }

  if ($failed) {
    Write-Status "check-release-signal.ps1 failed for $SourceId (exit=$checkExit)."
  }

  return @{
    Failed  = $failed
    Outputs = $outputs
  }
}

function Get-OpenPrForBranch {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoName,
    [Parameter(Mandatory = $true)]
    [string]$HeadBranch
  )

  $owner = ($RepoName -split '/')[0]
  $prs = Invoke-GhJson -Args @(
    'api',
    "repos/$RepoName/pulls?state=open&head=$owner`:$HeadBranch&per_page=1"
  )

  if (-not @($prs).Count) {
    return $null
  }

  return @($prs)[0]
}

function Test-RemoteBranchExist {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BranchName
  )

  $result = & git ls-remote --exit-code --heads origin "refs/heads/$BranchName" 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0 -or -not $result) {
    return $false
  }

  return $true
}

function Convert-JoinedList {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Outputs,
    [Parameter(Mandatory = $true)]
    [string]$Key
  )

  if (-not $Outputs.ContainsKey($Key) -or -not $Outputs[$Key]) {
    return @()
  }

  return @($Outputs[$Key] -split ' \|\| ' | Where-Object { $_ })
}

function Invoke-UpsertPrComment {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoName,
    [Parameter(Mandatory = $true)]
    [int]$PrNumber,
    [Parameter(Mandatory = $true)]
    [hashtable]$Outputs,
    [Parameter(Mandatory = $true)]
    [bool]$Failed,
    [Parameter(Mandatory = $false)]
    [object[]]$Actions = @()
  )

  $releaseLikely = if ($Outputs.ContainsKey('release_likely')) { $Outputs['release_likely'] } else { 'unknown' }
  $docsRequired = if ($Outputs.ContainsKey('docs_required')) { $Outputs['docs_required'] } else { 'unknown' }
  $releaseReason = if ($Outputs.ContainsKey('release_reason')) { $Outputs['release_reason'] } else { '(missing)' }
  $recommendedLabel = if ($Outputs.ContainsKey('recommended_release_label')) { $Outputs['recommended_release_label'] } else { '(none)' }
  $warnings = Convert-JoinedList -Outputs $Outputs -Key 'warnings_joined'
  $errors = Convert-JoinedList -Outputs $Outputs -Key 'errors_joined'

  $marker = '<!-- release-signal-local-pre-push -->'
  $alertType = if ($Failed) { '[!CAUTION]' } else { '[!TIP]' }
  $statusEmoji = if ($Failed) { '❌' } else { '✔️' }
  $statusText = if ($Failed) { 'FAIL' } else { 'PASS' }

  $rlEmoji = if ($releaseLikely -eq 'true') { '🔥' } else { '❄️' }
  $docsEmoji = if ($docsRequired -eq 'true') { '📚' } else { '✅' }
  $labelEmoji = if ($recommendedLabel -eq 'release:needed') { '🚀' } else { '🏷️' }

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add($marker) | Out-Null
  $lines.Add("> $alertType") | Out-Null
  $lines.Add("> ### $statusEmoji $statusText") | Out-Null
  $lines.Add("> ") | Out-Null
  $lines.Add("> - **Release likely**: ``$releaseLikely`` $rlEmoji") | Out-Null
  $lines.Add("> - **Docs required**: ``$docsRequired`` $docsEmoji") | Out-Null
  $lines.Add("> - **Recommended label**: ``$recommendedLabel`` $labelEmoji") | Out-Null
  $lines.Add("> - **Reason**: $releaseReason") | Out-Null

  if (@($errors).Count) {
    $lines.Add("> ") | Out-Null
    $lines.Add("> #### Errors") | Out-Null
    foreach ($entry in $errors) {
      $lines.Add("> - $entry") | Out-Null
    }
  }

  if (@($warnings).Count) {
    $lines.Add("> ") | Out-Null
    $lines.Add("> #### Warnings") | Out-Null
    foreach ($entry in $warnings) {
      $lines.Add("> - $entry") | Out-Null
    }
  }

  $mergedActions = New-Object System.Collections.Generic.List[string]
  foreach ($a in $Actions) { $mergedActions.Add($a) | Out-Null }

  $comments = Invoke-GhJson -Args @(
    'api',
    "repos/$RepoName/issues/$PrNumber/comments?per_page=100"
  )
  $existing = @($comments | Where-Object {
      $_.body -and $_.body.Contains($marker)
    } | Select-Object -First 1)

  $actionsMetadataMarker = '<!-- release-signal-actions: '
  if (@($existing).Count) {
    $existingBody = [string]$existing[0].body
    if ($existingBody -match "(?s)$([regex]::Escape($actionsMetadataMarker))(?<json>.*?) -->") {
      try {
        $prevActions = $Matches['json'] | ConvertFrom-Json
        foreach ($pa in @($prevActions)) {
          if (-not $mergedActions.Contains($pa)) {
            $mergedActions.Add($pa) | Out-Null
          }
        }
      }
      catch {
        Write-Status "Failed to parse previous actions metadata: $($_.Exception.Message)"
      }
    }
  }

  if ($mergedActions.Count) {
    $lines.Add("> ") | Out-Null
    $lines.Add("> #### ☑️ Auto-Applied Actions") | Out-Null
    foreach ($action in $mergedActions) {
      $lines.Add("> - $action") | Out-Null
    }
    # Persist as invisible metadata
    $actionsJson = $mergedActions | ConvertTo-Json -Compress
    $lines.Add("$actionsMetadataMarker$actionsJson -->") | Out-Null
  }

  $body = ($lines -join "`n")

  if (@($existing).Count) {
    if ([string]$existing[0].body -eq $body) {
      Write-Status "No release-signal comment change for PR #$PrNumber."
      return
    }

    [void](Invoke-GhJson -Args @(
        'api',
        '--method',
        'PATCH',
        "repos/$RepoName/issues/comments/$($existing[0].id)",
        '-f',
        "body=$body"
      ))
    Write-Status "Updated local release-signal PR comment for #$PrNumber."
    return
  }

  [void](Invoke-GhJson -Args @(
      'api',
      '--method',
      'POST',
      "repos/$RepoName/issues/$PrNumber/comments",
      '-f',
      "body=$body"
    ))
  Write-Status "Created local release-signal PR comment for #$PrNumber."
}

function Resolve-WatchBranch {
  param(
    [AllowEmptyString()]
    [string]$RequestedBranch
  )

  if ($RequestedBranch) {
    return $RequestedBranch
  }

  return Get-CurrentBranchName
}

function Get-DefaultBaseBranch {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoName
  )

  $repo = Invoke-GhJson -Args @(
    'repo',
    'view',
    $RepoName,
    '--json',
    'defaultBranchRef'
  )
  $base = [string]$repo.defaultBranchRef.name
  if (-not $base) {
    throw "Unable to resolve default base branch for '$RepoName'."
  }

  return $base
}

function New-PullRequestForBranch {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoName,
    [Parameter(Mandatory = $true)]
    [string]$HeadBranch,
    [Parameter(Mandatory = $true)]
    [string]$BaseBranch
  )

  $owner = ($RepoName -split '/')[0]
  $title = "Auto PR: $HeadBranch"
  $body = "Auto-created by `scripts/watch-release-signal.ps1 -Apply` after branch publish."
  return Invoke-GhJson -Args @(
    'api',
    '--method',
    'POST',
    "repos/$RepoName/pulls",
    '-f',
    "title=$title",
    '-f',
    "head=$owner`:$HeadBranch",
    '-f',
    "base=$BaseBranch",
    '-f',
    "body=$body"
  )
}

function Invoke-ReleaseSignalForRun {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoName,
    [Parameter(Mandatory = $true)]
    [pscustomobject]$Run
  )

  $runId = [string]$Run.id
  $eventName = [string]$Run.event
  $headSha = [string]$Run.head_sha
  $prNumber = $null
  if ($Run.pull_requests -and @($Run.pull_requests).Count -gt 0) {
    $prNumber = @($Run.pull_requests)[0].number
  }

  if ($eventName -ne 'pull_request') {
    Write-Status "Skipping run $runId (`"$eventName`"): workflow logic depends on pull_request context."
    return
  }

  if (-not $prNumber) {
    Write-Status "Skipping run $runId no pull request metadata available."
    return
  }

  $pr = Invoke-GhJson -Args @(
    'api',
    "repos/$RepoName/pulls/$prNumber"
  )
  $baseSha = [string]$pr.base.sha
  if (-not $baseSha -or -not $headSha) {
    Write-Status "Skipping run $runId missing base/head SHA."
    return
  }

  $evaluation = Invoke-ReleaseSignalEvaluation `
    -SourceId "run-$runId" `
    -Trigger "completed workflow run id=$runId event=$eventName" `
    -PrNumber ([int]$prNumber) `
    -BaseSha $baseSha `
    -HeadSha $headSha `
    -PrBody ([string]$pr.body) `
    -Labels @($pr.labels)

  $remediationActions = @()
  if ($Apply) {
    $statusState = if ($evaluation['Failed']) { 'failure' } else { 'success' }
    $statusDescription = if ($evaluation['Failed']) { 'Local release-signal failed' } else { 'Local release-signal passed' }
    Update-ReleaseSignalStatusSafe -RepoName $RepoName -Sha $headSha -State $statusState -Description $statusDescription

    try {
      $remediationActions = Invoke-AutoRemediation -RepoName $RepoName -PrNumber ([int]$prNumber) -PrTitle ([string]$pr.title) -Outputs $evaluation['Outputs']
      Invoke-UpsertPrComment -RepoName $RepoName -PrNumber ([int]$prNumber) -Outputs $evaluation['Outputs'] -Failed ([bool]$evaluation['Failed']) -Actions $remediationActions
    }
    catch {
      Write-Status "Auto-apply failed for PR #$prNumber $($_.Exception.Message)"
    }
  }
}

if ($PollSeconds -lt 5) {
  throw 'PollSeconds must be >= 5.'
}
if ($PerPage -lt 1 -or $PerPage -gt 100) {
  throw 'PerPage must be between 1 and 100.'
}

$repoName = Get-RepositoryName -Repo $Repository
$seenKeys = New-Object 'System.Collections.Generic.HashSet[string]'
$watchBranch = Resolve-WatchBranch -RequestedBranch $Branch
$lastWatchBranch = $null

if ($Mode -eq 'current-pr') {
  Write-Status "Watching open PR for branch '$watchBranch' in '$repoName' every $PollSeconds seconds."
}
else {
  Write-Status "Watching workflow '$Workflow' in '$repoName' every $PollSeconds seconds."
}
if ($Apply) {
  Write-Status "Auto-apply mode enabled (labels + release audit sync at '$UnreleasedPath')."
}
Write-Host 'WATCHER_READY'
$global:HasStartedPolling = $false

while ($true) {
  try {
    if ($Mode -eq 'current-pr') {
      $watchBranch = Resolve-WatchBranch -RequestedBranch $Branch
      if ($watchBranch -eq 'main' -or $watchBranch -eq 'master') {
        if ($watchBranch -ne $lastWatchBranch) {
          Write-Status "On '$watchBranch' branch; polling suspended until branch switch."
          $lastWatchBranch = $watchBranch
        }
        if ($Once) {
          break
        }
        Start-Sleep -Seconds $PollSeconds
        continue
      }
      if (-not $watchBranch) {
        Write-Status 'No current branch detected; skipping current-pr poll.'
        if ($Once) {
          break
        }
        Start-Sleep -Seconds $PollSeconds
        continue
      }
      if ($watchBranch -ne $lastWatchBranch) {
        Write-Status "Current branch changed: '$lastWatchBranch' -> '$watchBranch'."
        $lastWatchBranch = $watchBranch
      }

      $pr = Get-OpenPrForBranch -RepoName $repoName -HeadBranch $watchBranch
      if (-not $pr) {
        if ($Apply -and $watchBranch -ne 'main') {
          if (Test-RemoteBranchExist -BranchName $watchBranch) {
            # Wait for manual PR creation while continuing to poll so we stop immediately if a PR appears.
            $delaySeconds = $PollSeconds * 3
            Write-Status "⏳ Waiting up to ${delaySeconds}s for manual PR creation... (polling every ${PollSeconds}s)"
            $deadline = (Get-Date).AddSeconds($delaySeconds)
            while ((Get-Date) -lt $deadline) {
              $currentBranchDuringWait = Resolve-WatchBranch -RequestedBranch $Branch
              if ($currentBranchDuringWait -ne $watchBranch) {
                Write-Status "Branch changed during PR wait: '$watchBranch' -> '$currentBranchDuringWait'. Canceling auto-create for '$watchBranch'."
                $watchBranch = $currentBranchDuringWait
                break
              }

              $pr = Get-OpenPrForBranch -RepoName $repoName -HeadBranch $watchBranch
              if ($pr) {
                break
              }

              $remainingSeconds = [Math]::Max(0, [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds))
              Write-Status "Still waiting for manual PR creation on '$watchBranch' (${remainingSeconds}s remaining)."
              Start-Sleep -Seconds $PollSeconds
            }

            if ($pr) {
              Write-Status "✓ Found manual PR #$($pr.number) for branch '$watchBranch' — using that"
            }
            else {
              try {
                $baseBranch = Get-DefaultBaseBranch -RepoName $repoName
                $createdPr = New-PullRequestForBranch -RepoName $repoName -HeadBranch $watchBranch -BaseBranch $baseBranch
                if ($createdPr -and $createdPr.number) {
                  Write-Status "Auto-apply created PR #$($createdPr.number) for branch '$watchBranch' ($baseBranch <- $watchBranch)."
                  $pr = $createdPr
                }
              }
              catch {
                Write-Status "Auto-apply PR create failed for branch '$watchBranch': $($_.Exception.Message)"
              }
            }
          }
          else {
            Write-Status "No open PR found for branch '$watchBranch' and no origin ref exists yet; waiting for first publish push."
          }
        }
      }

      if (-not $pr) {
        Write-Status "No open PR found for branch '$watchBranch'."
      }
      else {
        $prNumber = [int]$pr.number
        $baseSha = [string]$pr.base.sha
        $headSha = [string]$pr.head.sha
        $key = "pr-$prNumber-$headSha"
        if ($seenKeys.Add($key)) {
          [object[]]$remediationActions = @()
          if ($Apply) {
            Update-ReleaseSignalStatusSafe -RepoName $repoName -Sha $headSha -State 'pending' -Description 'Local release-signal running'
          }
          $global:HasStartedPolling = $false
          Write-Status "Trigger: new PR head detected for #$prNumber (head=$headSha)."
          $evaluation = Invoke-ReleaseSignalEvaluation `
            -SourceId "pr-$prNumber-$headSha" `
            -Trigger "new PR head SHA detected ($headSha)" `
            -PrNumber $prNumber `
            -BaseSha $baseSha `
            -HeadSha $headSha `
            -PrBody ([string]$pr.body) `
            -Labels @($pr.labels)

          if ($Apply) {
            try {
              $remediationActions = Invoke-AutoRemediation -RepoName $repoName -PrNumber $prNumber -PrTitle ([string]$pr.title) -Outputs $evaluation['Outputs'] -BaseSha $baseSha -HeadSha $headSha

              # Remediation already handled by Invoke-AutoRemediation

              # If we performed remediations that don't trigger a new commit (like PR body fixes),
              # we should re-evaluate to see if we now pass.
              if ($evaluation['Failed'] -and @($remediationActions).Count -gt 0) {
                # Fetch fresh PR metadata in case body changed
                $pr = Invoke-GhJson -Args @('api', "repos/$repoName/pulls/$prNumber")
                $evaluation = Invoke-ReleaseSignalEvaluation `
                  -SourceId "pr-$prNumber-$headSha-retry" `
                  -Trigger "re-evaluating after auto-remediation" `
                  -PrNumber $prNumber `
                  -BaseSha $baseSha `
                  -HeadSha $headSha `
                  -PrBody ([string]$pr.body) `
                  -Labels @($pr.labels) `
                  -Actions $remediationActions
              }

              $statusState = if ($evaluation['Failed']) { 'failure' } else { 'success' }
              $statusDescription = if ($evaluation['Failed']) { 'Local release-signal failed' } else { 'Local release-signal passed' }
              Update-ReleaseSignalStatusSafe -RepoName $repoName -Sha $headSha -State $statusState -Description $statusDescription

              Invoke-UpsertPrComment -RepoName $repoName -PrNumber $prNumber -Outputs $evaluation['Outputs'] -Failed ([bool]$evaluation['Failed']) -Actions $remediationActions
            }
            catch {
              Write-Status "Auto-apply failed for PR #$prNumber $($_.Exception.Message)"
            }
          }
        }
      }
    }
    else {
      $runsResponse = Invoke-GhJson -Args @(
        'api',
        "repos/$repoName/actions/workflows/$Workflow/runs?per_page=$PerPage"
      )

      $runs = @($runsResponse.workflow_runs | Sort-Object created_at)
      foreach ($run in $runs) {
        $runId = [string]$run.id
        if (-not $runId) {
          continue
        }
        if (-not $seenKeys.Add("run-$runId")) {
          continue
        }
        if ([string]$run.status -ne 'completed') {
          continue
        }
        $global:HasStartedPolling = $false
        Invoke-ReleaseSignalForRun -RepoName $repoName -Run $run
      }
    }
  }
  catch {
    Write-Status "Watcher polling failed: $($_.Exception.Message)"
  }

  if ($Once) {
    break
  }

  if (-not $global:HasStartedPolling) {
    Write-Status "Watching for changes (polling every $($PollSeconds)s)"
    $global:HasStartedPolling = $true
  }
  Write-Host "." -NoNewline -ForegroundColor Gray
  Start-Sleep -Seconds $PollSeconds
}
