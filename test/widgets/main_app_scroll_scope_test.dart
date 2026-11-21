// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsumiru/src/tsumiru_app.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';
import 'package:tsumiru/src/widgets/main_app_scroll_scope.dart';

Future<ScrollController> _pumpList(
  WidgetTester tester, {
  bool scoped = true,
  bool reducedMotion = false,
}) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  Widget list = ListView.builder(
    controller: controller,
    itemCount: 100,
    itemBuilder: (_, i) => SizedBox(height: 50, child: Text('Item $i')),
  );
  if (scoped) list = MainAppScrollScope(child: list);
  await tester.pumpWidget(
    MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Scaffold(body: list),
      ),
    ),
  );
  return controller;
}

Future<void> _sendWheel(WidgetTester tester, double delta) async {
  final mouse = TestPointer(90, PointerDeviceKind.mouse);
  mouse.hover(tester.getCenter(find.byType(ListView).first));
  await tester.sendEventToBinding(mouse.scroll(Offset(0, delta)));
}

void main() {
  group('MainAppScrollScope and AppScrollBehavior wheel regressions', () {
    testWidgets('multi-frame 53px easing in MainAppScrollScope', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: MainAppScrollScope(
              child: ListView.builder(
                controller: controller,
                itemCount: 100,
                itemBuilder: (_, i) =>
                    SizedBox(height: 50, child: Text('Item $i')),
              ),
            ),
          ),
        ),
      );

      final point = tester.getCenter(find.text('Item 0'));
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      mouse.hover(point);

      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 53.0)));
      await tester.pump(const Duration(milliseconds: 16));

      // With smooth wheel follower active, frame 1 does not jump instantly to the full target
      final frame1 = controller.position.pixels;
      expect(frame1, greaterThan(0.0));
      expect(
        frame1,
        lessThan(90.1),
        reason: 'Expected gradual easing rather than an instant jump',
      );

      await tester.pump(const Duration(milliseconds: 16));
      final frame2 = controller.position.pixels;
      expect(frame2, greaterThan(frame1));
      expect(frame2, lessThan(90.1));

      await tester.pumpAndSettle();
      expect(controller.position.pixels, closeTo(90.1, 0.01));
    });

    testWidgets('cumulative small notches and direction reversal', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: MainAppScrollScope(
              child: ListView.builder(
                controller: controller,
                itemCount: 200,
                itemBuilder: (_, i) =>
                    SizedBox(height: 50, child: Text('Item $i')),
              ),
            ),
          ),
        ),
      );

      final point = tester.getCenter(find.text('Item 0'));
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      mouse.hover(point);

      // Send 3 notches of 20px
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 20.0)));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 20.0)));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 20.0)));
      await tester.pump(const Duration(milliseconds: 16));

      // Reversal notch of -30px
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -30.0)));
      await tester.pumpAndSettle();

      expect(controller.position.pixels, closeTo(51.0, 0.01));
    });

    testWidgets('actual nested-scroll target resolution (resolves innermost)', (
      tester,
    ) async {
      final outerController = ScrollController();
      final innerController = ScrollController();
      addTearDown(outerController.dispose);
      addTearDown(innerController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: MainAppScrollScope(
              child: ListView(
                controller: outerController,
                children: [
                  const SizedBox(height: 100, child: Text('Outer Top')),
                  SizedBox(
                    height: 300,
                    child: ListView.builder(
                      controller: innerController,
                      itemCount: 50,
                      itemBuilder: (_, i) =>
                          SizedBox(height: 40, child: Text('Inner $i')),
                    ),
                  ),
                  const SizedBox(height: 800, child: Text('Outer Bottom')),
                ],
              ),
            ),
          ),
        ),
      );

      final innerPoint = tester.getCenter(find.text('Inner 0'));
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      mouse.hover(innerPoint);

      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 53.0)));
      await tester.pump(const Duration(milliseconds: 16));

      expect(
        innerController.position.pixels,
        greaterThan(0.0),
        reason: 'Inner list should receive scroll',
      );
      expect(
        outerController.position.pixels,
        0.0,
        reason: 'Outer list should not move when inner is scrolled',
      );

      await tester.pumpAndSettle();
      expect(innerController.position.pixels, closeTo(90.1, 0.01));
      expect(outerController.position.pixels, 0.0);
      innerController.jumpTo(innerController.position.maxScrollExtent);
      await tester.pump();
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 53)));
      await tester.pumpAndSettle();
      expect(outerController.offset, closeTo(90.1, 0.01));
      expect(innerController.offset, innerController.position.maxScrollExtent);
    });

    testWidgets(
      'Shift modifier and horizontal wheel bypasses vertical follower',
      (tester) async {
        final vController = ScrollController();
        final hController = ScrollController();
        addTearDown(vController.dispose);
        addTearDown(hController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: Scaffold(
              body: MainAppScrollScope(
                child: SizedBox(
                  height: 200,
                  child: ListView.builder(
                    controller: hController,
                    scrollDirection: Axis.horizontal,
                    itemCount: 50,
                    itemBuilder: (_, i) =>
                        SizedBox(width: 80, child: Text('Col $i')),
                  ),
                ),
              ),
            ),
          ),
        );

        final point = tester.getCenter(find.text('Col 0'));
        final mouse = TestPointer(1, PointerDeviceKind.mouse);
        mouse.hover(point);

        // Pure horizontal scroll event
        await tester.sendEventToBinding(mouse.scroll(const Offset(40.0, 0.0)));
        await tester.pumpAndSettle();
        expect(hController.position.pixels, closeTo(40.0, 0.01));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, 30)));
        await tester.pumpAndSettle();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(hController.offset, closeTo(70, 0.01));
      },
    );

    testWidgets('interruption cancels active glide immediately', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: MainAppScrollScope(
              child: ListView.builder(
                controller: controller,
                itemCount: 100,
                itemBuilder: (_, i) =>
                    SizedBox(height: 50, child: Text('Row $i')),
              ),
            ),
          ),
        ),
      );

      final point = tester.getCenter(find.text('Row 0'));
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      mouse.hover(point);

      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100.0)));
      await tester.pump(const Duration(milliseconds: 16));
      final midway = controller.position.pixels;
      expect(midway, greaterThan(0.0));
      expect(midway, lessThan(100.0));

      // Simulate a user drag or notification interruption (e.g. touch or drag start)
      final touch = TestPointer(2, PointerDeviceKind.touch);
      await tester.sendEventToBinding(touch.down(point));
      await tester.pump(const Duration(milliseconds: 16));

      // Follower should have stopped gliding towards 100
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.position.pixels, closeTo(midway, 1.0));

      await tester.sendEventToBinding(touch.up());
      await tester.pumpAndSettle();
    });
  });

  testWidgets('reduced motion keeps the immediate wheel response', (
    tester,
  ) async {
    final controller = await _pumpList(tester, reducedMotion: true);
    await _sendWheel(tester, 53);
    expect(controller.offset, 90.1);
    await tester.pumpAndSettle();
    expect(controller.offset, 90.1);
  });

  testWidgets('outside main navigation the wheel behavior stays unchanged', (
    tester,
  ) async {
    final controller = await _pumpList(tester, scoped: false);
    await _sendWheel(tester, 53);
    expect(controller.offset, 53);
  });

  testWidgets('mobile retains the platform wheel handling', (tester) async {
    debugDesktopPlatformOverride = false;
    addTearDown(() => debugDesktopPlatformOverride = null);
    final controller = await _pumpList(tester);
    await _sendWheel(tester, 53);
    expect(controller.offset, 53);
  });

  testWidgets('trackpad movement bypasses the mouse follower', (tester) async {
    final controller = await _pumpList(tester);
    final point = tester.getCenter(find.byType(ListView));
    final pointer = TestPointer(91, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.panZoomStart(point));
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(
        point,
        pan: const Offset(0, -0.5),
        timeStamp: const Duration(milliseconds: 6),
      ),
    );
    expect(controller.offset, 0.5);
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(
        point,
        pan: const Offset(0, -1.75),
        timeStamp: const Duration(milliseconds: 12),
      ),
    );
    expect(controller.offset, 1.75);
    await tester.sendEventToBinding(
      pointer.panZoomEnd(timeStamp: const Duration(milliseconds: 18)),
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
    'external scrolling cancels the glide and disposal leaves no ticker',
    (tester) async {
      final controller = await _pumpList(tester);
      await _sendWheel(tester, 200);
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.offset, lessThan(200));
      controller.jumpTo(500);
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.offset, 500);
      await _sendWheel(tester, 200);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    },
  );
}
