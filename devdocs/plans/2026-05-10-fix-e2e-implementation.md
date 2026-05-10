# Plan: Fix E2E Implementation

## Scope

- In: Review and fix `tests/e2e/all-in-one-substep.spec.js` for Playwright/Chrome Extension compatibility.
- Out: New tests, smoke tests, validation.

## Action items

- [ ] Review `tests/e2e/all-in-one-substep.spec.js` for common pitfalls:
  - Service worker detection timing.
  - Extension ID extraction.
  - Popup URL construction.
  - Selector robustness.
- [ ] Update `unreleased.md` with PR footer.
- [ ] Create PR.

## Decisions

- Stick to the existing mock strategy but ensure it's robust.

## Open questions

- None.

## Validation

- [ ] Tests: USER
- [ ] Smoke: USER
