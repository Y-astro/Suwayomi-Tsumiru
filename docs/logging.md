# Tsumiru activity logs

The desktop launcher can set `TSUMIRU_LOG_DIR` to choose the log directory. This
installation uses `/home/astro/repos/tsumiru/logs`. Without an override, logs use
the platform application-support directory under `logs`.

`crash.log` retains its existing filename for compatibility with the settings
screen. It now includes normal release activity: startup, lifecycle, navigation
route templates, settings key changes, GraphQL operation names and numeric IDs,
request timings and outcomes, existing download/notification events, and errors.
Request/response bodies, settings values, and per-frame events are not recorded.
Credential redaction runs before file and application console output.

The active file and nine archives (`crash.log.1` through `crash.log.9`) share a
20,000,000-byte limit. Each segment holds at most 2,000,000 bytes. Oversized
records are truncated on a UTF-8 boundary. Oldest segments are removed first.
Zero-byte lock and migration markers do not contain log data.

Normal writes use asynchronous file operations and a 256 KiB pending queue.
When overloaded, the queue drops oldest pending events and records a summary.
The desktop close handler allows up to two seconds to drain diagnostics. Forced
termination can lose queued events; storage failures do not interrupt the app.

The existing **Copy debug log** and **Clear debug log** controls operate on the
whole retained history. They serialize with queued writes. Initial setup imports
the recent complete tail of the previous owned crash log, redacts it, and removes
the old file only after successful persistence. Other files are left alone.
