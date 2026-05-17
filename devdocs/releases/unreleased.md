## Unreleased

### Highlights
- Restore the last visited ChatGPT conversation URL across side panel, popup, and tab relaunches.
- Improve side panel compatibility for ChatGPT's built-in copy buttons.


### Added
- Shared last-URL persistence backed by extension storage for all launch modes.


### Changed
- Side panel now restores the last saved ChatGPT URL instead of always loading the home page.



### Fixed
- Added an extension-side clipboard fallback for side panel iframe copy actions.

## Release audit

- PRs: #17, #18, #19
- Scope: Version Bump 2.0.0; release 2 0 0; automation release publish workflow; restore last ChatGPT URL across reopen flows; improve side panel copy compatibility
