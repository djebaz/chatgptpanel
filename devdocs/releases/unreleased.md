## Unreleased

### Highlights

- Refreshed and standardized Node.js development tooling.

### Added

- `package-lock.json` committed for reproducible builds.

### Changed

- Migrated unit tests from Jest to native Node.js test runner.
- Updated devDependencies: Node v24, Playwright v1.59, ESLint v10. (Removed Jest and Babel).
- Normalized dependency graph and regenerated lockfile.
- Initialized `scripts/release-signal-config.json` to enable data-driven release classification.

### Fixed

- Pruned stale/extraneous packages.
- Minimize GitHub Actions artifact storage usage by transitioning logs to Job Summaries.

## Release audit

- PRs: #1, #2, #3, #4
- Scope: tooling; artifact-optimization; README, docsync and formatting; doc sync tooling; comprehensive unit tests for core logic
