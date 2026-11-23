import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/update_status/update_status_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/updates/controller/updates_filter_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/updates/updates_screen.dart';
import 'package:tsumiru/src/features/manga_book/presentation/updates/widgets/updates_grid_card.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/widgets/manga_cover/grid/manga_cover_grid_tile.dart';

import '../../../../helpers/unreachable_server_stubs.dart';

Map<String, dynamic> _chapter(int id, bool read) => {
  '__typename': 'ChapterType',
  'id': id,
  'mangaId': 1,
  'chapterNumber': id.toDouble(),
  'fetchedAt': '0',
  'name': 'Chapter $id',
  'pageCount': 1,
  'sourceOrder': id,
  'uploadDate': '0',
  'url': 'chapter/$id',
  'meta': [],
  'realUrl': null,
  'scanlator': null,
  'user': {
    '__typename': 'ChapterUserType',
    'isBookmarked': false,
    'isDownloaded': false,
    'isRead': read,
    'lastPageRead': 0,
    'lastReadAt': '1',
  },
};

ChapterWithMangaDto _row(int id, bool read) => ChapterWithMangaDto.fromJson({
  ..._chapter(id, read),
  'manga': {
    '__typename': 'MangaType',
    'id': 1,
    'genre': [],
    'initialized': true,
    'meta': [],
    'sourceId': '1',
    'status': 'ONGOING',
    'title': 'Fixture series',
    'updateStrategy': 'ALWAYS_UPDATE',
    'url': 'series/1',
    'user': {
      '__typename': 'MangaUserType',
      'inLibrary': true,
      'inLibraryAt': '0',
      'unreadCount': 2,
    },
  },
});

class _Updates extends UpdatesRepository {
  _Updates(GraphQLClient client) : super(client, client);
  int reads = 0;
  bool read = false;
  bool allRead = false;
  @override
  Future<UpdatesPage?> getRecentChaptersPage({
    int pageNo = 0,
    UpdatesFilter filter = kNoUpdatesFilter,
    int? offset,
  }) async {
    reads++;
    return (
      nodes: [
        for (final row in [_row(7, read || allRead), _row(8, allRead)])
          if (filter.unread == null || row.user.isRead != filter.unread) row,
      ],
      hasNextPage: false,
    );
  }
}

ChapterWithMangaDto _feedRow(int id, bool read) {
  final row = _row(id, read);
  final mangaId = id == 22 || id == 60 ? 21 : id;
  return ChapterWithMangaDto.fromJson({
    ...row.toJson(),
    'mangaId': mangaId,
    'fetchedAt': id == 60 ? '86400' : '0',
    'manga': {...row.manga.toJson(), 'id': mangaId, 'title': 'Series $mangaId'},
  });
}

class _PagedUpdates extends UpdatesRepository {
  _PagedUpdates(GraphQLClient client) : super(client, client);
  final offsets = <int>[];
  final readIds = <int>{};

  @override
  Future<UpdatesPage?> getRecentChaptersPage({
    int pageNo = 0,
    UpdatesFilter filter = kNoUpdatesFilter,
    int? offset,
  }) async {
    final start = offset ?? pageNo * updatesPageSize;
    offsets.add(start);
    final rows = [
      for (var id = 1; id <= 65; id++) _feedRow(id, readIds.contains(id)),
    ];
    return splitPageWindow(
      rows
          .where(
            (row) => filter.unread == null || row.user.isRead != filter.unread,
          )
          .skip(start)
          .take(updatesPageSize + 1)
          .toList(),
      updatesPageSize,
    );
  }
}

void main() {
  test('retained finished rows no longer occupy unread or started pages', () {
    final row = _row(7, true);
    expect(matchesUpdatesFilter(row, kNoUpdatesFilter), isTrue);
    expect(
      matchesUpdatesFilter(row, (
        downloaded: null,
        unread: true,
        started: null,
        bookmarked: null,
      )),
      isFalse,
    );
    expect(
      matchesUpdatesFilter(row, (
        downloaded: null,
        unread: false,
        started: null,
        bookmarked: null,
      )),
      isTrue,
    );
    for (final started in [true, false]) {
      expect(
        matchesUpdatesFilter(row, (
          downloaded: null,
          unread: null,
          started: started,
          bookmarked: null,
        )),
        isFalse,
      );
    }
    expect(
      matchesUpdatesFilter(row, (
        downloaded: true,
        unread: null,
        started: null,
        bookmarked: null,
      )),
      isFalse,
    );
    expect(
      matchesUpdatesFilter(row, (
        downloaded: null,
        unread: null,
        started: null,
        bookmarked: true,
      )),
      isFalse,
    );
  });

  for (final bulk in [false, true]) {
    for (final read in [true, false, null]) {
      for (final outcome in ['saved', 'empty', 'error']) {
        test(
          '${bulk ? 'bulk' : 'single'} read=$read outcome=$outcome publishes only confirmed read-state writes',
          () async {
            var changes = 0;
            final field = bulk ? 'updateChapters' : 'updateChapter';
            final client = GraphQLClient(
              link: Link.function(
                (_, [forward]) => Stream.value(
                  Response(
                    data: {
                      '__typename': 'Mutation',
                      field: bulk
                          ? {
                              '__typename': 'UpdateChaptersPayload',
                              'chapters': outcome == 'empty'
                                  ? []
                                  : [_chapter(7, read ?? false)],
                            }
                          : outcome == 'empty'
                          ? null
                          : {
                              '__typename': 'UpdateChapterPayload',
                              'chapter': _chapter(7, read ?? false),
                            },
                    },
                    errors: outcome == 'error'
                        ? [GraphQLError(message: 'write rejected')]
                        : null,
                    response: {},
                  ),
                ),
              ),
              cache: GraphQLCache(),
            );
            final repo = MangaBookRepository(
              client,
              onReadStateChanged: (chapters) {
                changes++;
                expect(chapters.single.id, 7);
                expect(chapters.single.user.isRead, read);
              },
            );
            final patch = read == null
                ? ChapterChange(lastPageRead: 1)
                : ChapterChange(isRead: read);
            final pending = bulk
                ? repo.modifyBulkChapters(ChapterBatch(ids: [7], patch: patch))
                : repo.putChapter(chapterId: 7, patch: patch);
            if (outcome == 'error') {
              await expectLater(pending, throwsException);
            } else {
              await pending;
            }
            expect(changes, outcome == 'saved' && read != null ? 1 : 0);
          },
        );
      }
    }
  }

  for (final unreadOnly in [false, true]) {
    testWidgets(
      'reader pop keeps scroll, pages and completed groups (unread-only=$unreadOnly)',
      (tester) async {
        Future<void> flushFrames() async {
          // The paging footer shimmers while another page remains available.
          for (var frame = 0; frame < 4; frame++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final finalWrite = Completer<Response>();
        final operations = <int>[];
        final client = GraphQLClient(
          link: Link.function((request, [forward]) {
            final input = request.variables['input'] as Map<String, dynamic>;
            final id = input['id'] as int;
            operations.add(id);
            if (id == 22) return finalWrite.future.asStream();
            return Stream.value(
              Response(
                data: {
                  '__typename': 'Mutation',
                  'updateChapter': {
                    '__typename': 'UpdateChapterPayload',
                    'chapter': {..._chapter(id, true), 'mangaId': 21},
                  },
                },
                response: {},
              ),
            );
          }),
          cache: GraphQLCache(),
        );
        final updates = _PagedUpdates(client);
        final container = ProviderContainer(
          overrides: [
            ...unreachableServerStubs,
            sharedPreferencesProvider.overrideWithValue(prefs),
            graphQlClientProvider.overrideWith((ref) => client),
            updatesRepositoryProvider.overrideWith((ref) => updates),
            libraryLastUpdatedProvider.overrideWith((ref) async => null),
            failedUpdateCountProvider.overrideWith((ref) async => 0),
            updatesFilterProvider.overrideWith(
              (ref) => (
                downloaded: null,
                unread: unreadOnly ? true : null,
                started: null,
                bookmarked: null,
              ),
            ),
            updateProgressSocketProvider.overrideWith(
              (ref) => Stream<UpdateProgressDto?>.value(null),
            ),
          ],
        );
        addTearDown(container.dispose);
        Future<void>? pending;
        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const UpdatesScreen()),
            GoRoute(
              path: Uri.parse(
                const ReaderRoute(mangaId: 21, chapterId: 21).location,
              ).path,
              builder: (context, _) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final repo = container.read(mangaBookRepositoryProvider);
                    updates.readIds.add(21);
                    await repo.putChapter(
                      chapterId: 21,
                      patch: ChapterChange(isRead: true),
                    );
                    if (!context.mounted) return;
                    context.pop();
                    pending = repo.putChapter(
                      chapterId: 22,
                      patch: ChapterChange(isRead: true),
                    );
                  },
                  child: const Text('Finish reading'),
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await flushFrames();
        final scrollable = find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text('Series 21'),
          350,
          scrollable: scrollable,
        );
        await flushFrames();
        final position = tester.state<ScrollableState>(scrollable).position;
        final offset = position.pixels;
        expect(offset, greaterThan(0));
        final pagesBefore = List<int>.of(updates.offsets);
        final paging = tester
            .widget<PagingListener<int, ChapterWithMangaDto>>(
              find.byType(PagingListener<int, ChapterWithMangaDto>),
            )
            .controller;
        final keys = List<int>.of(paging.keys!);
        await tester.tap(find.text('Series 21'));
        await flushFrames();
        expect(find.text('Finish reading'), findsOneWidget);
        await tester.tap(find.text('Finish reading'));
        await flushFrames();
        expect(position.pixels, offset);
        expect(updates.offsets, pagesBefore);
        expect(paging.keys, keys);
        MangaCoverGridTile cover() => tester
            .widgetList<MangaCoverGridTile>(find.byType(MangaCoverGridTile))
            .singleWhere((tile) => tile.titleOverride == 'Series 21');
        expect(cover().badgeCountOverride, 1);
        expect(cover().dimmed, isFalse);
        updates.readIds.add(22);
        finalWrite.complete(
          Response(
            data: {
              '__typename': 'Mutation',
              'updateChapter': {
                '__typename': 'UpdateChapterPayload',
                'chapter': {..._chapter(22, true), 'mangaId': 21},
              },
            },
            response: {},
          ),
        );
        await pending;
        await flushFrames();
        expect(position.pixels, offset);
        expect(updates.offsets, pagesBefore);
        expect(cover().dimmed, isTrue);
        expect(cover().badgeCountOverride, isNull);
        expect(operations, [21, 22]);
        await tester.scrollUntilVisible(
          find.text('Series 65'),
          400,
          scrollable: scrollable,
        );
        await flushFrames();
        expect(updates.offsets, [0, unreadOnly ? 48 : 50]);
        expect(
          paging.items!.map((row) => row.id),
          unorderedEquals([for (var id = 1; id <= 65; id++) id]),
        );
        final otherInstance = tester
            .widgetList<UpdatesGridCard>(find.byType(UpdatesGridCard))
            .singleWhere((card) => card.group.head.id == 60);
        expect(otherInstance.group.head.user.isRead, isFalse);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final unreadOnly in [false, true]) {
    testWidgets('saved reads patch Updates (unread-only=$unreadOnly)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final response = Completer<Response>();
      final responses = <Future<Response>>[response.future];
      final client = GraphQLClient(
        link: Link.function((_, [forward]) => responses.removeAt(0).asStream()),
        cache: GraphQLCache(),
      );
      final updates = _Updates(client);
      final container = ProviderContainer(
        overrides: [
          ...unreachableServerStubs,
          sharedPreferencesProvider.overrideWithValue(prefs),
          graphQlClientProvider.overrideWith((ref) => client),
          updatesRepositoryProvider.overrideWith((ref) => updates),
          libraryLastUpdatedProvider.overrideWith((ref) async => null),
          failedUpdateCountProvider.overrideWith((ref) async => 0),
          updatesFilterProvider.overrideWith(
            (ref) => unreadOnly
                ? (
                    downloaded: null,
                    unread: true,
                    started: null,
                    bookmarked: null,
                  )
                : kNoUpdatesFilter,
          ),
          updateProgressSocketProvider.overrideWith(
            (ref) => Stream<UpdateProgressDto?>.value(null),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const UpdatesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(updates.reads, 1);
      expect(
        tester
            .widget<MangaCoverGridTile>(find.byType(MangaCoverGridTile))
            .badgeCountOverride,
        2,
      );
      expect(
        tester
            .widget<UpdatesGridCard>(find.byType(UpdatesGridCard))
            .group
            .head
            .user
            .isRead,
        isFalse,
      );

      // The reader route has returned, but its final server write is still pending.
      final pending = container
          .read(mangaBookRepositoryProvider)
          .putChapter(chapterId: 7, patch: ChapterChange(isRead: true));
      await tester.pump();
      expect(updates.reads, 1);
      updates.read = true;
      response.complete(
        Response(
          data: {
            '__typename': 'Mutation',
            'updateChapter': {
              '__typename': 'UpdateChapterPayload',
              'chapter': _chapter(7, true),
            },
          },
          response: {},
        ),
      );
      await pending;
      await tester.pumpAndSettle();

      expect(updates.reads, 1);
      expect(
        tester
            .widget<MangaCoverGridTile>(find.byType(MangaCoverGridTile))
            .badgeCountOverride,
        1,
      );
      final card = tester.widget<UpdatesGridCard>(find.byType(UpdatesGridCard));
      final rows = [card.group.head, ...card.group.tail];
      expect(rows.map((row) => row.id), unorderedEquals([7, 8]));
      expect(rows.singleWhere((row) => row.id == 7).user.isRead, isTrue);
      expect(
        tester
            .widget<MangaCoverGridTile>(find.byType(MangaCoverGridTile))
            .dimmed,
        isFalse,
      );

      updates.allRead = true;
      responses.add(
        Future.value(
          Response(
            data: {
              '__typename': 'Mutation',
              'updateChapter': {
                '__typename': 'UpdateChapterPayload',
                'chapter': _chapter(8, true),
              },
            },
            response: {},
          ),
        ),
      );
      await container
          .read(mangaBookRepositoryProvider)
          .putChapter(chapterId: 8, patch: ChapterChange(isRead: true));
      await tester.pumpAndSettle();
      expect(updates.reads, 1);
      final finished = tester.widget<MangaCoverGridTile>(
        find.byType(MangaCoverGridTile),
      );
      expect(finished.badgeCountOverride, isNull);
      expect(finished.dimmed, isTrue);
      expect(find.byType(UpdatesGridCard), findsOneWidget);
      responses.add(
        Future.value(
          Response(
            data: {
              '__typename': 'Mutation',
              'updateChapters': {
                '__typename': 'UpdateChaptersPayload',
                'chapters': [_chapter(7, false), _chapter(8, false)],
              },
            },
            response: {},
          ),
        ),
      );
      await container
          .read(mangaBookRepositoryProvider)
          .modifyBulkChapters(
            ChapterBatch(ids: [7, 8], patch: ChapterChange(isRead: false)),
          );
      await tester.pumpAndSettle();
      final unread = tester.widget<MangaCoverGridTile>(
        find.byType(MangaCoverGridTile),
      );
      expect(unread.dimmed, isFalse);
      expect(unread.badgeCountOverride, 2);
      expect(updates.reads, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
