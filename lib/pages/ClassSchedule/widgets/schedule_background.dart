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

  static Future<void> precacheFile(BuildContext context, String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final provider = FileImage(file);
    await provider.evict();
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
