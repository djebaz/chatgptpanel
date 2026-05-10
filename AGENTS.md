# AGENTS.md — AI Development Guide (v2.1.1)

This guide equips AI agents with the architecture, patterns, and rules needed to safely extend and maintain chatgptpanel.

- Environment: Windows + PowerShell (pwsh 7+). Use Get-ChildItem, Get-Content, Set-Content, Select-String. All `.ps1` scripts now include `#Requires -PSEdition Core` and runtime checks to enforce this environment. See HOWTO.md at repo root. Prefer the harness apply_patch tool for edits.
- Encoding & Line Endings: All source files (JS/JSON/CSS/HTML/MD/PS1) are UTF-8 without BOM with LF line endings. Enforce via `.editorconfig` (`end_of_line = lf`), `.gitattributes` (`* text=auto eol=lf`), and `.prettierrc` (`endOfLine: "lf"`). Windows Git config: `core.autocrlf=false` and `core.eol=lf`. Format commands: `npm run format:write` (code-focused) and `npm run format:all` (comprehensive with scripts, workflows, devdocs).
- Release automation:
  - `.github/workflows/release-signal.yml` validates Release audit metadata on pull requests. Same-repository PRs can auto-fix `devdocs/releases/unreleased.md`, push the fix to the PR branch, and re-run release-signal validation inside the same workflow job.
  - Auto-fix commits made with the default workflow `GITHUB_TOKEN` do not trigger a second GitHub Actions run. Configure a `RELEASE_SIGNAL_PUSH_TOKEN` secret if follow-up checks must run automatically after an auto-fix push.
  - The workflow comments on PRs when an auto-fix is applied or when final release-signal validation fails.
  - `scripts/watch-release-signal.ps1` is the local watcher/remediator path for developers. It can update labels/comments/statuses and apply Release audit fixes from a local machine.
  - `scripts/update-unreleased-audit.ps1` is the focused helper for Release audit footer updates. It expects a non-detached feature branch and may create/use a PR via `gh`.
- Artifact Strategy: GitHub Action storage is optimized to minimize GB-Hours.
  - Text-based logs and test results are captured in **Job Summaries** (using Markdown tables and ✅/❌ icons for high-level visibility) instead of file artifacts.
  - Binary artifacts (if any) are only uploaded on failure (`if: failure()`), with `retention-days: 1` and `continue-on-error: true`.
  - An **Artifact Sweeper** cron job aggressively purges all artifacts older than 30 minutes.
- Coding: Keep changes minimal. The extension is a simple wrapper utilizing an action popup (`popup.html` and `popup.js`) to provide options for opening ChatGPT (Side Panel, Standalone Window, New Tab). It uses `rules.json` (declarativeNetRequest) to allow iframing in the side panel. Use `manifest.json` for all configuration.
- Testing: Core configurations should be covered by unit tests in `tests/unit/` (e.g., manifest validation) using the Node.js native test runner (`npm run test:unit`).
  - End-to-end flows are covered by Playwright tests in `tests/e2e/`.
  - Use `npm run test` to execute both test suites.
