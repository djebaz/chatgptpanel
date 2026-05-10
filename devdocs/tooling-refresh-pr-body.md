# Tooling refresh

## Summary

This PR refreshes and standardizes the Node.js development tooling for the repository.

Testing configuration: Native Node.js test runner (`node --test`)

Main goals:

- clean dependency graph
- modernize dev tooling packages
- remove obsolete packages/configuration
- reduce tooling drift
- ensure clean install/audit state

## Dependency updates

### devDependencies

- "eslint": "^10.3.0"
- "jsdom": "^24.1.0"
- "prettier": "^3.2.5"
- "prettier-plugin-powershell": "^2.0.11"

### dependencies

- none



## Testing

- Repo uses Native Node.js test runner (`node --test`)
- No Jest tooling installed

## Playwright

- No Playwright/E2E tooling configured for this repo
- Removed stale Playwright declarations/scripts if present

## Cleanup performed

- verified npm cache
- pruned stale/extraneous packages
- normalized lockfile state
- removed obsolete chromium npm package declarations
- regenerated dependency tree

## Validation

- `npm run format`
- `npm run lint`
- `npm test`
- `npm audit`

## Audit

- 
pm audit completed successfully
- no known vulnerabilities remaining after refresh

## Notes

- Prettier remains the formatting authority
- ESLint is kept/configured as a bug-oriented safety check
- Lockfile was regenerated/updated as part of dependency normalization
