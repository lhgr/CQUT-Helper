import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:flutter/material.dart';

Future<void> showThemeSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => const ThemeSettingsSheet(),
  );
}

class ThemeSettingsSheet extends StatelessWidget {
  const ThemeSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeManager(),
      builder: (context, _) {
        final currentMode = ThemeManager().themeMode;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "主题设置",
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            RadioGroup<ThemeMode>(
              groupValue: currentMode,
              onChanged: (value) {
                if (value != null) {
                  final navigator = Navigator.of(context);
                  () async {
                    await ThemeManager().setThemeMode(value);
                    if (navigator.mounted) {
                      navigator.pop();
                    }
                  }();
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<ThemeMode>(
                    title: Text("跟随系统"),
                    value: ThemeMode.system,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text("亮色模式"),
                    value: ThemeMode.light,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text("深色模式"),
                    value: ThemeMode.dark,
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Divider(),
            SwitchListTile(
              title: Text("跟随系统主题色"),
              value: ThemeManager().isSystemColor,
              onChanged: (value) {
                ThemeManager().setSystemColor(value);
              },
            ),
            if (!ThemeManager().isSystemColor) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Colors.blue,
                    Colors.red,
                    Colors.green,
                    Colors.orange,
                    Colors.purple,
                    Colors.teal,
                    Colors.pink,
                    Colors.indigo,
                    Colors.brown,
                    Colors.cyan,
                    Colors.amber,
                    Colors.lime,
                  ].map((color) {
                    return GestureDetector(
                      onTap: () {
                        ThemeManager().setCustomColor(color);
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: ThemeManager().customColor == color
                              ? Border.all(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  width: 3,
                                )
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              SizedBox(height: 16),
            ],
            SizedBox(height: 16),
          ],
        );
      },
    );
  }
}
