import 'package:flutter/material.dart';

/// Resolves timetable grid lines from the active Material color scheme.
///
/// Using [ColorScheme.outlineVariant] keeps the lines in sync with system
/// dynamic color, a custom theme color, and light/dark mode changes.
Color scheduleGridLineColor(BuildContext context, double opacity) {
  final alpha = (opacity.clamp(0.0, 1.0) * 255).round();
  return Theme.of(context).colorScheme.outlineVariant.withAlpha(alpha);
}
