// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../constants/navigation_bar_data.dart';
import '../../features/library/presentation/library/controller/library_manga_list.dart';
import '../../features/manga_book/data/updates/updates_repository.dart';
import '../../features/offline/data/server_reachability.dart';

typedef NavCounts = ({int library, int? updates});

final updatesUnreadChapterCountProvider = FutureProvider.autoDispose<int?>((
  ref,
) async {
  final library = ref.watch(
    libraryMangaListProvider.select((state) => state.value),
  );
  if (library == null) return null;

  final offline =
      ref.watch(serverUnreachableProvider) || ref.watch(viewOfflineNowProvider);
  if (offline) return null;

  return ref.watch(updatesRepositoryProvider).getUnreadUpdateChapterCount();
});

final navCountsProvider = Provider.autoDispose<NavCounts?>((ref) {
  final library = ref.watch(libraryMangaListProvider).value;
  if (library == null) return null;

  final offline =
      ref.watch(serverUnreachableProvider) || ref.watch(viewOfflineNowProvider);
  final updatesCount = offline
      ? null
      : ref.watch(updatesUnreadChapterCountProvider).value;

  return (
    library: {for (final manga in library) manga.id}.length,
    updates: updatesCount,
  );
});

String countedNavLabel(
  BuildContext context,
  NavigationBarData data,
  NavCounts? counts,
) {
  final label = data.label(context);
  final count = switch (data.motion) {
    NavMotion.library => counts?.library,
    NavMotion.updates => counts?.updates,
    _ => null,
  };
  return count == null ? label : '$label ($count)';
}
