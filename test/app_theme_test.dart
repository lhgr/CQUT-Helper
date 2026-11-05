import 'dart:math' as math;

import 'package:cqut_helper/theme/app_theme.dart';
import 'package:cqut_helper/theme/app_theme_catalog.dart';
import 'package:cqut_helper/theme/schedule_course_card_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('深色课程卡片使用低亮背景并保持文字可读', () {
    final theme = ScheduleCourseCardTheme.dark();

    for (var index = 0; index < theme.backgrounds.length; index++) {
      final background = theme.backgroundAt(index);
      expect(background.computeLuminance(), lessThan(0.12));
      expect(
        _contrastRatio(background, theme.titleAt(index)),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(background, theme.descriptionAt(index)),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  for (final brightness in Brightness.values) {
    test('${brightness.name} 主题在增强表面和选择状态保持文字可读', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: brightness,
      );
      final theme = brightness == Brightness.light
          ? AppTheme.light(scheme, strengthenSurfaceContrast: true)
          : AppTheme.dark(scheme, strengthenSurfaceContrast: true);
      final colors = theme.colorScheme;

      for (final surface in <Color>[
        colors.surface,
        theme.cardTheme.color!,
        theme.dialogTheme.backgroundColor!,
        Color.alphaBlend(theme.inputDecorationTheme.fillColor!, colors.surface),
      ]) {
        expect(
          _contrastRatio(surface, colors.onSurface),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(
        _contrastRatio(colors.secondaryContainer, colors.onSecondaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(theme.textTheme.bodyMedium!.height, greaterThanOrEqualTo(1.4));
    });
  }

  test('可关闭 Android 预测性返回转场', () {
    final theme = AppTheme.light(
      ColorScheme.fromSeed(seedColor: Colors.blue),
      predictiveBackEnabled: false,
    );

    expect(
      theme.pageTransitionsTheme.builders[TargetPlatform.android],
      isA<ZoomPageTransitionsBuilder>(),
    );
  });

  test('课表局部深色界面不改变应用浅色课程卡片', () {
    final appTheme = AppTheme.light(
      ColorScheme.fromSeed(seedColor: Colors.blue),
    );
    final interfaceTheme = AppTheme.dark(
      ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
    );

    final composed = withAppScheduleCourseCardTheme(
      interfaceTheme: interfaceTheme,
      appTheme: appTheme,
    );

    expect(composed.brightness, Brightness.dark);
    expect(
      composed.extension<ScheduleCourseCardTheme>()!.backgrounds,
      appTheme.extension<ScheduleCourseCardTheme>()!.backgrounds,
    );
  });

  test('动态取色仅增强中性表面层级并保留系统强调色', () {
    final original = ColorScheme.fromSeed(seedColor: Colors.teal);
    final flat = original.copyWith(
      surfaceContainerLow: original.surface,
      surfaceContainer: original.surface,
      surfaceContainerHigh: original.surface,
      surfaceContainerHighest: original.surface,
    );
    final normal = AppTheme.light(flat);
    final strengthened = AppTheme.light(flat, strengthenSurfaceContrast: true);

    expect(strengthened.colorScheme.primary, flat.primary);
    expect(strengthened.colorScheme.secondary, flat.secondary);
    expect(strengthened.colorScheme.surface, flat.surface);
    expect(
      _contrastRatio(
        strengthened.scaffoldBackgroundColor,
        strengthened.cardTheme.color!,
      ),
      greaterThan(
        _contrastRatio(normal.scaffoldBackgroundColor, normal.cardTheme.color!),
      ),
    );
    expect(
      strengthened.inputDecorationTheme.fillColor!.a,
      greaterThan(normal.inputDecorationTheme.fillColor!.a),
    );
  });
}

double _contrastRatio(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = math.max(first, second);
  final darker = math.min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}
