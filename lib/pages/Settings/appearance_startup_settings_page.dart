import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:flutter/material.dart';

class AppearanceStartupSettingsPage extends StatefulWidget {
  const AppearanceStartupSettingsPage({super.key});

  @override
  State<AppearanceStartupSettingsPage> createState() =>
      _AppearanceStartupSettingsPageState();
}

class _AppearanceStartupSettingsPageState
    extends State<AppearanceStartupSettingsPage> {
  final ScheduleSettingsManager _settingsManager = ScheduleSettingsManager();
  bool _loading = true;
  int _defaultHomeTab = 1;

  static const List<Color> _colors = [
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
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _settingsManager.load();
    if (!mounted) return;
    setState(() {
      _defaultHomeTab = _settingsManager.defaultHomeTab;
      _loading = false;
    });
  }

  Future<void> _saveDefaultHomeTab(int value) async {
    setState(() => _defaultHomeTab = value);
    await _settingsManager.saveExperienceSettings(
      remindersEnabled: _settingsManager.remindersEnabled,
      defaultReminderMinutes: _settingsManager.defaultReminderMinutes,
      displayDensity: _settingsManager.displayDensity,
      defaultHomeTab: value,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('外观与启动')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('外观与启动')),
      body: ListenableBuilder(
        listenable: ThemeManager(),
        builder: (context, _) {
          final themeManager = ThemeManager();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text('主题模式', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                child: RadioGroup<ThemeMode>(
                  groupValue: themeManager.themeMode,
                  onChanged: (value) {
                    if (value != null) themeManager.setThemeMode(value);
                  },
                  child: const Column(
                    children: [
                      RadioListTile(
                        title: Text('跟随系统'),
                        value: ThemeMode.system,
                      ),
                      RadioListTile(
                        title: Text('亮色模式'),
                        value: ThemeMode.light,
                      ),
                      RadioListTile(title: Text('深色模式'), value: ThemeMode.dark),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('主题颜色', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('跟随系统主题色'),
                      subtitle: const Text('使用设备的动态配色'),
                      value: themeManager.isSystemColor,
                      onChanged: themeManager.setSystemColor,
                    ),
                    if (!themeManager.isSystemColor) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _colors.map((color) {
                            final selected = themeManager.customColor == color;
                            return Semantics(
                              button: true,
                              selected: selected,
                              label: '选择主题颜色',
                              child: InkWell(
                                onTap: () => themeManager.setCustomColor(color),
                                customBorder: const CircleBorder(),
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: selected
                                        ? Border.all(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                            width: 3,
                                          )
                                        : null,
                                  ),
                                  child: selected
                                      ? const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('启动', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: DropdownButtonFormField<int>(
                    initialValue: _defaultHomeTab,
                    decoration: const InputDecoration(labelText: '启动后的默认页面'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('今日')),
                      DropdownMenuItem(value: 1, child: Text('课表')),
                      DropdownMenuItem(value: 2, child: Text('我的')),
                    ],
                    onChanged: (value) {
                      if (value != null) _saveDefaultHomeTab(value);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
