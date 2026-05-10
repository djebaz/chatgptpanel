# Release Signal Config — Detailed Task Prompt

This prompt guides an agent or operator to maintain, validate, and update the release-signal configuration system for a repository, with full rationale, definitions, and examples.

---

## Task: Maintain and Validate Release Signal Config System

### Goal
- Keep release classification policy in JSON, not scripts.
- Ensure the config, schema, and validation scripts are correct, up-to-date, and follow best practices.
- All logic for release classification must be data-driven and generic.

### Inputs to Inspect
- scripts/check-release-signal.ps1
- scripts/release-signal-config.json
- scripts/release-signal-config.schema.json
- README.md, AGENTS.md, CHANGELOG.md, devdocs/releases/unreleased.md
- The repository tree and any files changed by the current branch

### PowerShell Version Requirement
- All scripts must require PowerShell 7+.
- If the version is below 7, notify the user to upgrade and terminate the script.

### Config and Schema Checks
- Both config and schema files must exist.
- Both must be valid JSON.
- Config must validate against the schema (using Test-Json if available).
- If missing or invalid, notify and terminate with an error.

### Required Config Architecture
- The JSON config must contain:
  - version
  - project
  - lowSignal
  - nonTrivialLines
  - highSignal
  - conditionalFiles
  - labels
  - docsPolicy
- The schema must validate the config and use `additionalProperties: false` for strictness.

### Rule Selection
- **lowSignal**: For docs, tests, mocks, CI, config docs, and release tooling that should not trigger a release by itself.
  - Use: lowSignal.exactFiles, lowSignal.pathPrefixes
- **highSignal**: For files/folders that are release-significant whenever changed.
  - Use: file, files, pathPrefixes
  - Each rule needs: reason, userFacing
- **conditionalFiles**: Use only when a file contains both changes that impact user-facing release functionality (e.g., logic, UI, shipped behavior) and changes that are purely for code cleanup (such as formatting, comments, or refactoring with no user-visible effect).
  - Example: If a JavaScript file has both a bug fix (user-facing) and whitespace cleanup (cleanup-only), apply a conditional rule.
  - **Ambiguous changes in mixed files:** If a file contains both user-facing and cleanup-only changes, prioritize user-facing changes for release classification. Example: If a CSS file changes both a visible selector and a variable name, treat the change as user-facing.

#### Supported Conditional Rule Types
- **token_any_vs_token_all** (JavaScript):
  - Fields: userFacingTokens, helperOnlyTokens, jsActionNames, userFacingReason, helperOnlyReason, ambiguousReason, userFacing
- **css_visible_vs_cleanup** (CSS):
  - Fields: userFacingSelectors, userFacingProperties, cleanupPropertiesUsingCssVariable, userFacingReason, cleanupOnlyReason, ambiguousReason, userFacing
- **metadata_selector** (site metadata):
  - Fields: selectorKeys, metadataFunctionPrefixes, metadataTokens, formatOnlyReason, metadataReason, ambiguousReason, userFacing

### How to Infer Config from Repo Code
1. List top-level files and production source folders.
2. Identify shipped runtime files: manifest, content scripts, background scripts, popup pages, runtime adapters, filter engines, metadata/config consumed by shipped code.
3. Put always-shipped behavior files in highSignal.
4. Put docs/tests/mocks/tooling in lowSignal.
5. For mixed files, inspect function names, exported APIs, browser API calls, CSS selectors, and metadata keys.
6. Add conditional rules using plain tokens, not regex.
7. Keep reasons concise (≤15 words) and specific (clearly state the user-facing or technical impact).
   - Example: Good: "Affects popup UI controls, visible to users"; Bad: "UI change" or "Miscellaneous"

### Prohibited Practices and Patterns
| Category                    | Prohibited Practice/Pattern                                                                 |
|-----------------------------|--------------------------------------------------------------------------------------------|
| Regex Patterns              | Regex macro systems such as `<ws>`, `<dot>`, `<lb>`, `<rb>`                               |
| PowerShell Practices        | Project-specific hardcoded arrays, duplicate rules in both JSON and PowerShell             |
| Rule Definition             | Broad regexes where exact files, prefixes, or plain tokens work                           |
| Release Classification      | Silent fallback that makes ambiguous changes release-significant without a reason          |

### Error Handling
- If the JSON config file is missing, notify the user and terminate validation with an error message.
- If the JSON config is invalid (cannot be parsed or fails schema validation), notify the user and terminate validation with an error message.
- If PowerShell version is too low, notify and terminate.

### Validation Workflow
1. Edit config → 2. Run validator → 3. Fix issues → 4. Verify all checks pass → 5. Commit only if exit code is 0.

### Expected Output
- Pass/fail summary for each check
- Clear error messages for any failures
- Final summary with counts of passes, warnings, and failures

---

## Usage Example

> "Your task: Validate and update the release-signal configuration system for this repository. Follow the detailed checklist above. If any check fails, provide a clear error message and halt. If all checks pass, summarize the results and next steps."

---

## References
- See scripts/release-signal-config/SKILL.md for full skill details and rationale.
- See scripts/check-release-signal-config.ps1 for implementation reference.
