# Other Features

Smaller features: about, history, migration, offline, quick_open.

## about

App/server version info and server update checks.

- `data/about_repository.dart` — `checkServerUpdate()` uses the server's GraphQL `checkForServerUpdates`. `checkUpdate()` remains a compatibility no-op with no HTTP request.
- `controllers/about_controller.dart` — `aboutProvider` (GraphQL `GetAbout`); `packageInfoProvider` is overridden in `main.dart`.
- This personal fork disables upstream Tsumiru update scans and prompts in every distribution. Startup and About no longer offer app checks. Background workers never fetch app releases or post app-update notifications.
- The app-update notification toggle and settings-search entry are removed. Legacy stored preferences remain untouched but cannot enable checks. Direct or stale JSON `NotificationWorkerConfig` values also resolve app updates to false, so app-only configurations cannot schedule a worker.
- Server, extension, chapter and download notifications retain their existing behavior. Server dialogs still require an explicit `isServerUpdate` flag.
- Installed version information, What's New, project/help links and Privacy policy remain available. Server-hosted revision reload banners and server-managed WebUI controls remain available; the shell no longer checks upstream Tsumiru WebUI releases.
- Distribution mode still uses `--dart-define=TSUMIRU_GOOGLE_PLAY=true`; see [repo-build-release.md](repo-build-release.md#google-play-distribution-mode) for commands.

## history

Per-manga reading history grouped by date, with search + per-item removal.

- `data/history_repository.dart` — GraphQL with `ChapterFilterInput` (`lastReadAt`/`isRead`/`lastPageRead`); **dedup is client-side** (over-fetches `pageSize*10`, keeps most-recent chapter per manga, re-paginates). `clearAllHistory()` is `throw UnimplementedError`.
- `presentation/history_controller.dart` — `ReadingHistory` notifier; `removeFromHistory()` patches `isRead=false, lastPageRead=0` (no true delete; `lastReadAt` can't be cleared via the API).
- `HistoryGroup` (freezed) groups by date key with localized headers.
- **Gotchas:** the `pageSize*10` over-fetch can be slow at scale; removed items may reappear until server restart; manga-title search is client-side only.

## migration

Migrate a manga from one source to another (status/categories/progress/bookmarks, optional source delete). Five-screen flow.

- `data/migration_repository.dart` — sequential GraphQL; chapter matching by number (±0.01) → exact name → partial name; chapters updated one-by-one. `cancelMigration()` is `throw UnimplementedError`.
- `controller/migration_controller.dart` — `MigrationExecution` notifier with **artificial progress delays**; global search via `rateLimitQueueProvider`.
- **Gotchas:** `migrateDownloads` and `migrateTracking` flags exist in the UI but are **not implemented**; cancel is unimplemented (controller fakes `cancelled`); progress percentages are cosmetic (real work happens at the 75%→100% step).

## offline

Offline reading is a full subsystem with its own doc — see [offline.md](offline.md).

## quick_open

Command-palette overlay for fast navigation (library/manga/chapters/sources via typed prefixes).

- `controller/quick_search_controller.dart` — `processesQuickSearchProvider` routes by prefix/context: `?` help, `@source` / `@source/query` sources, `#cat` / `#cat/manga` / `#cat/manga:chapter` library drill-down, context-aware default (chapter search on a manga route, else manga search).
- `domain/quick_search_result.dart` — `QuickSearchResult` freezed union (helpText/source/category/manga/chapter/globalSearch/...).
- `widgets/search_stack_screen.dart` stacks the overlay on the shell.
- **Gotcha:** `processesQuickSearchProvider` takes a `BuildContext` (for `context.location` route awareness) — unusual for Riverpod; it must be called from a widget subtree and falls back to manga search if route parsing fails.
