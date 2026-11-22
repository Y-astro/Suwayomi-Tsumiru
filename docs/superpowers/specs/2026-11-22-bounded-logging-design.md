# Detailed bounded app and server logs

Backlog item 3 only. The user confirmed **20 MB per application**, including
active and rotated log files, for 40 MB combined. This design uses 20,000,000
bytes per application and retains recent events by removing the oldest logs.
The user approved this design with “go ahead with the plan”.

## Locations

- Phone: `/storage/emulated/0/Suwayomi/logs`, inside the Suwayomi folder shown
  in the user's File Browser screenshot. The folder mapping was verified.
- Laptop: `/home/astro/repos/tsumiru/logs`, beside the maintained Tsumiru fork.
  Ignore the entire directory in Git. Keep the app portable with its existing
  application-support directory as the default when no custom location is set.

## Approach

Extend existing Tsumiru diagnostics and Suwayomi logging. Keep logs local to
their respective machines, with readable timestamps, event names, severity,
operation/chapter identifiers where relevant, outcomes, durations, and error
stack traces. No remote collector or telemetry service is introduced.

The app's current crash sink stores roughly 256 KB and performs synchronous
writes. Move routine diagnostic I/O off the UI isolate, with bounded buffering
and size-based rotation. Keep startup/crash reporting, existing copy/clear
controls, and web compatibility working. Existing logger events must also be
retained in release builds. Reuse the existing diagnostics entry point.

Capture startup and lifecycle, navigation, settings changes, API operations and
timings, library updates and retries, read-state synchronization, download and
offline work, warnings, and failures. Log meaningful activity transitions rather
than frame rendering or raw image/page contents. Preserve reader/native behavior.

On the server, first reuse its existing Logback/settings support. Account for
the active file, archives, and duplicate stdout/stderr capture when enforcing
the 20 MB budget. Add only the minimum server change needed if existing settings
cannot enforce that combined bound or publish at the requested path. The
read-only diagnosis confirmed that periodic supervisor cleanup and Logback's
archive cap are not a strict aggregate limit. Use a single coordinated bounded
capture path for Suwayomi and its helper streams, retaining the direct Java
service lifecycle. Do not depend on periodic cleanup to enforce the byte cap.

Redact credentials before persistence and console output: passwords, access and
refresh tokens, cookies, authorization headers, and credential-bearing URLs.
Do not dump request/response bodies or settings values that may contain secrets.
Log files may contain reading/activity identifiers, as requested for diagnosis.

## Retention and compatibility

Rotation deletes oldest owned logs first. Oversized individual entries must not
break the cap. Import recent owned legacy entries into the same budget after
redaction, pruning oldest entries when necessary; do not duplicate the old log
set outside the new budget or delete unrelated service logs. Copy/clear,
restart, rapid writes, and unavailable storage must behave safely. Disk failures
must not crash or stall the app. A hard process/power kill can lose buffered
events that have not reached disk; no logger can preserve unflushed memory.

Keep the custom server at v2.4.2366/r2366. Preserve the installed retry,
downloader, library-query, Android, and WebUI customizations. No upstream upgrade,
reader change, or work on backlog items 4 and 5.

## Verification and delivery

Test aggregate byte caps at UTF-8 and rotation boundaries, oversized records,
restart, rapid writes, redaction, request outcomes, and copy/clear behavior.
Compare logging overhead and verify release-build event capture without
mutating production reading progress. Check real phone storage visibility and
runtime survival. Use the maintained reviewed server release mechanisms with
backups and an idle activation window. Install the verified laptop build and
push completed changes to the user's fork through AGY. Do not create a PR.
