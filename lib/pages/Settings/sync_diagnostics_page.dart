import 'package:cqut_helper/manager/schedule_refresh_state.dart';
import 'package:cqut_helper/pages/Login/Login.dart';
import 'package:cqut_helper/pages/Mine/ClearCache.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:material_ui/material_ui.dart';

import 'notification_settings_page.dart';
import 'settings_schedule_scope.dart';
import 'sync_diagnostics_service.dart';

class SyncDiagnosticsPage extends StatefulWidget {
  final Future<String?> Function()? readEncryptedPassword;
  final SyncDiagnosticsService? service;

  const SyncDiagnosticsPage({
    super.key,
    this.readEncryptedPassword,
    this.service,
  });

  @override
  State<SyncDiagnosticsPage> createState() => _SyncDiagnosticsPageState();
}

class _SyncDiagnosticsPageState extends State<SyncDiagnosticsPage>
    with WidgetsBindingObserver {
  late final SyncDiagnosticsService _service;
  SyncDiagnosticsSnapshot? _snapshot;
  SyncActionResult? _result;
  WidgetUpdateResult? _widgetResult;
  bool _reading = false;
  bool _working = false;
  int _readGeneration = 0;

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ??
        SyncDiagnosticsService(
          readEncryptedPassword: widget.readEncryptedPassword,
        );
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _readGeneration++;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_working) _load();
  }

  Future<void> _load() async {
    final generation = ++_readGeneration;
    setState(() => _reading = true);
    try {
      final snapshot = await _service.load();
      if (!mounted || generation != _readGeneration) return;
      setState(() => _snapshot = snapshot);
    } catch (error, stack) {
      _service.logFailure('load diagnostics failed', error, stack);
      if (!mounted || generation != _readGeneration) return;
      setState(
        () => _snapshot = const SyncDiagnosticsSnapshot(
          failures: {DiagnosticRead.settings},
        ),
      );
    } finally {
      if (mounted && generation == _readGeneration) {
        setState(() => _reading = false);
      }
    }
  }

  void _showResult(SyncActionResult result) {
    if (!mounted) return;
    setState(() {
      _result = result;
      if (result.widgetResult != null) _widgetResult = result.widgetResult;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.title)));
  }

  Future<void> _run(Future<SyncActionResult> Function() action) async {
    if (_working || _reading) return;
    setState(() => _working = true);
    ++_readGeneration;
    try {
      _showResult(await action());
    } catch (error, stack) {
      _service.logFailure('diagnostic action failed', error, stack);
      _showResult(
        const SyncActionResult(details: ['操作暂时未能完成，请稍后重试'], hasFailure: true),
      );
    } finally {
      if (mounted) {
        await _load();
        if (mounted) setState(() => _working = false);
      }
    }
  }

  Future<void> _login() async {
    if (_working || _reading) return;
    setState(() => _working = true);
    try {
      await requestReauthentication(context);
    } finally {
      if (mounted) {
        await _load();
        if (mounted) setState(() => _working = false);
      }
    }
  }

  Future<void> _openNotifications() async {
    if (_working || _reading) return;
    setState(() => _working = true);
    try {
      final scope = await SettingsScheduleScope.resolve();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NotificationSettingsPage(scope: scope),
        ),
      );
    } finally {
      if (mounted) {
        await _load();
        if (mounted) setState(() => _working = false);
      }
    }
  }

  Future<void> _openLogs() async {
    if (_working || _reading) return;
    setState(() => _working = true);
    try {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ClearCachePage()));
    } finally {
      if (mounted) {
        await _load();
        if (mounted) setState(() => _working = false);
      }
    }
  }

  Future<void> _systemSettings(Future<bool> Function() action) => _run(
    () async {
      final opened = await action();
      return SyncActionResult(
        details: [opened ? '已打开系统设置，返回后会重新检查' : '暂时无法打开该设置，请在系统设置中找到本应用后手动检查'],
        hasFailure: !opened,
      );
    },
  );

  bool get _busy => _working || _reading;
  String _problemSummary(SyncDiagnosticsSnapshot data) {
    final conditions = [
      data.accountCondition,
      data.reminderCondition,
      if (data.enhancementEnabled) data.backgroundCondition,
    ];
    final problems = <String>[
      if (data.accountCondition == DiagnosticCondition.problem) '登录',
      if (data.reminderCondition == DiagnosticCondition.problem) '课前提醒',
      if (data.enhancementEnabled &&
          data.backgroundCondition == DiagnosticCondition.problem)
        '调课通知增强',
      if (data.refresh?.widgetState == ScheduleWidgetRefreshState.failed &&
          !data.credentialInvalid)
        '课表同步',
      if (_widgetResult == WidgetUpdateResult.failed) '桌面组件',
    ];
    if (problems.isNotEmpty) return '需处理问题：${problems.join('、')}';
    return data.failures.isNotEmpty
        ? '部分信息暂时无法获取，可重新检测'
        : conditions.contains(DiagnosticCondition.pending)
        ? '部分状态待确认，可查看详情或立即同步'
        : '暂未发现需要处理的问题';
  }

  String _time(DateTime? value) {
    if (value == null) return '暂无记录';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.month}/${value.day} ${two(value.hour)}:${two(value.minute)}';
  }

  String _label(DiagnosticCondition condition) => switch (condition) {
    DiagnosticCondition.normal => '正常',
    DiagnosticCondition.off => '未开启',
    DiagnosticCondition.pending => '待确认',
    DiagnosticCondition.problem => '异常',
  };

  Widget _status({
    required IconData icon,
    required String title,
    required String detail,
    required DiagnosticCondition condition,
    String? action,
    VoidCallback? onAction,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = condition == DiagnosticCondition.problem
        ? scheme.error
        : condition == DiagnosticCondition.normal
        ? scheme.primary
        : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 12),
            child: Icon(icon, color: color),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      _label(condition),
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: color),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(detail, style: Theme.of(context).textTheme.bodyMedium),
                if (action != null)
                  TextButton(
                    onPressed: _busy ? null : onAction,
                    child: Text(action),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) => Card(
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );

  Widget _accountStatus(SyncDiagnosticsSnapshot data) {
    final unreadable =
        data.account == null ||
        data.failures.contains(DiagnosticRead.credential);
    final detail = data.account == null
        ? '账号暂时无法获取，请重试'
        : data.account!.isEmpty
        ? '登录后可同步课表与更新提醒'
        : unreadable
        ? '登录信息暂时无法获取，可重试或重新登录'
        : data.credentialInvalid
        ? '最近同步发现登录信息已失效，请重新登录'
        : data.hasCredential == false
        ? '本机缺少登录信息，请重新登录'
        : '本机已保存登录信息，是否可用会在同步时检查';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _status(
          icon: Icons.person_outline,
          title: '登录状态',
          detail: detail,
          condition: data.accountCondition,
          action: unreadable
              ? '重试'
              : data.needsLogin
              ? '重新登录'
              : null,
          onAction: unreadable ? _load : _login,
        ),
        if (unreadable)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 52, bottom: 8),
              child: TextButton(
                onPressed: _busy ? null : _login,
                child: const Text('重新登录'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _scheduleStatus(SyncDiagnosticsSnapshot data) {
    final failedRead = data.failures.contains(DiagnosticRead.refresh);
    final failed =
        data.refresh?.widgetState == ScheduleWidgetRefreshState.failed;
    return _status(
      icon: Icons.cloud_sync_outlined,
      title: '最近同步',
      detail: failedRead
          ? '暂时无法获取'
          : '${_time(data.refresh?.lastSuccessfulRefreshAt)}${failed ? ' · 最近一次课表同步未完成' : ''}',
      condition: failedRead
          ? DiagnosticCondition.pending
          : failed
          ? DiagnosticCondition.problem
          : data.refresh?.lastSuccessfulRefreshAt == null
          ? DiagnosticCondition.pending
          : DiagnosticCondition.normal,
      action: failedRead
          ? '重试'
          : failed
          ? data.credentialInvalid
                ? '重新登录'
                : '立即同步'
          : null,
      onAction: failedRead
          ? _load
          : data.credentialInvalid
          ? _login
          : () => _run(() => _service.synchronize(data)),
    );
  }

  Widget _reminderStatus(SyncDiagnosticsSnapshot data) {
    String detail;
    if (data.remindersEnabled == false) {
      detail = '开启后会根据课表生成未来 60 天提醒';
    } else if (data.remindersEnabled == null ||
        data.failures.contains(DiagnosticRead.reminders) ||
        data.failures.contains(DiagnosticRead.notifications) ||
        data.failures.contains(DiagnosticRead.exactAlarm)) {
      detail = '暂时无法获取，请重试';
    } else if (data.notifications == false || data.exactAlarm == false) {
      detail = '通知或精确闹钟权限未授予，请修复提醒或检查系统设置';
    } else if (data.reminders?.updatedAt == null ||
        data.reminders?.enabled != true) {
      detail = '尚未建立提醒计划，可修复提醒';
    } else {
      detail = data.reminders!.reason;
    }
    final unreadable = detail.contains('暂时无法获取');
    return _status(
      icon: Icons.alarm_on_outlined,
      title: '提醒就绪状态',
      detail: detail,
      condition: data.reminderCondition,
      action: unreadable
          ? '重试'
          : data.remindersEnabled == true &&
                data.reminderCondition != DiagnosticCondition.normal
          ? '修复提醒'
          : null,
      onAction: unreadable
          ? _load
          : () => _run(() => _service.synchronize(data, repairReminders: true)),
    );
  }

  Widget _details(SyncDiagnosticsSnapshot data) => _card([
    ExpansionTile(
      title: const Text('查看详情'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.accountCondition == DiagnosticCondition.normal)
          _accountStatus(data),
        Text(
          '缓存课表：${data.failures.contains(DiagnosticRead.cache)
              ? '暂时无法获取'
              : data.cachedWeeks == null
              ? '暂无记录'
              : '${data.cachedWeeks} 周'}',
        ),
        const SizedBox(height: 8),
        Text(
          data.remindersEnabled == false
              ? '提醒覆盖：未开启'
              : data.remindersEnabled == null ||
                    data.failures.contains(DiagnosticRead.reminders)
              ? '提醒覆盖：暂时无法获取'
              : '提醒覆盖：${data.reminders?.cachedWeekCount ?? 0}/${data.reminders?.expectedWeekCount ?? 0} 周 · 已安排 ${data.reminders?.scheduledCount ?? 0} 条',
        ),
        if (data.remindersEnabled == true) ...[
          const SizedBox(height: 8),
          Text('下一条提醒：${_time(data.reminders?.nextReminderAt)}'),
        ],
        if (data.enhancementEnabled) ...[
          const SizedBox(height: 8),
          Text(
            '后台最近执行：${data.failures.contains(DiagnosticRead.background) ? '暂时无法获取' : _time(data.background?.lastRunAt)}',
          ),
          Text(
            '后台最近成功：${data.failures.contains(DiagnosticRead.background) ? '暂时无法获取' : _time(data.background?.lastSuccessAt)}',
          ),
          Text(
            '电池优化：${data.batteryIgnored == null
                ? '暂时无法获取'
                : data.batteryIgnored!
                ? '已忽略'
                : '未忽略'}',
          ),
          Text(
            '系统后台限制：${data.backgroundRestricted == null
                ? '暂时无法获取'
                : data.backgroundRestricted!
                ? '已限制'
                : '未限制'}',
          ),
        ],
        if (data.failures.isNotEmpty)
          TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('重试读取'),
          ),
        TextButton.icon(
          onPressed: _busy ? null : _openLogs,
          icon: const Icon(Icons.description_outlined),
          label: const Text('查看或导出日志'),
        ),
      ],
    ),
  ]);

  @override
  Widget build(BuildContext context) {
    final data = _snapshot;
    final backgroundUnreadable =
        data?.failures.any(
          (item) => const {
            DiagnosticRead.background,
            DiagnosticRead.notifications,
            DiagnosticRead.battery,
            DiagnosticRead.restriction,
          }.contains(item),
        ) ??
        false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('同步与修复'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            tooltip: '重新检测',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (_reading) const LinearProgressIndicator(),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _problemSummary(data),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                _heading('课表与组件'),
                _card([
                  _scheduleStatus(data),
                  if (data.accountCondition != DiagnosticCondition.normal) ...[
                    const Divider(height: 1),
                    _accountStatus(data),
                  ],
                  const Divider(height: 1),
                  _status(
                    icon: Icons.widgets_outlined,
                    title: '桌面组件',
                    detail: switch (_widgetResult) {
                      WidgetUpdateResult.accepted => '本页最近刷新请求已提交，显示结果请查看桌面',
                      WidgetUpdateResult.failed => '本页最近刷新请求失败，可再次立即同步',
                      WidgetUpdateResult.notSupported => '当前平台不支持桌面组件',
                      null => '本页暂无刷新请求记录，可立即同步后查看桌面',
                    },
                    condition: _widgetResult == WidgetUpdateResult.failed
                        ? DiagnosticCondition.problem
                        : DiagnosticCondition.pending,
                    action: _widgetResult == WidgetUpdateResult.failed
                        ? '立即同步'
                        : null,
                    onAction: () => _run(() => _service.synchronize(data)),
                  ),
                ]),
                _heading('课前提醒'),
                _card([
                  _reminderStatus(data),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: _busy ? null : _openNotifications,
                          child: const Text('通知设置'),
                        ),
                        if (data.remindersEnabled == true &&
                            (data.notifications == false ||
                                data.exactAlarm == false ||
                                _result?.permissionDenied == true))
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () =>
                                      _systemSettings(_service.openAppSettings),
                            child: const Text('打开系统设置'),
                          ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      _busy || data.account == null || data.account!.isEmpty
                      ? null
                      : () => _run(() => _service.synchronize(data)),
                  icon: _working
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_working ? '正在处理…' : '立即同步'),
                ),
                const SizedBox(height: 8),
                const Text('更新课表、请求刷新桌面组件，并更新已开启的课前提醒。'),
                if (_result case final result?) ...[
                  _heading('本次操作结果'),
                  _card([
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          for (final detail in result.details)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(detail),
                            ),
                          if (result.needsLogin)
                            TextButton(
                              onPressed: _busy ? null : _login,
                              child: const Text('重新登录'),
                            ),
                          if (result.permissionDenied)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _systemSettings(
                                      _service.openAppSettings,
                                    ),
                              child: const Text('打开系统设置'),
                            ),
                        ],
                      ),
                    ),
                  ]),
                ],
                if (data.enhancementEnabled) ...[
                  _heading('调课通知增强'),
                  _card([
                    _status(
                      icon: Icons.sync_outlined,
                      title: '后台检查',
                      detail: backgroundUnreadable
                          ? '部分后台信息暂时无法获取，请重试'
                          : data.background?.detail ?? '暂无执行记录，等待系统安排',
                      condition: data.backgroundCondition,
                      action: backgroundUnreadable
                          ? '重试'
                          : data.backgroundCondition ==
                                DiagnosticCondition.problem
                          ? '检查后台设置'
                          : null,
                      onAction: backgroundUnreadable
                          ? _load
                          : _openNotifications,
                    ),
                    if (data.notifications == false)
                      _status(
                        icon: Icons.notifications_outlined,
                        title: '调课通知权限',
                        detail: '通知权限未授予，请在系统设置中允许通知',
                        condition: DiagnosticCondition.problem,
                        action: '打开系统设置',
                        onAction: () =>
                            _systemSettings(_service.openAppSettings),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _systemSettings(
                                    _service.openBatterySettings,
                                  ),
                            child: const Text('电池与后台设置'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _systemSettings(
                                    _service.openAutoStartSettings,
                                  ),
                            child: const Text('自启动设置'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                    await _service.resetBackground();
                                    return const SyncActionResult(
                                      details: ['后台任务设置已提交，实际执行情况需等待系统安排后查看'],
                                    );
                                  }),
                            child: const Text('重新设置后台任务'),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 20),
                _details(data),
              ],
            ),
    );
  }
}
