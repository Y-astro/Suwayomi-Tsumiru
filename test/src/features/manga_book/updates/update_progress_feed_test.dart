// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/update_status/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/update_status/update_status_model.dart';

class _ErrorsRepository extends UpdatesRepository {
  _ErrorsRepository(GraphQLClient client) : super(client, client);
  int countReads = 0;
  int listReads = 0;

  @override
  Future<int?> failedUpdateCount() async => ++countReads;

  @override
  Future<List<MangaDto>> failedUpdates() async {
    listReads++;
    return [];
  }
}

Fragment$UpdateProgressDto _progress(bool running, int total, int finished) =>
    Fragment$UpdateProgressDto(
      isRunning: running,
      totalJobs: total,
      finishedJobs: finished,
    );

void main() {
  test(
    'error list and count refresh after each completed run, without querying on progress ticks',
    () async {
      final feed = StreamController<UpdateProgressDto?>();
      addTearDown(feed.close);
      final repository = _ErrorsRepository(
        GraphQLClient(
          link: Link.function((_, [_]) => const Stream.empty()),
          cache: GraphQLCache(),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          updatesRepositoryProvider.overrideWith((ref) => repository),
          updateProgressSocketProvider.overrideWith((ref) => feed.stream),
        ],
      );
      addTearDown(container.dispose);
      container.listen(failedUpdatesProvider, (_, _) {});
      container.listen(failedUpdateCountProvider, (_, _) {});
      await pumpEventQueue();
      final baselineCount = repository.countReads;
      final baselineList = repository.listReads;

      for (final p in [_progress(true, 10, 0), _progress(true, 10, 5)]) {
        feed.add(p);
        await pumpEventQueue();
      }
      expect(repository.countReads, baselineCount);
      expect(repository.listReads, baselineList);

      for (var run = 1; run <= 2; run++) {
        feed.add(_progress(false, 10, 10));
        await pumpEventQueue();
        expect(repository.countReads, baselineCount + run);
        expect(repository.listReads, baselineList + run);
        feed.add(_progress(true, 10, 0));
        await pumpEventQueue();
      }
    },
  );

  test('the running signal follows the one progress feed and changes only on '
      'its edges, not on every progress push', () async {
    final feed = StreamController<UpdateProgressDto?>();
    addTearDown(feed.close);
    final container = ProviderContainer(
      overrides: [
        updateProgressSocketProvider.overrideWith((ref) => feed.stream),
      ],
    );
    addTearDown(container.dispose);
    final seen = <bool?>[];
    container.listen(
      updateRunningSocketProvider,
      (_, next) => seen.add(next.value),
    );

    for (final p in [
      _progress(false, 0, 0),
      _progress(true, 360, 0),
      _progress(true, 360, 12),
      _progress(true, 360, 200),
      _progress(true, 360, 359),
      _progress(false, 360, 360),
      _progress(false, 360, 360),
    ]) {
      feed.add(p);
      await pumpEventQueue();
    }

    expect(seen, [false, true, false]);
  });
}
