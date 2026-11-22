// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

/// Scripts a single canned response for whatever request the client sends.
class _FakeLink extends Link {
  _FakeLink(this.response);
  final Response response;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    yield response;
  }
}

GraphQLClient _clientWith(Response response) => GraphQLClient(
      link: _FakeLink(response),
      cache: GraphQLCache(),
    );

Response _updateMangasResponse(List<int> ids) => Response(
      data: {
        'updateMangas': {
          'mangas': [
            for (final id in ids) {'id': id, '__typename': 'MangaType'},
          ],
          '__typename': 'UpdateMangasPayload',
        },
        '__typename': 'Mutation',
      },
      response: {},
    );

void main() {
  test('the repository provider invalidates both error views after a sync', () async {
    var countReads = 0;
    var listReads = 0;
    final container = ProviderContainer(overrides: [
      graphQlClientProvider.overrideWith((ref) => _clientWith(Response(data: {
        'fetchChapters': {'chapters': [], '__typename': 'FetchChaptersPayload'},
        '__typename': 'Mutation',
      }, response: {}))),
      failedUpdateCountProvider.overrideWith((ref) async => ++countReads),
      failedUpdatesProvider.overrideWith((ref) async {
        listReads++;
        return [];
      }),
    ]);
    addTearDown(container.dispose);
    container.listen(failedUpdateCountProvider, (_, _) {});
    container.listen(failedUpdatesProvider, (_, _) {});
    await pumpEventQueue();

    await container.read(mangaBookRepositoryProvider).getChapterList(5);
    await pumpEventQueue();

    expect(countReads, 2);
    expect(listReads, 2);
  });

  for (final metadata in [false, true]) {
    final field = metadata ? 'fetchMangaAndChapters' : 'fetchChapters';
    Future<void> fetch(MangaBookRepository repo) async {
      if (metadata) {
        await repo.getMangaAndChapterList(5);
      } else {
        await repo.getChapterList(5);
      }
    }

    test(
      '$field reconciles errors after a successful empty chapter sync',
      () async {
        var reconciled = 0;
        final repo = MangaBookRepository(
          _clientWith(
            Response(
              data: {
                field: {'chapters': [], '__typename': 'Payload'},
                '__typename': 'Mutation',
              },
              response: {},
            ),
          ),
          onChaptersSynced: () => reconciled++,
        );

        await fetch(repo);

        expect(reconciled, 1);
      },
    );

    test(
      '$field does not reconcile cached chapters alongside a source error',
      () async {
        var reconciled = 0;
        final repo = MangaBookRepository(
          _clientWith(
            Response(
              data: {
                field: {'chapters': [], '__typename': 'Payload'},
                '__typename': 'Mutation',
              },
              errors: [GraphQLError(message: 'source fetch failed')],
              response: {},
            ),
          ),
          onChaptersSynced: () => reconciled++,
        );

        await expectLater(fetch(repo), throwsException);

        expect(reconciled, 0);
      },
    );

    test('$field does not reconcile a missing payload', () async {
      var reconciled = 0;
      final repo = MangaBookRepository(
        _clientWith(
          Response(data: {field: null, '__typename': 'Mutation'}, response: {}),
        ),
        onChaptersSynced: () => reconciled++,
      );

      await fetch(repo);

      expect(reconciled, 0);
    });
  }

  test('addMangasToLibrary reflects a partial server-side apply', () async {
    // Server only confirmed one of the two requested ids.
    final repo = MangaBookRepository(_clientWith(_updateMangasResponse([5])));

    final result = await repo.addMangasToLibrary([5, 9]);

    expect(result, [5]);
  });
}
