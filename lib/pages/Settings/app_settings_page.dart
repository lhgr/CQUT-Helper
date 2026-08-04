import 'dart:async';

import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:cqut_helper/pages/Mine/ClearCache.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'about_settings_page.dart';
import 'appearance_startup_settings_page.dart';
import 'notification_settings_page.dart';
import 'schedule_courses_settings_page.dart';
import 'settings_schedule_scope.dart';
import 'settings_section_tile.dart';

enum AppSettingsSection { schedule, notifications, appearance, storage, about }

Future<void> openAppSettings(
  BuildContext context, {
  AppSettingsSection? section,
  String? userId,
  String? yearTerm,
}) async {
  final scope = await SettingsScheduleScope.resolve(
    userId: userId,
    yearTerm: yearTerm,
  );
  if (!context.mounted) return;
  final Widget page = switch (section) {
    AppSettingsSection.schedule => ScheduleCoursesSettingsPage(scope: scope),
    AppSettingsSection.notifications => NotificationSettingsPage(scope: scope),
    AppSettingsSection.appearance => const AppearanceStartupSettingsPage(),
    AppSettingsSection.storage => const ClearCachePage(),
    AppSettingsSection.about => const AboutSettingsPage(),
    null => AppSettingsPage(initialScope: scope),
  };
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => page));
}

class AppSettingsPage extends StatefulWidget {
  final SettingsScheduleScope? initialScope;

  const AppSettingsPage({super.key, this.initialScope});

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  final ScheduleSettingsManager _manager = ScheduleSettingsManager();
  SettingsScheduleScope? _scope;
  String _version = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _manager.load();
    final scope = widget.initialScope ?? await SettingsScheduleScope.resolve();
    if (!mounted) return;
    setState(() {
      _scope = scope;
      _loading = false;
    });
    unawaited(_loadVersion());
  }

  Future<void> _loadVersion() async {
    String version = '';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      // 部分测试和不支持的平台没有 package_info 通道。
    }
    if (!mounted) return;
    setState(() => _version = version);
  }

  String get _scheduleSummary {
    final weekend = _manager.showWeekend ? '显示周末' : '仅工作日';
    final density = switch (_manager.displayDensity) {
      ScheduleDisplayDensity.compact => '紧凑',
      ScheduleDisplayDensity.comfortable => '标准',
      ScheduleDisplayDensity.spacious => '宽松',
    };
    return '$weekend · $density密度 · 课程显示';
  }

  String get _notificationSummary {
    final reminders = _manager.remindersEnabled ? '课前提醒已开启' : '课前提醒已关闭';
    final polling = _manager.backgroundPollingEnabled ? '调课通知已开启' : '调课通知已关闭';
    return '$reminders · $polling';
  }

  String get _appearanceSummary {
    final mode = switch (ThemeManager().themeMode) {
      ThemeMode.system => '跟随系统',
      ThemeMode.light => '亮色模式',
      ThemeMode.dark => '深色模式',
    };
    const tabs = ['今日', '课表', '我的'];
    return '$mode · 默认打开${tabs[_manager.defaultHomeTab]}';
  }

  Future<void> _openSection(AppSettingsSection section) async {
    final scope = _scope;
    if (scope == null) return;
    await openAppSettings(
      context,
      section: section,
      userId: scope.userId,
      yearTerm: scope.yearTerm,
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: ThemeManager(),
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  SettingsSectionTile(
                    icon: Icons.calendar_month_outlined,
                    title: '课表与课程',
                    subtitle: _scheduleSummary,
                    onTap: () => _openSection(AppSettingsSection.schedule),
                  ),
                  SettingsSectionTile(
                    icon: Icons.notifications_outlined,
                    title: '通知与提醒',
                    subtitle: _notificationSummary,
                    onTap: () => _openSection(AppSettingsSection.notifications),
                  ),
                  SettingsSectionTile(
                    icon: Icons.palette_outlined,
                    title: '外观与启动',
                    subtitle: _appearanceSummary,
                    onTap: () => _openSection(AppSettingsSection.appearance),
                  ),
                  SettingsSectionTile(
                    icon: Icons.storage_outlined,
                    title: '存储与诊断',
                    subtitle: '缓存占用、清理与日志导出',
                    onTap: () => _openSection(AppSettingsSection.storage),
                  ),
                  SettingsSectionTile(
                    icon: Icons.info_outline,
                    title: '关于应用',
                    subtitle: _version.isEmpty
                        ? '版本、更新与开源信息'
                        : '版本 $_version · 更新与开源信息',
                    onTap: () => _openSection(AppSettingsSection.about),
                  ),
                ],
              ),
            ),
    );
  }
}
