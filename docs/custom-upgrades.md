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
2. **Library update errors and bounded retries — deployed, fork push pending.** Correct stale error
   markers after a successful title refresh and synchronization with the latest
   chapters. Retry error-marked titles at one hour and two hours after the main
   library update finishes, then stop automatic retries for that update cycle.
3. **Detailed bounded logs — queued.** Add detailed server and app diagnostics
   with a 20 MB size limit. Confirm the exact retention/size policy when this
   item starts. The user authorized server access through ADB on the Redmi K20
   Pro or their supplied SSH connection; connection details stay out of git.
4. **Counts beside category and navigation labels — queued.** Show title counts
   beside library category names, such as `Reading (12)`, and show counts beside
   `Library` and `Updates` in navigation. Skip History. Resolve the meaning of
   the Updates count when this item starts.
5. **Disable upstream Tsumiru update checks and notifications — queued.** This
   fork is personal; future upstream features will be imported deliberately.

The initial native high-refresh optimization and launcher replacement are done.
Item 2 has passed client, backend, and packaged-runtime tests. The existing custom
v2.4.2366 server is patched without an upstream upgrade, and the application
launcher uses the verified build. Fork delivery remains pending. Items 3–5 remain queued.
