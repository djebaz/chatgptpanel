# AGENTS.md — AI Development Guide (v2.1.1)

This guide equips AI agents with the architecture, patterns, and rules needed to safely extend and maintain chatgptpanel.

- Environment: Windows + PowerShell (pwsh 7+). Use Get-ChildItem, Get-Content, Set-Content, Select-String. All `.ps1` scripts now include `#Requires -PSEdition Core` and runtime checks to enforce this environment. See HOWTO.md at repo root. Prefer the harness apply_patch tool for edits.
- Encoding & Line Endings: All source files (JS/JSON/CSS/HTML/MD/PS1) are UTF-8 without BOM with LF line endings. Enforce via `.editorconfig`, `.gitattributes`, and `.prettierrc` (`endOfLine: "lf"`). Windows Git config: `core.autocrlf=false` and `core.eol=lf`. Format commands: `npm run format` checks formatting, `npm run format:write` rewrites code-focused files, and `npm run format:all` rewrites code, workflows, devdocs, and related Markdown.
- Release automation:
  - `scripts/check-release-signal.ps1` is the release-signal validator used by CI. It classifies changes, validates release-audit metadata, emits GitHub Actions outputs, and fails when release-audit requirements are not met.
  - `.github/workflows/release-signal.yml` runs on pull requests and manual dispatch. Same-repository pull requests can auto-fix the `devdocs/releases/unreleased.md` Release audit footer, push the update back to the PR branch, and re-run validation as the final hard gate. Forked PRs and manual dispatches are validation-only.
  - `scripts/watch-release-signal.ps1` is the local watcher/remediator. It can monitor the current PR, update labels/comments/statuses, and auto-apply Release audit fixes from a developer machine when invoked with the appropriate options.
  - `scripts/update-unreleased-audit.ps1` is the focused helper for Release audit footer updates. It expects a non-detached feature branch and may create/use a PR via `gh`.
- Artifact Strategy: GitHub Action storage is optimized to minimize GB-Hours.
  - Text-based logs and test results are captured in **Job Summaries** (using Markdown tables and ✅/❌ icons for high-level visibility) instead of file artifacts.
  - Binary artifacts (if any) are only uploaded on failure (`if: failure()`), with `retention-days: 1` and `continue-on-error: true`.
  - An **Artifact Sweeper** cron job aggressively purges all artifacts older than 30 minutes.
- Coding: Keep changes minimal. The extension is a simple wrapper utilizing an action popup (`popup.html` and `popup.js`) to provide options for opening ChatGPT (Side Panel, Standalone Window, New Tab). It uses `rules.json` (declarativeNetRequest) to allow iframing in the side panel. Use `manifest.json` for all extension configuration.
- Testing:
  - Core configurations are covered by unit tests in `tests/unit/` using the Node.js native test runner (`npm run test:unit`).
  - End-to-end flows are covered by Playwright tests in `tests/e2e/` (`npm run test:e2e`). Chrome extension E2E runs headful under `xvfb-run` in CI.
  - The GitHub Actions test workflow runs Prettier and ESLint as advisory checks. They warn and appear in the job summary but do not fail the workflow. Unit and E2E test failures remain hard failures.
  - The local `npm test` script currently runs formatting, linting, unit tests, and E2E tests. Do not assume CI has the same failure policy as `npm test`; inspect `.github/workflows/tests.yml` when changing gates.
