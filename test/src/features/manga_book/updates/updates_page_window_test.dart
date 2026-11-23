// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';

void main() {
  test('retained filtered rows use an adjusted server offset', () async {
    final offsets = <int?>[];
    final client = GraphQLClient(
      link: Link.function((request, [forward]) {
        offsets.add(request.variables['offset'] as int?);
        expect(request.variables['first'], 51);
        return Stream.value(
          Response(
            data: {
              '__typename': 'Query',
              'chapters': {
                '__typename': 'ChapterNodeList',
                'nodes': <dynamic>[],
              },
            },
            response: {},
          ),
        );
      }),
      cache: GraphQLCache(),
      defaultPolicies: DefaultPolicies(
        query: Policies(fetch: FetchPolicy.noCache),
      ),
    );
    final repository = UpdatesRepository(client, client);
    await repository.getRecentChaptersPage(pageNo: 1);
    await repository.getRecentChaptersPage(pageNo: 1, offset: 48);
    expect(offsets, [50, 48]);
  });

  group('splitPageWindow', () {
    test('one row past the page means another page follows', () {
      final page = splitPageWindow(List.generate(51, (i) => i), 50);
      expect(page.nodes, List.generate(50, (i) => i));
      expect(page.hasNextPage, isTrue);
    });
  });
}
