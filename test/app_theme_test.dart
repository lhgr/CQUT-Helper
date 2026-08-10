import 'dart:math' as math;

import 'package:cqut_helper/theme/app_theme.dart';
import 'package:cqut_helper/theme/schedule_course_card_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('亮色课程卡片保留原有配色', () {
    final theme = ScheduleCourseCardTheme.light();

    expect(theme.backgrounds, const <Color>[
      Color(0xFFE6F4FF),
      Color(0xFFFDEBDD),
      Color(0xFFDEFBF7),
      Color(0xFFEEEDFF),
      Color(0xFFFCEBCD),
      Color(0xFFFFEFF0),
      Color(0xFFFFEEF8),
      Color(0xFFE2F9F3),
      Color(0xFFFFF9C9),
      Color(0xFFFAEDFF),
      Color(0xFFF4F2FD),
      Color(0xFFE6E6FF),
      Color(0xFFEEFDDD),
      Color(0xFFEADEFB),
      Color(0xFFFFEFED),
      Color(0xFFCDF2FC),
      Color(0xFFEFFFFF),
      Color(0xFFEEFFFF),
      Color(0xFFF9F5E2),
      Color(0xFFEDF0FF),
      Color(0xFFF2F4FD),
    ]);
  });

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

  test('应用主题包含统一组件样式和课程卡片扩展', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    final theme = AppTheme.light(scheme);
    final cardShape = theme.cardTheme.shape! as RoundedRectangleBorder;

    expect(theme.useMaterial3, isTrue);
    expect(cardShape.borderRadius, BorderRadius.circular(AppTheme.cardRadius));
    expect(theme.navigationBarTheme.height, 72);
    expect(theme.dialogTheme.shape, isA<RoundedRectangleBorder>());
    expect(theme.extension<ScheduleCourseCardTheme>(), isNotNull);
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
