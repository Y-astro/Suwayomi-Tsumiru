// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/theme/brand.dart';
import 'package:tsumiru/src/widgets/manga_cover/grid/cover_scrim_decoration.dart';

Future<Uint8List> _render(
  Decoration decoration,
  Size size,
  Offset offset,
  Color background,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..drawColor(background, ui.BlendMode.src);
  final ready = decoration is CoverScrimDecoration ? Completer<void>() : null;
  final painter = decoration.createBoxPainter(() {
    ready?.complete();
  });
  if (ready != null) await ready.future.timeout(const Duration(seconds: 5));
  painter.paint(canvas, offset, ImageConfiguration(size: size));
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (size.width + 20).ceil(),
    (size.height + 24).ceil(),
  );
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  painter.dispose();
  return bytes;
}

void main() {
  testWidgets('scrim retains the original foreground pixels', (tester) async {
    await tester.runAsync(() async {
      const border = Color(0xFF112233);
      final original = BoxDecoration(
        border: Border.all(width: 0, color: border),
        gradient: const LinearGradient(
          begin: Alignment(0, 1 / 3),
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), OnImage.scrim],
        ),
      );
      final optimized = CoverScrimDecoration(borderColor: border);
      for (final size in [const Size(128, 192), const Size(125.5, 187.25)]) {
        for (final offset in [Offset.zero, const Offset(7.25, 11.5)]) {
          for (final background in [
            const Color(0xFFFFFFFF),
            const Color(0xFF405060),
          ]) {
            final before = await _render(original, size, offset, background);
            final after = await _render(optimized, size, offset, background);
            var maximumDifference = 0;
            for (var i = 0; i < before.length; i++) {
              final difference = (before[i] - after[i]).abs();
              if (difference > maximumDifference) {
                maximumDifference = difference;
              }
            }
            expect(
              maximumDifference,
              lessThanOrEqualTo(1),
              reason: 'Foreground differs at size=$size, offset=$offset',
            );
          }
        }
      }
    });
  });
}
