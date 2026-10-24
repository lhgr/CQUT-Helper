import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showThemeSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
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
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("主题设置", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '选择应用外观和主题颜色',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
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
                      title: const Text("跟随系统"),
                      value: ThemeMode.system,
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text("亮色模式"),
                      value: ThemeMode.light,
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text("深色模式"),
                      value: ThemeMode.dark,
                    ),
                  ],
                ),
              ),
              const Divider(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("跟随系统主题色"),
                value: ThemeManager().isSystemColor,
                onChanged: ThemeManager().setSystemColor,
              ),
              if (!ThemeManager().isSystemColor) ...[
                const SizedBox(height: 8),
                Text('主题颜色', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children:
                      [
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
                          behavior: HitTestBehavior.opaque,
                          onTap: () => ThemeManager().setCustomColor(color),
                          child: SizedBox.square(
                            dimension: 48,
                            child: Center(
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: ThemeManager().customColor == color
                                      ? Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                          width: 3,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        );
      },
    );
  }
}
