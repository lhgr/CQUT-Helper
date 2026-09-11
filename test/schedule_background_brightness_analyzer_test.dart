import 'dart:typed_data';

import 'package:cqut_helper/utils/schedule_background_brightness_analyzer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  Uint8List solidImage(int channel) {
    final image = img.Image(width: 24, height: 48);
    img.fill(image, color: img.ColorRgb8(channel, channel, channel));
    return Uint8List.fromList(img.encodePng(image));
  }

  test('明亮背景选择浅色界面', () async {
    expect(
      await ScheduleBackgroundBrightnessAnalyzer.analyzeBytes(solidImage(245)),
      Brightness.light,
    );
  });

  test('深色背景选择深色界面', () async {
    expect(
      await ScheduleBackgroundBrightnessAnalyzer.analyzeBytes(solidImage(18)),
      Brightness.dark,
    );
  });

  test('无效图片不会猜测配色', () async {
    expect(
      await ScheduleBackgroundBrightnessAnalyzer.analyzeBytes(
        Uint8List.fromList([1, 2, 3]),
      ),
      isNull,
    );
  });
}
