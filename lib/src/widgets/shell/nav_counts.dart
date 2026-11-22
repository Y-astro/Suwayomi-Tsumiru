// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../constants/navigation_bar_data.dart';
import '../../features/library/presentation/library/controller/library_manga_list.dart';

typedef NavCounts = ({int library, int updates});

final navCountsProvider = Provider.autoDispose<NavCounts?>((ref) {
  final library = ref.watch(libraryMangaListProvider).value;
  if (library == null) return null;

  final titleIds = <int>{};
  var unreadChapters = 0;
  for (final manga in library) {
    if (titleIds.add(manga.id)) unreadChapters += manga.user.unreadCount;
  }
  return (library: titleIds.length, updates: unreadChapters);
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
