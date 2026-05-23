# chatgptpanel

Access OpenAI ChatGPT in a mini window, perfect for multitasking devs to stay connected without leaving their workspace.

This extension provides a dedicated action popup allowing you to open the official ChatGPT website in three ways:

- **Side Panel**: Pin ChatGPT to the side of your browser.
- **PopUp**: A clean, distraction-free popup window.
- **New Tab**: Standard full-tab experience.

When you reopen ChatGPT from any of these launch modes, the extension restores the last valid ChatGPT home or conversation URL so you can jump back into the same conversation. Internal ChatGPT helper URLs are ignored so they cannot become the saved reopen target. In side panel mode, the iframe host also enables a clipboard fallback to improve compatibility with ChatGPT's built-in copy buttons.

## Development

### Prerequisites

- Node.js (v24+)
- PowerShell 7+
- GitHub CLI (`gh`) for local release publishing

### Setup

```powershell
npm install
```

### Testing

We use the native Node.js test runner for manifest validation and Playwright for E2E verification.

```powershell
# Run the package test script
npm test

# Run manifest validation only
npm run test:unit

# Run Playwright E2E only
npm run test:e2e
```

The local `npm test` script currently runs formatting, linting, unit tests, and E2E tests. In GitHub Actions, the test workflow runs Prettier and ESLint as advisory checks: they emit warnings and appear in the job summary, but only unit and E2E failures fail the workflow.

### Formatting and linting

```powershell
# Check formatting without rewriting files
npm run format

# Rewrite formatted files
npm run format:write

# Format the full repo, including workflows and devdocs
npm run format:all

# Run ESLint
npm run lint
```

### Release signal workflow

The release signal workflow validates release-audit metadata in `devdocs/releases/unreleased.md`. On same-repository pull requests, it can auto-fix the Release audit footer, push the update back to the PR branch, and then re-run validation as the final required gate. Forked PRs and manual workflow runs are validation-only.

### Publishing a release

After the version-bump PR is merged to `main`, publish locally with:

```powershell
npm run release -- -Version "2.0.1"
```

The release script validates the current branch and version surfaces, packages the extension, creates/pushes the `v2.0.1` tag, publishes the GitHub release, uploads `dist/ChatPTPanel-2.0.1.zip`, and verifies the uploaded asset.

A manual GitHub Actions workflow, **Publish Release**, is also available from the Actions tab. It accepts a version and release ref, packages the extension on GitHub-hosted runners, creates the tag if needed, publishes the GitHub release, uploads the zip, and writes a release summary.
