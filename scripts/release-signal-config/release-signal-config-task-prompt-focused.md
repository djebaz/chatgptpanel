# Release Signal Config — Focused Task Prompt

This prompt guides an agent or operator to maintain and update primarily this file:

**scripts/release-signal-config.json**

The schema, scripts, docs, and skill file are references unless this prompt explicitly says a related release-audit update is required.

---

## Task: Keep release-signal-config.json Up To Date

### Goal

- Ensure **scripts/release-signal-config.json** is accurate, complete, and aligned with the current repository structure.
- Keep release classification policy data-driven.
- Keep `scripts/check-release-signal.ps1` generic: no project-specific file lists, token lists, labels, documentation paths, or release reasons in the script.

### Inputs to inspect

- `scripts/release-signal-config.json` — target for config edits
- `scripts/release-signal-config.schema.json` — reference for required structure
- `scripts/check-release-signal.ps1` — reference for release classification behavior
- `scripts/release-signal-config/check-release-signal-config.ps1` — preferred validator to run after edits when PowerShell 7+ is available
- `scripts/release-signal-config/check-release-signal-config.py` — Python 3.11+ fallback validator when PowerShell 7+ is unavailable
- `scripts/release-signal-config/SKILL.md` — rationale, rule definitions, and prohibited patterns
- `README.md`, `AGENTS.md`, `CHANGELOG.md`, `devdocs/releases/unreleased.md` — repository and release-audit context
- repository tree and current branch changes

### How to detect and track changes

Use git commands to identify files and folders added, removed, renamed, or modified since the last config update.

Recommended commands:

```powershell
git status --short
git log -1 --format=%H -- scripts/release-signal-config.json
git diff --name-status <last-config-commit>..HEAD
```

If preparing a PR and a PR number is needed for release-audit docs, use:

```powershell
gh pr list --state all --limit 1 --json number --jq '.[0].number + 1'
```

This helps capture repository changes even if `main` is behind or the branch was rebased.

---

## Required actions

### 1. Validate and update config structure

Ensure all required sections are present:

- `version`
- `project`
- `lowSignal`
- `nonTrivialLines`
- `highSignal`
- `conditionalFiles`
- `labels`
- `docsPolicy`

All fields must conform to `scripts/release-signal-config.schema.json`.

### 2. Apply the precise release-classification model

Use this exact model:

```text
releaseLikely = matched highSignal
             OR matched release-significant conditionalFiles rule
             OR release:needed label override
```

`userFacing` is metadata on a matched rule result. It is not a coverage bucket.

Do not model coverage as:

```text
highSignal + userFacing + conditionalFiles
```

Use this instead:

```text
release-signal coverage = highSignal + conditionalFiles
```

### 3. Update rules for repository changes

When files, folders, or shipped code change, update the config accordingly.

Use:

- `highSignal` for files or folders that are release-significant whenever non-trivial changed lines are detected
- `lowSignal` for docs, tests, mocks, CI, config docs, and tooling that should not trigger a release by itself
- `conditionalFiles` for mixed files where some changes are user-facing or shipped behavior, while other changes are cleanup-only

Keep reasons concise, no more than 15 words, and specific.

### 4. Preserve conditional rule semantics

For conditional files:

| Case | Classification |
| --- | --- |
| user-facing token, selector, metadata, parser, UI, or shipped behavior change | release-significant |
| every non-trivial changed line is safely cleanup-only | non-release |
| ambiguous, mixed, or not safely cleanup-only | release-significant |

Ambiguous conditional changes must use `ambiguousReason` and must not silently become non-release.

### 5. Maintain coverageAudit correctly

If `coverageAudit` is present, it should use release-signal coverage names:

```json
{
  "coverageAudit": {
    "requiredReleaseSignalFiles": [],
    "requiredReleaseSignalPathPrefixes": []
  }
}
```

Coverage means the required file or prefix is covered by `highSignal` or `conditionalFiles`.

Rules:

- exact files go in `requiredReleaseSignalFiles`
- path prefixes go in `requiredReleaseSignalPathPrefixes`
- do not put exact files such as `styles.css` or `popup.html` in a prefix list
- path prefixes should normally end with `/`
- do not force mixed files into `highSignal` if they belong in `conditionalFiles`

### 6. Handle errors

- If a required config section or field is missing, add it.
- If a referenced file/folder no longer exists, remove or update the entry.
- If a new shipped file/folder is added, add it to `highSignal` or `conditionalFiles` as appropriate.
- If a new docs/test/tooling path is added, add it to `lowSignal` as appropriate.

---

## What not to do

- Do **not** edit `scripts/release-signal-config.schema.json`, `scripts/check-release-signal.ps1`, or validator scripts as part of this focused config-maintenance task.
- Do **not** change validation logic or schema in this task.
- Do **not** use regex macro systems such as `<ws>`, `<dot>`, `<lb>`, or `<rb>`.
- Do **not** duplicate project-specific rules in PowerShell.
- Do **not** treat `userFacing` as a coverage source.
- Do **not** place exact file paths in prefix audit arrays.

Exception: if `scripts/release-signal-config.json` is modified for a PR, update `devdocs/releases/unreleased.md` only if the repository release-audit process requires the PR number, audit footer, or config-change summary.

---

## Validation

After editing, prefer the PowerShell validator when PowerShell 7+ is available:

```powershell
pwsh -NoProfile -File 'scripts\release-signal-config\check-release-signal-config.ps1'
```

If `pwsh` is unavailable or the installed PowerShell version is below 7, use the Python 3.11+ fallback:

```powershell
python scripts\release-signal-config\check-release-signal-config.py
```

The default output should be compact: summary plus failure/warning references only.

For detailed per-check output, run:

```powershell
pwsh -NoProfile -File 'scripts\release-signal-config\check-release-signal-config.ps1' -Verbose
```

or, with the Python fallback:

```powershell
python scripts\release-signal-config\check-release-signal-config.py -Verbose
```

If any check fails, update only `scripts/release-signal-config.json` to resolve the issue, unless the failure proves that the schema or script itself is out of date. In that case, stop and report that this focused task cannot be completed by config-only edits.

---

## PR body requirement

Before opening or updating the PR, run the validator.

Prefer PowerShell 7+:

```powershell
pwsh -NoProfile -File 'scripts\release-signal-config\check-release-signal-config.ps1'
```

If PowerShell 7+ is unavailable, use the Python 3.11+ fallback:

```powershell
python scripts\release-signal-config\check-release-signal-config.py
```

Add the exact output to the PR body in this section. Include the command used, especially when the Python fallback is used:

````md
### Release Signal Config Check

Command used: `python scripts\release-signal-config\check-release-signal-config.py`

```text
<paste validator output here>
```
````

If the validator fails, paste the failing output and do not claim the config is valid.

---

## Special note

If `scripts/release-signal-config.json` is modified, ensure the release-audit process is satisfied before opening the PR. When required by the repository process, update `devdocs/releases/unreleased.md` with:

- PR number
- release audit footer entry
- concise summary of the config change

---

## Usage example

> Your task: Update `scripts/release-signal-config.json` so it is fully up to date with the current repository. Do not edit schema or validation logic. Run `scripts\release-signal-config\check-release-signal-config.ps1`, or `scripts\release-signal-config\check-release-signal-config.py` if PowerShell 7+ is unavailable, and add the validator output to the PR body.

---

## References

- See `scripts/release-signal-config/SKILL.md` for rationale and rule definitions.
- See `scripts/release-signal-config.schema.json` for required structure.
- See `scripts/check-release-signal.ps1` for release classification logic.
- See `scripts/release-signal-config/check-release-signal-config.ps1` for preferred config validation.
- See `scripts/release-signal-config/check-release-signal-config.py` for Python 3.11+ fallback validation when PowerShell 7+ is unavailable.
