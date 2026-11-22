# Library update retries: pinned server patch

This implements custom upgrade 2 alongside Tsumiru's client cache invalidation.
The server clears a tracked failure only after chapters synchronize successfully.
Metadata refreshes, stored chapter reads, and failed GraphQL fetches do not clear it.
Queue results are recorded before releasing the per-title fetch mutex, so a later
successful manual refresh cannot be overwritten by an earlier failed queue job.
A source-channel failure affects only that source's pending/running jobs.

After a main library/category update finishes, remaining failures retry at +1h
and +2h. Both deadlines use the main completion timestamp. The server checks
deadlines every 30 seconds, waits until idle, and reuses normal source queues and
concurrency limits. New main updates and Stop cancel the previous retry cycle.
Successful titles leave the retry set. Deleted or removed library titles are
excluded at dispatch. Unresolved failures stay visible after attempt two.

The plan persists under `libraryUpdateRetriesV1` in existing `server_util`
preferences. Closing Tsumiru does not stop it. After server sleep/restart, two
missed slots coalesce into the latest due attempt. Reserving a slot before
dispatch prevents duplicate scheduling; a crash during dispatch can consume that
slot. A crash before the main update finishes has no completed retry plan to
restore. No schema or database migration is involved.

## Reproduce

Use a separate checkout of Suwayomi-Server commit
`40bc5da57820324ed0ae724cbbc020cc4673b594` (v2.4.2366), its Gradle wrapper,
Kotlin 2.4.10, and JVM target 21. The patch also pins the mutable Android stubs
repository to commit `3983289d9481a8ba99c0b16350b27f41364906a2`; its stubs JAR
SHA-256 is `2743be4f4c9ba50f8c86ccc0769e5be5246542488b34e6085a2574ca8ac303e3`.

With `tsumiru` pointing to this checkout and `server` to the separate server checkout:

```sh
git -C "$server" apply "$tsumiru/tool/server/library-update-retries-v2.4.2366.patch"
cd "$server"
./gradlew :server:test --no-daemon \
  --init-script "$tsumiru/tool/server/isolated-tests.init.gradle.kts"
```

The isolated test script gives each class its own JVM because upstream CEF and
ApplicationTest fixtures have incompatible global Koin lifecycles. New tests
cover deadlines, two-attempt bounds, restart serialization, sleep, busy updates,
reset, title removal, actual chapter writes, metadata-only and failed refreshes,
main-completion persistence, and source isolation. Client tests cover provider
refresh and partial GraphQL errors without per-progress-tick queries.

## Preserve the installed custom server

Do not install a fresh upstream JAR over the custom server. Its downloader,
library-query, Android, and embedded WebUI fixes must remain. The packager accepts
only the reviewed installed base SHA-256
`16e21700dfd60cab4b9f113839dc2c04d10066df896ad3bc8d31522801bc695f`.
It replaces six class owners and their nested classes, removes their obsolete
classes, requires Java 21 bytecode, and verifies every other ZIP occurrence is
unchanged, including duplicate resources and the original manifest. Separate
provenance records the base, source patch, and replacement class hashes.

```sh
python3 "$tsumiru/tool/server/package_update_retries.py" \
  --base /path/to/verified-installed.jar \
  --classes "$server/server/build/classes/kotlin/main" \
  --patch "$tsumiru/tool/server/library-update-retries-v2.4.2366.patch" \
  --output /path/to/new-candidate.jar
./gradlew :server:test --tests '*LibraryUpdate*Test' --no-daemon \
  --init-script "$tsumiru/tool/server/packaged-tests.init.gradle.kts" \
  -Dtsumiru.server.jar=/path/to/new-candidate.jar
python3 -m unittest discover -s "$tsumiru/tool/server" -p 'test_*.py'
```

Packaged verification puts the candidate first and checks class origins and
method linkage. Activation uses the maintained mobile-server `suwayomi-jar`
release profile with a complete hashed manifest, exact live preconditions,
only the JAR changed, backend-only restart, and retained recovery preimages.
Unrelated live drift must be preserved in the candidate's frozen unchanged
assets. Do not bypass activation checks or restart unrelated services.
