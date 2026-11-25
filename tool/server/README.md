# Late Server Recovery & Extension Maintenance: pinned server patch

This implements late server recovery alongside Tsumiru's client cache invalidation.
The server recovers failed library updates and unread, not-downloaded failed chapter downloads
when source fixes arrive late, with deadlines at +1, +2, +6, and +12 hours after main update completion.
In addition, the server performs persistent 6-hour automatic update checks for installed extensions
from configured repositories while the server is idle.

Key behaviors:
1. Deadlines (+1h, +2h, +6h, +12h) are anchored to the main update completion timestamp.
2. Library retries and download retries maintain independent clocks and states. Successful library reconciliation does not cancel download recovery.
3. Pending downloads are captured when the main update completes, so image failures that occur afterward still receive recovery deadlines.
4. Extension checks run on a persistent 6-hour cycle (surviving restarts), checking configured extension repositories and updating only installed extensions.
5. If deadlines coincide, extensions update before retry dispatch.
6. Successfully updated extensions trigger one recovery attempt for their affected failed downloads.
7. Requeue only targets entries currently in `ERROR` that are unread, in library, and not downloaded; removed or deliberately paused queue entries are never recreated or resumed.
8. Missed retry slots coalesce after device sleep or restart.

## Reproduce

Use a separate checkout of Suwayomi-Server commit
`40bc5da57820324ed0ae724cbbc020cc4673b594` (v2.4.2366), its Gradle wrapper,
Kotlin 2.4.10, and JVM target 21. The patch pins the Android stubs
repository to commit `3983289d9481a8ba99c0b16350b27f41364906a2`
(stubs JAR SHA-256 `2743be4f4c9ba50f8c86ccc0769e5be5246542488b34e6085a2574ca8ac303e3`).

With `tsumiru` pointing to this checkout and `server` to the separate server checkout:

```sh
git -C "$server" apply "$tsumiru/tool/server/library-update-retries-v2.4.2366.patch"
cd "$server"
./gradlew :server:test --tests 'suwayomi.tachidesk.manga.impl.update.*' --no-daemon \
  --init-script "$tsumiru/tool/server/isolated-tests.init.gradle.kts"
```

## Packaging and candidate verification

The packager targets the reviewed installed base JAR:
SHA-256 `a8f28de60db71e874e0930c5ba0abd8487dce7597b48abdc54bea146634676c3`.

It preserves all previous custom features (WebUI memory/preload fixes, downloader network budget,
bounded logging, library count GraphQL loaders) and replaces only the explicit reviewed recovery/updater owners.

```sh
python3 "$tsumiru/tool/server/package_update_retries.py" \
  --base /path/to/suwayomi-parallel.jar \
  --classes "$server/server/build/classes/kotlin/main" \
  --patch "$tsumiru/tool/server/library-update-retries-v2.4.2366.patch" \
  --output /path/to/suwayomi-candidate.jar

./gradlew :server:test --tests '*ServerRecovery*' --tests '*LibraryUpdate*' --tests '*ExtensionUpdateScheduleTest' --no-daemon \
  --init-script "$tsumiru/tool/server/packaged-tests.init.gradle.kts" \
  -Dtsumiru.server.jar=/path/to/suwayomi-candidate.jar

python3 -m unittest discover -s "$tsumiru/tool/server" -p 'test_*.py'
```
