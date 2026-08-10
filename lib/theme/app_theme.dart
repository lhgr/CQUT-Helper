import 'package:cqut_helper/theme/schedule_course_card_theme.dart';
import 'package:flutter/material.dart';

/// Centralized visual language for the app.
///
/// Keep page-specific layout in each feature, while common surfaces, controls
/// and feedback components stay consistent here.
abstract final class AppTheme {
  static const double cardRadius = 20;
  static const double controlRadius = 16;

  static ThemeData light(
    ColorScheme colorScheme, {
    bool strengthenSurfaceContrast = false,
  }) {
    return _build(
      strengthenSurfaceContrast
          ? _withStrongerSurfaceContrast(colorScheme)
          : colorScheme,
      courseCardTheme: ScheduleCourseCardTheme.light(),
      strengthenedSurfaceContrast: strengthenSurfaceContrast,
    );
  }

  static ThemeData dark(
    ColorScheme colorScheme, {
    bool strengthenSurfaceContrast = false,
  }) {
    return _build(
      strengthenSurfaceContrast
          ? _withStrongerSurfaceContrast(colorScheme)
          : colorScheme,
      courseCardTheme: ScheduleCourseCardTheme.dark(),
      strengthenedSurfaceContrast: strengthenSurfaceContrast,
    );
  }

  static ThemeData _build(
    ColorScheme colorScheme, {
    required ScheduleCourseCardTheme courseCardTheme,
    required bool strengthenedSurfaceContrast,
  }) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
    );
    final subtleBorder = colorScheme.outlineVariant.withAlpha(
      strengthenedSurfaceContrast ? (isDark ? 150 : 180) : (isDark ? 112 : 150),
    );
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(cardRadius),
      side: BorderSide(color: subtleBorder),
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );

    return base.copyWith(
      scaffoldBackgroundColor: colorScheme.surface,
      canvasColor: colorScheme.surface,
      textTheme: _textTheme(base.textTheme, colorScheme),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleSpacing: 20,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        minTileHeight: 64,
        shape: controlShape,
        titleTextStyle: base.textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          height: 1.35,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withAlpha(
          strengthenedSurfaceContrast
              ? (isDark ? 225 : 235)
              : (isDark ? 130 : 170),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        prefixIconColor: colorScheme.onSurfaceVariant,
        suffixIconColor: colorScheme.onSurfaceVariant,
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.outline),
        border: _inputBorder(Colors.transparent, 0),
        enabledBorder: _inputBorder(Colors.transparent, 0),
        focusedBorder: _inputBorder(colorScheme.primary, 1.5),
        errorBorder: _inputBorder(colorScheme.error, 1),
        focusedErrorBorder: _inputBorder(colorScheme.error, 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          elevation: 0,
          shape: controlShape,
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          elevation: 0,
          shape: controlShape,
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          side: BorderSide(color: subtleBorder),
          shape: controlShape,
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: selected ? 24 : 23,
            color: selected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return base.textTheme.labelMedium?.copyWith(
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 1,
        focusElevation: 1,
        hoverElevation: 2,
        highlightElevation: 1,
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogThemeData(
        elevation: 3,
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 2,
        modalElevation: 3,
        backgroundColor: colorScheme.surfaceContainerLow,
        modalBackgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 2,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        actionTextColor: colorScheme.inversePrimary,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: base.chipTheme.copyWith(
        elevation: 0,
        pressElevation: 0,
        backgroundColor: colorScheme.surfaceContainerHigh,
        side: BorderSide(color: subtleBorder),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        shape: const StadiumBorder(),
      ),
      dividerTheme: DividerThemeData(
        color: subtleBorder,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: colorScheme.surfaceContainerHighest,
      ),
      extensions: <ThemeExtension<dynamic>>[courseCardTheme],
    );
  }

  static TextTheme _textTheme(TextTheme base, ColorScheme colorScheme) {
    return base.copyWith(
      headlineLarge: base.headlineLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.45,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
      titleLarge: base.titleLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: base.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.4),
      bodySmall: base.bodySmall?.copyWith(height: 1.35),
    );
  }

  static ColorScheme _withStrongerSurfaceContrast(ColorScheme colorScheme) {
    Color deepen(Color color, double amount) =>
        Color.lerp(color, colorScheme.onSurface, amount)!;

    return colorScheme.copyWith(
      surfaceContainerLow: deepen(colorScheme.surfaceContainerLow, 0.035),
      surfaceContainer: deepen(colorScheme.surfaceContainer, 0.05),
      surfaceContainerHigh: deepen(colorScheme.surfaceContainerHigh, 0.065),
      surfaceContainerHighest: deepen(
        colorScheme.surfaceContainerHighest,
        0.09,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(controlRadius),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
