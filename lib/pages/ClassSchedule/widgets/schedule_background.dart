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

  @override
  Widget build(BuildContext context) {
    final file = imageFile(settings);
    final surface = Theme.of(context).colorScheme.surface;
    if (file == null) return ColoredBox(color: surface);

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
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(color: surface),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
