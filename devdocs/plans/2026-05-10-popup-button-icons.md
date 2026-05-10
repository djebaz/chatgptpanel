# Plan: Add SVG Icons to Popup Buttons

## Scope
- In: Add SVG icons (ChatGPT-style outline icons) to the right of the text in `popup.html` buttons. Update CSS to align them properly.
- Out: Any other UI changes, changing functionality.

## Action items
- [ ] Inspect `src/popup.html` and `src/popup.css`.
- [ ] Add SVG elements to the buttons in `popup.html`.
- [ ] Update `src/popup.css` to align text and SVGs (flexbox).
- [ ] Sync release docs.
- [ ] Commit and PR.

## Decisions
- Icons will be placed inside the `<button>` tags, after the text span, styled with `display: flex; justify-content: space-between; align-items: center;`.
- SVGs will use `currentColor` to respect existing button text colors.
- Changed wording from "Open in Window" to "Open in PopUp" per user request.

## Open questions
- None.

## Validation
- [ ] Tests: USER
- [ ] Smoke: USER
