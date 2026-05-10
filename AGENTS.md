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

See also:

- CHANGELOG.md
- devdocs/per-tab-params-consistency.md
- devdocs/action_sequences_report_v1.9.md (canonical runtime flow + messaging contract/runbook for popup/content/background/offscreen/manager)
- devdocs/dedupe-start-stabilization-plan.md
- devdocs/dedupe-start-stabilization-checklist.md
- devdocs/features/detached-player-window-experiment-plan.md
- devdocs/features/detached-player-window-experiment-checklist.md
- devdocs/features/released-detached-shortcuts-parity-vs-main.md
- devdocs/features/detached-next-source-prefetch.md
- devdocs/features/detached-mosaic-current-logic.md
- devdocs/features/detached-mosaic-canonical-source-dedupe.md
- devdocs/features/splitscreen_implementation_plan.md
- devdocs/releases/v1.9.6.md
- devdocs/releases/v1.9.7.md
- devdocs/releases/v1.9.8.md
- devdocs/releases/v1.9.9.md
- devdocs/releases/v2.0.0.md
- devdocs/releases/v2.0.1.md
- devdocs/releases/v2.0.2.md
- devdocs/releases/v2.0.3.md
- devdocs/releases/v2.0.4.md
- devdocs/releases/v2.0.5.md
- devdocs/releases/v2.0.6.md
- devdocs/releases/v2.0.7.md
- devdocs/releases/v2.0.8.md
- devdocs/releases/v2.0.9.md
- devdocs/releases/unreleased.md
- devdocs/releases/v2.1.0.md
- devdocs/releases/v2.1.1.md
- devdocs/plans/2026-04-01-segment-start-percent-remux.md
- devdocs/plans/2026-04-08-detached-countdown-realtime.md
- devdocs/plans/2026-04-08-action-status-dots.md
- devdocs/plans/2026-04-08-detached-transition-order.md
- devdocs/plans/2026-04-09-fix-offscreen-paths.md
- devdocs/plans/2026-04-09-release-v2.0.7.md
- devdocs/plans/2026-04-10-detached-mock-e2e-single-run.md
- .agent/workflows/branch-guard.md
- .agent/workflows/new-feature.md
- .agent/workflows/documentation-sync.md
- .agent/workflows/quality-check.md
- .agent/workflows/workflow-management.md
- devdocs/release-signal-config-maintainers.md (how to update release classification rules)
- devdocs/release-signal-config-ai-agents.md (AI agent guide for release-signal changes)

## Architecture Overview

### Modules and Responsibilities

```
ContentScriptController
  deps: [AutoClicker, VideoDetector, CountdownManager, ContentPreloader, VideoUrlCache, ExtensionMessenger]
  role: orchestration, event coordination, lifecycle

Background (service worker)
  deps: [chrome.action, chrome.tabs, chrome.storage, chrome.downloads]
  role: per‑tab state registry, badge rendering, persistence, tab lifecycle

Popup (UI)
  deps: [chrome.tabs, chrome.runtime, chrome.storage]
  role: current‑tab control, start/stop, display state

Detached Player (src/detached/detached-player.html)
  deps: [chrome.runtime messaging, chrome.tabs messaging, HTML5 video]
  role: detached playback surface, detached countdown/timing source, start/stop/pause/next/refresh/export-log controls; supports "Compact Mode" toggle (`h`, persists) and native Picture-in-Picture mode (`t`).
  - When Picture-in-Picture is toggled ON, the detached player window resizes to 960x34px; when toggled OFF, it restores to the last non-PiP window size and position.

Progress Manager (src/manager/manager.html)
  deps: [chrome.runtime (port "progress-ui"), chrome.storage.local]
  role: download/remux queue UI with thumbnails, stage/pct status, and clear/completed controls; opens via popup button or OPEN_PROGRESS_MANAGER message

Offscreen (src/offscreen/offscreen.html)
  deps: [chrome.runtime messaging, WebCodecs, mediabunny-loader]
  role: remux worker for segment processing; resolves percent-based segment windows from media metadata when needed and emits heartbeat/progress/result back to background

Shared
  src/shared/* (constants.js, extension-messenger.js, element/video utils)

Assets & Manifest
  src/manifest.json (Extension entry point)
  src/assets/icons/* (Extension icons)
  src/lib/* (External libraries)
```

### Communication Patterns

```
Popup  --(chrome.runtime.sendMessage)--> Background --(chrome.tabs.sendMessage)--> Content
Content--(chrome.runtime.sendMessage)--> Background
Manager (port "progress-ui") <--> Background (SNAPSHOT/JOB_UPDATE broadcasts; GET_SNAPSHOT, OPEN_MANAGER, clearCompletedJobs)

Events (content)
  VideoDetector.onVideoEnd()           -> ContentScriptController.handleVideoEnd()
  VideoDetector.onVideoStateChange(s)  -> ContentScriptController.handleVideoStateChange(s)
  CountdownManager.onTick(n)           -> ContentScriptController.handleCountdownTick(n)
  CountdownManager.onComplete()        -> ContentScriptController.handleCountdownComplete()
  AutoClicker.onElementClicked(sel,t)  -> ContentScriptController.handleElementClicked(sel,t)
```

### Countdown Ownership

- Source of truth: Content computes remaining seconds and triggers actions at 0.
- Background mirrors ticks for per‑tab badges. It does NOT decrement time or trigger actions.

## Per-Tab State Model

Background memory: `activeTabs: Map<number, TabState>` mirrored to `chrome.storage.local.activeTabs`.

Notes (v1.8.15+):

- TabState adds `focusMode` (per‑tab cinema/focus flag), `aspectFilter`, and segment download fields (`segmentDownload`, `segmentStartSeconds`, `segmentStartPercent`, `segmentDurationSeconds`).
- `isCountdownActive` defaults to `false` in the constructor (v2.0.4+) to prevent race conditions; it is explicitly enabled only on `startCountdown`.
- startCountdown MERGES into existing TabState when present; do not recreate blindly.
- Preserve flags with stability semantics: `state.focusMode = state.focusMode || incoming.focusMode`.
- `aspectFilter` persists per tab/resume; default is `any`.
- Speed-mode `updateTabParams` must preserve segment fields and `startAtPercent`; later remux queue/offscreen resolution depends on that state surviving navigation.
- If `setVideoMode` arrives before `startCountdown`, cache intent by tab (pending) and apply on registration.
- Ignore a `focusMode: false` override if state already has `true` (prevents resume races from clearing focus).

Example snapshot (newly registered tab)

```
{
  "381227372": {
    tabId: 381227372,
    selector: ".view-group-next",
    selectorText: "Next Video + Auto-play + Cache",
    interval: 11000,
    saveVideo: false,
    speedMode: false,
    startAtPercent: 0,
    aspectFilter: 'any',
    segmentDownload: false,
    segmentStartSeconds: 0,
    segmentStartPercent: 0,
    segmentDurationSeconds: 30,
    totalSeconds: 11,
    remainingSeconds: 11,
    isVideoMode: true,
    isCountdownActive: false,
    countdownPaused: false,
    lastPauseReason: "",
    hasTriggeredThisCycle: false,
    isSpeedModeBadge: false,
    focusMode: false
  },
  "381227397": {
    tabId: 381227397,
    selector: ".view-group-next",
    selectorText: "Next Video + Auto-play + Cache",
    interval: 11000,
    saveVideo: true,
    speedMode: true,
    startAtPercent: 39,
    aspectFilter: 'vertical',
    segmentDownload: true,
    segmentStartSeconds: 0,
    segmentStartPercent: 39,
    segmentDurationSeconds: 45,
    totalSeconds: 11,
    remainingSeconds: 11,
    isVideoMode: false,
    isCountdownActive: true,
    countdownPaused: false,
    lastPauseReason: "",
    isSpeedModeBadge: true,
    hasTriggeredThisCycle: false,
    focusMode: true
  }
}
```

Per‑tab context keys written by content only when `tabId` is known:

- `lastGalleryContext:<tabId>`: `{ href, page, ts }`
- `downloadedBaseUrls`: array of base URLs (VideoUrlCache)

Global defaults (popup writes for convenience):

- `autoClickerInterval`, `autoClickerSelector`, `autoClickerSelectorText`
- `runMode` in { none, watch, speed }, `saveVideoEnabled`, `speedModeEnabled`
- `startAtPercent`
- `focusModeEnabled`
- `aspectFilter`
- `segmentDownloadEnabled`, `segmentDurationSeconds`, `segmentStartSeconds`, `segmentStartPercent`
- `autoOpenProgressManager`

## Messaging Interfaces

Defined in code or background router:

- Content → Background
  - `startCountdown`, `stopCountdown`, `updateCountdown`, `pauseCountdown`, `resumeCountdown`, `tickCountdown`
  - `updateLastAction`, `downloadVideo`, `remuxSegment`, `ping`
  - `getTabState`, `getResumeState`, `shouldResumeOnThisTab`, `setVideoMode`, `setSpeedModeBadge`, `updateTabParams`
  - On state `playing`, content always sends `resumeCountdown` to keep badges synced
- Popup → Content
  - `start`, `stop`, `getStatus`, `triggerVideoSeek`, `setFocusMode`
- Background → Content
  - `triggerVideoSeek` (legacy; disabled in v1.5 since content owns 0-action)
- Background → Content (detached)
  - `detachedRunStateChanged`
- Popup → Background
  - `openProgressManager`, `openDetachedPlayer`, `closeDetachedPlayer`
- Content → Background (detached)
  - `detachedPlayerSetSource`, `getDetachedPlayerSource`, `detachedPlayerNextVideo`
  - `detachedPlayerPauseState`
  - `detachedPageHttpError` (content reports HTTP 500/502 signals so background can apply guarded reload recovery)
- Progress Manager (port "progress-ui") ↔ Background
  - Port messages: `GET_SNAPSHOT`, `SNAPSHOT`, `JOB_UPDATE`, `OPEN_MANAGER`
  - Runtime messages: `clearCompletedJobs`, `emptyPendingQueueJobs`, `cancelRunningJobs`, `cancelJob`, `clearAllJobs`

Example payloads

```
// Popup -> Content start
{ action: 'start', tabId, selector, interval, saveVideo, speedMode, startAtPercent, focusMode }

// Popup -> Background start
{ action: 'startCountdown', tabId, selector, selectorText, interval, saveVideo, isVideoMode, startAtPercent, speedMode?, focusMode }

// Popup -> Background open progress UI
{ action: 'openProgressManager' }

// Content -> Background tick
{ action: 'tickCountdown', remaining, tabId }

// Content -> Background queued remux
{ action: 'remuxSegment', videoUrl, tabId, filenameHint, durationSeconds, segmentStartPercent?, respondOnQueue? }

// Popup/Content -> Background focus update
{ action: 'setVideoMode', tabId, selector, focusMode }
```

## Component Public APIs

ExtensionMessenger

- `send(action: string, data?: object): Promise<any>`
- `onMessage(action: string, handler: (data) => any)`

CountdownManager

- `start(intervalMs: number, videoMode: boolean, selector: string, startAtPercent: number)`
- `stop()`, `pause(reason)`, `resume()`, `reset()`
- `onComplete(handler)`, `onTick(handler)`

VideoDetector

- `start()`, `stop()`, `autoPlayVideo(): Promise<boolean>`
- `seekToEnd(): Promise<boolean>`, `seekToPercent(percent: number): Promise<boolean>`
- `getCurrentVideoUrl(): Promise<string|null>`
- `onVideoEnd(handler)`, `onVideoStateChange(handler)`

AutoClicker

- `start(selector: string, intervalMs: number)`
- `stop()`, `onElementClicked(handler)`

ContentPreloader (preloads next video tokenized sources)

- `start(videoCache)`, `stop()`

VideoUrlCache

- `store(fullUrl, baseUrl, ttlMs)`, `get(baseUrl)`, `hasValidUrl(baseUrl)`
- `markAsDownloaded(url)`, `isAlreadyDownloaded(url)`
- `extractCurrentPageUrls()`, maintenance APIs

Job Cancellation (src/background/background.js)

- `isTerminalJobStatus(status)` — checks if job is success/error/canceled
- `isQueuedJob(job)` — identifies pending/queued jobs by stage or message
- `isRunningJob(job)` — identifies active, non-terminal, non-queued jobs
- `cancelJobByRecord(jobId, job, message)` — unified cancellation with download/remux cleanup
- `cancelQueuedJobs()` — cancel pending queue only
- `cancelRunningJobs()` — cancel active jobs only
- `cancelTrackedDownload(downloadId, options)` — browser download cancellation + optional file removal
- `cancelPendingRemuxRequest(requestId, message)` — remux job cleanup with timeout clearing
- `removeQueuedRemuxEntryByRequestId(requestId, message)` — dequeue remux entry from queue
- `cancelJobById(jobId, message)` — public API for per-job cancellation (Manager UI)
- Tracking sets: `canceledDownloadIds`, `canceledRemuxRequests` (prevent state races)

## Development Patterns

Component skeleton

```
export class NewComponent {
  constructor() { this.isActive = false; this.handlers = []; }
  start(config) { this.stop(); this.isActive = true; this.setup(); }
  stop() { this.isActive = false; this.cleanup(); }
  onEvent(fn) { this.handlers.push(fn); }
}
```

Error handling

```
async performOperation(data) {
  try { const out = await this.execute(data); return { success: true, data: out }; }
  catch (e) { console.error(`${this.constructor.name}:`, e); return { success: false, error: e.message }; }
}
```

Adding a new mode

```
// 1) constants.js: add SELECTORS.NEW_MODE
// 2) ContentScriptController.isVideoModeSelector() if it’s a video mode
// 3) Implement behavior in content (startVideoMode/startNormalMode branches)
// 4) Popup: add option and selectorText
```

Adding a new component

```
src/content/new-component.js
src/shared/new-utility.js
src/background/new-service.js
// Update manifest.json content_scripts order accordingly
```

## Multi‑Tab Rules (Critical)

- Always pass and persist `tabId`; `TabState.toJSON()` includes it.
- Content must not write per‑tab keys without a known `tabId`.
- Do not add background decrements or 0‑triggers; content owns timing and actions.
- Speed Mode is per‑tab; ensure popup sends `speedMode` to content, and background sets `setSpeedModeBadge` per tab.
- Keep speed-mode segment remux queue-driven: do not add autoplay/seek hydration in content; queue the remux and let offscreen resolve percent-based windows from metadata.

## Chrome Extension Patterns

- Service worker messaging: return `true` from listeners when responding async.
- Handle tab removal: `chrome.tabs.onRemoved` cleans state and clears badges.
- Storage resume: content calls `getResumeState` (consolidated) or `shouldResumeOnThisTab` then `getTabState` and restarts with a short delay.

### Keyboard

- `Esc`: toggles Focus/Cinema mode on/off per tab (handled in content; persists via background `focusMode`).
- In-page shortcut takeover messages from injected page scripts are not trusted on their own; content must observe the matching trusted `keydown` before executing playback or next actions.

## Workflow & Ritual Governance

Workflows in `.agent/workflows/` are **Actionable Intelligence**. They transform static knowledge into executable checklists.

### Why Workflows?

1. **Reduce Cognitive Load**: Don't memorize 20-step release processes; follow the script.
2. **Safety Enforcement**: Workflows like `branch-guard` prevent accidental direct commits to `main`.
3. **Consistency**: Ensure every feature is documented, tested, and versioned identically.
4. **Agent Onboarding**: New or re-initialized agents can pick up the project's "rhythm" immediately.

### When to Create a Workflow?

- **Repetition**: If a task is performed more than once per release (e.g., Bug Fixes, Feature adds).
- **Complexity**: If a task involves >3 manual steps or cross-file data synchronization.
- **Risk**: If missing a step leads to broken builds, missing documentation, or version mismatch.
- **Aesthetics**: When quality/design standards must be verified (e.g., `ui-theme` check).

### How to Create?

Follow the `.agent/workflows/workflow-management.md` ritual.

- Keep steps atomic and actionable.
- Use `// turbo` for commands that are safe to run automatically.
- Integrate into `documentation-sync.md` to ensure the "meta-doc" stays updated.

## Testing Guidelines

Required order (run in sequence):

1. `npm run format:write`
2. `npm test`
3. `npm run test:e2e` (required before committing code; takes several minutes)

Unit

- Favor small component tests. Mock `chrome.*`, DOM, and timers.

Integration

- Validate message routing and event coordination across content components.

E2E (Playwright)

- Primary command: `npm run test:e2e` (packages `dist/AutoClickerPro-99-dev`, sets `EXTENSION_PATH`, and runs the root `playwright.config.js` against `tests/e2e/all-in-one-substep.spec.js`).
- Canary mode: `npm run test:e2e:canary` runs the same suite against the latest Chrome for Testing Canary build (if available under `C:\chrome-for-testing`). **Do not run canary mode unless specifically testing future browser compatibility.**

  - The unified all-in-one E2E test (`tests/e2e/all-in-one-substep.spec.js`) robustly covers extension startup, group navigation, detached player UI/controls, and substep progress reporting with per-substep timeouts. Use the `DISABLE_VIDEO_DOWNLOAD` flag to skip all video download/remux logic for fast test runs.
  - Mock host fixtures, captured assets, and the offline server live under `tests/e2e/mock-site/`.

When a suite fails, rerun only the failing test first (faster feedback), then rerun full required order before commit.

- Targeted E2E example (PowerShell):
  - `$env:EXTENSION_PATH='.\dist\AutoClickerPro-99-dev';npx playwright test tests/e2e/all-in-one-substep.spec.js --config=playwright.config.js --grep "Trigger segment remux once and verify offscreen activity"`
  - Playwright debug mode (inspector): add `$env:PWDEBUG=1`.
  - Full artifact debug capture (local): add `$env:PW_E2E_DEBUG_ARTIFACTS=1`.
  - Optional local debug only: add `$env:PW_SMOKE_KEEP_OPEN=1` to keep browser open.
  - Manual human debug option: run the targeted test with `PW_SMOKE_KEEP_OPEN=1`, then inspect extension popup/service worker logs and page behavior before closing the browser.
- Targeted unit examples:
  - `node --experimental-vm-modules ./node_modules/jest/bin/jest.js tests/unit/countdown-manager.test.js --runInBand`
  - `node --experimental-vm-modules ./node_modules/jest/bin/jest.js --runInBand -t "resumeCountdown"`

## Performance Notes

- Minimize DOM queries; cache selectors.
- Cleanup timers/listeners on stop.
- Batch DOM writes.
- Avoid frequent storage writes (no per‑tick persistence from background).
- Use `data-*` attributes pushed to `document.documentElement` to share runtime state between script contexts without hitting `getBoundingClientRect` overhead on multiple elements.
- Use recursive `setTimeout` with adaptive backoff instead of fixed-interval `setInterval` for constant polling functions to gracefully handle hidden or missing elements.
- Keep background threads event-driven; avoid repeating tasks unconditionally across all active tabs, and lazy-start any large cleanup intervals so idle tabs stay completely idle.

## Code Quality Targets

- Cyclomatic complexity < 10 per method
- Test coverage > 70% overall, > 90% critical paths
- Function length < 50 lines; file length reasonable
- Dependencies shallow; constants in `constants.js`

## Version Notes (v1.9.0)

### Progress Manager UI & Global Visibility

- Topbar now displays global progress: `"Completed X / Current Y / Queued Z (P%)"` + window title `"X/Y/Z P% - ..."` for at-a-glance queue status.
- `computeGlobalProgress(list)` aggregates job counts and calculates average percent.
- `renderGlobalProgress(list)` updates display on every render.

### Granular Queue Controls (split-menu UI)

- Replaced three separate buttons with split-button: `Clear completed` + dropdown toggle `▾`.
- Dropdown menu items: `Empty pending queue`, `Cancel running jobs`, `Clear all` (danger).
- Confirm-button UX: first click arms button, second click executes (prevents accidental actions).
- New background message handlers: `emptyPendingQueueJobs`, `cancelRunningJobs`, `clearAllJobs`.

### Per-Job Cancellation

- Individual `Cancel` button per job row in Manager list.
- Auto-disabled for terminal jobs (success/error/canceled).
- Calls `cancelJobById(jobId)` which routes to appropriate cleanup (download/remux/queued).

### Download Deletion & Robustness

- Detects file deletion (browser or OS) via `delta.exists.current === false`.
- Marks jobs as terminal error: `{ status: 'error', stage: 'download', message: 'Download deleted' }`.
- Prevents stuck "Downloading…" rows.

### Manager Window & Port Resilience

- Added `openManagerWindowPromise` lock to prevent duplicate manager windows from concurrent open requests.
- Manager now auto-reconnects `progress-ui` port after service-worker restart with `scheduleReconnect()` (700ms delay).
- Refreshes snapshot on reconnect to ensure UI stays in sync.

### Service-Worker Restart Recovery

- After service-worker restart, in-memory maps reset but jobs persist in `chrome.storage.local`.
- On download progress/completion events, background recovers job mapping from persisted `meta.downloadId`.
- Backfills `extensionDownloadIds` and `downloadIdToRequest` maps for subsequent progress updates.

### Cancellation Race Prevention

- Tracking sets `canceledDownloadIds` and `canceledRemuxRequests` mark canceled jobs.
- Progress/completion handlers check these sets and skip state updates for canceled jobs.
- Prevents canceled jobs from starting downloads when `downloadId` assignment races with cancellation.
- On interrupted downloads, checks if canceled and transitions to `{ status: 'canceled', message: 'Canceled by user' }` instead of error.

### Progress Bar Colors (v1.9.0+)

- State-based colors: `.bar-fill-running` (purple), `.bar-fill-queued` (slate), `.bar-fill-success` (green), `.bar-fill-error` (red), `.bar-fill-canceled` (orange).
- Manager applies color class based on job status/stage.

### v1.8.15 Baseline

- Remux queue dedupe short-circuits before queue insertion.
- Remux timeout windows shorter for faster recovery (90s heartbeat, 120s pending).
- Mock equivalent E2E standardized via `npm run test:e2e`.
- Progress Manager thumbnails, job metadata, remux fallback, aspect filters, segment defaults all persist from v1.8.15.

## v1.5.2 Addenda (Dev Facing)

- Shared Tab Params helper
  - File: `src/shared/tab-params.js`
  - Provides schema, normalize, merge and payload builders.
  - Use in Popup to build `start`/`startCountdown` payloads; in Content to normalize `start`.

- Canonical Message Types
  - File: `src/shared/constants.js` (MESSAGE_TYPES)
  - Prefer using constants in popup/content instead of inline strings.
  - See `devdocs/messaging-contracts.md` for contracts and required fields.

- Background Merge + Migration
  - Helper merge: rule-based, sticky `focusMode` (OR), clamp numeric ranges.
  - Lightweight migration hook upgrades `chrome.storage.local.activeTabs` to current schema on load and on-demand resume; persists only when changed.

- Focus/Cinema Controller
  - File: `src/content/focus-mode.js`
  - Encapsulates apply/re-apply/assert logic with a MutationObserver; debounced background assertions.

- Detached Player Transition Guards (v2.0.5+)
  - **Monotonic Source Guard**: `setSource` uses `payload.ts` to ignore out-of-order/stale heartbeats from old tabs.
  - **Source Tab Lockdown**: `setSource` enforces `sourceTabId` matching during active runs to prevent cross-talk.
  - **Forced Request Bypass**: `requestNextVideo(..., { force: true })` clears local prefetch guards to ensure end-of-video fallbacks always attempt a fresh fetch.
  - **Ready vs Activation Pending**: detached `next-ready` semantics are split. Warm/prefetch hits mean a prepared detached source exists and may switch immediately; group-page navigation commits without a prepared source must be treated as activation-pending and keep the UI in `Awaiting source...` until `initial-autoplay` or a later prefetch-hit arrives.
  - **Retry Suppression After Commit**: when background has already committed a group-page next navigation, detached must suppress watchdog/countdown/manual re-dispatches against the old source URL until the pending activation settles or times out.
  - **Authoritative Group-Next Ordering**: for detached group-page transitions, do not block the main-tab click/navigation on detached prefetch warm-up. Warm immediately, commit the main-tab next action, then let post-navigation prefetch apply land opportunistically.

- Debug/Telemetry
  - Background: concise merge diffs on `startCountdown`; enriched `setVideoMode` logs.
  - Content: `resumeCountdown` logged on `playing` transitions.
  - Optional send logs: set `AutoClickerConstants.DEBUG.LOG_MESSAGES = true` in page console to log outgoing message keys.
- Remux outputs (mediabunny)
  - Default container is MP4 (H.264 + AAC) via `AutoClickerConstants.REMUX_OUTPUT`; offscreen auto-falls back to WebM (VP9/VP8 + Opus) when H.264/AAC encoders are unavailable (e.g., Playwright/CI).
  - Offscreen assets live in `lib/webcodecs/` (`mediabunny-loader.js`, `mediabunny.min.mjs`); dist scripts drop the full build when minified is present.

## Release Workflow (follow this order, keep it lean)

- Start with a short feature doc (Markdown): goal, behavior, examples, tasks, open questions/decisions; get explicit answers before coding. Everything that changes sinces last tag/release.
- Implement change + tests, then validate locally (unit/integration/E2E) before touching versions. Correct code or tests until they pass.
- Bump version everywhere: `manifest.json`, README header + example zip name, `CHANGELOG.md` (move Unreleased), and add `devdocs/releases/vX.Y.Z.md`.
- Build release zip to `dist/` using `scripts/package-extension.ps1 -AppName "AutoClickerPro"` (add `-DevBuild` for `version_name=<version>-dev` and `-TargetName` if needed). Zips are flat (no extra root folder). Ensure `dist/` excludes test helpers like `src/tests` or anything that does not belong in a Chrome/Brave extension.
- Smoke test the built zip: load unpacked, start/stop in two tabs, verify badges, download trigger, and offscreen remux path if applicable.
- Commit (clear message), push, then create GitHub release + tag with name "AutoClickerPro vx.x.x" and notes about changes since last Github release/tag and attach the zip (replace asset if reissuing same tag).
- Release notes: use real newlines in GitHub release descriptions (avoid literal "\n") so bullets render correctly.

## Dev Scripts (Dist/Chrome)

- `scripts/package-extension.ps1`: canonical packager. `-DevBuild` sets `version_name=<version>-dev` in staged manifest and outputs `<AppName>-<version>-dev` zip/folder; zips are flat. Defaults to `scripts/package-config.json`.
- `scripts/launch-chrome-manual.ps1`: builds a dist copy and launches Chrome; if you need dev logging, run the packager with `-DevBuild` first.

## Release checklist (bump + publish)

- Bump version in `manifest.json`, README header and example zip name, `CHANGELOG.md`, and add `devdocs/releases/vX.Y.Z.md`
- Run targeted tests, build a versioned zip in `dist/` (include `ffmpeg/` assets if present), and ensure `dist/` excludes test helpers (e.g., `src/tests`)
- Smoke check: load unpacked, start/stop in two tabs, verify badges, downloads, and offscreen remux path
- Commit, push, tag, and publish the GitHub release with the zip asset

### Changelog discipline

- Follow "Keep a Changelog" style (Added / Changed / Fixed) with "Unreleased" at the top.
- Move Unreleased items into the versioned section during release.
- Release notes must match shipped binaries.
- If keeping devdocs release notes, use one convention: `devdocs/releases/vX.Y.Z.md` (max one file per version).

## Best Practices

- Use PowerShell cmdlets (Get-ChildItem, Get-Content, etc.) and `apply_patch`; avoid POSIX tools.
- Keep changes minimal and aligned with existing style; content owns countdown, background only mirrors badges.
- Always carry `tabId` through messages/state; never let background decrement time or trigger zero-actions.
- Prefer MESSAGE_TYPES/constants over inline strings; reuse tab-params helpers; keep focusMode sticky on merges; ignore `focusMode:false` overrides if already true.
- Run targeted tests after changes; update docs/release notes alongside features; log sparingly (only useful single-line signals with context).
- Respect per-tab isolation (speed/watch) and dedupe guards (e.g., `_lastSegmentKey`); avoid cross-tab writes without a known `tabId`.
- Clamp numeric inputs defensively (durations, percents) and keep segment flows consistent (remux/range/capture fallback order).

References

- `devdocs/per-tab-params-consistency.md`
- `devdocs/per-tab-params-sync-plan.md`
- `devdocs/messaging-contracts.md`
- `devdocs/per-tab-param-cookbook.md`
- `devdocs/dedupe-start-stabilization-plan.md`
- `devdocs/dedupe-start-stabilization-checklist.md`
- Docs reorganized: dev docs under `devdocs/`, `HOWTO.md` at root.

## Addendum (up to v1.8.7)

- Focus/Cinema mode: overlay controls (progress/volume/Next), Esc toggle, in‑page “×”.
- Per‑tab focusMode persistence with background merge + pending intent; ignore false overrides.
- Playback → countdown sync: content sends `resumeCountdown` on `playing` transitions for badge consistency.

## Quick Checklists

Starting a run

- Popup: prepare payload with `selector, interval, saveVideo, speedMode, startAtPercent, tabId`.
- Background: create/update TabState; render badge.
- Content: start controller; if video mode and not speed, start CountdownManager and VideoDetector.

Resume after reload

- Content: ask background `getResumeState` (consolidated); use `state.tabId || currentTabId` and call `start(...)`.

Two‑tab isolation

- Tab A normal vs Tab B speed: badges and behaviors remain independent; stop in one does not affect the other.
