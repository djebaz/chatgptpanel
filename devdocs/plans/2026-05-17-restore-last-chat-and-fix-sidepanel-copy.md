# Plan: restore last chat and fix side panel copy

## Scope
- In: Persist the last visited ChatGPT URL across popup window, tab, and side panel launches.
- In: Improve side panel clipboard behavior so ChatGPT's built-in copy buttons work more reliably inside the iframe host.
- Out: Draft restore, multi-entry history, or changes to the overall side panel architecture.

## Action items
- [x] Check repo guidance, git state, and branch off `main`.
- [x] Add a shared last-URL persistence flow through the extension background/service worker.
- [x] Update popup, tab, and side panel launch flows to reuse the stored URL with a default fallback.
- [x] Add a ChatGPT content script for SPA URL tracking and side-panel copy fallback signaling.
- [x] Replace isolated-world history patching with live URL watchers so ChatGPT SPA route changes persist reliably.
- [x] Update side panel host logic to restore the iframe URL and perform extension-side fallback copy writes.
- [x] Sync packaging allowlist and user-facing docs.
- [ ] Validation: USER

## Decisions
- Use one shared last ChatGPT URL across all launch modes.
- Persist the URL in `chrome.storage.local`.
- Keep the existing side panel iframe approach and add clipboard fallback without extra visible UI.

## Open questions
- None.

## Validation
- [ ] Tests: USER
- [ ] Smoke: USER
