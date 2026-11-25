// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/data/default_category.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/desktop_library_toolbar.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/updates/controller/updates_filter_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/updates/updates_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';

import '../../../../helpers/unreachable_server_stubs.dart';

class _Updates extends UpdatesRepository {
  _Updates(GraphQLClient client) : super(client, client);
  int reads = 0;

  @override
  Future<UpdatesPage?> getRecentChaptersPage({
    int pageNo = 0,
    UpdatesFilter filter = kNoUpdatesFilter,
    int? offset,
  }) async {
    reads++;
    return (nodes: <ChapterWithMangaDto>[], hasNextPage: false);
  }
}

void main() {
  testWidgets('desktop Refresh reloads Updates without a library mutation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDesktopPlatformOverride = true;
    addTearDown(() => debugDesktopPlatformOverride = null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => call.method == 'isMaximized' ? false : null,
        );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var mutations = 0;
    final client = GraphQLClient(
      link: Link.function((request, [forward]) {
        mutations += request.operation.document.definitions
            .whereType<OperationDefinitionNode>()
            .where((node) => node.type == OperationType.mutation)
            .length;
        return Stream.value(Response(data: {}, response: {}));
      }),
      cache: GraphQLCache(),
    );
    final updates = _Updates(client);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: Column(
              children: [
                DesktopTopBar(),
                Expanded(child: UpdatesScreen()),
              ],
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...unreachableServerStubs,
          sharedPreferencesProvider.overrideWithValue(prefs),
          graphQlClientProvider.overrideWith((ref) => client),
          updatesRepositoryProvider.overrideWith((ref) => updates),
          libraryLastUpdatedProvider.overrideWith((ref) async => null),
          failedUpdateCountProvider.overrideWith((ref) async => 0),
          defaultCategoryIdProvider.overrideWith((ref) async => 1),
          updateProgressSocketProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
          updatesFilterProvider.overrideWith(
            (ref) => (
              downloaded: null,
              unread: true,
              started: null,
              bookmarked: null,
            ),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final refresh = find.descendant(
      of: find.byType(DesktopToolbarBox),
      matching: find.text('Refresh'),
    );
    expect(refresh, findsOneWidget);
    expect(
      tester.getTopLeft(refresh).dx,
      lessThan(tester.getTopLeft(find.text('Update')).dx),
    );
    final filter = find.ancestor(
      of: find.byIcon(FluentIcons.filter_24_regular),
      matching: find.byType(DesktopToolbarBox),
    );
    expect(tester.widget<DesktopToolbarBox>(filter).borderColor, isNull);
    final initialReads = updates.reads;
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(updates.reads, initialReads + 1);
    expect(mutations, 0);
    tester.view.physicalSize = const Size(800, 700);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(updates.reads, initialReads + 2);
    expect(mutations, 0);
    expect(tester.takeException(), isNull);
  });
}
