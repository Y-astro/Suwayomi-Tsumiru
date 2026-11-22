# Detailed Bounded Logging Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for inline app implementation and bounded AGY execution for the independent server component.

**Goal:** Retain useful app/server activity logs with a strict 20,000,000-byte budget each.

**Architecture:** Reuse the app diagnostic sink with asynchronous bounded file I/O and release event capture. Route Suwayomi-related process output through coordinated bounded capture, removing duplicate application file output. Keep Java as the directly managed service process and retain reviewed deployment controls.

**Tech Stack:** Existing Dart/Flutter/logger/GraphQL; Python standard library in maintained mobile-server operations; existing Kotlin/Logback where required. No new dependency or upstream upgrade.

**Spec:** `docs/superpowers/specs/2026-11-22-bounded-logging-design.md` (approved).

## Global constraints

- Budget: 20,000,000 bytes per application, including active and rotated logs.
- Phone path: `/storage/emulated/0/Suwayomi/logs`.
- Laptop path: `/home/astro/repos/tsumiru/logs`, ignored by Git; portable default remains application support.
- Preserve reader/native behavior and custom server v2.4.2366/r2366.
- Redact before disk/console; never emit whole request bodies, credentials, or settings values.
- Source must be committed before controlled phone deployment. No PRs; push the verified fork through AGY.

## Review focus

- One huge UTF-8 record and simultaneous producers must not defeat aggregate caps.
- A stopped/disk-failing log writer must not crash or indefinitely block the app/server.
- Copy/clear and shutdown must serialize with queued writes without resurrecting cleared history.
- Supervisor replacement and short-lived control commands must not kill log capture or orphan Java ownership.
- Migration must preserve recent useful records without leaving duplicate legacy application logs outside the budget.

## Task 1: App storage, redaction, and activity capture (root)

**Files:** Existing `lib/src/utils/crash/{crash_log_io.dart,crash_log_stub.dart,diagnostics.dart,redact_tokens.dart,copy_crash_log.dart}`, new `lib/src/utils/crash/bounded_log_store_io.dart`; existing logger/link, `lib/main.dart`, route configuration, shared-preference mixins, crash-copy UI callers; matching tests and `.gitignore`.

**Interfaces:** Keep `initCrashLog(): Future<String?>`. Make `writeCrashLog(String?, String): Future<void>`, `readCrashLog(String?): Future<String?>`, `clearCrashLog(String?): Future<void>`, and `crashLogForClipboard(...): Future<String?>` consistently awaitable at all existing callers. Error sinks remain fire-and-forget and never propagate storage failures. Use asynchronous filesystem calls, a serialized bounded queue, and no synchronous normal-event flush on the UI thread.

- [ ] Write tests for 2,000,000-byte segments/20,000,000-byte aggregate bounds, UTF-8, oversize records, restart, copy/clear order, queue overload reporting, and unavailable storage. Observe failures before implementing.
- [ ] Implement the bounded store and queued sink; use `TSUMIRU_LOG_DIR` for the laptop override and migrate/redact owned legacy crash data inside the same budget. Keep web stubs compatible.
- [ ] Extend redaction to auth headers, cookies, secret assignments, query credentials and URL userinfo. Test representative real-looking secrets before changing capture levels.
- [ ] Enable existing logger events in release builds, persist sanitized output, and log GraphQL operation names/allowlisted identifiers, elapsed time and outcomes without bodies. Avoid unbounded subscription-payload logs.
- [ ] Add central navigation/lifecycle and settings-key change events. Reuse existing offline/download diagnostics; do not edit reader files or log per-frame state.
- [ ] Update existing copy/clear/crash-screen callers and tests for ordered async reads. Test failures, stream cancellation, sensitive inputs, and release logging filters.
- [ ] Run focused tests/analysis and commit this independently testable component.

## Task 2: Server storage and capture (bounded AGY implementation)

**Files:** Isolated worktree of `/home/astro/repos/mobile-server` from current HEAD: `scripts/server_supervisor.py`, `scripts/start_suwayomi.sh`, `scripts/suwayomi_{daily_update,graphql_filter}.py`, a new maintained `app/suwayomi_logs.py` capture/rotation helper, focused tests, and exact deployment-profile compatibility pins where required. Minimal pinned Kotlin logging patch under `tool/server/` in Tsumiru, from the existing server checkout, only if needed to suppress duplicate Logback file output. No live edits.

**Interfaces:** Python capture CLI consumes bounded stdin records tagged by service name and appends through a cross-process coordinated store at the approved phone path. Every producer shares the same 20,000,000-byte budget and 2,000,000-byte rotation segments; credentials are sanitized before persistence. Capture must survive the launching CLI/SSH session and exit after stream EOF. Keep Java as the actual service PID, with no Java launch wrapper or new managed daemon.

- [ ] Reproduce the old cap failure with oversized/incompressible data. The old proof's compressed output below its configured limit is not cap verification; supervisor polling is not a hard bound.
- [ ] Add failing tests for aggregate bounds, huge records, multi-process writers, Unicode, redaction, pipe draining on disk failure, EOF and control-parent exit. Preserve unrelated service launch behavior and disabled flags.
- [ ] Implement coordinated capture of Java stdout/stderr and Suwayomi helper output. Stop duplicate application file appenders/handlers in bounded mode while keeping default behavior outside that mode.
- [ ] Import/prune exact owned legacy logs safely; never sweep unrelated service logs or expose raw credentials. Verify visible-folder publication with source-owned controls.
- [ ] Build and test any minimal Kotlin logging patch against the pinned base JAR `b42be40c310af37a6f5d9a4bdf3fd0ab57b6cfb90ce10c1ab6fc4e12d5d9c403`. Replace only reviewed class owners, preserve all other ZIP entries, and test the packaged runtime.
- [ ] Supply reproducible source patches, focused tests, cap proofs, and a reviewed activation plan/rollback path. Do not weaken unknown-hash or lifecycle refusals. Stop with concrete evidence if a required invariant cannot be preserved.

## Task 3: Integrate, verify, and deliver (root)

- [ ] Inspect the decisive server diff and cap/runtime proofs; correct important findings once.
- [ ] Run final app suite, scoped analysis, Linux release build, and copied-build startup/resize/close. Compare burst logging overhead and verify the release build writes useful sanitized events.
- [ ] Commit verified server/app source before deployment. Stage complete release manifests with exact live preconditions and rollback assets. Use separate controlled operations/JAR activations if the existing profiles require them; preserve all unrelated live drift.
- [ ] Activate only while relevant jobs/downloads are idle. Verify all owned hashes, actual requested paths in File Browser, aggregate caps after bursts/restart, API health, process ownership and SSH-disconnection survival. Do not mutate production reading progress for testing.
- [ ] Update the laptop launcher with the tested build and `TSUMIRU_LOG_DIR` override, preserving old versions and launcher backup. Verify log rotation/copy/clear at that path.
- [ ] Record exact coverage/limitations, update backlog, and have AGY push verified changes to the fork without a PR.
