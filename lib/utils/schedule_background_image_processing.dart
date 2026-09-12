import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;

const int scheduleBackgroundMaxLongEdge = 2400;
const int scheduleBackgroundJpegQuality = 88;

@immutable
class ScheduleBackgroundOutputSize {
  final int width;
  final int height;

  const ScheduleBackgroundOutputSize({
    required this.width,
    required this.height,
  });
}

ScheduleBackgroundOutputSize constrainScheduleBackgroundSize({
  required int width,
  required int height,
  int maxLongEdge = scheduleBackgroundMaxLongEdge,
}) {
  if (width <= 0 || height <= 0 || maxLongEdge <= 0) {
    throw ArgumentError('Image dimensions and maxLongEdge must be positive.');
  }
  final longest = width > height ? width : height;
  if (longest <= maxLongEdge) {
    return ScheduleBackgroundOutputSize(width: width, height: height);
  }
  final scale = maxLongEdge / longest;
  return ScheduleBackgroundOutputSize(
    width: (width * scale).round().clamp(1, maxLongEdge),
    height: (height * scale).round().clamp(1, maxLongEdge),
  );
}

Future<Uint8List> encodeScheduleBackgroundJpeg(
  ui.Image image, {
  int quality = scheduleBackgroundJpegQuality,
}) async {
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (rgba == null) throw StateError('Unable to read cropped image pixels.');
  return encodeScheduleBackgroundRgbaAsJpeg(
    rgba,
    width: image.width,
    height: image.height,
    quality: quality,
  );
}

@visibleForTesting
Uint8List encodeScheduleBackgroundRgbaAsJpeg(
  ByteData rgba, {
  required int width,
  required int height,
  int quality = scheduleBackgroundJpegQuality,
}) {
  final raster = image_lib.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
    rowStride: width * 4,
    order: image_lib.ChannelOrder.rgba,
  );
  return image_lib.encodeJpg(raster, quality: quality.clamp(1, 100));
}
