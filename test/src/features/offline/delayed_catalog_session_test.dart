import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/library/data/category_repository.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_cover_warmer.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_sync.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/widgets/shell/nav_counts.dart';

import '../manga_book/manga_details/chapter_test_helpers.dart';

GraphQLClient _client() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

class _Session extends AuthCredentialsStore {
  int epoch = 0;
  @override
  int get sessionEpoch => epoch;
  @override
  Future<AuthCredentialsState> build() async => const AuthCredentialsState();
}

class _Library extends CategoryRepository {
  _Library() : super(_client());
  final entered = Completer<void>();
  final response = Completer<List<MangaDto>?>();
  Future<List<MangaDto>?>? nextResponse;
  int requests = 0;
  @override
  Future<List<MangaDto>?> getAllLibraryMangas({bool withFirstUnread = true}) {
    if (requests++ == 0) entered.complete();
    return nextResponse ?? response.future;
  }
}

class _Details extends MangaBookRepository {
  _Details() : super(_client());
  final entered = Completer<void>();
  final manga = Completer<MangaDto?>();
  final chapters = Completer<List<ChapterDto>?>();
  int sourceFetches = 0;
  @override
  Future<MangaDto?> getManga({required int mangaId}) {
    entered.complete();
    return manga.future;
  }

  @override
  Future<List<ChapterDto>?> getStoredChapterList(int mangaId) {
    entered.complete();
    return chapters.future;
  }

  @override
  Future<List<ChapterDto>?> getMangaAndChapterList(int mangaId) async {
    sourceFetches++;
    return [ch(id: 2, number: 2)];
  }
}

class _Sync extends Fake implements OfflineSync {
  int mangaWrites = 0;
  int chapterWrites = 0;
  int prunes = 0;
  @override
  int get syncGeneration => 0;
  @override
  Future<void> syncManga(
    MangaDto manga, {
    required int fetchedAtGen,
    bool isSettleRetry = false,
  }) async {
    mangaWrites++;
  }

  @override
  Future<Set<int>> syncChapters(List<ChapterDto> chapters) async {
    chapterWrites++;
    return {};
  }

  @override
  Future<void> pruneRemovedLibraryManga(List<MangaDto> serverLibrary) async {
    prunes++;
  }
}

class _Covers extends OfflineCoverWarmer {
  int calls = 0;
  @override
  void build() {}
  @override
  Future<void> warmLibraryCovers(List<MangaDto> mangas) async {
    calls++;
  }
}

MangaDto _manga({int unreadCount = 1}) => MangaDto(
  id: 1,
  title: 'First account',
  chapters: Fragment$MangaDto$chapters(totalCount: 1),
  genre: const [],
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/1',
  user: Fragment$MangaDto$user(
    bookmarkCount: 0,
    downloadCount: 0,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: unreadCount,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Session auth;
  late _Library library;
  late _Details details;
  late _Sync sync;
  late _Covers covers;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    auth = _Session();
    library = _Library();
    details = _Details();
    sync = _Sync();
    covers = _Covers();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authCredentialsStoreProvider.overrideWith(() => auth),
        categoryRepositoryProvider.overrideWithValue(library),
        updateRunningSocketProvider.overrideWithValue(
          const AsyncData<bool?>(false),
        ),
        mangaBookRepositoryProvider.overrideWithValue(details),
        offlineReadDatabaseProvider.overrideWithValue(null),
        offlineActiveProvider.overrideWithValue(false),
        offlineSyncProvider.overrideWithValue(sync),
        offlineCoverWarmerProvider.overrideWith(() => covers),
      ],
    );
    await container.read(authCredentialsStoreProvider.future);
  });
  tearDown(() => container.dispose());

  test(
    'delayed library from previous account cannot mirror prune or warm covers',
    () async {
      container.listen(libraryMangaListProvider, (_, _) {});
      final pending = container.read(libraryMangaListProvider.future);
      await library.entered.future;
      auth.epoch++;
      library.response.complete([_manga()]);
      expect(await pending, isNull);
      expect(sync.mangaWrites, 0);
      expect(sync.prunes, 0);
      expect(covers.calls, 0);
    },
  );

  test(
    'confirmed read changes refresh the count once for a burst of writes',
    () async {
      final counted = Completer<NavCounts>();
      container.listen(navCountsProvider, (_, next) {
        if (next != null && next.updates == 1) counted.complete(next);
      });
      await library.entered.future;
      library.response.complete([_manga(unreadCount: 2)]);
      await container.read(libraryMangaListProvider.future);
      expect(container.read(navCountsProvider), (library: 1, updates: 2));

      library.nextResponse = Future.value([_manga(unreadCount: 1)]);
      final revision = container.read(updatesReadRevisionProvider.notifier);
      revision.bump();
      revision.bump();

      expect(await counted.future.timeout(const Duration(seconds: 3)), (
        library: 1,
        updates: 1,
      ));
      expect(library.requests, 2);
    },
  );
}
