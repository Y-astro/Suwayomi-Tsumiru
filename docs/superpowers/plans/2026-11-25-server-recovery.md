# Server Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Recover failed chapter downloads and library syncs after late extension fixes, with four bounded deadlines and six-hour extension maintenance.

**Architecture:** Extend the existing native updater patch at the pinned r2366 source revision. Keep persistent library, failed-download and extension-maintenance clocks separate where cancellation and success semantics differ; reuse existing queues and extension APIs, with network work outside lifecycle locks. Package explicit class owners over the exact current custom JAR.

**Tech Stack:** Kotlin/JVM 21, existing coroutines/serialization/SharedPreferences, Gradle/JUnit, Python ZIP packaging and existing controlled mobile-server activation.

**Spec:** `docs/superpowers/specs/2026-11-25-server-recovery-design.md`

## Global Constraints

- Deadlines are +1, +2, +6 and +12 hours after main completion, followed by no further scheduled attempts for that cycle.
- Installed extension checks recur every six hours and survive restart. Existing repositories only.
- Preserve custom r2366 JAR base SHA-256 a8f28de60db71e874e0930c5ba0abd8487dce7597b48abdc54bea146634676c3 and all unrelated ZIP entries, including duplicate names and prior provenance.
- No reader/client/native-engine changes, upstream upgrade, PR, full live library-update test or unrelated service restart.
- Maintain and commit code before controlled manifest-verified activation. Root owns deployment and acceptance.

## Review Focus

- All library titles sync successfully while file downloads fail: download deadlines must still arm and survive library reconciliation.
- Android sleeps past several deadlines: coalesce rather than burst or repeat consumed attempts.
- A user reads/removes a failed chapter or pauses unrelated queued work: do not recreate or resume that work.
- An extension scan/update fails or returns no new versions: do not loop or falsely clear errors.
- A new extension becomes available at a retry deadline: install before retry and avoid concurrent duplicate dispatch.

### Task 1: Extend native recovery and pin regression tests

**Files:** Modify `tool/server/library-update-retries-v2.4.2366.patch`; generated source changes stay in an ignored isolated checkout of upstream commit `40bc5da57820324ed0ae724cbbc020cc4673b594`.

**Interfaces:** Existing `LibraryUpdateRetries`, `LibraryUpdateRetryState` and `Updater` lifecycle hooks. Add narrowly scoped maintenance policy/state classes only as needed for deterministic clock/dependency tests.

- [x] Build a fresh isolated upstream source checkout and apply the existing maintained patch; never modify the earlier dirty server-source checkout.
- [x] Add failing tests for four deadlines, persistence/migration, missed slots, successful reconciliation, failed-download eligibility and the five review-focus cases.
- [x] Implement +1/+2/+6/+12 library retries, persistent failed-download recovery, and six-hour installed-extension update scheduling using existing APIs.
- [x] Run relevant unit and updater integration tests through existing isolated test harness; regenerate the complete maintained patch from the pinned clean source baseline.

### Task 2: Package and verify the existing custom server

**Files:** Modify or extend `tool/server/package_update_retries.py`, its Python tests, `tool/server/packaged-tests.init.gradle.kts`, and `tool/server/README.md`.

**Interfaces:** An exact fingerprinted installed JAR input, Java 21 compiled application classes, explicit owner list, and new versioned provenance without deleting existing provenance.

- [x] Add failing packaging tests for the current already-patched base, new owner coverage, wrong-base refusal, preservation of every unrelated entry/occurrence and existing metadata.
- [x] Implement the minimum versioned overlay packaging needed; do not broaden arbitrary class selection or disable integrity checks.
- [x] Compile selected production classes; run relevant tests against packaged candidate and verify class origins/linkage.
- [x] Commit reviewed source, patch, tests, plan progress and README. Report exact artifact hashes and unresolved limits. No live mutation, credentials, installs, remote push, PR or deployment from the worker.

### Task 3: Root controlled deployment and acceptance

- [x] Independently inspect decisive source/diff and test results; verify exact live JAR preimage and fresh full owned-file/process/disabled-flag baseline.
- [x] Stage complete release manifest, preserving every unchanged live asset and drift. Review JAR-only activation plan.
- [x] Activate through existing mobile-server release mechanism; verify backend health, unrelated service identities, disabled flags, midnight schedule, log cap and detached survival.
- [x] Verify safe maintenance status without forcing a complete library update; report future clock-cycle validation limits honestly.
- [x] Fast-forward reviewed source onto the user's app branch and push fork; no PR. Client build need not change for server-only logic.


## Root acceptance, 2026-11-25

Root corrected late image-failure capture, fresh read-state checks, paused-queue preservation, library-dispatch locking, omitted extension-clock source, and unnecessary overlay owners after worker review. The maintained patch reproduces all 12 source/test files from the pinned source. Actual final results: 22 packaged native tests, 4 packaging tests, and 160 activation tests passed.

Controlled activation completed with one JAR change in the full 59-file manifest. Only backend Java and its log capture restarted; unrelated process identities, eight disabled-service flags, midnight Reading schedule and bounded logging remained intact. The first automatic extension check ran and persisted its timestamp. Five remaining stuck downloads finished, with all five CBZs and 104 image pages verified. Source was fast-forwarded and pushed to the user's fork on its active main branch, without a PR. Desktop binaries and reader files did not change.

The real +1/+2/+6/+12-hour recovery windows and the next six-hour extension scan have not elapsed; deterministic clocks, serialization tests and the initial production scan cover their implementation.
