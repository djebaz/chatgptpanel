## Unreleased

### Highlights

- Refreshed and standardized Node.js development tooling.

### Added

- `package-lock.json` committed for reproducible builds.

### Changed

- Updated devDependencies: Jest v30, Playwright v1.59, ESLint v10.
- Normalized dependency graph and regenerated lockfile.
- Initialized `scripts/release-signal-config.json` to enable data-driven release classification.

### Fixed

- Pruned stale/extraneous packages.
- Minimize GitHub Actions artifact storage usage by transitioning logs to Job Summaries.

## Release audit

- PRs: #1, #2, #3
- Scope: tooling; artifact-optimization; README, docsync and formatting;
