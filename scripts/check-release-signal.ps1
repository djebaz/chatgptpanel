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
  if ($null -eq $property) {
    return $Default
  }

  if ($null -eq $property.Value) {
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

function Read-ReleaseSignalConfig {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Release signal config not found: $Path"
  }

  $config = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
  if (-not (Get-ConfigValue -Object $config -Name 'version')) {
    throw "Release signal config is missing required field: version"
  }
  if (-not (Get-ConfigValue -Object $config -Name 'project')) {
    throw "Release signal config is missing required field: project"
  }

  return $config
}

function Invoke-Git {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Args
  )

  $result = & git @Args 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "git $($Args -join ' ') failed ($exitCode): $($result -join [Environment]::NewLine)"
  }

  return ($result -join "`n")
}

function Test-StringEquals {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Left,
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Right
  )

  return [string]::Equals($Left, $Right, [StringComparison]::Ordinal)
}

function Test-StringStartsWith {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Text,
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Prefix
  )

  return $Text.StartsWith($Prefix, [StringComparison]::Ordinal)
}

function Test-StringContains {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Text,
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Token
  )

  if ($Token.Length -eq 0) {
    return $false
  }

  return $Text.Contains($Token, [StringComparison]::Ordinal)
}

function Test-ContainsAnyToken {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Text,
    [Parameter(Mandatory = $false)]
    [AllowEmptyCollection()]
    [object[]]$Tokens = @()
  )

  foreach ($token in (Get-ConfigArray $Tokens)) {
    if (Test-StringContains -Text $Text -Token ([string]$token)) {
      return $true
    }
  }

  return $false
}

function Test-FileListMatch {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $false)]
    [AllowEmptyCollection()]
    [object[]]$Files = @()
  )

  foreach ($file in (Get-ConfigArray $Files)) {
    if (Test-StringEquals -Left $FilePath -Right ([string]$file)) {
      return $true
    }
  }

  return $false
}

function Test-PathPrefixMatch {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $false)]
    [AllowEmptyCollection()]
    [object[]]$PathPrefixes = @()
  )

  foreach ($prefix in (Get-ConfigArray $PathPrefixes)) {
    if (Test-StringStartsWith -Text $FilePath -Prefix ([string]$prefix)) {
      return $true
    }
  }

  return $false
}

function Test-LowSignalFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [object]$Config
  )

  $lowSignal = Get-ConfigValue -Object $Config -Name 'lowSignal'
  $exactFiles = Get-ConfigArray (Get-ConfigValue -Object $lowSignal -Name 'exactFiles')
  $pathPrefixes = Get-ConfigArray (Get-ConfigValue -Object $lowSignal -Name 'pathPrefixes')

  return (Test-FileListMatch -FilePath $FilePath -Files $exactFiles) -or
  (Test-PathPrefixMatch -FilePath $FilePath -PathPrefixes $pathPrefixes)
}

function Test-HighSignalRuleMatch {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [object]$Rule
  )

  $file = Get-ConfigValue -Object $Rule -Name 'file'
  if ($file -and (Test-StringEquals -Left $FilePath -Right ([string]$file))) {
    return $true
  }

  $files = Get-ConfigArray (Get-ConfigValue -Object $Rule -Name 'files')
  if (Test-FileListMatch -FilePath $FilePath -Files $files) {
    return $true
  }

  $pathPrefixes = Get-ConfigArray (Get-ConfigValue -Object $Rule -Name 'pathPrefixes')
  if (Test-PathPrefixMatch -FilePath $FilePath -PathPrefixes $pathPrefixes) {
    return $true
  }

  return $false
}

function Get-ChangedLines {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Patch
  )

  $added = New-Object System.Collections.Generic.List[string]
  $removed = New-Object System.Collections.Generic.List[string]

  foreach ($line in ($Patch -split "`r?`n")) {
    if ($line.StartsWith('+++') -or $line.StartsWith('---') -or $line.StartsWith('@@')) {
      continue
    }

    if ($line.StartsWith('+')) {
      $added.Add($line.Substring(1))
      continue
    }

    if ($line.StartsWith('-')) {
      $removed.Add($line.Substring(1))
    }
  }

  return @{
    Added   = @($added)
    Removed = @($removed)
    All     = @($added + $removed)
  }
}

function Get-ChangedFilePatches {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Patch
  )

  $patches = @{}
  $currentFile = $null
  $buffer = New-Object System.Collections.Generic.List[string]

  foreach ($line in ($Patch -split "`r?`n")) {
    if ($line.StartsWith('diff --git ')) {
      if ($currentFile) {
        $patches[$currentFile] = $buffer -join "`n"
      }
      $currentFile = $null
      $buffer = New-Object System.Collections.Generic.List[string]
    }

    $buffer.Add($line) | Out-Null

    if ($line.StartsWith('+++ b/')) {
      $currentFile = $line.Substring(6)
    }
  }

  if ($currentFile) {
    $patches[$currentFile] = $buffer -join "`n"
  }

  return $patches
}

function Test-PunctuationOnlyLine {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Line,
    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string]$AllowedChars = '{}[](),;'
  )

  $trimmed = $Line.Trim()
  if ($trimmed.Length -eq 0) {
    return $false
  }

  foreach ($char in $trimmed.ToCharArray()) {
    if ($AllowedChars.IndexOf($char) -lt 0) {
      return $false
    }
  }

  return $true
}

function Get-NonTrivialLines {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [AllowEmptyString()]
    [string[]]$Lines,
    [Parameter(Mandatory = $true)]
    [object]$Config
  )

  $lineConfig = Get-ConfigValue -Object $Config -Name 'nonTrivialLines'
  $lineCommentPrefixes = Get-ConfigArray (Get-ConfigValue -Object $lineConfig -Name 'lineCommentPrefixes')
  $blockCommentPrefixes = Get-ConfigArray (Get-ConfigValue -Object $lineConfig -Name 'blockCommentPrefixes')
  $punctuationOnlyChars = [string](Get-ConfigValue -Object $lineConfig -Name 'punctuationOnlyChars' -Default '{}[](),;')
  $ignoredPrefixes = @($lineCommentPrefixes + $blockCommentPrefixes)

  return @(
    foreach ($line in $Lines) {
      $trimmed = $line.Trim()
      if ($trimmed.Length -eq 0) {
        continue
      }

      $isComment = $false
      foreach ($prefix in $ignoredPrefixes) {
        if ($trimmed.StartsWith([string]$prefix, [StringComparison]::Ordinal)) {
          $isComment = $true
          break
        }
      }
      if ($isComment) {
        continue
      }

      if (Test-PunctuationOnlyLine -Line $line -AllowedChars $punctuationOnlyChars) {
        continue
      }

      $line
    }
  )
}

function Get-NormalizedSet {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [AllowEmptyString()]
    [string[]]$Values
  )

  return @(
    $Values |
    ForEach-Object { ([string]$_).Trim() } |
    Where-Object { $_ } |
    Sort-Object -Unique
  )
}

function Get-CssPropertyName {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Line
  )

  $trimmed = $Line.Trim()
  $colonIndex = $trimmed.IndexOf(':')
  if ($colonIndex -le 0) {
    return ''
  }

  $candidate = $trimmed.Substring(0, $colonIndex).Trim()
  if ($candidate -notmatch '^[A-Za-z-]+$') {
    return ''
  }

  return $candidate
}

function Test-CssPropertyFamilyMatch {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$PropertyName,
    [Parameter(Mandatory = $false)]
    [AllowEmptyCollection()]
    [object[]]$Families = @()
  )

  if ($PropertyName.Length -eq 0) {
    return $false
  }

  foreach ($family in (Get-ConfigArray $Families)) {
    $familyName = [string]$family
    if ((Test-StringEquals -Left $PropertyName -Right $familyName) -or
      $PropertyName.StartsWith("$familyName-", [StringComparison]::Ordinal)) {
      return $true
    }
  }

  return $false
}

function Test-CssUserFacingLine {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Line,
    [Parameter(Mandatory = $true)]
    [object]$Rule
  )

  $selectors = Get-ConfigArray (Get-ConfigValue -Object $Rule -Name 'userFacingSelectors')
  if (Test-ContainsAnyToken -Text $Line -Tokens $selectors) {
    return $true
  }

  $propertyName = Get-CssPropertyName -Line $Line
  $properties = Get-ConfigArray (Get-ConfigValue -Object $Rule -Name 'userFacingProperties')
  return Test-CssPropertyFamilyMatch -PropertyName $propertyName -Families $properties
}

function Test-CssCleanupOnlyLine {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Line,
    [Parameter(Mandatory = $true)]
    [object]$Rule
  )

  $trimmed = $Line.Trim()
  if ($trimmed.StartsWith('--', [StringComparison]::Ordinal) -and $trimmed.Contains(':', [StringComparison]::Ordinal)) {
    return $true
  }

  if (-not $trimmed.Contains('var(--', [StringComparison]::Ordinal)) {
    return $false
  }

  $propertyName = Get-CssPropertyName -Line $Line
  if ($propertyName.Length -eq 0) {
    return $true
  }

  $cleanupFamilies = Get-ConfigArray (Get-ConfigValue -Object $Rule -Name 'cleanupPropertiesUsingCssVariable')
  return Test-CssPropertyFamilyMatch -PropertyName $propertyName -Families $cleanupFamilies
}

function Test-JsActionName {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Text,
    [Parameter(Mandatory = $true)]
    [string]$ActionName
  )

  $escaped = [regex]::Escape($ActionName)
  $pattern = 'action\s*:\s*[''\"]' + $escaped + '[''\"]'
  return $Text -match $pattern
}

function Test-JsFunctionNamePrefix {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Text,
    [Parameter(Mandatory = $true)]
    [string]$Prefix
  )

  $escaped = [regex]::Escape($Prefix)
  return $Text -match ("\bfunction\s+$escaped")
}

function Test-TokenAnyVsTokenAllRule {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$NonTrivialLines,
    [Parameter(Mandatory = $true)]
    [object]$Rule
  )

  $text = $NonTrivialLines -join "`n"
  $userFacingTokens = Get-ConfigArray (Get-ConfigValue -Object $Rule -Name 'userFacingTokens')
  $helperOnlyTokens = Get-ConfigArray (Get-ConfigValue -Object $Rule -Name 'helperOnlyTokens')
  $jsActionNames = Get-ConfigArray (Get-ConfigValue -Object $Rule -Name 'jsActionNames')

  $isUserFacing = Test-ContainsAnyToken -Text $text -Tokens $userFacingTokens
  if (-not $isUserFacing) {
    foreach ($actionName in $jsActionNames) {
      if (Test-JsActionName -Text $text -ActionName ([string]$actionName)) {
        $isUserFacing = $true
        break
      }
    }
  }

  $isHelperOnly = $false
  if (-not $isUserFacing -and @($NonTrivialLines).Count -gt 0) {
    $nonHelperLines = @($NonTrivialLines | Where-Object {
        -not (Test-ContainsAnyToken -Text $_ -Tokens $helperOnlyTokens)
      })
    $isHelperOnly = @($nonHelperLines).Count -eq 0
  }

  if ($isUserFacing) {
    return @{
      ReleaseLikely = $true
      Reason        = [string](Get-ConfigValue -Object $Rule -Name 'userFacingReason')
      UserFacing    = [bool](Get-ConfigValue -Object $Rule -Name 'userFacing' -Default $true)
    }
  }

  if ($isHelperOnly) {
    return @{
      ReleaseLikely = $false
      Reason        = [string](Get-ConfigValue -Object $Rule -Name 'helperOnlyReason')
      UserFacing    = [bool](Get-ConfigValue -Object $Rule -Name 'userFacing' -Default $true)
    }
  }

  return @{
    ReleaseLikely = $true
    Reason        = [string](Get-ConfigValue -Object $Rule -Name 'ambiguousReason')
    UserFacing    = [bool](Get-ConfigValue -Object $Rule -Name 'userFacing' -Default $true)
  }
}

function Test-CssVisibleVsCleanupRule {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$NonTrivialLines,
    [Parameter(Mandatory = $true)]
    [object]$Rule
  )

  $isUserFacing = @($NonTrivialLines | Where-Object { Test-CssUserFacingLine -Line $_ -Rule $Rule }).Count -gt 0
  $isCleanupOnly = $false

  if (-not $isUserFacing -and @($NonTrivialLines).Count -gt 0) {
    $nonCleanupLines = @($NonTrivialLines | Where-Object { -not (Test-CssCleanupOnlyLine -Line $_ -Rule $Rule) })
    $isCleanupOnly = @($nonCleanupLines).Count -eq 0
  }

  if ($isUserFacing) {
    return @{
      ReleaseLikely = $true
      Reason        = [string](Get-ConfigValue -Object $Rule -Name 'userFacingReason')
      UserFacing    = [bool](Get-ConfigValue -Object $Rule -Name 'userFacing' -Default $true)
    }
  }

  if ($isCleanupOnly) {
    return @{
      ReleaseLikely = $false
      Reason        = [string](Get-ConfigValue -Object $Rule -Name 'cleanupOnlyReason')
      UserFacing    = [bool](Get-ConfigValue -Object $Rule -Name 'userFacing' -Default $true)
    }
  }

  return @{
    ReleaseLikely = $true
    Reason        = [string](Get-ConfigValue -Object $Rule -Name 'ambiguousReason')
    UserFacing    = [bool](Get-ConfigValue -Object $Rule -Name 'userFacing' -Default $true)
  }
}

function Get-SelectorKeyAlternation {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$SelectorKeys
  )

  $escapedKeys = @($SelectorKeys | ForEach-Object { [regex]::Escape([string]$_) })
  if (-not $escapedKeys.Count) {
    throw 'metadata_selector rule requires selectorKeys.'
  }

  return ($escapedKeys -join '|')
}

function Test-SelectorFormatLine {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Line,
    [Parameter(Mandatory = $true)]
    [string]$KeyAlternation
  )

  $patterns = @(
    '^\s*(' + $KeyAlternation + '):\s*\[$',
    '^\s*(' + $KeyAlternation + '):\s*[''\"].*[''\"]\.join\('',''\),?$',
    '^\s*[''\"].*[''\"],?$',
    '^\s*\]\.join\('',''\),?$',
    '^\s*[\[\]],?$'
  )

  foreach ($pattern in $patterns) {
    if ($Line -match $pattern) {
      return $true
    }
  }

  return $false
}

function Get-SelectorPropertyKeysFromLines {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [AllowEmptyString()]
    [string[]]$Lines,
    [Parameter(Mandatory = $true)]
    [string]$KeyAlternation
  )

  $pattern = '^\s*(?<key>' + $KeyAlternation + '):'

  return @(
    foreach ($line in $Lines) {
      $match = [regex]::Match($line, $pattern)
      if ($match.Success) {
        $match.Groups['key'].Value
      }
    }
  )
}

function Get-SelectorLiteralValuesFromLines {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [AllowEmptyString()]
    [string[]]$Lines,
    [Parameter(Mandatory = $true)]
    [string]$KeyAlternation
  )

  $standalonePattern = '^[''\"](?<value>.*?)[''\"],?$'
  $joinedPattern = '^(' + $KeyAlternation + '):\s*[''\"](?<value>.*?)[''\"]\.join\('',''\),?$'

  return @(
    foreach ($line in $Lines) {
      $trimmed = $line.Trim()

      $standalone = [regex]::Match($trimmed, $standalonePattern)
      if ($standalone.Success) {
        $standalone.Groups['value'].Value
        continue
      }

      $joined = [regex]::Match($trimmed, $joinedPattern)
      if ($joined.Success) {
        $joined.Groups['value'].Value
      }
    }
  )
}

function Test-SelectorFormattingOnlyChange {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Changed,
    [Parameter(Mandatory = $true)]
    [object]$Rule
  )

  $selectorKeys = Get-ConfigArray (Get-ConfigValue -Object $Rule -Name 'selectorKeys')
  $keyAlternation = Get-SelectorKeyAlternation -SelectorKeys $selectorKeys
  $allLines = @($Changed.All)
  if (-not @($allLines).Count) {
    return $false
  }

  foreach ($line in $allLines) {
    if (-not (Test-SelectorFormatLine -Line $line -KeyAlternation $keyAlternation)) {
      return $false
    }
  }

  $addedLiterals = Get-NormalizedSet -Values (Get-SelectorLiteralValuesFromLines -Lines @($Changed.Added) -KeyAlternation $keyAlternation)
  $removedLiterals = Get-NormalizedSet -Values (Get-SelectorLiteralValuesFromLines -Lines @($Changed.Removed) -KeyAlternation $keyAlternation)
  $addedKeys = Get-NormalizedSet -Values (Get-SelectorPropertyKeysFromLines -Lines @($Changed.Added) -KeyAlternation $keyAlternation)
  $removedKeys = Get-NormalizedSet -Values (Get-SelectorPropertyKeysFromLines -Lines @($Changed.Removed) -KeyAlternation $keyAlternation)

  return (@($addedLiterals) -join "`n") -eq (@($removedLiterals) -join "`n") -and
  (@($addedKeys) -join "`n") -eq (@($removedKeys) -join "`n")
}

function Test-MetadataSelectorRule {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Changed,
    [Parameter(Mandatory = $true)]
    [string[]]$NonTrivialLines,
    [Parameter(Mandatory = $true)]
    [object]$Rule
  )

  if (Test-SelectorFormattingOnlyChange -Changed $Changed -Rule $Rule) {
    return @{
      ReleaseLikely = $false
      Reason        = [string](Get-ConfigValue -Object $Rule -Name 'formatOnlyReason')
      UserFacing    = $false
    }
  }

  $text = $NonTrivialLines -join "`n"
  $metadataTokens = Get-ConfigArray (Get-ConfigValue -Object $Rule -Name 'metadataTokens')
  $metadataFunctionPrefixes = Get-ConfigArray (Get-ConfigValue -Object $Rule -Name 'metadataFunctionPrefixes')
  $hasMetadataSignal = Test-ContainsAnyToken -Text $text -Tokens $metadataTokens

  if (-not $hasMetadataSignal) {
    foreach ($prefix in $metadataFunctionPrefixes) {
      if (Test-JsFunctionNamePrefix -Text $text -Prefix ([string]$prefix)) {
        $hasMetadataSignal = $true
        break
      }
    }
  }

  return @{
    ReleaseLikely = $true
    Reason        = if ($hasMetadataSignal) {
      [string](Get-ConfigValue -Object $Rule -Name 'metadataReason')
    }
    else {
      [string](Get-ConfigValue -Object $Rule -Name 'ambiguousReason')
    }
    UserFacing    = [bool](Get-ConfigValue -Object $Rule -Name 'userFacing' -Default $true)
  }
}

function Get-ReleaseClassification {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [hashtable]$Changed,
    [Parameter(Mandatory = $true)]
    [object]$Config
  )

  $nonTrivial = @(Get-NonTrivialLines -Lines $Changed.All -Config $Config)
  if (-not @($nonTrivial).Count) {
    return @{
      ReleaseLikely = $false
      Reason        = "$FilePath only changes comments, whitespace, or punctuation-only lines."
      UserFacing    = $false
    }
  }

  foreach ($rule in (Get-ConfigArray (Get-ConfigValue -Object $Config -Name 'highSignal'))) {
    if (Test-HighSignalRuleMatch -FilePath $FilePath -Rule $rule) {
      return @{
        ReleaseLikely = $true
        Reason        = "$FilePath $([string](Get-ConfigValue -Object $rule -Name 'reason'))"
        UserFacing    = [bool](Get-ConfigValue -Object $rule -Name 'userFacing' -Default $true)
      }
    }
  }

  foreach ($rule in (Get-ConfigArray (Get-ConfigValue -Object $Config -Name 'conditionalFiles'))) {
    $ruleFile = Get-ConfigValue -Object $rule -Name 'file'
    if (-not $ruleFile -or -not (Test-StringEquals -Left $FilePath -Right ([string]$ruleFile))) {
      continue
    }

    $type = [string](Get-ConfigValue -Object $rule -Name 'type')
    switch ($type) {
      'token_any_vs_token_all' {
        $classification = Test-TokenAnyVsTokenAllRule -NonTrivialLines $nonTrivial -Rule $rule
      }
      'css_visible_vs_cleanup' {
        $classification = Test-CssVisibleVsCleanupRule -NonTrivialLines $nonTrivial -Rule $rule
      }
      'metadata_selector' {
        $classification = Test-MetadataSelectorRule -Changed $Changed -NonTrivialLines $nonTrivial -Rule $rule
      }
      default {
        throw "Unsupported release-signal conditional rule type '$type' for file '$FilePath'."
      }
    }

    $classification.Reason = "$FilePath $($classification.Reason)"
    return $classification
  }

  return @{
    ReleaseLikely = $false
    Reason        = "$FilePath is outside the high-signal release rules."
    UserFacing    = $false
  }
}

function Write-OutputValue {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Value
  )

  if ($OutputPath) {
    Add-Content -LiteralPath $OutputPath -Value "$Name=$Value"
  }
}

function Add-SummaryLine {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Line
  )

  if ($SummaryPath) {
    Add-Content -LiteralPath $SummaryPath -Value $Line
  }
}

function Get-ReleaseAuditMetadata {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Text
  )

  $prsMatch = [regex]::Match($Text, '(?m)^- PRs:\s*(.+?)\r?$')
  $scopeMatch = [regex]::Match($Text, '(?m)^- Scope:\s*(.+?)\r?$')

  return @{
    HasParsablePrs = $prsMatch.Success
    Prs            = @([regex]::Matches($prsMatch.Groups[1].Value, '#\d+') | ForEach-Object { $_.Value }) | Sort-Object -Unique
    Scope          = if ($scopeMatch.Success) { $scopeMatch.Groups[1].Value.Trim() } else { '' }
  }
}

function Convert-ToSingleLineList {
  param(
    [Parameter(Mandatory = $false)]
    [AllowEmptyCollection()]
    [AllowEmptyString()]
    [string[]]$Items = @()
  )

  return (@($Items) | ForEach-Object { ($_ -replace '\r?\n', ' ').Trim() } | Where-Object { $_ }) -join ' || '
}

$config = Read-ReleaseSignalConfig -Path $ConfigPath
$labelsConfig = Get-ConfigValue -Object $config -Name 'labels'
$releaseNeededLabel = [string](Get-ConfigValue -Object $labelsConfig -Name 'releaseNeeded' -Default 'release:needed')
$releaseNoneLabel = [string](Get-ConfigValue -Object $labelsConfig -Name 'releaseNone' -Default 'release:none')
$docsPolicy = Get-ConfigValue -Object $config -Name 'docsPolicy'
$unreleasedFile = [string](Get-ConfigValue -Object $docsPolicy -Name 'unreleasedFile' -Default 'devdocs/releases/unreleased.md')
$readmeFile = [string](Get-ConfigValue -Object $docsPolicy -Name 'readmeFile' -Default 'README.md')
$agentsFile = [string](Get-ConfigValue -Object $docsPolicy -Name 'agentsFile' -Default 'AGENTS.md')
$workflowPathPrefixes = Get-ConfigArray (Get-ConfigValue -Object $docsPolicy -Name 'workflowPathPrefixes')

$eventcheck = $null
$labels = @()
$currentPrNumber = $null
$prBody = $null
if ($eventPath -and (Test-Path -LiteralPath $eventPath)) {
  $eventcheck = Get-Content -Raw -LiteralPath $eventPath | ConvertFrom-Json
  if (Get-ConfigValue -Object (Get-ConfigValue -Object $eventcheck -Name 'pull_request') -Name 'number') {
    $currentPrNumber = [int]$eventcheck.pull_request.number
  }
  if (Get-ConfigValue -Object (Get-ConfigValue -Object $eventcheck -Name 'pull_request') -Name 'labels') {
    $labels = @($eventcheck.pull_request.labels | ForEach-Object { $_.name })
  }
  if ($null -ne (Get-ConfigValue -Object (Get-ConfigValue -Object $eventcheck -Name 'pull_request') -Name 'body')) {
    $prBody = [string]$eventcheck.pull_request.body
  }
}

$hasReleaseNeeded = $labels -contains $releaseNeededLabel
$hasReleaseNone = $labels -contains $releaseNoneLabel
$hasReleaseLabel = $hasReleaseNeeded -or $hasReleaseNone

$diffRange = "$BaseRef...$HeadRef"
$changedFilesRaw = Invoke-Git -Args @('diff', '--name-only', '--diff-filter=ACMR', $diffRange)
$changedFiles = @($changedFilesRaw -split "`r?`n" | Where-Object { $_ })
$fullPatch = Invoke-Git -Args @('diff', '--unified=0', '--no-color', '--diff-filter=ACMR', $diffRange)
$patchByFile = Get-ChangedFilePatches -Patch $fullPatch

$releaseReasons = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$errors = New-Object System.Collections.Generic.List[string]
$userFacingHighSignalTouched = $false
$highSignalTouched = $false
$candidateFiles = @($changedFiles | Where-Object { -not (Test-LowSignalFile -FilePath $_ -Config $config) })
$progressEvery = 25
$processedCount = 0

Write-Host "release_signal_candidates=$($candidateFiles.Count)"

foreach ($filePath in $candidateFiles) {
  $patch = if ($patchByFile.ContainsKey($filePath)) { $patchByFile[$filePath] } else { '' }
  $changed = Get-ChangedLines -Patch $patch
  $classification = Get-ReleaseClassification -FilePath $filePath -Changed $changed -Config $config
  $processedCount++

  if (($processedCount % $progressEvery) -eq 0 -or $processedCount -eq $candidateFiles.Count) {
    Write-Host "release_signal_progress=$processedCount/$($candidateFiles.Count)"
  }

  if ($classification.ReleaseLikely) {
    $highSignalTouched = $true
    if ($classification.UserFacing) {
      $userFacingHighSignalTouched = $true
    }
    $releaseReasons.Add($classification.Reason) | Out-Null
  }
}

$releaseLikely = $highSignalTouched -or $hasReleaseNeeded
$docsRequired = $true

$hasUnreleasedUpdate = $changedFiles -contains $unreleasedFile
$hasReadmeUpdate = $changedFiles -contains $readmeFile
$hasAgentsUpdate = $changedFiles -contains $agentsFile
$workflowTouched = @($changedFiles | Where-Object { Test-PathPrefixMatch -FilePath $_ -PathPrefixes $workflowPathPrefixes }).Count -gt 0

if ($releaseLikely -and -not $hasReleaseLabel) {
  $warnings.Add(('⚠️High-signal shipped-code changes were detected without an explicit `{0}` or `{1}` label.' -f $releaseNeededLabel, $releaseNoneLabel)) | Out-Null
}

if ($highSignalTouched -and $hasReleaseNone) {
  $warnings.Add(('⚠️`{0}` overrides the release-signal heuristic for this PR. Confirm that this runtime/UI change really should not increase release pressure.' -f $releaseNoneLabel)) | Out-Null
}

if ($prBody -and $prBody -match '\\n') {
  $errors.Add('⭕PR body contains literal `\n` sequences. Use real line breaks (or `gh pr create/edit --body-file`) instead of escaped newline text.') | Out-Null
}

if (-not $hasUnreleasedUpdate) {
  $warnings.Add(('⚠️Every PR should update `{0}` before merge. Add or adjust the relevant unreleased bullet if needed, and always update the `Release audit` footer with this PR number and the current unreleased scope.' -f $unreleasedFile)) | Out-Null
}
else {
  $unreleasedText = Get-Content -Raw -LiteralPath $unreleasedFile
  $releaseAuditPattern = '(?s)## Release audit\r?\n\r?\n- PRs:\s*.+\r?\n- Scope:\s*.+\s*$'
  if ($unreleasedText -notmatch $releaseAuditPattern) {
    $errors.Add(('⭕`{0}` must end with a `Release audit` footer containing exactly two bullets: `PRs:` and `Scope:`.' -f $unreleasedFile)) | Out-Null
  }
  else {
    $releaseAudit = Get-ReleaseAuditMetadata -Text $unreleasedText
    if (-not $releaseAudit.HasParsablePrs) {
      $errors.Add(('⭕`{0}` is missing a parseable `Release audit` `PRs:` line. Add a line like `- PRs: #95, #96`.' -f $unreleasedFile)) | Out-Null
    }
    else {
      $listedPrs = $releaseAudit.Prs
      if (-not @($listedPrs).Count) {
        $errors.Add(('⭕`{0}` must list at least one PR number in `Release audit` `PRs:`. Add comma-separated entries like `#95, #96`.' -f $unreleasedFile)) | Out-Null
      }
      if ($currentPrNumber -and ($listedPrs -notcontains "#$currentPrNumber")) {
        $errors.Add(('⭕ `{0}` must list the current PR number `#{1}` in `Release audit` `PRs:`. Add `#{1}` to that comma-separated list.' -f $unreleasedFile, $currentPrNumber)) | Out-Null
      }
      if ($currentPrNumber) {
        try {
          $baseUnreleasedText = Invoke-Git -Args @('show', "$BaseRef`:$unreleasedFile")
          $baseReleaseAudit = Get-ReleaseAuditMetadata -Text $baseUnreleasedText
          $currentPrToken = "#$currentPrNumber"
          $prWasAddedToAudit = ($listedPrs -contains $currentPrToken) -and ($baseReleaseAudit.Prs -notcontains $currentPrToken)
          if ($prWasAddedToAudit -and $baseReleaseAudit.Scope -eq $releaseAudit.Scope) {
            $errors.Add(('⭕ `{0}` adds `#{1}` to `Release audit` `PRs:` but does not update the cumulative `Scope:` summary.' -f $unreleasedFile, $currentPrNumber)) | Out-Null
          }
        }
        catch {
          $warnings.Add('⚠️Unable to compare the base `Release audit` footer while validating the cumulative `Scope:` summary. Verify that `Scope:` reflects the full unreleased PR set.') | Out-Null
        }
      }
    }
  }
}

if ($hasReleaseNeeded -and -not $highSignalTouched) {
  $warnings.Add(('⚠️`{0}` is set even though the heuristic did not classify the diff as high-signal shipped behavior. Verify that the label is intentional or switch to `{1}`.' -f $releaseNeededLabel, $releaseNoneLabel)) | Out-Null
}

if (-not $hasReleaseLabel) {
  $recommendedLabel = if ($releaseLikely) { $releaseNeededLabel } else { $releaseNoneLabel }
  $warnings.Add(('⚠️Every PR should carry either `{0}` or `{1}` so release pressure is explicit; CI auto-applies the inferred label `{2}` until a maintainer confirms or changes it.' -f $releaseNeededLabel, $releaseNoneLabel, $recommendedLabel)) | Out-Null
}

if ($hasReleaseNeeded) {
  $unreleasedText = if (Test-Path -LiteralPath $unreleasedFile) { Get-Content -Raw -LiteralPath $unreleasedFile } else { '' }
  $userFacingBulletPattern = '(?s)## Highlights\r?\n.*?-\s.+|## Fixes & Improvements\r?\n.*?-\s.+|## Security / CI\r?\n.*?-\s.+|## Tests\r?\n.*?-\s+'
  if ($unreleasedText -notmatch $userFacingBulletPattern) {
    $warnings.Add(('⚠️`{0}` PRs should add at least one unreleased bullet outside the `Release audit` footer so the user-facing change is represented in the note.' -f $releaseNeededLabel)) | Out-Null
  }
}

if ($userFacingHighSignalTouched -and -not $hasReadmeUpdate) {
  $warnings.Add(('⚠️User-facing runtime or popup changes were detected without a matching `{0}` update. Update the README if install, usage, supported behavior, or UI expectations changed.' -f $readmeFile)) | Out-Null
}

if ($workflowTouched -and -not $hasAgentsUpdate) {
  $warnings.Add(('⚠️Workflow changes were detected without an `{0}` update describing the new automation surface. Update AGENTS when maintainer workflow or automation expectations changed.' -f $agentsFile)) | Out-Null
}

$releaseReasonText = if ($releaseReasons.Count) {
  ($releaseReasons | Sort-Object -Unique) -join ' | '
}
elseif ($hasReleaseNeeded) {
  ('The PR is explicitly labeled `{0}`.' -f $releaseNeededLabel)
}
else {
  "Low priority changes, won't trigger a release."
}

Write-Host "release_likely=$releaseLikely"
Write-Host "docs_required=$docsRequired"
Write-Host "release_reason=$releaseReasonText"

Write-OutputValue -Name 'release_likely' -Value $releaseLikely.ToString().ToLowerInvariant()
Write-OutputValue -Name 'docs_required' -Value $docsRequired.ToString().ToLowerInvariant()
Write-OutputValue -Name 'warning_count' -Value ([string]$warnings.Count)
Write-OutputValue -Name 'error_count' -Value ([string]$errors.Count)
Write-OutputValue -Name 'release_reason' -Value $releaseReasonText
Write-OutputValue -Name 'has_release_label' -Value $hasReleaseLabel.ToString().ToLowerInvariant()
Write-OutputValue -Name 'recommended_release_label' -Value $(if ($releaseLikely) { $releaseNeededLabel } else { $releaseNoneLabel })
Write-OutputValue -Name 'warnings_joined' -Value (Convert-ToSingleLineList -Items $warnings)
Write-OutputValue -Name 'errors_joined' -Value (Convert-ToSingleLineList -Items $errors)

if ($SummaryPath) {
  Add-SummaryLine -Line '## Release signal'
  Add-SummaryLine -Line ''
  Add-SummaryLine -Line "- Release likely: $releaseLikely"
  Add-SummaryLine -Line "- Docs required: $docsRequired"
  Add-SummaryLine -Line "- Labels: $(if ($labels.Count) { $labels -join ', ' } else { '(none)' })"
  Add-SummaryLine -Line "- Reason: $releaseReasonText"

  if ($warnings.Count) {
    Add-SummaryLine -Line ''
    Add-SummaryLine -Line '### Warnings'
    foreach ($warning in $warnings) {
      Add-SummaryLine -Line "- $warning"
    }
  }

  if ($errors.Count) {
    Add-SummaryLine -Line ''
    Add-SummaryLine -Line '### Errors'
    foreach ($errorEntry in $errors) {
      Add-SummaryLine -Line "- $errorEntry"
    }
  }
}

foreach ($warning in $warnings) {
  Write-Host "::warning::$warning"
}

foreach ($errorMessage in $errors) {
  Write-Host "::error::$errorMessage"
}

if ($errors.Count -gt 0) {
  throw "Release-signal validation failed with $($errors.Count) error(s)."
}
