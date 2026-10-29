import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:cqut_helper/pages/Mine/ClearCache.dart';
import 'package:material_ui/material_ui.dart';

import 'about_settings_page.dart';
import 'appearance_startup_settings_page.dart';
import 'notification_settings_page.dart';
import 'schedule_courses_settings_page.dart';
import 'backup_restore_page.dart';
import 'sync_diagnostics_page.dart';
import 'settings_schedule_scope.dart';
import 'settings_section_tile.dart';

enum AppSettingsSection {
  schedule,
  notifications,
  appearance,
  diagnostics,
  backup,
  storage,
  about,
}

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
    AppSettingsSection.diagnostics => const SyncDiagnosticsPage(),
    AppSettingsSection.backup => const BackupRestorePage(),
    AppSettingsSection.storage => const ClearCachePage(),
    AppSettingsSection.about => const AboutSettingsPage(),
    null => AppSettingsPage(initialScope: scope),
  };
  await Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => page));
}

class AppSettingsPage extends StatefulWidget {
  final SettingsScheduleScope? initialScope;

  const AppSettingsPage({super.key, this.initialScope});

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  SettingsScheduleScope? _scope;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scope = widget.initialScope ?? await SettingsScheduleScope.resolve();
    if (!mounted) return;
    setState(() {
      _scope = scope;
      _loading = false;
    });
  }

  String get _scheduleSummary {
    return '显示方式与课程卡片';
  }

  String get _notificationSummary {
    return '课前提醒与调课通知增强';
  }

  String get _appearanceSummary {
    return '主题、配色与启动页面';
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _SettingsGroup(
                    title: '使用偏好',
                    children: [
                      SettingsSectionTile(
                        icon: Icons.calendar_month_outlined,
                        title: '课表与课程',
                        subtitle: _scheduleSummary,
                        onTap: () => _openSection(AppSettingsSection.schedule),
                      ),
                      const Divider(height: 1, indent: 56),
                      SettingsSectionTile(
                        icon: Icons.notifications_outlined,
                        title: '通知与提醒',
                        subtitle: _notificationSummary,
                        onTap: () =>
                            _openSection(AppSettingsSection.notifications),
                      ),
                      const Divider(height: 1, indent: 56),
                      SettingsSectionTile(
                        icon: Icons.palette_outlined,
                        title: '外观与启动',
                        subtitle: _appearanceSummary,
                        onTap: () =>
                            _openSection(AppSettingsSection.appearance),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SettingsGroup(
                    title: '数据与维护',
                    children: [
                      SettingsSectionTile(
                        icon: Icons.settings_backup_restore,
                        title: '备份与恢复',
                        subtitle: '保存或恢复课程偏好与应用设置',
                        onTap: () => _openSection(AppSettingsSection.backup),
                      ),
                      const Divider(height: 1, indent: 56),
                      SettingsSectionTile(
                        icon: Icons.health_and_safety_outlined,
                        title: '同步与修复',
                        subtitle: '查看同步状态，处理课表和提醒问题',
                        onTap: () =>
                            _openSection(AppSettingsSection.diagnostics),
                      ),
                      const Divider(height: 1, indent: 56),
                      SettingsSectionTile(
                        icon: Icons.storage_outlined,
                        title: '存储与日志',
                        subtitle: '管理缓存并导出问题日志',
                        onTap: () => _openSection(AppSettingsSection.storage),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SettingsGroup(
                    title: null,
                    children: [
                      SettingsSectionTile(
                        icon: Icons.info_outline,
                        title: '关于应用',
                        subtitle: '版本与项目信息',
                        onTap: () => _openSection(AppSettingsSection.about),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title!, style: Theme.of(context).textTheme.titleSmall),
          ),
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ],
    );
  }
}
