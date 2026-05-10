# Plan: multi-open-popup

## Scope

- In: Add an extension popup (`popup.html` / `popup.js`) with 3 buttons: Side Panel, Window Popup, New Tab. Update manifest to use action popup. Include rules.json to allow framing chatgpt.com in side panel.
- Out: Complex styling.

## Action items

- [ ] Create `src/popup.html` and `src/popup.js`
- [ ] Create `src/sidepanel.html`
- [ ] Create `src/rules.json` to strip X-Frame-Options for side panel iframe
- [ ] Update `src/manifest.json`
- [ ] Update package-config.json to include new files
- [ ] Docs Sync (README.md, devdocs/releases/unreleased.md)

## Decisions

- Use `chrome.sidePanel.open` and declarativeNetRequest to bypass iframe restrictions.

## Open questions

- None

## Validation

- [ ] Tests: USER
- [ ] Smoke: USER
