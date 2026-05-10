## Unreleased

### Highlights

- Simplified extension to a "Simple Wrapper" approach, directly opening ChatGPT in a popup window.

### Added

- `package-lock.json` committed for reproducible builds.

### Changed

- Standardized devDependencies: Node v24, Playwright v1.59, ESLint v10.
- Normalized dependency graph and regenerated lockfile.
- Initialized `scripts/release-signal-config.json` to enable data-driven release classification.

### Fixed

- Pruned stale/extraneous packages.
- Minimize GitHub Actions artifact storage usage by transitioning logs to Job Summaries.
- Removed obsolete API client logic and complex unit tests in favor of a clean, minimal wrapper.

## Release audit

- PRs: #1, #2, #3, #4
- Scope: tooling; artifact-optimization; README; project simplification to browser-wrapper approach;
