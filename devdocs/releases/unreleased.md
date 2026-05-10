## Unreleased

### Highlights

- Added a ChatGPT-style dark theme popup with options to open ChatGPT in the side panel, a popup, or a new tab.
- Simplified extension to a "Simple Wrapper" approach, directly opening ChatGPT in a popup window.

### Added

- `package-lock.json` committed for reproducible builds.
- Added ChatGPT-style SVG outline icons to popup buttons.

### Changed

- Standardized devDependencies: Node v24, Playwright v1.59, ESLint v10.
- Normalized dependency graph and regenerated lockfile.
- Initialized `scripts/release-signal-config.json` to enable data-driven release classification.

### Fixed

- Pruned stale/extraneous packages.
- Minimize GitHub Actions artifact storage usage by transitioning logs to Job Summaries.
- Removed obsolete API client logic and complex unit tests in favor of a clean, minimal wrapper.
- Fixed E2E test suite: corrected stale `package-config.json` allowlist, `run-e2e.ps1` dist path, and rewrote spec to match the minimal wrapper architecture.
- Fixed GitHub Actions Playwright execution by installing browser dependencies, adding `xvfb-run` for headful mode, and ensuring failure propagation with `set -o pipefail`.

## Release audit

- PRs: #1, #2, #3, #4, #5, #6, #7, #8, #9
- Scope: tooling; artifact-optimization; README, docsync and formatting; Removed obsolete API client logic and complex unit tests in favor of a clean, minimal wrapper; implement e2e tests playwright; fix e2e implementation and package config; add multi-open popup with side panel and tab options; add svg icons to popup buttons; fix CI playwright setup and reporting
