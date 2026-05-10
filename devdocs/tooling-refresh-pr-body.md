# Tooling refresh

## Summary

This PR refreshes and standardizes the Node.js development tooling for the repository.

Testing configuration: Jest

Main goals:

- clean dependency graph
- modernize dev tooling packages
- remove obsolete packages/configuration
- reduce tooling drift
- ensure clean install/audit state

## Dependency updates

### devDependencies

- "@babel/core": "^7.25.8"
- "@babel/preset-env": "^7.25.8"
- "@playwright/test": "^1.59.1"
- "@types/chrome": "^0.0.277"
- "babel-jest": "^29.7.0"
- "chrome-mock": "^0.0.9"
- "cross-env": "^10.1.0"
- "eslint": "^10.3.0"
- "jest": "^30.4.2"
- "jest-environment-jsdom": "^30.4.1"
- "prettier": "^3.3.3"

### dependencies

- none

## ESLint

- Updated ESLint to the latest compatible version
- Migrated/replaced the repo config with slint.config.mjs
- Removed legacy ESLint config/ignore files
- Configured ESLint as a low-noise, high-signal bug guard
- Formatting remains handled by Prettier

Enabled high-signal rules include:

- 
o-const-assign
- 
o-dupe-keys
- 
o-func-assign
- 
o-import-assign
- 
o-unreachable
- 
o-unsafe-finally
- alid-typeof
"@
    }
    else {
        @"
## ESLint

- Updated ESLint package
- Kept the existing ESLint configuration unchanged
- Formatting remains handled by Prettier

## Jest

- Jest usage detected
- Updated Jest tooling to v30
- Split normal test runs from coverage runs
- Coverage tooling no longer runs during standard unit tests

## Playwright

- Playwright/E2E usage detected
- Normalized Playwright tooling
- Removed obsolete chromium npm package if present

## Cleanup performed

- verified npm cache
- pruned stale/extraneous packages
- normalized lockfile state
- removed obsolete chromium npm package declarations
- regenerated dependency tree

## Validation

- Validation was not run automatically

## Audit

- npm audit completed successfully
- no known vulnerabilities remaining after refresh

## Notes

- Prettier remains the formatting authority
- ESLint is kept/configured as a bug-oriented safety check
- Lockfile was regenerated/updated as part of dependency normalization
