import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';

void main() {
  group('UpdatesRepository.getUnreadUpdateChapterCount', () {
    test(
      'sends exact count-only query with inLibrary=true, isRead=false, first=0',
      () async {
        Request? capturedRequest;
        final client = GraphQLClient(
          link: Link.function((request, [forward]) {
            capturedRequest = request;
            return Stream.value(
              Response(
                data: {
                  'chapters': {'totalCount': 172},
                },
                response: {},
              ),
            );
          }),
          cache: GraphQLCache(),
        );

        final repo = UpdatesRepository(client, client);
        final count = await repo.getUnreadUpdateChapterCount();

        expect(count, 172);
        expect(capturedRequest, isNotNull);
        expect(
          capturedRequest!.operation.operationName,
          'GetChapterWithMangaPageUnreadCount',
        );

        final docStr = printNode(capturedRequest!.operation.document);
        expect(docStr, contains('query GetChapterWithMangaPageUnreadCount'));
        expect(docStr, contains('chapters(filter: \$filter, first: 0)'));
        expect(docStr, contains('totalCount'));
        expect(docStr, isNot(contains('nodes')));

        final filter =
            capturedRequest!.variables['filter'] as Map<String, dynamic>;
        expect(filter['inLibrary'], {'equalTo': true});
        expect(filter['isRead'], {'equalTo': false});
      },
    );

    test(
      'returns null on graphQLErrors or partial error or null data',
      () async {
        final errorClient = GraphQLClient(
          link: Link.function((request, [forward]) {
            return Stream.value(
              Response(
                errors: [GraphQLError(message: 'server error')],
                response: {},
              ),
            );
          }),
          cache: GraphQLCache(),
        );

        final repo = UpdatesRepository(errorClient, errorClient);
        final count = await repo.getUnreadUpdateChapterCount();
        expect(count, isNull);
      },
    );

    test('returns null when totalCount is missing or malformed', () async {
      final badClient = GraphQLClient(
        link: Link.function((request, [forward]) {
          return Stream.value(Response(data: {'chapters': null}, response: {}));
        }),
        cache: GraphQLCache(),
      );

      final repo = UpdatesRepository(badClient, badClient);
      final count = await repo.getUnreadUpdateChapterCount();
      expect(count, isNull);
    });

    for (final malformed in [
      'invalid object',
      <dynamic>[],
      {'totalCount': '172'},
    ]) {
      test('malformed chapter result stays unavailable: $malformed', () async {
        final client = GraphQLClient(
          link: Link.function(
            (request, [forward]) => Stream.value(
              Response(data: {'chapters': malformed}, response: {}),
            ),
          ),
          cache: GraphQLCache(),
        );
        expect(
          await UpdatesRepository(client, client).getUnreadUpdateChapterCount(),
          isNull,
        );
      });
    }

    test('partial errors cannot supply a misleading chapter count', () async {
      final client = GraphQLClient(
        link: Link.function(
          (request, [forward]) => Stream.value(
            Response(
              data: {
                'chapters': {'totalCount': 172},
              },
              errors: [GraphQLError(message: 'partial failure')],
              response: {},
            ),
          ),
        ),
        cache: GraphQLCache(),
      );
      expect(
        await UpdatesRepository(client, client).getUnreadUpdateChapterCount(),
        isNull,
      );
    });

    test('returns 0 when totalCount is genuine 0', () async {
      final zeroClient = GraphQLClient(
        link: Link.function((request, [forward]) {
          return Stream.value(
            Response(
              data: {
                'chapters': {'totalCount': 0},
              },
              response: {},
            ),
          );
        }),
        cache: GraphQLCache(),
      );

      final repo = UpdatesRepository(zeroClient, zeroClient);
      final count = await repo.getUnreadUpdateChapterCount();
      expect(count, 0);
    });
  });
}
