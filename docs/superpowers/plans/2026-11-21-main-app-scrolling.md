# Main-app scrolling implementation plan

> **For agentic workers:** Use the requested AGY worker for bounded execution;
> Codex owns design, integration and acceptance. Follow the test-first workflow.

**Goal:** Smooth main-app mouse-wheel scrolling and remove the desktop Library
trackpad start delay while preserving the reader.

**Architecture:** Main-navigation-only wheel scope and per-scrollable target
metadata reuse the existing reader wheel follower unchanged. A Library-only
gesture setting tunes the inner desktop tab body, not its horizontal pager.

**Tech stack:** Pinned Flutter 3.47.9, existing material_ui widgets, existing
native high-refresh embedder and Flutter widget tests. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-21-main-app-scrolling-design.md`

## Constraints

- Implement item 1 only. Do not edit reader files or the native engine.
- Preserve Updates/History trackpad behavior, mobile behavior and reduced motion.
- No server calls, keyring access or production state in automated tests.
- Preserve the active installed process. Do not create a PR.

## Tasks

- [x] Verify wheel jumps and compare standalone versus nested trackpad onset.
- [x] Add regression tests that fail for the demonstrated behaviors.
- [x] Add a main-navigation-only wheel scope in a focused shared widget file;
      integrate target decoration in `AppScrollBehavior` and scope activation in
      `NavigationShellScreen`. Reuse `MouseWheelSpeed` without changing it.
- [x] Apply the desktop Library inner-tab gesture setting and verify its actual
      screen fixture, fractional panning, tab switching and control behavior.
- [x] Run focused scrolling, shell, library and reader regressions plus analysis.
- [x] Build and smoke the release app with local content and isolated data.
- [x] Review the diff, verify reader and native sources unchanged, commit and
      push to the fork without a PR, then deploy a verified stable launcher build.


## Follow-up after the user's feel check

- [x] Reproduce cached-cover rendering separately from network loading, using
      the real cover widget, actual app theme and compositor feedback.
- [x] Discard shadow, title-row, gradient-removal and cache-hint experiments;
      retain the measured shared-texture scrim after pixel comparisons.
- [x] Increase main-navigation wheel distance from 1.0 to 1.7 without touching
      reader preferences or History's trackpad path.
- [x] Disable desktop pull-to-refresh throughout main-app sections. Preserve
      mobile pull gestures and explicit update controls; verify real input.
- [x] Run all 997 tests, scoped analysis and a native release build.

Evidence and limits: `docs/architecture/cover-grid-performance.md`. Physical
full-library feel remains the user's acceptance check. Items 2–5 stay queued.
