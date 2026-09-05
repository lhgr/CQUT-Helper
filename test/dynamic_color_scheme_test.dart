import 'package:cqut_helper/theme/app_theme.dart';
import 'package:cqut_helper/theme/dynamic_color_scheme.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as material_ui;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DynamicColorPlugin.channel, null);
  });

  for (final brightness in Brightness.values) {
    test('conversion preserves system palette roles in $brightness', () {
      final source =
          material_ui.ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: brightness,
          ).copyWith(
            surfaceContainerLow: const Color(0xFF123456),
            primaryFixed: const Color(0xFF654321),
            outlineVariant: const Color(0xFF789ABC),
          );
      final harmonized = source.harmonized();
      final converted = harmonized.toFlutterColorScheme();

      expect(converted.brightness, brightness);
      expect(converted.primary, source.primary);
      expect(converted.secondary, source.secondary);
      expect(converted.tertiary, source.tertiary);
      expect(converted.surfaceContainerLow, const Color(0xFF123456));
      expect(converted.primaryFixed, const Color(0xFF654321));
      expect(converted.outlineVariant, const Color(0xFF789ABC));
      expect(converted.surfaceContainerHighest, source.surfaceContainerHighest);
      expect(converted.inverseSurface, source.inverseSurface);
      expect(converted.error, harmonized.error);
      expect(converted.onError, harmonized.onError);
      expect(converted.errorContainer, harmonized.errorContainer);
      expect(converted.onErrorContainer, harmonized.onErrorContainer);
      expect(converted.error, isNot(source.error));
    });

    testWidgets(
      'dynamic colors build a Flutter Material theme in $brightness',
      (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(DynamicColorPlugin.channel, (call) async {
              return call.method == DynamicColorPlugin.accentColorMethodName
                  ? Colors.teal.toARGB32()
                  : null;
            });

        await tester.pumpWidget(
          DynamicColorBuilder(
            builder: (light, dark) {
              final dynamicScheme = brightness == Brightness.light
                  ? light
                  : dark;
              final scheme =
                  dynamicScheme?.harmonized().toFlutterColorScheme() ??
                  ColorScheme.fromSeed(
                    seedColor: Colors.blue,
                    brightness: brightness,
                  );
              return MaterialApp(
                theme: brightness == Brightness.light
                    ? AppTheme.light(scheme)
                    : AppTheme.dark(scheme),
                home: const Scaffold(body: Text('Dynamic theme')),
              );
            },
          ),
        );
        await tester.pumpAndSettle();

        final theme = Theme.of(tester.element(find.text('Dynamic theme')));
        final expected = material_ui.ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ).harmonized();
        expect(theme.colorScheme.brightness, brightness);
        expect(theme.colorScheme.primary, expected.primary);
        expect(theme.colorScheme.error, expected.error);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
