import 'dart:typed_data';

import 'package:cqut_helper/utils/background_color_extractor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('extracts a representative color from a background image', () async {
    final image = img.Image(width: 24, height: 24);
    img.fill(image, color: img.ColorRgb8(30, 180, 80));
    final bytes = Uint8List.fromList(img.encodePng(image));

    final color = await BackgroundColorExtractor.extractFromBytes(bytes);

    expect(color, isNotNull);
    final hsv = HSVColor.fromColor(color!);
    expect(hsv.hue, inInclusiveRange(120, 160));
    expect(hsv.saturation, greaterThan(0.35));
  });

  test('returns null for invalid image data', () async {
    final color = await BackgroundColorExtractor.extractFromBytes(
      Uint8List.fromList(const [1, 2, 3, 4]),
    );

    expect(color, isNull);
  });
}
