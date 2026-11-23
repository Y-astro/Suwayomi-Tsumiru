import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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

void main() {
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
              onReadStateChanged: () => changes++,
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
    testWidgets('a late read write refreshes Updates (unread-only=$unreadOnly)', (
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

      expect(updates.reads, 2);
      expect(
        tester
            .widget<MangaCoverGridTile>(find.byType(MangaCoverGridTile))
            .badgeCountOverride,
        1,
      );
      final card = tester.widget<UpdatesGridCard>(find.byType(UpdatesGridCard));
      final rows = [card.group.head, ...card.group.tail];
      if (unreadOnly) {
        expect(rows.map((row) => row.id), isNot(contains(7)));
      } else {
        expect(rows.singleWhere((row) => row.id == 7).user.isRead, isTrue);
      }

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
      expect(updates.reads, 3);
      if (unreadOnly) {
        expect(find.byType(UpdatesGridCard), findsNothing);
      } else {
        expect(
          tester
              .widget<MangaCoverGridTile>(find.byType(MangaCoverGridTile))
              .badgeCountOverride,
          isNull,
        );
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
