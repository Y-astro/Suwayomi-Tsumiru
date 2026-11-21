// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/data/default_category.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/library/presentation/library/library_screen.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/desktop_library_toolbar.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/library_manga_grid_view.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/data/syncyomi_settings_provider.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/tsumiru_app.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';
import 'package:tsumiru/src/widgets/main_app_scroll_scope.dart';

Fragment$CategoryDto _category(int id, String name) => Fragment$CategoryDto(
  defaultCategory: false,
  id: id,
  includeInDownload: Enum$IncludeOrExclude.UNSET,
  includeInUpdate: Enum$IncludeOrExclude.UNSET,
  name: name,
  order: id,
  mangas: Fragment$CategoryDto$mangas(totalCount: 0),
  meta: const [],
);

Fragment$MangaDto _manga(int id, String title) => Fragment$MangaDto(
  id: id,
  title: title,
  thumbnailUrl: null,
  chapters: Fragment$MangaDto$chapters(totalCount: 4),
  genre: const [],
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/$id',
  user: Fragment$MangaDto$user(
    bookmarkCount: 0,
    downloadCount: 1,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: 2,
  ),
);

/// Pumps the real [LibraryScreen] with two empty categories by default. Phone
/// widths take the legacy app bar; desktop widths take the toolbar + tab strip.
Future<ProviderContainer> _pumpLibrary(
  WidgetTester tester, {
  required Size surface,
  bool withManga = false,
  List<Fragment$CategoryDto>? categories,
}) async {
  final visibleCategories =
      categories ?? [_category(1, 'One'), _category(2, 'Two')];
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      // Never hit the network in widget tests.
      loggedInTrackersProvider.overrideWithValue(
        const AsyncData(<Fragment$TrackerDto>[]),
      ),
      updateRunningSocketProvider.overrideWithValue(
        const AsyncData<bool?>(null),
      ),
      failedUpdateCountProvider.overrideWithValue(const AsyncData(0)),
      syncYomiSettingsProvider.overrideWithValue(const AsyncData(null)),
      settledDefaultCategoryIdProvider.overrideWithValue(1),
      nonZeroCategoryListProvider.overrideWithValue(
        AsyncData(visibleCategories),
      ),
      visibleCategoryListProvider.overrideWithValue(
        AsyncData(visibleCategories),
      ),
      categoryMangaListProvider.overrideWith(
        (ref, categoryId) async => <Fragment$MangaDto>[],
      ),
      // The sticky search bar gates on the whole-library list being loaded.
      libraryMangaListProvider.overrideWith(
        (ref) async => <Fragment$MangaDto>[],
      ),
      categoryMangaListWithQueryAndFilterProvider(
        categoryId: 1,
      ).overrideWithValue(
        AsyncData([
          for (var i = 1; i <= 120; i++)
            if (withManga) _manga(i, 'Alpha $i'),
        ]),
      ),
      categoryMangaListWithQueryAndFilterProvider(
        categoryId: 2,
      ).overrideWithValue(
        AsyncData([
          for (var i = 1; i <= 120; i++)
            if (withManga) _manga(100 + i, 'Beta $i'),
        ]),
      ),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('window_manager'), (
        call,
      ) async {
        if (call.method == 'isMaximized') return false;
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        scrollBehavior: const AppScrollBehavior(),
        // Native desktop draws the toolbar in the shell bar above the
        // page; narrower surfaces keep the page on its own.
        home: MainAppScrollScope(child: Builder(
          builder: (context) => showsMergedTopBar(context)
              ? const Scaffold(
                  body: Column(
                    children: [
                      DesktopTopBar(),
                      Expanded(child: LibraryScreen(categoryId: 1)),
                    ],
                  ),
                )
              : const LibraryScreen(categoryId: 1),
        )),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('LibraryScreen responsive header', () {
    testWidgets('desktop shows the toolbar, phone keeps the AppBar', (
      tester,
    ) async {
      await _pumpLibrary(tester, surface: const Size(1400, 980));

      expect(tester.takeException(), isNull);
      expect(find.byType(DesktopLibraryToolbar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Library'), findsNothing);
      // Both categories fit: the strip shows them, no More control.
      expect(find.text('One', findRichText: true), findsOneWidget);
      expect(find.text('Two', findRichText: true), findsOneWidget);
      expect(find.textContaining('More (', findRichText: true), findsNothing);

      // Crossing the breakpoint re-renders the same screen as the phone
      // layout, so both branches are checked without remounting the tree.
      tester.view.physicalSize = const Size(412, 800);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(DesktopLibraryToolbar), findsNothing);
      expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
    });

    testWidgets('desktop keeps the top bar search with no visible categories', (
      tester,
    ) async {
      await _pumpLibrary(
        tester,
        surface: const Size(1400, 980),
        categories: const [],
      );

      expect(tester.takeException(), isNull);
      expect(find.text('No visible categories'), findsOneWidget);
      expect(find.text('Search title or author...'), findsOneWidget);
    });

    testWidgets('desktop library tab responds to precise trackpad pan and preserves horizontal paging', (
      tester,
    ) async {
      await _pumpLibrary(tester, surface: const Size(1400, 980), withManga: true);

      final grid = find.byType(LibraryMangaGridView).first;
      final point = tester.getCenter(grid);
      final scrollPosition = tester.state<ScrollableState>(
        find.descendant(of: grid, matching: find.byType(Scrollable)).first,
      ).position;
      final tabs = DefaultTabController.of(tester.element(grid));

      final pointer = TestPointer(9, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pointer.panZoomStart(point));

      double? onset;
      for (var step = 1; step <= 50; step++) {
        await tester.sendEventToBinding(
          pointer.panZoomUpdate(
            point,
            pan: Offset(0, -step * 0.5),
            timeStamp: Duration(milliseconds: step * 6),
          ),
        );
        await tester.pump(const Duration(milliseconds: 6));
        if (onset == null && scrollPosition.pixels > 0) onset = step * 0.5;
      }

      expect(onset, isNotNull);
      // Under kPrecisePointerHitSlop (1.0) and TouchTabPager competition, onset is <= 3px.
      // Without patch, it took > 18px!
      expect(onset!, lessThanOrEqualTo(3.0), reason: 'Trackpad scrolling should start quickly on desktop library tab');

      await tester.sendEventToBinding(pointer.panZoomEnd(timeStamp: const Duration(milliseconds: 306)));
      await tester.pumpAndSettle();

      final horizontal = TestPointer(10, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(horizontal.panZoomStart(point,
          timeStamp: const Duration(seconds: 1)));
      for (var step = 1; step <= 24; step++) {
        await tester.sendEventToBinding(horizontal.panZoomUpdate(point,
          pan: Offset(-step * 50.0, 0),
          timeStamp: Duration(milliseconds: 1000 + step * 12)));
        await tester.pump(const Duration(milliseconds: 12));
      }
      await tester.sendEventToBinding(horizontal.panZoomEnd(
          timeStamp: const Duration(milliseconds: 1300)));
      await tester.pumpAndSettle();
      expect(tabs.index, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
