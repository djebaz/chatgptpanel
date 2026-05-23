# Plan: Filter ChatGPT stored URL

## Scope
- In: Prevent internal ChatGPT frame/backend URLs from being stored or launched as `lastChatGptUrl`.
- In: Package a version 99 dev build for user smoke testing after the fix.
- Out: New tests, unit test runs, E2E runs, and smoke tests.

## Action items
- [x] Inspect branch state and URL persistence code.
- [x] Add a strict restorable ChatGPT URL filter.
- [x] Sync release-facing notes.
- [x] Package `ChatPTPanel-99-dev` for user smoke testing.
- [ ] Commit, push, and open a PR to `main`.

## Decisions and Design Changes
- 2026-05-23 Store only canonical ChatGPT home or conversation URLs: `https://chatgpt.com/`, `https://chatgpt.com/c/<uuid>`, or `https://chatgpt.com/<uuid>`.
- 2026-05-23 Treat `https://chatgpt.com/backend-api/...` and other internal paths as non-restorable so iframe/helper pages cannot poison reopen storage.
- 2026-05-23 Repair corrupt stored reopen values to `https://chatgpt.com/`, while ignoring bad incoming frame URLs so they do not overwrite an existing valid chat URL.
- 2026-05-23 Use the repo package script spelling `-DevBuild` with `-Version 99` for the smoke artifact.
- 2026-05-23 Packaged `dist/ChatPTPanel-99-dev.zip` for user smoke testing.

## Open questions
- None.

## Validation
- [x] Tests were not run.
- [x] Smoke tests were not run.
- [x] Final tests and smoke tests deferred to user.
