import 'dart:math' as math;

import 'package:cqut_helper/theme/app_theme.dart';
import 'package:cqut_helper/theme/app_theme_catalog.dart';
import 'package:cqut_helper/theme/schedule_course_card_theme.dart';
import 'package:material_ui/material_ui.dart';
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
    expect(theme.iconButtonTheme.variant, StyleVariant.material3Expressive);
    expect(cardShape.borderRadius, BorderRadius.circular(AppTheme.cardRadius));
    expect(theme.navigationBarTheme.height, 72);
    expect(theme.dialogTheme.shape, isA<RoundedRectangleBorder>());
    expect(theme.extension<ScheduleCourseCardTheme>(), isNotNull);
    expect(
      theme.pageTransitionsTheme.builders[TargetPlatform.android],
      isA<PredictiveBackPageTransitionsBuilder>(),
    );
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

  testWidgets('原生 Expressive 图标按钮按下时改变形状并保留点击', (tester) async {
    const key = ValueKey('expressive-icon');
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(ColorScheme.fromSeed(seedColor: Colors.blue)),
        home: Scaffold(
          body: Center(
            child: IconButton.filled(
              key: key,
              onPressed: () => taps++,
              icon: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    );

    final button = find.byKey(key);
    expect(tester.getSize(button).shortestSide, greaterThanOrEqualTo(48));
    final resting = _paintedButtonShape(tester, button);
    expect(resting, isA<StadiumBorder>());
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final pressed = _paintedButtonShape(tester, button);
    expect(pressed, isNot(resting));
    // Inspect the painted outline as well as the target style: interpolating
    // a stadium and a rounded rectangle can use an internal border class.
    const bounds = Rect.fromLTWH(0, 0, 48, 48);
    const nearCorner = Offset(4, 4);
    expect(resting.getOuterPath(bounds).contains(nearCorner), isFalse);
    expect(pressed.getOuterPath(bounds).contains(nearCorner), isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(
      _paintedButtonShape(
        tester,
        button,
      ).getOuterPath(bounds).contains(nearCorner),
      isFalse,
    );
  });

  testWidgets('主要操作按钮的按下形状由原生 Material 连续插值', (tester) async {
    const key = ValueKey('primary-action');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(ColorScheme.fromSeed(seedColor: Colors.blue)),
        home: Scaffold(
          body: Center(
            child: FilledButton(
              key: key,
              onPressed: () {},
              child: const Text('查看课表'),
            ),
          ),
        ),
      ),
    );

    final button = find.byKey(key);
    final resting = _roundedButtonRadius(tester, button);
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final duringPress = _roundedButtonRadius(tester, button);
    await tester.pump(const Duration(milliseconds: 150));
    final held = _roundedButtonRadius(tester, button);
    expect(duringPress, lessThan(resting));
    expect(duringPress, greaterThan(held));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_roundedButtonRadius(tester, button), resting);
  });

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

ShapeBorder _paintedButtonShape(WidgetTester tester, Finder button) {
  final physicalShape = tester.widget<PhysicalShape>(
    find.descendant(of: button, matching: find.byType(PhysicalShape)).first,
  );
  return (physicalShape.clipper as ShapeBorderClipper).shape;
}

double _roundedButtonRadius(WidgetTester tester, Finder button) {
  final shape = _paintedButtonShape(tester, button) as RoundedRectangleBorder;
  return shape.borderRadius.resolve(TextDirection.ltr).topLeft.x;
}

double _contrastRatio(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = math.max(first, second);
  final darker = math.min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}
