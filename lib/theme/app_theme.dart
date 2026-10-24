import 'package:cqut_helper/theme/schedule_course_card_theme.dart';
import 'package:material_ui/material_ui.dart';

/// Centralized visual language for the app.
///
/// Keep page-specific layout in each feature, while common surfaces, controls
/// and feedback components stay consistent here.
abstract final class AppTheme {
  static const double cardRadius = 20;
  static const double controlRadius = 14;

  static ThemeData light(
    ColorScheme colorScheme, {
    bool strengthenSurfaceContrast = false,
    bool predictiveBackEnabled = true,
  }) {
    return _build(
      strengthenSurfaceContrast
          ? _withStrongerSurfaceContrast(colorScheme)
          : colorScheme,
      courseCardTheme: ScheduleCourseCardTheme.light(),
      strengthenedSurfaceContrast: strengthenSurfaceContrast,
      predictiveBackEnabled: predictiveBackEnabled,
    );
  }

  static ThemeData dark(
    ColorScheme colorScheme, {
    bool strengthenSurfaceContrast = false,
    bool predictiveBackEnabled = true,
  }) {
    return _build(
      strengthenSurfaceContrast
          ? _withStrongerSurfaceContrast(colorScheme)
          : colorScheme,
      courseCardTheme: ScheduleCourseCardTheme.dark(),
      strengthenedSurfaceContrast: strengthenSurfaceContrast,
      predictiveBackEnabled: predictiveBackEnabled,
    );
  }

  static ThemeData _build(
    ColorScheme colorScheme, {
    required ScheduleCourseCardTheme courseCardTheme,
    required bool strengthenedSurfaceContrast,
    required bool predictiveBackEnabled,
  }) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
    );
    final subtleBorder = colorScheme.outlineVariant.withAlpha(
      strengthenedSurfaceContrast ? (isDark ? 150 : 180) : (isDark ? 112 : 150),
    );
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(cardRadius),
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );

    return base.copyWith(
      pageTransitionsTheme: PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: predictiveBackEnabled
              ? const PredictiveBackPageTransitionsBuilder()
              : const ZoomPageTransitionsBuilder(),
        },
      ),
      scaffoldBackgroundColor: colorScheme.surface,
      canvasColor: colorScheme.surface,
      textTheme: _textTheme(base.textTheme, colorScheme),
      appBarTheme: AppBarThemeData(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleSpacing: 16,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        minTileHeight: 56,
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
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withAlpha(
          strengthenedSurfaceContrast
              ? (isDark ? 225 : 235)
              : (isDark ? 130 : 170),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        prefixIconColor: colorScheme.onSurfaceVariant,
        suffixIconColor: colorScheme.onSurfaceVariant,
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        border: _inputBorder(Colors.transparent, 0),
        enabledBorder: _inputBorder(Colors.transparent, 0),
        focusedBorder: _inputBorder(colorScheme.primary, 1.5),
        errorBorder: _inputBorder(colorScheme.error, 1),
        focusedErrorBorder: _inputBorder(colorScheme.error, 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              minimumSize: const Size(64, 48),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 0,
              textStyle: base.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ).copyWith(
              shape: _actionButtonShape,
              animationDuration: Durations.short3,
            ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style:
            ElevatedButton.styleFrom(
              minimumSize: const Size(64, 48),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 0,
              textStyle: base.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ).copyWith(
              shape: _actionButtonShape,
              animationDuration: Durations.short3,
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              minimumSize: const Size(64, 48),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              textStyle: base.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ).copyWith(
              shape: _actionButtonShape,
              animationDuration: Durations.short3,
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style:
            TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: base.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ).copyWith(
              shape: _actionButtonShape,
              animationDuration: Durations.short3,
            ),
      ),
      iconButtonTheme: IconButtonThemeData(
        // material_ui exposes Expressive as a component variant, not as a
        // ThemeData factory. Keep its native selected/pressed shape tokens.
        variant: StyleVariant.material3Expressive,
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          sizeVariant: ButtonSizeVariant.small,
          shapeVariant: ButtonShapeVariant.round,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(48, 48),
          selectedBackgroundColor: colorScheme.secondaryContainer,
          selectedForegroundColor: colorScheme.onSecondaryContainer,
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
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
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        modalElevation: 0,
        backgroundColor: colorScheme.surfaceContainerLow,
        modalBackgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
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
        selectedColor: colorScheme.secondaryContainer,
        checkmarkColor: colorScheme.onSecondaryContainer,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: subtleBorder,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        // The package still requires this opt-in for its gapped 2024 design.
        // ignore: deprecated_member_use
        year2023: false,
        color: colorScheme.primary,
        linearMinHeight: 6,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: colorScheme.surfaceContainerHighest,
      ),
      sliderTheme: SliderThemeData(
        // Preserve the native handle, track gap, and pressed handle motion.
        // ignore: deprecated_member_use
        year2023: false,
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.secondaryContainer,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primary.withValues(
          alpha: isDark ? .32 : .20,
        ),
        selectionHandleColor: colorScheme.primary,
      ),
      extensions: <ThemeExtension<dynamic>>[courseCardTheme],
    );
  }

  // Material animates this shape through its existing ShapeBorderTween. A
  // rounded resting button tightens while held, matching Expressive feedback
  // without adding a second animation/controller around every action.
  static final WidgetStateProperty<OutlinedBorder> _actionButtonShape =
      WidgetStateProperty.resolveWith((states) {
        return RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            states.contains(WidgetState.pressed) ? 12 : controlRadius,
          ),
        );
      });

  static TextTheme _textTheme(TextTheme base, ColorScheme colorScheme) {
    return base.copyWith(
      headlineLarge: base.headlineLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleLarge: base.titleLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
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
