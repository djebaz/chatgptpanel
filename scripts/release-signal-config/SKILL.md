---
name: release-signal-config
description: Maintain or install the repo release-signal JSON config, schema, and generic PowerShell evaluator based on repository code.
---

# Release Signal Config Skill

Use this skill when the user asks to create, install, refactor, audit, or update the release-signal system.

The target system is data-driven:

```text
scripts/
  check-release-signal.ps1
  release-signal-config.json
  release-signal-config.schema.json
  release-signal-config/
    check-release-signal-config.ps1
    check-release-signal-config.py
    test-script.ps1
    SKILL.md
```

## Goal

Keep release classification policy in JSON.

`scripts/check-release-signal.ps1` must be a generic evaluator. It may know generic rule types, but it must not contain project-specific file lists, token lists, labels, documentation paths, or release reasons.

## Inputs to inspect

Always inspect these files if present:

```text
scripts/check-release-signal.ps1
scripts/release-signal-config.json
scripts/release-signal-config.schema.json
scripts/release-signal-config/check-release-signal-config.ps1
scripts/release-signal-config/check-release-signal-config.py
scripts/release-signal-config/test-script.ps1
README.md
AGENTS.md
CHANGELOG.md
devdocs/releases/unreleased.md
```

Then inspect the repository tree and any files changed by the current branch.

Use PowerShell 7+ style commands on Windows.

Preferred commands:

```powershell
Get-ChildItem
Get-Content
Set-Content
Test-Path
Join-Path
ConvertFrom-Json
ConvertTo-Json
Select-String
```

**PowerShell / Python Runtime Requirement:**

- Prefer PowerShell 7+ for validation on Windows.
- Before running the PowerShell validator, check that PowerShell version is 7 or higher.
- If PowerShell 7+ is not available, use the Python 3.11+ validator fallback:
  `python scripts/release-signal-config/check-release-signal-config.py`
- If neither PowerShell 7+ nor Python 3.11+ is available, stop and report the missing runtime.

Do not use Bash heredocs or POSIX-only shell syntax.

## Required architecture

The JSON config should contain:

- `version`
- `project`
- `lowSignal`
- `nonTrivialLines`
- `highSignal`
- `conditionalFiles`
- `labels`
- `docsPolicy`

The schema should validate the config and use `additionalProperties: false` for strictness.

## Release classification model

Use this exact model when maintaining the config or scripts:

```text
releaseLikely = matched highSignal
             OR matched release-significant conditionalFiles rule
             OR release:needed label override
```

`release:none` may suppress release classification when the release script supports that policy.

### `lowSignal`

`lowSignal` is for docs, tests, mocks, CI, config docs, and release tooling that should not trigger a release by itself.

Use:

- `lowSignal.exactFiles`
- `lowSignal.pathPrefixes`

### `highSignal`

`highSignal` is for files or folders that are release-significant whenever non-trivial changed lines are detected.

Use:

- `file`
- `files`
- `pathPrefixes`

Each rule needs:

- `reason`
- `userFacing`

### `conditionalFiles`

Use conditional rules only when a file contains both:

- changes that can impact release functionality, shipped behavior, UI, selectors, metadata, parsing, or user-visible behavior
- changes that can be cleanup-only, such as formatting, comments, variable extraction, or refactoring with no shipped behavior change

A conditional rule must classify changed lines into one of these outcomes:

| Outcome | Release classification |
| --- | --- |
| clearly user-facing / shipped behavior | release-significant |
| clearly cleanup-only | non-release |
| ambiguous, mixed, or not safely cleanup-only | release-significant |

Ambiguous conditional changes must never silently become non-release. If the rule cannot prove the change is cleanup-only, return the rule's `ambiguousReason` and treat it as release-significant.

Supported types:

#### `token_any_vs_token_all`

Use for JavaScript files.

Fields:

- `userFacingTokens`
- `helperOnlyTokens`
- `jsActionNames`
- `userFacingReason`
- `helperOnlyReason`
- `ambiguousReason`
- `userFacing`

Expected behavior:

- if any user-facing token or action name is touched, classify as release-significant
- if every non-trivial changed line is helper-only and no user-facing token matched, classify as non-release
- otherwise classify as release-significant using `ambiguousReason`

#### `css_visible_vs_cleanup`

Use for CSS files.

Fields:

- `userFacingSelectors`
- `userFacingProperties`
- `cleanupPropertiesUsingCssVariable`
- `userFacingReason`
- `cleanupOnlyReason`
- `ambiguousReason`
- `userFacing`

Expected behavior:

- selector, layout, visibility, typography, spacing, positioning, interaction, or visible-property changes are release-significant
- pure extraction of existing values to CSS variables can be cleanup-only
- mixed visible CSS and cleanup-only changes are release-significant
- ambiguous CSS changes are release-significant using `ambiguousReason`

#### `metadata_selector`

Use for site metadata files.

Fields:

- `selectorKeys`
- `metadataFunctionPrefixes`
- `metadataTokens`
- `formatOnlyReason`
- `metadataReason`
- `ambiguousReason`
- `userFacing`

Expected behavior:

- parser, capability, selector key, site support, or metadata behavior changes are release-significant
- pure selector-array reformatting with unchanged selector meaning can be non-release
- mixed or ambiguous metadata changes are release-significant using `ambiguousReason`

## `userFacing` semantics

`userFacing` is metadata on a matched rule result. It is not a coverage bucket.

Use `userFacing` to decide downstream documentation expectations, for example README or user-facing release-note warnings.

Do not compute coverage as:

```text
highSignal + userFacing + conditionalFiles
```

Use this instead:

```text
release-signal coverage = highSignal + conditionalFiles
```

A non-user-facing high-signal rule can still be release-significant, for example shipped declarative net request rules or packaging behavior.

## Coverage audit model

`coverageAudit` verifies that critical shipped files and path prefixes are represented by release-signal rules.

Coverage means a required item is covered by either:

- `highSignal.file`
- `highSignal.files`
- `highSignal.pathPrefixes`
- `conditionalFiles.file`
- `conditionalFiles.files`, if supported by the schema/script
- `conditionalFiles.pathPrefixes`, if supported by the schema/script

Use these field names for the precise coverage model:

```json
{
  "coverageAudit": {
    "requiredReleaseSignalFiles": [],
    "requiredReleaseSignalPathPrefixes": []
  }
}
```

Do not use `requiredHighSignalFiles` or `requiredHighSignalPathPrefixes` for this model. Those names imply conditional rules are not valid coverage, which is incorrect.

Rules:

- exact files belong in `requiredReleaseSignalFiles`
- real path prefixes belong in `requiredReleaseSignalPathPrefixes`
- do not put exact files such as `styles.css` or `popup.html` in a prefix list
- path prefixes should normally end with `/`
- the audit must not require every critical file to be in `highSignal`; mixed files may be covered by `conditionalFiles`

## How to infer config from repo code

When adding or updating config based on repo code:

1. List top-level files and production source folders.
2. Identify shipped runtime files:
   - manifest
   - content scripts
   - background scripts
   - popup pages
   - runtime adapters
   - filter engines
   - metadata/config consumed by shipped code
   - browser extension rulesets and other shipped assets
3. Put always-shipped behavior files in `highSignal`.
4. Put mixed shipped files in `conditionalFiles` when cleanup-only edits should not trigger a release.
5. Put docs/tests/mocks/tooling in `lowSignal`.
6. For mixed files, inspect function names, exported APIs, browser API calls, CSS selectors, and metadata keys.
7. Add conditional rules using plain tokens, not regex.
8. Keep reasons concise, no more than 15 words, and specific.

Examples:

- Good: `Affects popup UI controls, visible to users`
- Bad: `UI change`
- Bad: `Miscellaneous`

## Prohibited practices and patterns

| Category | Prohibited practice or pattern |
| --- | --- |
| Regex patterns | Regex macro systems such as `<ws>`, `<dot>`, `<lb>`, `<rb>` |
| PowerShell practices | Project-specific hardcoded arrays, duplicate rules in both JSON and PowerShell |
| Rule definition | Broad regexes where exact files, prefixes, or plain tokens work |
| Release classification | Silent fallback that makes ambiguous conditional changes non-release |
| Coverage audit | Treating `userFacing` as a coverage source |
| Coverage audit | Requiring mixed files to appear in `highSignal` instead of allowing `conditionalFiles` coverage |
| Coverage audit | Putting exact file paths in path-prefix audit arrays |

## Schema update rules

Update `release-signal-config.schema.json` when:

- adding a new top-level config field
- adding a new conditional rule type
- changing required fields
- renaming fields
- changing allowed value types
- renaming `coverageAudit` fields, for example from `requiredHighSignalFiles` to `requiredReleaseSignalFiles`

Do not update the schema for ordinary rule data changes.

## Validation scripts

This skill includes repo-aware validation scripts. They work from any directory by auto-detecting the repository root. Prefer the PowerShell validator when PowerShell 7+ is available; use the Python 3.11+ validator when PowerShell 7+ is missing.

**Error handling:**

- If the JSON config file is missing, notify the user and terminate validation with an error message.
- If the JSON config is invalid, cannot be parsed, or fails schema validation, notify the user and terminate validation with an error message.
- If PowerShell is below version 7, run the Python 3.11+ validator fallback when available.
- If neither PowerShell 7+ nor Python 3.11+ is available, notify the user and terminate validation.

### `check-release-signal-config.ps1`

Comprehensive config validation covering:

- JSON structure and file existence
- configuration field completeness
- file and directory presence
- release-signal coverage of shipped code, where coverage means `highSignal` or `conditionalFiles`
- lowSignal / release-signal overlap detection
- rule consistency, including duplicate exact file assignments
- tracked-file alignment with git

**Execute from any directory:**

```powershell
pwsh -NoProfile -File 'scripts/release-signal-config/check-release-signal-config.ps1'
```

**Parameters:**

- `-RepoRoot` optional — explicit repository root path, auto-detected if omitted
- `-ConfigPath` optional — custom config path, relative to repo root
- `-SchemaPath` optional — custom schema path, relative to repo root
- `-Verbose` optional — shows detailed per-check output

**Exit code:**

- `0` = all required checks pass
- `1` = failure

**Default output:**

The default run should be compact. It should print only:

- final pass/warning/fail counts
- failure and warning references, including the affected file, prefix, rule, or section
- final success or failure status

**Verbose output:**

Use `-Verbose` to show detailed section headers and per-check pass results.

```powershell
pwsh -NoProfile -File 'scripts/release-signal-config/check-release-signal-config.ps1' -Verbose
```

### `check-release-signal-config.py`

Python 3.11+ fallback for environments without PowerShell 7+.

Run this validator when `pwsh` is unavailable or when the installed PowerShell version is below 7:

```powershell
python scripts/release-signal-config/check-release-signal-config.py
```

Use verbose mode for detailed per-check output:

```powershell
python scripts/release-signal-config/check-release-signal-config.py -Verbose
```

Use an explicit repo root from any directory:

```powershell
python scripts/release-signal-config/check-release-signal-config.py `
  -RepoRoot 'C:\path\to\repo'
```

The Python validator should be equivalent to the PowerShell validator for config checks, compact default output, verbose output, exit codes, and PR-body reporting. If it auto-installs optional dependencies such as `jsonschema`, that install should happen at startup before validation begins. In locked-down CI, use `-NoInstallDeps` if dependency installation is forbidden.

### `test-script.ps1`

Tests the release-signal script (`scripts/check-release-signal.ps1`) execution against a branch diff.

**Execute from the repository:**

```powershell
pwsh -NoProfile -File 'scripts/release-signal-config/test-script.ps1'
```

**Parameters:**

- `-BaseRef` default: `origin/main` — base git reference
- `-HeadRef` default: `HEAD` — head git reference
- `-ScriptPath` optional — custom path to `check-release-signal.ps1`

**Exit code:**

- `0` = script executed successfully
- `1` = execution failure

**Output:** release likelihood, candidate count, classification reason, and warnings/errors.

## PR body requirement

When `scripts/release-signal-config.json`, `scripts/release-signal-config.schema.json`, `scripts/check-release-signal.ps1`, or any file under `scripts/release-signal-config/` changes, run the validator.

Prefer PowerShell 7+:

```powershell
pwsh -NoProfile -File 'scripts\release-signal-config\check-release-signal-config.ps1'
```

If PowerShell 7+ is not available, use the Python 3.11+ fallback:

```powershell
python scripts\release-signal-config\check-release-signal-config.py
```

Add the exact validator output to the PR body in a fenced block. If the Python fallback was used, keep the heading and mention the fallback command before the output:

````md
### Release Signal Config Check

Command used: `python scripts\release-signal-config\check-release-signal-config.py`

```text
<paste validator output here>
```
````

If the validator fails, do not claim the config is valid. Paste the failing output and explain which config/schema/script change is required.

## Usage examples

### Run compact validation from repository

```powershell
cd C:\path\to\repo
pwsh -NoProfile -File 'scripts/release-signal-config/check-release-signal-config.ps1'
```

Expected compact success shape:

```text
Release Signal Config Check

Passed:   54
Warnings: 0
Failed:   0

✓ All required checks passed
```

Expected compact failure shape:

```text
Release Signal Config Check

Passed:   51
Warnings: 1
Failed:   2

Failures:
- Required release-signal file covered: styles.css
- Configured file path exists: popup.html

Warnings:
- No coverageAudit section found; release-signal coverage audit skipped

✗ Required checks failed
```

### Run Python fallback when PowerShell 7+ is unavailable

```powershell
python scripts/release-signal-config/check-release-signal-config.py
```

Verbose Python fallback:

```powershell
python scripts/release-signal-config/check-release-signal-config.py -Verbose
```

### Run verbose validation

```powershell
pwsh -NoProfile -File 'scripts/release-signal-config/check-release-signal-config.ps1' -Verbose
```

Verbose output may include all section headers and per-check pass/fail details.

### Run from any directory with explicit repo path

```powershell
pwsh -NoProfile -File 'scripts/release-signal-config/check-release-signal-config.ps1' `
  -RepoRoot 'C:\path\to\repo'
```

### Run release signal test

```powershell
cd C:\path\to\repo
pwsh -NoProfile -File 'scripts/release-signal-config/test-script.ps1'
```

Expected output shape:

```text
Release Signal Script Test

Testing: origin/main...HEAD

Results:
  Release likely: False
  Candidates: 13
  Reason: Low priority changes, won't trigger a release.

Warnings/Errors (1):
  ::warning::Every PR should carry either `release:needed` or `release:none`...

✓ Script executed successfully
```

## Quick validation workflow

1. Edit config, schema, or validation script.
2. Run `scripts/release-signal-config/check-release-signal-config.ps1`, or `scripts/release-signal-config/check-release-signal-config.py` when PowerShell 7+ is unavailable.
3. Fix all failures.
4. Re-run the validator.
5. Add the validator output to the PR body.
6. Commit only if exit code is 0, unless intentionally committing a failing state for review.

## Expected final report

Report:

```md
### Release Signal Config

- Config changes:
  - ...
- Schema changes:
  - ...
- PowerShell changes:
  - ...
- Validation:
  - Config check: pass/fail
  - Release signal script: pass/fail
- PR body:
  - Added release-signal config validator output: yes/no
  - Validator command used: `pwsh ...check-release-signal-config.ps1` or `python ...check-release-signal-config.py`
```

If validation could not be run, say exactly why.
