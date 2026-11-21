// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsumiru/src/constants/app_theme.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/theme/app_theme_builder.dart';
import 'package:tsumiru/src/widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import 'package:tsumiru/src/widgets/manga_cover/widgets/continue_reading_button.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('cover title and continue control at text scale $scale', (
      tester,
    ) async {
      var opened = 0;
      var continued = 0;
      const title = 'A long cover title with two lines';
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildAppTheme(
            theme: AppTheme.indigoNight,
            brightness: Brightness.dark,
            customSeed: const Color(0xFF7C7BFF),
            amoled: false,
          ),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 128,
                    height: 192,
                    child: MangaCoverGridTile(
                      titleOverride: title,
                      onPressed: () => opened++,
                      onContinueReading: () => continued++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(ContinueReadingButton));
      await tester.pumpAndSettle();
      expect(continued, 1);
      expect(opened, 0);
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
