// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../global_providers/global_providers.dart';
import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../domain/chapter/chapter_model.dart';
import '../../domain/chapter_page/chapter_page_model.dart';
import '../../domain/manga/manga_model.dart';
import '../../domain/update_status/update_status_model.dart';
import '../../domain/updates/updates_filter.dart';
import './graphql/__generated__/query.graphql.dart';

part 'updates_repository.g.dart';

/// Updates keeps its own paging state, outside the chapter and library providers.
final updatesReadRevisionProvider = NotifierProvider<
  UpdatesReadRevision,
  ({int revision, List<ChapterDto> chapters})
>(UpdatesReadRevision.new);

class UpdatesReadRevision
    extends Notifier<({int revision, List<ChapterDto> chapters})> {
  @override
  ({int revision, List<ChapterDto> chapters}) build() =>
      (revision: 0, chapters: const []);

  void bump([List<ChapterDto> chapters = const []]) =>
      state = (revision: state.revision + 1, chapters: chapters);
}

/// Maximum chapter rows per page; retained filtered rows do not advance offsets.
const int updatesPageSize = 50;

/// At most [updatesPageSize] chapters, newest first, with a flag for another page.
typedef UpdatesPage = ({List<ChapterWithMangaDto> nodes, bool hasNextPage});

/// Splits a window fetched as [pageSize] + 1 rows into the page and whether
/// another one follows.
({List<T> nodes, bool hasNextPage}) splitPageWindow<T>(
  List<T> window,
  int pageSize,
) => (
  nodes: window.take(pageSize).toList(),
  hasNextPage: window.length > pageSize,
);

Input$BooleanFilterInput? _equals(bool? value) =>
    value == null ? null : Input$BooleanFilterInput(equalTo: value);

Input$ChapterFilterInput updatesFilterInput(UpdatesFilter filter) =>
    Input$ChapterFilterInput(
      inLibrary: Input$BooleanFilterInput(equalTo: true),
      isDownloaded: _equals(filter.downloaded),
      isRead: filter.unread == null ? null : _equals(!filter.unread!),
      isBookmarked: _equals(filter.bookmarked),
      // Finished chapters count as neither started nor not-started (updatesView.sq).
      and: filter.started == null
          ? null
          : [
              Input$ChapterFilterInput(isRead: _equals(false)),
              Input$ChapterFilterInput(
                lastPageRead: filter.started!
                    ? Input$IntFilterInput(greaterThan: 0)
                    : Input$IntFilterInput(equalTo: 0),
              ),
            ],
    );

class UpdatesRepository {
  const UpdatesRepository(this.client, this.subscriptionClient);

  final GraphQLClient client;
  final GraphQLClient subscriptionClient;

  /// Count unread chapters in the Updates feed without fetching chapter rows.
  Future<int?> getUnreadUpdateChapterCount() async {
    final result = await client.query(
      QueryOptions(
        operationName: 'GetChapterWithMangaPageUnreadCount',
        document: gql(
          r'''
query GetChapterWithMangaPageUnreadCount($filter: ChapterFilterInput) {
  chapters(filter: $filter, first: 0) {
    totalCount
  }
}
''',
        ),
        variables: {
          'filter': updatesFilterInput(
            (
              downloaded: null,
              unread: true,
              started: null,
              bookmarked: null,
            ),
          ).toJson(),
        },
        fetchPolicy: FetchPolicy.noCache,
      ),
    );
    if (result.hasException) return null;
    final chapters = result.data?['chapters'];
    final totalCount = chapters is Map ? chapters['totalCount'] : null;
    return totalCount is int ? totalCount : null;
  }

  /// Fetch one extra row to detect another page without the server cost of COUNT/pageInfo.
  Future<UpdatesPage?> getRecentChaptersPage({
    int pageNo = 0,
    UpdatesFilter filter = kNoUpdatesFilter,
    int? offset,
  }) async {
    final page = await _getRecentChaptersWindow(
      offset ?? pageNo * updatesPageSize, filter,
    );
    return page == null ? null : splitPageWindow(page.nodes, updatesPageSize);
  }

  Future<ChapterPageWithMangaDto?> _getRecentChaptersWindow(
    int offset,
    UpdatesFilter filter,
  ) =>
      client
          .query$GetChapterWithMangaPage(
            Options$Query$GetChapterWithMangaPage(
              variables: Variables$Query$GetChapterWithMangaPage(
                filter: updatesFilterInput(filter),
                first: updatesPageSize + 1,
                offset: offset,
                order: [
                  Input$ChapterOrderInput(
                    by: Enum$ChapterOrderBy.FETCHED_AT,
                    byType: Enum$SortOrder.DESC,
                  ),
                  Input$ChapterOrderInput(
                    by: Enum$ChapterOrderBy.SOURCE_ORDER,
                    byType: Enum$SortOrder.DESC,
                  ),
                ],
              ),
            ),
          )
          .getData((data) => data.chapters);

  Future<List<ChapterWithMangaDto>> getChaptersInRange({
    required DateTime start,
    required DateTime end,
  }) async {
    const pageSize = 200;
    final chapters = <ChapterWithMangaDto>[];
    for (var offset = 0; ; offset += pageSize) {
      final page =
          await client
              .query$GetChapterWithMangaPage(
                Options$Query$GetChapterWithMangaPage(
                  variables: Variables$Query$GetChapterWithMangaPage(
                    filter: Input$ChapterFilterInput(
                      inLibrary: Input$BooleanFilterInput(equalTo: true),
                      fetchedAt: Input$LongFilterInput(
                        greaterThanOrEqualTo:
                            '${start.millisecondsSinceEpoch ~/ 1000}',
                        lessThan: '${end.millisecondsSinceEpoch ~/ 1000}',
                      ),
                    ),
                    first: pageSize,
                    offset: offset,
                    order: [
                      Input$ChapterOrderInput(
                        by: Enum$ChapterOrderBy.FETCHED_AT,
                        byType: Enum$SortOrder.DESC,
                      ),
                      Input$ChapterOrderInput(
                        by: Enum$ChapterOrderBy.ID,
                        byType: Enum$SortOrder.DESC,
                      ),
                    ],
                  ),
                ),
              )
              .getData((data) => data.chapters.nodes) ??
          const <ChapterWithMangaDto>[];
      chapters.addAll(page);
      if (page.length < pageSize) return chapters;
    }
  }

  Future<void> fetchUpdates({
    int? categoryId,
  }) async {
    if (categoryId != null) {
      await client.mutate$UpdateCategoryMangas(
        Options$Mutation$UpdateCategoryMangas(
          variables: Variables$Mutation$UpdateCategoryMangas(
            input: Input$UpdateCategoryMangaInput(categories: [categoryId]),
          ),
        ),
      );
    } else {
      await client.mutate$UpdateLibraryMangas(
        Options$Mutation$UpdateLibraryMangas(
          variables: Variables$Mutation$UpdateLibraryMangas(
            input: Input$UpdateLibraryMangaInput(),
          ),
        ),
      );
    }
  }

  Future<void> stopUpdates() => client.mutate$StopCategoryUpdate(
        Options$Mutation$StopCategoryUpdate(
          variables: Variables$Mutation$StopCategoryUpdate(
            input: Input$UpdateStopInput(),
          ),
        ),
      );

  Future<UpdateProgressDto?> updateProgress() async => client
      .query$UpdateProgress(Options$Query$UpdateProgress())
      .getData((data) => data.libraryUpdateStatus.jobsInfo);

  /// Reads current failure status; the deprecated updateStatus job lists can hang.
  Future<List<MangaDto>> failedUpdates() async =>
      (await client
          .query$LibraryUpdateFailures(
            Options$Query$LibraryUpdateFailures(
              variables: Variables$Query$LibraryUpdateFailures(
                withLibraryFields: false,
                withFirstUnread: false,
              ),
            ),
          )
          .getData((data) => [
                for (final update in data.libraryUpdateStatus.mangaUpdates)
                  if (update.status == Enum$MangaJobStatus.FAILED) update.manga,
              ])) ??
      const [];

  Future<int?> failedUpdateCount() async => client
      .query$LibraryUpdateFailureCount(
        Options$Query$LibraryUpdateFailureCount(),
      )
      .getData(
        (data) => data.libraryUpdateStatus.mangaUpdates
            .where((update) => update.status == Enum$MangaJobStatus.FAILED)
            .length,
      );

  /// Epoch-millis (as a string) of the last global library update, or null.
  Future<String?> lastUpdateTimestamp() async => client
      .query$LastUpdateTimestamp(Options$Query$LastUpdateTimestamp())
      .getData((data) => data.lastUpdateTimestamp.timestamp);

  /// Live progress is pushed at most once a second from server memory, without a query.
  Stream<UpdateProgressDto?> updateProgressSubscription() => subscriptionClient
      .subscribe$UpdateProgressChange(
        Options$Subscription$UpdateProgressChange(),
      )
      .getData((data) => data.libraryUpdateStatusChanged.jobsInfo);
}

@riverpod
UpdatesRepository updatesRepository(Ref ref) => UpdatesRepository(
    ref.watch(graphQlClientProvider),
    ref.watch(graphQlSubscriptionClientProvider));

/// One-shot fallback when [updateProgressSocketProvider] has not delivered data.
@riverpod
Future<UpdateProgressDto?> updateProgressSummary(Ref ref) =>
    ref.watch(updatesRepositoryProvider).updateProgress();

@riverpod
Future<String?> libraryLastUpdated(Ref ref) =>
    ref.watch(updatesRepositoryProvider).lastUpdateTimestamp();

/// Share one progress subscription across features to avoid duplicate server subscriptions.
@riverpod
Stream<UpdateProgressDto?> updateProgressSocket(Ref ref) =>
    ref.watch(updatesRepositoryProvider).updateProgressSubscription();

/// Emits running-state changes from the progress socket, ignoring count-only ticks.
@riverpod
AsyncValue<bool?> updateRunningSocket(Ref ref) => ref.watch(
  updateProgressSocketProvider.select(
    (progress) => progress.whenData((value) => value?.isRunning),
  ),
);

@riverpod
Future<List<MangaDto>> failedUpdates(Ref ref) {
  ref.listen(updateRunningSocketProvider, (_, next) {
    if (next.value == false) ref.invalidateSelf();
  });
  return ref.watch(updatesRepositoryProvider).failedUpdates();
}

@riverpod
Future<int> failedUpdateCount(Ref ref) async {
  ref.listen(updateRunningSocketProvider, (_, next) {
    if (next.value == false) ref.invalidateSelf();
  });
  return await ref.watch(updatesRepositoryProvider).failedUpdateCount() ?? 0;
}
