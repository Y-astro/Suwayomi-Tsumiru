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
- [x] Package a pinned reproducible backend patch and review the complete diff.
- [x] Back up/stage server, deploy only when idle, and verify detached API health.
- [x] Install verified app build and update backlog.
- [ ] Push verified changes to the fork without a PR.

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
production retry cycle has not been triggered for testing.

Code was committed before activation. AGY's bounded review found no important
defects; root verified the diff and candidate provenance. The reviewed release
transaction `act_bb0477cd0311` completed successfully and restarted only Suwayomi.
Independent post-activation checks verified all 58 owned hashes, sizes, owners,
modes, and the unchanged boot-link identity. API health and the same Java 21
process survived an SSH disconnect for at least 49 seconds.

Server version remains v2.4.2366 / r2366. Only the six reviewed class groups were
replaced; all other JAR entries and the original manifest remain unchanged.
The original custom JAR and transaction recovery assets are retained. The desktop
launcher now points to the standalone `7faed5e8` release copy, whose installed
startup/resize/close check exits 0. Reader and native-engine source remain unchanged.
