import 'dart:typed_data';

import 'package:cqut_helper/utils/schedule_background_image_processing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;

void main() {
  test('背景输出保持宽高比并限制最长边', () {
    final constrained = constrainScheduleBackgroundSize(
      width: 1800,
      height: 4000,
    );

    expect(constrained.width, 1080);
    expect(constrained.height, 2400);

    final alreadySmall = constrainScheduleBackgroundSize(
      width: 1080,
      height: 1920,
    );
    expect(alreadySmall.width, 1080);
    expect(alreadySmall.height, 1920);
  });

  test('RGBA 裁剪像素编码为 JPEG 而不是无损 PNG', () {
    final rgba = Uint8List.fromList(<int>[
      255,
      0,
      0,
      255,
      0,
      255,
      0,
      255,
      0,
      0,
      255,
      255,
      255,
      255,
      255,
      255,
    ]).buffer.asByteData();

    final encoded = encodeScheduleBackgroundRgbaAsJpeg(
      rgba,
      width: 2,
      height: 2,
    );
    final decoded = image_lib.decodeJpg(encoded);

    expect(encoded.sublist(0, 2), orderedEquals(<int>[0xff, 0xd8]));
    expect(decoded, isNotNull);
    expect(decoded!.width, 2);
    expect(decoded.height, 2);
  });
}
