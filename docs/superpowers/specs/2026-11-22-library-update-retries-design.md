# Library update errors and retries

Implement backlog item 2 only. The user authorized continuing the upgrade list,
server edits, and pushing completed changes to their fork. No pull requests.

## Approach

Own retries on the server. Desktop timers stop when Tsumiru closes; a server
patch can use the actual update tracker and successful chapter database writes.
Keep the patch pinned to the installed server's v2.4.2366 source revision
`40bc5da57820324ed0ae724cbbc020cc4673b594` and retain reproducible sources in
this fork as a patch. Do not commit binaries or private server configuration.

## Behavior

- A main library/category update supersedes the previous retry cycle.
- After it finishes, persist failed title IDs and the completion timestamp.
- Retry remaining failures at completion +1 hour and +2 hours, then stop.
- Use the existing source queues and concurrency limits. Wait until idle.
- A successful chapter fetch and database synchronization removes that title
  from both the failure tracker and pending retries. Metadata-only refreshes,
  cached chapters, and GraphQL partial errors do not count as success.
- Refresh Tsumiru's error list/count after a successful manual chapter refresh
  and after server update completion. Preserve the lightweight progress feed.
- Persist the plan across server restarts. If sleep/restart misses both slots,
  dispatch the latest due slot once rather than burst two source requests.
  Reserve an attempt before dispatch: a crash during dispatch can consume it.
- Stop/reset cancels pending retries. Deleted or removed library titles are
  excluded. Unresolved errors remain visible after the final retry.

The missed-slot and crash rules are implementation decisions. No new settings,
reader changes, logging project, counts, or upstream update-check changes.

## Verification

Test timing, two-attempt bounds, restart, manual success, mixed source failures,
busy updates, reset, GraphQL partial errors, and frontend cache invalidation.
Build the pinned server and native high-refresh app. Stage and back up the live
server before replacing its JAR during an idle window. Verify API health and
detached survival. Do not trigger a full production library update for testing.
