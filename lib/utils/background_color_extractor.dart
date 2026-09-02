import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

abstract final class BackgroundColorExtractor {
  static Future<Color?> extractFromPath(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return extractFromBytes(await file.readAsBytes());
  }

  @visibleForTesting
  static Future<Color?> extractFromBytes(Uint8List bytes) async {
    final argb = await Isolate.run(() => _extractSeedArgb(bytes));
    if (argb == null) return null;
    return _normalizeSeed(Color(argb));
  }

  static Color _normalizeSeed(Color color) {
    final hsl = HSLColor.fromColor(color);
    if (hsl.saturation < 0.08) {
      return const Color(0xFF607D8B);
    }
    return hsl
        .withSaturation(hsl.saturation.clamp(0.38, 0.78).toDouble())
        .withLightness(hsl.lightness.clamp(0.38, 0.62).toDouble())
        .toColor();
  }
}

int? _extractSeedArgb(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    return null;
  }
  if (decoded == null || decoded.width == 0 || decoded.height == 0) {
    return null;
  }
  final sampleWidth = math.min(decoded.width, 96);
  final sampleHeight = math.max(
    1,
    (decoded.height * sampleWidth / decoded.width).round(),
  );
  final sampled = img.copyResize(
    decoded,
    width: sampleWidth,
    height: sampleHeight,
    interpolation: img.Interpolation.average,
  );

  final buckets = <int, _ColorBucket>{};
  var fallbackR = 0.0;
  var fallbackG = 0.0;
  var fallbackB = 0.0;
  var fallbackWeight = 0.0;

  for (final pixel in sampled) {
    final alpha = pixel.a.toDouble();
    if (alpha < 128) continue;
    final r = pixel.r.toDouble().clamp(0.0, 255.0);
    final g = pixel.g.toDouble().clamp(0.0, 255.0);
    final b = pixel.b.toDouble().clamp(0.0, 255.0);
    final alphaWeight = alpha / 255.0;
    fallbackR += r * alphaWeight;
    fallbackG += g * alphaWeight;
    fallbackB += b * alphaWeight;
    fallbackWeight += alphaWeight;

    final hsv = _rgbToHsv(r, g, b);
    if (hsv.value < 0.12 || hsv.value > 0.94 || hsv.saturation < 0.12) {
      continue;
    }
    final hueBin = (hsv.hue / 20).floor().clamp(0, 17);
    final saturationBin = (hsv.saturation * 3).floor().clamp(0, 2);
    final valueBin = (hsv.value * 3).floor().clamp(0, 2);
    final key = hueBin * 100 + saturationBin * 10 + valueBin;
    final weight =
        alphaWeight * (0.35 + hsv.saturation * 1.8) * (0.65 + hsv.value * 0.7);
    buckets
        .putIfAbsent(key, _ColorBucket.new)
        .add(r: r, g: g, b: b, weight: weight);
  }

  if (buckets.isNotEmpty) {
    final selected = buckets.values.reduce(
      (a, b) => a.totalWeight >= b.totalWeight ? a : b,
    );
    return selected.toArgb();
  }
  if (fallbackWeight <= 0) return null;
  return _argb(
    fallbackR / fallbackWeight,
    fallbackG / fallbackWeight,
    fallbackB / fallbackWeight,
  );
}

_Hsv _rgbToHsv(double r255, double g255, double b255) {
  final r = r255 / 255;
  final g = g255 / 255;
  final b = b255 / 255;
  final maximum = math.max(r, math.max(g, b));
  final minimum = math.min(r, math.min(g, b));
  final delta = maximum - minimum;
  var hue = 0.0;
  if (delta > 0) {
    if (maximum == r) {
      hue = 60 * (((g - b) / delta) % 6);
    } else if (maximum == g) {
      hue = 60 * (((b - r) / delta) + 2);
    } else {
      hue = 60 * (((r - g) / delta) + 4);
    }
  }
  if (hue < 0) hue += 360;
  final saturation = maximum == 0 ? 0.0 : delta / maximum;
  return _Hsv(hue: hue, saturation: saturation, value: maximum);
}

int _argb(double r, double g, double b) {
  final red = r.round().clamp(0, 255);
  final green = g.round().clamp(0, 255);
  final blue = b.round().clamp(0, 255);
  return (255 << 24) | (red << 16) | (green << 8) | blue;
}

class _Hsv {
  final double hue;
  final double saturation;
  final double value;

  const _Hsv({
    required this.hue,
    required this.saturation,
    required this.value,
  });
}

class _ColorBucket {
  double totalWeight = 0;
  double red = 0;
  double green = 0;
  double blue = 0;

  void add({
    required double r,
    required double g,
    required double b,
    required double weight,
  }) {
    totalWeight += weight;
    red += r * weight;
    green += g * weight;
    blue += b * weight;
  }

  int toArgb() =>
      _argb(red / totalWeight, green / totalWeight, blue / totalWeight);
}
