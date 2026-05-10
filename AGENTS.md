# AGENTS.md — AI Development Guide (v2.1.1)

This guide equips AI agents with the architecture, patterns, and rules needed to safely extend and maintain Auto Clicker Pro v2.0.0. It supersedes prior v1.4/v1.5/v1.8 guidance with the multi‑tab model, countdown ownership, global progress tracking, and granular job cancellation controls.

- Environment: Windows + PowerShell (pwsh 7+). Use Get-ChildItem, Get-Content, Set-Content, Select-String. All `.ps1` scripts now include `#Requires -PSEdition Core` and runtime checks to enforce this environment. See HOWTO.md at repo root. Prefer the harness apply_patch tool for edits.
- Encoding & Line Endings: All source files (JS/JSON/CSS/HTML/MD/PS1) are UTF-8 without BOM with LF line endings. Enforce via `.editorconfig` (`end_of_line = lf`), `.gitattributes` (`* text=auto eol=lf`), and `.prettierrc` (`endOfLine: "lf"`). Windows Git config: `core.autocrlf=false` and `core.eol=lf`. Format commands: `npm run format:write` (code-focused) and `npm run format:all` (comprehensive with scripts, workflows, devdocs).
- Release automation: `scripts/update-unreleased-audit.ps1` manages PR audit updates. It pauses 45 seconds after branch push to allow manual PR creation with proper body, then checks if a PR exists before auto-creating. Use `-DelaySeconds 0` to skip the wait. This prevents duplicate PRs from timing race conditions.
- Artifact Strategy: GitHub Action storage is optimized to minimize GB-Hours.
  - Text-based logs and test results are captured in **Job Summaries** instead of file artifacts.
  - Binary artifacts (if any) are only uploaded on failure, with `retention-days: 1` and `continue-on-error: true`.
  - An **Artifact Sweeper** cron job aggressively purges all artifacts older than 30 minutes.
- Coding: Keep changes minimal, follow existing style, avoid POSIX tools. Content owns countdown timing; background mirrors state and renders badges.

