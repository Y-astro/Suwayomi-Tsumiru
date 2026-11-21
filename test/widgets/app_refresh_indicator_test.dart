// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';
import 'package:tsumiru/src/widgets/app_refresh_indicator.dart';

void main() {
  for (final desktop in [true, false]) {
    testWidgets('pull refresh on desktop=$desktop', (tester) async {
      debugDesktopPlatformOverride = desktop;
      addTearDown(() => debugDesktopPlatformOverride = null);
      var refreshed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppRefreshIndicator(
              onRefresh: () async {
                refreshed++;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 1600, child: Text('Local content')),
                ],
              ),
            ),
          ),
        ),
      );
      final point = tester.getCenter(find.byType(ListView));
      final pointer = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pointer.panZoomStart(point));
      for (var i = 1; i <= 20; i++) {
        await tester.sendEventToBinding(
          pointer.panZoomUpdate(
            point,
            pan: Offset(0, i * 40.0),
            timeStamp: Duration(milliseconds: i * 16),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendEventToBinding(
        pointer.panZoomEnd(timeStamp: const Duration(milliseconds: 336)),
      );
      await tester.pumpAndSettle();
      expect(refreshed, desktop ? 0 : 1);
    });
  }
}
