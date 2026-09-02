import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:cqut_helper/widgets/app_select_field.dart';
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

  Future<void> _unlockWingColor() async {
    final themeManager = ThemeManager();
    final newlyUnlocked = await themeManager.unlockWingColor();
    await themeManager.setCustomColor(ThemeManager.wingColor);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newlyUnlocked ? 'Wing 已解锁 · #FF98A1' : 'Wing 已经解锁并应用'),
      ),
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
          final availableColors = [
            ..._colors,
            if (themeManager.wingColorUnlocked) ThemeManager.wingColor,
          ];
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
                child: RadioGroup<ThemeColorSource>(
                  groupValue: themeManager.colorSource,
                  onChanged: (source) {
                    if (source != null) themeManager.setColorSource(source);
                  },
                  child: Column(
                    children: [
                      const RadioListTile(
                        title: Text('系统自动取色'),
                        subtitle: Text('使用设备壁纸生成的动态配色'),
                        value: ThemeColorSource.system,
                        secondary: Icon(Icons.auto_awesome_outlined),
                      ),
                      RadioListTile(
                        title: const Text('课表背景取色'),
                        subtitle: Text(
                          themeManager.canUseScheduleBackgroundColor
                              ? '使用已从课表背景图片提取的颜色'
                              : '请先在课表设置中选择背景图片并完成取色',
                        ),
                        value: ThemeColorSource.scheduleBackground,
                        enabled: themeManager.canUseScheduleBackgroundColor,
                        secondary: _ColorDot(
                          color: themeManager.scheduleBackgroundColor,
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPress: _unlockWingColor,
                        child: RadioListTile(
                          title: const Text('手动选择颜色'),
                          subtitle: const Text('使用下方选择的固定主题颜色'),
                          value: ThemeColorSource.custom,
                          secondary: _ColorDot(color: themeManager.customColor),
                        ),
                      ),
                      if (themeManager.colorSource ==
                          ThemeColorSource.custom) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: availableColors.map((color) {
                              final selected =
                                  themeManager.customColor == color;
                              final isWing = color == ThemeManager.wingColor;
                              return Tooltip(
                                message: isWing ? 'Wing · #FF98A1' : '选择主题颜色',
                                child: Semantics(
                                  button: true,
                                  selected: selected,
                                  label: isWing ? 'Wing 主题颜色' : '选择主题颜色',
                                  child: InkWell(
                                    onTap: () =>
                                        themeManager.setCustomColor(color),
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
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('启动', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: AppSelectField<int>(
                    value: _defaultHomeTab,
                    labelText: '启动后的默认页面',
                    sheetTitle: '选择默认页面',
                    options: const [
                      AppSelectOption(
                        value: 0,
                        label: '今日',
                        icon: Icons.today_outlined,
                      ),
                      AppSelectOption(
                        value: 1,
                        label: '课表',
                        icon: Icons.calendar_month_outlined,
                      ),
                      AppSelectOption(
                        value: 2,
                        label: '我的',
                        icon: Icons.person_outline,
                      ),
                    ],
                    onChanged: _saveDefaultHomeTab,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('页面导航', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                child: SwitchListTile(
                  title: const Text('关闭预测性返回手势'),
                  subtitle: const Text('遇到返回动画异常时可关闭，关闭后使用普通页面返回动画'),
                  value: themeManager.predictiveBackDisabled,
                  onChanged: themeManager.setPredictiveBackDisabled,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color? color;

  const _ColorDot({this.color});

  @override
  Widget build(BuildContext context) {
    final value = color;
    if (value == null) return const Icon(Icons.colorize_outlined);
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: value,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}
