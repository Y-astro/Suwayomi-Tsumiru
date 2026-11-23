import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/settings/presentation/downloads/data/delete_chapters_settings_repository.dart';
import 'package:tsumiru/src/utils/graphql/legacy_user_fields_link.dart';

void main() {
  for (final legacy in [false, true]) {
    for (final state in [
      'eligible',
      'unread',
      'not-downloaded',
      'protected',
      'bookmarked',
      'unknown',
      'error',
    ]) {
      test('server delete eligibility $state legacy=$legacy', () async {
        var calls = 0;
        final user = {
          'isRead': state != 'unread',
          'isDownloaded': state != 'not-downloaded',
          'isBookmarked': state == 'bookmarked',
        };
        final response = {
          'chapter': state == 'unknown'
              ? null
              : {'id': 7, 'mangaId': 1, if (legacy) ...user else 'user': user},
          'manga': {
            'categories': {
              'nodes': [
                {'name': 'Reading'},
                if (state == 'protected') {'name': '  Currently Reading  '},
              ],
            },
          },
        };
        final downstream = Link.function((request, [forward]) async* {
          calls++;
          if (printNode(
            request.operation.document,
          ).contains('__type(name: "ChapterType")')) {
            yield Response(
              data: {
                '__type': {
                  'fields': [
                    {'name': 'id'},
                    if (!legacy) {'name': 'user'},
                  ],
                },
              },
              response: {},
            );
          } else {
            yield Response(
              data: response,
              response: {},
              errors: state == 'error'
                  ? [GraphQLError(message: 'denied')]
                  : null,
            );
          }
        });
        final client = GraphQLClient(
          link: legacy ? LegacyUserFieldsLink().concat(downstream) : downstream,
          cache: GraphQLCache(),
        );
        final repository = DeleteChaptersSettingsRepository(client);
        final allowed = await repository.canAutoDeleteServerChapter(
          mangaId: 1,
          chapterId: 7,
          allowBookmarked: false,
        );
        expect(allowed, state == 'eligible');
        if (state == 'bookmarked') {
          expect(
            await repository.canAutoDeleteServerChapter(
              mangaId: 1,
              chapterId: 7,
              allowBookmarked: true,
            ),
            isTrue,
          );
        }
        if (state == 'eligible') {
          user['isRead'] = false;
          if (legacy) (response['chapter'] as Map)['isRead'] = false;
          expect(
            await repository.canAutoDeleteServerChapter(
              mangaId: 1,
              chapterId: 7,
              allowBookmarked: false,
            ),
            isFalse,
          );
          expect(calls, greaterThanOrEqualTo(2));
        }
      });
    }
  }
}
