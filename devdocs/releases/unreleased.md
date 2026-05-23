## Unreleased

### Highlights


### Added


### Changed



### Fixed

- Prevented ChatGPT internal frame URLs such as `/backend-api/sentinel/frame.html` from being saved as the reopen target; stored launch URLs are now limited to ChatGPT home or canonical conversation URLs.

## Release audit

- PRs: #20, #22
- Scope: Version Bump 2.0.1; Filter stored ChatGPT reopen URLs to prevent internal frame paths from launching;
