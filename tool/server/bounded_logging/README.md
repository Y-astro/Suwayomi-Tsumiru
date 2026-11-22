# Bounded logging for the custom server

This overlay keeps the existing custom Suwayomi v2.4.2366/r2366 build. It replaces
only `xyz/nulldev/ts/config/LoggingKt` and its nested classes. Every other ZIP
entry, including duplicate resources, custom patches, manifest, and earlier retry
metadata, is preserved. The required base SHA-256 is:

`b42be40c310af37a6f5d9a4bdf3fd0ab57b6cfb90ce10c1ab6fc4e12d5d9c403`

Apply `bounded-logging-v2.4.2366.patch` to server source at
`40bc5da57820324ed0ae724cbbc020cc4673b594`, after the existing library-retry patch.
Build `:AndroidCompat:Config:compileKotlin` with the pinned dependencies from that
patch. Package the resulting Java 21 classes with:

```sh
python3 tool/server/bounded_logging/package_bounded_logging.py \
  reviewed-base.jar path/to/AndroidCompat/Config/build/classes/kotlin/main \
  candidate.jar tool/server/bounded_logging/bounded-logging-v2.4.2366.patch
TSUMIRU_BOUNDED_SERVER_JAR="$PWD/candidate.jar" \
  python3 -m unittest discover -s tool/server/bounded_logging -p 'test_*.py'
```

The integration probe checks actual file-appender creation, suppression, and
updates against the packaged JAR in normal, property, and environment modes.
Do not substitute a fresh upstream JAR for the customized base.

`mobile-server-logging.patch` contains the maintained operations changes from
base `af7b665a9cf58f00df6d3493524988eae0b36120`, committed separately as
`cb6253655ab15db20a2665c34a1c6ba9d0002b1c`. Apply it in an isolated checkout of the
mobile-server repository. Its documentation and tests cover the shared 20 MB
ring, private locking for Android shared storage, bounded capture, exact legacy
migration, and the service-scoped release profile.

Deploy the JAR and operations together using `suwayomi-bounded-logging`, a complete
manifest, frozen unrelated live preimages, and fresh exact preconditions. The
profile stops only Suwayomi, its filter/scheduler, and supervisor; it migrates
logs before restarting enabled services. Generic activation does not authorize
these changes. Follow the maintained activation/recovery commands, preserve
disabled flags, and never replace the phone files through ad-hoc copies.

The shared log directory is `/storage/emulated/0/Suwayomi/logs`. Log data, built
JARs, deployment preconditions, and private runtime artifacts do not belong in Git.
