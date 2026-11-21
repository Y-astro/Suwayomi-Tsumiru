// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../../utils/theme/brand.dart';

// One shared 1x256 texture replaces repeated gradient shading while covers scroll.
final _scrimTexture = _createScrimTexture();

Future<ui.Image> _createScrimTexture() async {
  final pixels = Uint8List(256 * 4);
  final alpha = OnImage.scrim.toARGB32() >> 24;
  for (var y = 0; y < 256; y++) {
    pixels[y * 4 + 3] = (alpha * y / 255).round();
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: 1,
    height: 256,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  ui.Codec? codec;
  try {
    codec = await descriptor.instantiateCodec();
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

/// Matches the original cover scrim using a small shared texture.
class CoverScrimDecoration extends Decoration {
  const CoverScrimDecoration({required this.borderColor});
  final Color borderColor;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _CoverScrimPainter(borderColor, onChanged);

  @override
  bool operator ==(Object other) =>
      other is CoverScrimDecoration && other.borderColor == borderColor;

  @override
  int get hashCode => Object.hash(CoverScrimDecoration, borderColor);
}

class _CoverScrimPainter extends BoxPainter {
  _CoverScrimPainter(Color borderColor, VoidCallback? onChanged)
    : _border = BoxDecoration(
        border: Border.all(width: 0, color: borderColor),
      ).createBoxPainter(onChanged),
      super(onChanged) {
    _scrimTexture.then(
      (image) {
        if (_disposed) return;
        _image = image;
        onChanged?.call();
      },
      onError: (Object error, StackTrace stack) {
        // Retain the original gradient if texture creation fails.
      },
    );
  }

  static const _gradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, OnImage.scrim],
  );
  final BoxPainter _border;
  final _imagePaint = ui.Paint()..filterQuality = ui.FilterQuality.low;
  final _gradientPaint = ui.Paint();
  ui.Image? _image;
  ui.Rect? _rect;
  bool _disposed = false;

  @override
  void paint(
    ui.Canvas canvas,
    Offset offset,
    ImageConfiguration configuration,
  ) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final rect = ui.Rect.fromLTWH(
      offset.dx,
      offset.dy + size.height * 2 / 3,
      size.width,
      size.height / 3,
    );
    final image = _image;
    if (image != null) {
      canvas.drawImageRect(
        image,
        const ui.Rect.fromLTWH(0, 0, 1, 256),
        rect,
        _imagePaint,
      );
    } else {
      if (_rect != rect) {
        _rect = rect;
        _gradientPaint.shader = _gradient.createShader(rect);
      }
      canvas.drawRect(rect, _gradientPaint);
    }
    _border.paint(canvas, offset, configuration);
  }

  @override
  void dispose() {
    _disposed = true;
    _image = null;
    _border.dispose();
    super.dispose();
  }
}
