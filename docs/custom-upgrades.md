# Custom upgrade backlog

Work on one item at a time, in the user's order. Do not create pull requests
unless explicitly requested. Push completed, verified changes to the user's fork.

1. **Main-app scrolling — implemented and pushed.** Smooth mouse-wheel scrolling throughout
   main navigation. The user clarified that touchpad scrolling is bad only in
   Library; Updates and History touchpad behavior is fine. The reader is perfect:
   do not change its files, settings or behavior. Preserve native high refresh.
   Follow-up: optimize cached-cover rendering, match main mouse-wheel distance
   to the reader default, and disable desktop pull-to-refresh while retaining
   explicit update controls.
2. **Library update errors and bounded retries — completed and pushed.** Correct stale error
   markers after a successful title refresh and synchronization with the latest
   chapters. Retry error-marked titles at one, two, six, and twelve hours after
   the main library update finishes, then stop retries for that cycle. Failed
   unread chapter downloads have independent recovery deadlines at the same
   offsets. Every six hours, while queues are idle, check configured repositories
   and auto-update installed extensions; successful updates retry affected failed
   downloads once. Recovery schedules persist on the server.
   Updates follow-up: confirmed read/unread writes refresh its cached cards and
   chapter badges, including saves finishing after reader exit. Unread-only
   filtering removes fully read entries and supports an empty result.
3. **Detailed bounded logs — completed.** Each application retains at most
   20,000,000 bytes across active and rotated logs. Laptop logs use the repository
   `logs/` folder; phone logs use `/storage/emulated/0/Suwayomi/logs`.
   Release activity includes API metadata/timings, lifecycle/navigation, settings
   keys, downloads, updates, and errors, with credential redaction. App writes
   are asynchronous; copy/clear serialize with pending writes. The custom server
   stays on v2.4.2366. Controlled migration removes duplicate legacy logs and
   preserves unrelated services and disabled flags. See [logging](logging.md)
   and [server packaging](../tool/server/bounded_logging/README.md).
4. **Counts beside category and navigation labels — completed.** Category labels
   show the number of displayed titles by default and keep the existing display
   toggle. Library counts distinct library titles. Updates counts all unread chapters
   in the feed and refreshes after confirmed read changes
   and library updates. History has no count.
5. **Disable upstream Tsumiru update checks and notifications — queued.** This
   fork is personal; future upstream features will be imported deliberately.

The initial native high-refresh optimization and launcher replacement are done.
Item 2 has passed client, backend, and packaged-runtime tests. The existing custom
v2.4.2366 server is patched without an upstream upgrade, and the application
launcher uses the verified build. Items 3 and 4 are complete. Item 5 remains queued.
Push completed, verified changes to the fork without creating a PR.
