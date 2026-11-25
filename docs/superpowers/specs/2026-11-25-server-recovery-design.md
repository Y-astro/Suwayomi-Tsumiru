# Server recovery after late extension fixes

## User-authorized behavior

Extend failed library-update recovery from +1/+2 hours to +1/+2/+6/+12 hours after main update completion. Every six hours, check configured extension repositories and auto-update installed extensions. The intended outcome is recovery when a source extension fix arrives after the old two-hour deadline. Everything runs on the phone server, independent of desktop Tsumiru.

The investigation found all 132 library updates complete but six chapter downloads in ERROR after three attempts, with UnknownHostException for gg.asuracomic.net. Increasing only library retries would not recover this case. Therefore the recovery schedule must also retry failed unread, not-downloaded chapter queue entries. Do not treat a successful chapter-list update as a successful file download.

## Chosen design

Build on the existing pinned native updater patch and normal extension/download APIs. Preserve +1/+2 semantics and add +6/+12 absolute deadlines. Persist deadlines and consumed slots across server restart and Android sleep, coalescing missed slots. Preserve successful-title reconciliation and visible unresolved errors. Failed-download recovery has its own persisted cycle clock when no library failures remain; removing the last library failure must not cancel download recovery.

Check extensions on an independent persistent six-hour clock, including an initial check when no previous check exists. Update only installed packages advertising an update from existing configured repositories; never install unrelated extensions or upgrade Suwayomi itself. Run updates while library/download work is idle, update extensions before recovery when deadlines coincide, and log per-package outcomes without secrets. A successfully updated extension may trigger one recovery of its affected failed downloads so a newly available fix is useful; unchanged or failed extension checks must not repeatedly restart download errors. Four scheduled recovery slots remain bounded per daily cycle.

Use existing source queues, concurrency limits, repository trust, extension installation, and bounded logging. Retry only entries still in ERROR, unread, in library, and not already downloaded; preserve removals, successful downloads, active work, and deliberate paused queued work. Do not clear errors on attempted recovery alone. Do not overlap maintenance dispatch, duplicate queue entries, or reset the midnight schedule.

## Preservation and acceptance

No reader, Flutter/native engine, app updater, downloads cleanup/category exclusions, library counts, upstream server version, configured repositories, global services, or disabled flags change. Base JAR is the exact current customized r2366 archive with SHA-256 a8f28de60db71e874e0930c5ba0abd8487dce7597b48abdc54bea146634676c3. Replace only explicit reviewed application class owners; preserve every unrelated ZIP occurrence, existing provenance, custom WebUI/Android/downloader/logging classes and dependencies. No fresh upstream server JAR. No PR.

Prove timing boundaries, migration of attempts 0..2, serialization/restart/sleep, success/removal/cancellation, empty library failures with download errors, extension-installed-only filtering, failure isolation, ordering, and no work while busy. Verify candidate production class origins/linkage before controlled full-manifest JAR-only activation. Do not trigger a full live library update for testing.

## Limits

Recovery requires a working published extension fix and reachable source servers. Broken new extensions, DNS/site outages, CAPTCHA/authentication, repository outages, and fixes released after the final slot are not guaranteed to heal. A later successful extension update can recover its affected failed downloads; otherwise the next daily update starts the next bounded cycle.
