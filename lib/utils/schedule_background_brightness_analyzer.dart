import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

abstract final class ScheduleBackgroundBrightnessAnalyzer {
  static Future<Brightness?> analyzePath(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return analyzeBytes(await file.readAsBytes());
  }

  @visibleForTesting
  static Future<Brightness?> analyzeBytes(Uint8List bytes) async {
    final result = await Isolate.run(() => _analyzeBrightness(bytes));
    return switch (result) {
      0 => Brightness.light,
      1 => Brightness.dark,
      _ => null,
    };
  }
}

int? _analyzeBrightness(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    return null;
  }
  if (decoded == null || decoded.width == 0 || decoded.height == 0) {
    return null;
  }

  final sampleWidth = math.min(decoded.width, 72);
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

  final samples = <_LuminanceSample>[];
  var weightedTotal = 0.0;
  var totalWeight = 0.0;
  for (var y = 0; y < sampled.height; y++) {
    final normalizedY = (y + 0.5) / sampled.height;
    for (var x = 0; x < sampled.width; x++) {
      final pixel = sampled.getPixel(x, y);
      if (pixel.a < 128) continue;
      final normalizedX = (x + 0.5) / sampled.width;
      var weight = 0.15;
      if (normalizedY <= 0.19) weight += 5.0;
      if (normalizedX <= 0.12 && normalizedY > 0.19 && normalizedY < 0.88) {
        weight += 3.0;
      }
      if (normalizedY >= 0.86) weight += 4.0;

      final luminance = _relativeLuminance(
        pixel.r.toDouble(),
        pixel.g.toDouble(),
        pixel.b.toDouble(),
      );
      samples.add(_LuminanceSample(luminance, weight));
      weightedTotal += luminance * weight;
      totalWeight += weight;
    }
  }
  if (samples.isEmpty || totalWeight <= 0) return null;

  samples.sort((a, b) => a.luminance.compareTo(b.luminance));
  final medianTarget = totalWeight * 0.5;
  var accumulatedWeight = 0.0;
  var weightedMedian = samples.last.luminance;
  for (final sample in samples) {
    accumulatedWeight += sample.weight;
    if (accumulatedWeight >= medianTarget) {
      weightedMedian = sample.luminance;
      break;
    }
  }
  final weightedMean = weightedTotal / totalWeight;
  final criticalLuminance = weightedMedian * 0.65 + weightedMean * 0.35;

  // Bright backgrounds use the light interface (dark foreground); dark
  // backgrounds use the dark interface (light foreground).
  return criticalLuminance >= 0.28 ? 0 : 1;
}

double _relativeLuminance(double red, double green, double blue) {
  double linearize(double value) {
    final channel = value / 255;
    return channel <= 0.04045
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize(red) +
      0.7152 * linearize(green) +
      0.0722 * linearize(blue);
}

class _LuminanceSample {
  final double luminance;
  final double weight;

  const _LuminanceSample(this.luminance, this.weight);
}
