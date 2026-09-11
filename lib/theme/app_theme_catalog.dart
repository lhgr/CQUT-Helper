import 'package:cqut_helper/theme/schedule_course_card_theme.dart';
import 'package:flutter/material.dart';

/// Makes both fully-built application themes available below [MaterialApp].
///
/// The schedule can therefore choose a local brightness without losing the
/// current dynamic or custom color palette.
class AppThemeCatalog extends InheritedWidget {
  final ThemeData lightTheme;
  final ThemeData darkTheme;

  const AppThemeCatalog({
    super.key,
    required this.lightTheme,
    required this.darkTheme,
    required super.child,
  });

  static AppThemeCatalog? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppThemeCatalog>();

  ThemeData themeFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkTheme : lightTheme;

  @override
  bool updateShouldNotify(AppThemeCatalog oldWidget) =>
      lightTheme != oldWidget.lightTheme || darkTheme != oldWidget.darkTheme;
}

/// Uses [interfaceTheme] for schedule chrome while keeping course-card colors
/// tied to the application's active light/dark theme.
ThemeData withAppScheduleCourseCardTheme({
  required ThemeData interfaceTheme,
  required ThemeData appTheme,
}) {
  final appCourseCardTheme =
      appTheme.extension<ScheduleCourseCardTheme>() ??
      (appTheme.brightness == Brightness.dark
          ? ScheduleCourseCardTheme.dark()
          : ScheduleCourseCardTheme.light());
  return interfaceTheme.copyWith(
    extensions: [
      ...interfaceTheme.extensions.values.where(
        (extension) => extension is! ScheduleCourseCardTheme,
      ),
      appCourseCardTheme,
    ],
  );
}
