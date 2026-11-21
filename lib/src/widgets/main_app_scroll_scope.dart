// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../features/manga_book/presentation/reader/widgets/mouse_wheel_speed.dart';
import '../utils/platform/platform_runtime.dart';

/// Marks a scrollable so [MainAppScrollScope] can locate its [ScrollPosition] under pointer events.
class MainAppScrollTarget extends SingleChildRenderObjectWidget {
  const MainAppScrollTarget({
    super.key,
    required this.state,
    required super.child,
  });

  final ScrollableState state;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderMetaData(metaData: state);
  }

  @override
  void updateRenderObject(BuildContext context, RenderMetaData renderObject) {
    renderObject.metaData = state;
  }
}

/// Wraps navigation shell content to provide smooth mouse-wheel scrolling via [MouseWheelSpeed].
class MainAppScrollScope extends StatefulWidget {
  const MainAppScrollScope({super.key, required this.child});

  final Widget child;

  static bool contains(BuildContext context) =>
      isDesktopPlatform &&
      context.findAncestorWidgetOfExactType<MainAppScrollScope>() != null;

  @override
  State<MainAppScrollScope> createState() => _MainAppScrollScopeState();
}

class _MainAppScrollScopeState extends State<MainAppScrollScope> {
  ScrollableState? _target;

  ScrollPosition? get _position =>
      _target?.mounted == true ? _target!.position : null;

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (event.kind != PointerDeviceKind.mouse) return;

    // Check keyboard modifiers; if Shift or modifier is pressed, horizontal behavior applies.
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final flipAxes = pressed.any(
      (ScrollConfiguration.of(context)).pointerAxisModifiers.contains,
    );

    // Only vertical wheel scrolling is handled by this follower.
    if (flipAxes || event.scrollDelta.dy == 0.0) {
      _target = null;
      return;
    }

    final hitTestResult = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      hitTestResult,
      event.position,
      event.viewId,
    );

    _target = null;
    for (final entry in hitTestResult.path) {
      final target = entry.target;
      if (target is RenderMetaData && target.metaData is ScrollableState) {
        final scrollableState = target.metaData as ScrollableState;
        if (!scrollableState.mounted) continue;
        final position = scrollableState.position;
        // NestedScrollView's coordinator uses combined offsets; retain its own wheel handling.
        if (position is! ScrollPositionWithSingleContext ||
            position.axisDirection != AxisDirection.down ||
            !position.physics.allowUserScrolling ||
            !position.hasContentDimensions) {
          continue;
        }
        final next = (position.pixels + event.scrollDelta.dy).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if (next == position.pixels) continue;
        _target = scrollableState;
        break; // First eligible innermost scrollable in hit path
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return widget.child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        MouseWheelSpeed(
          speed: 1.7,
          axis: Axis.vertical,
          reverse: false,
          positionOf: () => _position,
          child: widget.child,
        ),
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerSignal: _onPointerSignal,
          ),
        ),
      ],
    );
  }
}
