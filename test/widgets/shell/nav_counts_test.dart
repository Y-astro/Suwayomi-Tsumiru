import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/offline/data/server_reachability.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/widgets/shell/nav_counts.dart';

MangaDto _manga(int id, int unreadCount) => Fragment$MangaDto(
  id: id,
  title: 'Manga $id',
  chapters: Fragment$MangaDto$chapters(totalCount: 5),
  genre: const [],
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/$id',
  user: Fragment$MangaDto$user(
    bookmarkCount: 0,
    downloadCount: 0,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: unreadCount,
  ),
);

class _CountingUpdatesRepository extends UpdatesRepository {
  _CountingUpdatesRepository({this.countResponse})
    : super(_dummyClient(), _dummyClient());

  int? countResponse;
  int countCalls = 0;
  Completer<int?>? pendingCompleter;

  @override
  Future<int?> getUnreadUpdateChapterCount() async {
    countCalls++;
    if (pendingCompleter != null) {
      return await pendingCompleter!.future;
    }
    return countResponse;
  }
}

GraphQLClient _dummyClient() => GraphQLClient(
  link: Link.function((request, [forward]) => const Stream.empty()),
  cache: GraphQLCache(),
);

void main() {
  test(
    'navCountsProvider yields library title count and updates chapter count',
    () async {
      final repo = _CountingUpdatesRepository(countResponse: 6);
      final container = ProviderContainer(
        overrides: [
          updatesRepositoryProvider.overrideWithValue(repo),
          libraryMangaListProvider.overrideWith(
            (ref) async => [_manga(1, 5), _manga(2, 1), _manga(3, 0)],
          ),
        ],
      );
      addTearDown(container.dispose);

      // Initial read before library resolves
      expect(container.read(navCountsProvider), isNull);

      // Wait for library and updates count to resolve
      await container.read(libraryMangaListProvider.future);
      await container.read(updatesUnreadChapterCountProvider.future);

      final counts = container.read(navCountsProvider);
      expect(counts, isNotNull);
      expect(counts!.library, 3);
      expect(counts.updates, 6);
      expect(repo.countCalls, 1);
    },
  );

  test(
    'count result is independent of all-library unread totals and full feed > 50',
    () async {
      // 3 library titles with 500 unread chapters total, but Updates feed has 172 unread chapters
      final repo = _CountingUpdatesRepository(countResponse: 172);
      final container = ProviderContainer(
        overrides: [
          updatesRepositoryProvider.overrideWithValue(repo),
          libraryMangaListProvider.overrideWith(
            (ref) async => [_manga(1, 200), _manga(2, 300), _manga(3, 0)],
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(libraryMangaListProvider.future);
      await container.read(updatesUnreadChapterCountProvider.future);

      final counts = container.read(navCountsProvider);
      expect(counts!.library, 3);
      expect(counts.updates, 172);
    },
  );

  test('offline hides updates count but retains library title count', () async {
    final repo = _CountingUpdatesRepository(countResponse: 6);
    final container = ProviderContainer(
      overrides: [
        updatesRepositoryProvider.overrideWithValue(repo),
        libraryMangaListProvider.overrideWith(
          (ref) async => [_manga(1, 5), _manga(2, 1)],
        ),
        serverUnreachableProvider.overrideWith(_FixedUnreachable.new),
      ],
    );
    addTearDown(container.dispose);

    await container.read(libraryMangaListProvider.future);

    final counts = container.read(navCountsProvider);
    expect(counts, isNotNull);
    expect(counts!.library, 2);
    expect(counts.updates, isNull);
    expect(repo.countCalls, 0); // did not query while offline
  });

  test(
    'error/null response leaves updates count as null (unavailable), genuine 0 is shown',
    () async {
      final repo = _CountingUpdatesRepository(countResponse: null);
      final container = ProviderContainer(
        overrides: [
          updatesRepositoryProvider.overrideWithValue(repo),
          libraryMangaListProvider.overrideWith((ref) async => [_manga(1, 5)]),
        ],
      );
      addTearDown(container.dispose);

      await container.read(libraryMangaListProvider.future);
      await container.read(updatesUnreadChapterCountProvider.future);

      var counts = container.read(navCountsProvider);
      expect(counts!.library, 1);
      expect(counts.updates, isNull);

      // Now test genuine 0
      final repoZero = _CountingUpdatesRepository(countResponse: 0);
      final containerZero = ProviderContainer(
        overrides: [
          updatesRepositoryProvider.overrideWithValue(repoZero),
          libraryMangaListProvider.overrideWith((ref) async => [_manga(1, 0)]),
        ],
      );
      addTearDown(containerZero.dispose);

      await containerZero.read(libraryMangaListProvider.future);
      await containerZero.read(updatesUnreadChapterCountProvider.future);

      final countsZero = containerZero.read(navCountsProvider);
      expect(countsZero!.library, 1);
      expect(countsZero.updates, 0);
    },
  );

  test('a new settled library snapshot refreshes the feed count', () async {
    final repo = _CountingUpdatesRepository(countResponse: 6);
    final container = ProviderContainer(
      overrides: [
        updatesRepositoryProvider.overrideWithValue(repo),
        libraryMangaListProvider.overrideWith(
          (ref) async => [_manga(1, 5), _manga(2, 1)],
        ),
      ],
    );
    addTearDown(container.dispose);

    final subscription = container.listen(navCountsProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(libraryMangaListProvider.future);
    await container.read(updatesUnreadChapterCountProvider.future);
    expect(repo.countCalls, 1);

    container.invalidate(libraryMangaListProvider);
    await container.read(libraryMangaListProvider.future);
    await container.read(updatesUnreadChapterCountProvider.future);
    expect(repo.countCalls, 2);
  });

  test(
    'stale response from old repository / account is ignored upon replacement',
    () async {
      final completer1 = Completer<int?>();
      final repo1 = _CountingUpdatesRepository()..pendingCompleter = completer1;
      final repo2 = _CountingUpdatesRepository(countResponse: 42);

      final subRepo = Provider<UpdatesRepository>((ref) => repo1);

      final container = ProviderContainer(
        overrides: [
          updatesRepositoryProvider.overrideWith((ref) => ref.watch(subRepo)),
          subRepo.overrideWithValue(repo1),
          libraryMangaListProvider.overrideWith((ref) async => [_manga(1, 5)]),
        ],
      );
      addTearDown(container.dispose);

      await container.read(libraryMangaListProvider.future);
      // Start repo1's count fetch
      final sub = container.listen(
        updatesUnreadChapterCountProvider,
        (_, _) {},
      );
      expect(repo1.countCalls, 1);
      expect(container.read(navCountsProvider), (library: 1, updates: null));

      // Switch account / repository override by updating subRepo
      container.updateOverrides([
        updatesRepositoryProvider.overrideWith((ref) => ref.watch(subRepo)),
        subRepo.overrideWithValue(repo2),
        libraryMangaListProvider.overrideWith((ref) async => [_manga(1, 5)]),
      ]);

      await container.read(libraryMangaListProvider.future);
      await container.read(updatesUnreadChapterCountProvider.future);
      // Keep a subscription so navCountsProvider / updatesUnreadChapterCountProvider does not auto-dispose when sub is closed
      final sub2 = container.listen(navCountsProvider, (_, _) {});
      expect(container.read(navCountsProvider)!.updates, 42);

      // Complete repo1 and close old subscription
      completer1.complete(999);
      sub.close();
      await Future<void>.delayed(Duration.zero);

      // Old response did not overwrite new account's count
      expect(container.read(navCountsProvider)!.updates, 42);
      sub2.close();
    },
  );
}

class _FixedUnreachable extends ServerUnreachable {
  @override
  bool build() => true;
}
