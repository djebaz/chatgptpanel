# Usage & Release Notes

## Building

- Prod: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\package-extension.ps1`
- Dev (logs enabled): add `-DevBuild`.
- Outputs land in `dist/` as `<AppName>-<version>` (+ `-dev`), with matching `.zip`. Zips are flat (no root folder) and write `version_name` only in the staged manifest.

## Runtime logging

- The extension treats builds with `version_name` ending in `-dev` as verbose. Non-error logs are no-ops in prod builds.
- `background.js` and `content.js` both read `chrome.runtime.getManifest().version_name` to decide logging.

## Release hygiene (branch-guard)

- Work on a feature branch for code changes; docs-only updates may go directly to `main` when they only affect documentation/release-note/plan files and do not change shipped behavior. Every PR still updates `devdocs/releases/unreleased.md` and its `## Release audit` ledger.
- Apply exactly one release-intent label on every PR: `release:needed` when the branch should be released soon because this PR materially increases release pressure, or `release:none` when the PR does not increase release pressure by itself.
- PRs run `.github/workflows/release-signal.yml`, which combines high-signal path + hunk detection with objective `documentation-sync` checks. It requires `devdocs/releases/unreleased.md` on every PR, requires the current PR number in the `## Release audit` `PRs:` ledger, requires the cumulative `Scope:` line to change when a PR is newly added to that ledger, and, if no explicit `release:needed` or `release:none` label is present, warns and auto-applies one directly from the `release_likely` result until a maintainer confirms or changes it. Failing runs also upsert a single PR comment with the blocking errors and top warnings.
- Add `devdocs/features/<slug>.md` for the change summary and `devdocs/releases/vX.Y.Z.md` for the release.
- After merge to `main`, rebuild artifacts from `main@HEAD`, tag `vX.Y.Z`, and attach `dist/<App>-<version>.zip` to the GitHub release.

## Repo layout (docs)

- `README.md`: user-facing overview and install/build steps.
- `AGENTS.md`: quick rules for automation/assistants.
- `devdocs/features/`: feature/change write-ups.
- `devdocs/releases/`: release notes per version.
