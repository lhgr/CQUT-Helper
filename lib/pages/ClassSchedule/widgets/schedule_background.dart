import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:flutter/material.dart';

class ScheduleBackground extends StatelessWidget {
  final ScheduleLayoutSettings settings;

  const ScheduleBackground({super.key, required this.settings});

  static File? imageFile(ScheduleLayoutSettings settings) {
    final path = settings.backgroundImagePath?.trim();
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  static bool hasImage(ScheduleLayoutSettings settings) =>
      imageFile(settings) != null;

  /// Warms Flutter's image cache before the first app frame is rendered.
  static Future<void> preloadFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return;

    final stream = FileImage(file).resolve(ImageConfiguration.empty);
    final completer = Completer<void>();
    ImageInfo? resolvedImage;
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, _) {
        resolvedImage = image;
        if (!completer.isCompleted) completer.complete();
      },
      onError: (_, _) {
        if (!completer.isCompleted) completer.complete();
      },
    );
    stream.addListener(listener);
    await completer.future;
    stream.removeListener(listener);
    resolvedImage?.dispose();
  }

  static Future<void> precacheFile(
    BuildContext context,
    String path, {
    bool evict = true,
  }) async {
    final file = File(path);
    if (!await file.exists()) return;
    final provider = FileImage(file);
    if (evict) await provider.evict();
    if (!context.mounted) return;
    await precacheImage(provider, context, onError: (_, _) {});
  }

  @override
  Widget build(BuildContext context) {
    final file = imageFile(settings);
    final surface = Theme.of(context).colorScheme.surface;
    if (file == null) return ColoredBox(color: surface);
    final stat = file.statSync();
    final imageKey = ValueKey<String>(
      '${file.path}:${stat.modified.microsecondsSinceEpoch}:${stat.size}',
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: surface),
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: settings.backgroundBlur,
              sigmaY: settings.backgroundBlur,
            ),
            child: Opacity(
              opacity: settings.backgroundOpacity,
              child: Image.file(
                file,
                key: imageKey,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => ColoredBox(color: surface),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Keeps the configured image mounted while another main tab covers it.
///
/// An [Image] with an active image-stream listener is not evicted from the
/// live image cache. Keeping this layer in the tree therefore avoids decoding
/// the schedule background again when the user returns after a long absence.
class ScheduleBackgroundLayer extends StatelessWidget {
  final ScheduleLayoutSettings settings;
  final bool visible;

  const ScheduleBackgroundLayer({
    super.key,
    required this.settings,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final hasImage = ScheduleBackground.hasImage(settings);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasImage)
          ScheduleBackground(settings: settings)
        else
          ColoredBox(color: surface),
        if (!visible && hasImage) ColoredBox(color: surface),
      ],
    );
  }
}
