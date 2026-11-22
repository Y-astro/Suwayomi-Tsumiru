# Library Update Retries Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Clear repaired library errors and retry remaining failures twice.

**Architecture:** Persist a bounded retry plan in server preferences; dispatch
through existing updater queues. Reconcile errors only after chapter sync.
Invalidate existing client error providers when their server data changes.

**Tech Stack:** Kotlin/JVM 21, existing Gradle/serialization/coroutines; Flutter/Riverpod.

**Spec:** `docs/superpowers/specs/2026-11-22-library-update-retries-design.md`.

## Constraints

Preserve reader and native high refresh. No PRs. No private configuration or
binaries in git. Work only on backlog item 2. Main completion anchors both hours.

## Tasks

- [x] Add deterministic retry-policy tests, then implement persistence/timing.
- [x] Integrate main completion, reset, queue dispatch, and successful chapter
  reconciliation in the pinned backend. Verify source-failure isolation.
- [x] Test and fix client error list/count invalidation, including GraphQL errors.
- [x] Run backend tests/lint/build and relevant Flutter checks/build.
- [ ] Package a pinned reproducible backend patch and review the complete diff.
- [ ] Back up/stage server, deploy only when idle, and verify detached API health.
- [ ] Install verified app build, push fork without a PR, and update backlog.

## Verification ledger

Client: 1,005 tests pass, scoped analysis clean, native release build passes.
Isolated startup/resize/close exits 0; existing native shutdown warnings remain.
Backend: 73 tests pass with a JVM per test class, avoiding upstream CEF/Koin
global-state conflicts. Nine policy/integration tests also pass with the packaged
candidate first on the classpath. Three Python packaging tests pass. The patch
applies cleanly to the pinned source. Public JVM signatures remain compatible;
private synthetic accessors and their nested class owners are replaced together.

The phone's reviewed activation plan selects only `suwayomi` and its JAR. All
57 other owned files remain unchanged, including frozen live preimages where
the maintained mobile-server checkout differs. Existing download/library-query
customizations are preserved. The live baseline is idle with zero failures.

The two-hour schedule is verified with deterministic clock tests. A real two-hour
production retry cycle has not been triggered for testing. Commit before live
activation, then record activation and detached survival results.
