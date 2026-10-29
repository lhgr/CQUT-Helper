import 'dart:async';

import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/manager/schedule_refresh_state.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_refresh_orchestrator.dart';
import 'package:cqut_helper/pages/Settings/sync_diagnostics_page.dart';
import 'package:cqut_helper/pages/Settings/sync_diagnostics_service.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Controller extends ScheduleController {
  Object? networkError;
  SchedulePrefetchResult prefetch = SchedulePrefetchResult(completed: true);
  bool? forced;
  int loads = 0;
  bool disposed = false;

  @override
  Future<ScheduleData> loadFromNetwork({
    String? weekNum,
    String? yearTerm,
    bool persistLastViewed = true,
    bool updateWidgetPins = false,
  }) async {
    loads++;
    if (networkError != null) throw networkError!;
    return ScheduleData(
      yearTerm: '2026-2027-1',
      weekNum: '1',
      weekList: ['1', '2'],
    );
  }

  @override
  Future<SchedulePrefetchResult> prefetchAllWeeksInBackground(
    ScheduleData data,
    void Function()? onUpdate, {
    Duration interval = const Duration(seconds: 5),
    bool forceRefresh = false,
  }) async {
    forced = forceRefresh;
    return prefetch;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

class _Service extends SyncDiagnosticsService {
  final controller = _Controller();
  bool failCache = false;
  bool failCredential = false;
  bool failReminderRead = false;
  bool notificationPermission = true;
  bool permissionGranted = true;
  bool failPermissionRequest = false;
  WidgetUpdateResult widgetOutcome = WidgetUpdateResult.accepted;
  CourseReminderStatus reminder = CourseReminderStatus(
    enabled: true,
    ready: true,
    reason: '未来 60 天没有需要提醒的课程',
    updatedAt: DateTime(2026, 10, 29),
  );
  ScheduleRefreshSnapshot refresh = const ScheduleRefreshSnapshot(
    lastSuccessfulRefreshAt: null,
    widgetState: ScheduleWidgetRefreshState.idle,
    failure: null,
  );
  int widgetCalls = 0;
  int reschedules = 0;
  int permissionRequests = 0;
  int notificationReads = 0;
  int exactReads = 0;
  int reads = 0;
  List<Completer<SyncDiagnosticsSnapshot>>? queuedReads;
  Completer<WidgetUpdateResult>? pendingWidget;

  @override
  void logFailure(String operation, Object error, StackTrace stack) {}
  @override
  Future<String?> readCredential() async {
    if (failCredential) throw StateError('locked');
    return 'saved';
  }

  @override
  Future<int> readCachedWeeks(String account) async {
    if (failCache) throw StateError('db');
    return 20;
  }

  @override
  Future<ScheduleRefreshSnapshot> readRefresh(String account) async => refresh;
  @override
  Future<CourseReminderStatus> readReminders() async {
    if (failReminderRead) throw StateError('status');
    return reminder;
  }

  @override
  Future<bool> readNotifications() async {
    notificationReads++;
    return notificationPermission;
  }

  @override
  Future<bool> readExactAlarm() async {
    exactReads++;
    return true;
  }

  @override
  Future<ScheduleBackgroundPollHealthSnapshot> readBackground() async =>
      const ScheduleBackgroundPollHealthSnapshot(
        status: ScheduleBackgroundPollHealthStatus.observing,
        title: '观察中',
        detail: '等待系统安排后台检查',
      );
  @override
  Future<bool?> readBatteryIgnored() async => true;
  @override
  Future<bool?> readBackgroundRestricted() async => false;
  @override
  ScheduleController createController() => controller;
  @override
  Future<WidgetUpdateResult> refreshWidget() async {
    widgetCalls++;
    return pendingWidget == null ? widgetOutcome : await pendingWidget!.future;
  }

  @override
  Future<void> rescheduleReminders(String account) async {
    reschedules++;
  }

  @override
  Future<bool> requestReminderPermissions() async {
    permissionRequests++;
    if (failPermissionRequest) throw StateError('platform unavailable');
    return permissionGranted;
  }

  @override
  Future<bool> openAppSettings() async => false;
  @override
  Future<SyncDiagnosticsSnapshot> load() {
    final index = reads++;
    return queuedReads == null ? super.load() : queuedReads![index].future;
  }
}

void main() {
  void preferences({
    bool reminders = true,
    bool enhancement = false,
    bool consent = true,
  }) {
    SharedPreferences.setMockInitialValues({
      'account': '20260001',
      ScheduleSettingsManager.remindersEnabledKey: reminders,
      ScheduleSettingsManager.backgroundPollingEnabledKey: enhancement,
      ScheduleSettingsManager.noticePrivacyConsentVersionKey: consent
          ? ScheduleSettingsManager.currentNoticePrivacyConsentVersion
          : 0,
    });
  }

  Future<void> pumpPage(WidgetTester tester, _Service service) async {
    await tester.pumpWidget(
      MaterialApp(home: SyncDiagnosticsPage(service: service)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapSync(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, '立即同步');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  setUp(preferences);

  test('全周强制同步，分别确认课表、组件请求与提醒阶段', () async {
    final service = _Service();
    final result = await service.synchronize(await service.load());
    expect(result.hasFailure, isFalse);
    expect(result.completedStages, 4);
    expect(service.controller.forced, isTrue);
    expect(service.controller.disposed, isTrue);
    expect(service.widgetCalls, 1);
    expect(service.reschedules, 1);
    expect(service.permissionRequests, 0);
    expect(result.widgetResult, WidgetUpdateResult.accepted);
  });

  test('有失败周时继续组件和提醒并报告部分完成', () async {
    final service = _Service();
    service.controller.prefetch = SchedulePrefetchResult(
      completed: true,
      failedWeeks: ['2'],
    );
    final result = await service.synchronize(await service.load());
    expect(result.hasFailure, isTrue);
    expect(result.completedStages, 3);
    expect(result.title, contains('部分'));
    expect(result.details.any((detail) => detail.contains('1 周未完成')), isTrue);
    expect(service.widgetCalls, 1);
    expect(service.reschedules, 1);
  });

  test('组件请求失败不会阻断提醒或宣称组件已刷新', () async {
    final service = _Service()..widgetOutcome = WidgetUpdateResult.failed;
    final result = await service.synchronize(await service.load());
    expect(result.hasFailure, isTrue);
    expect(result.widgetResult, WidgetUpdateResult.failed);
    expect(service.reschedules, 1);
    expect(result.details.any((detail) => detail.contains('组件刷新请求失败')), isTrue);
  });

  test('当前周鉴权失败后仍尝试组件和缓存提醒', () async {
    final service = _Service();
    service.controller.networkError = StateError('请重新登录');
    final result = await service.synchronize(await service.load());
    expect(result.needsLogin, isTrue);
    expect(result.hasFailure, isTrue);
    expect(result.title, contains('部分'));
    expect(service.controller.forced, isNull);
    expect(service.widgetCalls, 1);
    expect(service.reschedules, 1);
  });

  test('所有可执行阶段失败时不称为部分完成', () async {
    preferences(reminders: false);
    final service = _Service()..widgetOutcome = WidgetUpdateResult.failed;
    service.controller.networkError = StateError('network');
    final result = await service.synchronize(await service.load());
    expect(result.completedStages, 0);
    expect(result.title, '操作未完成，请查看结果');
  });

  test('无凭据跳过网络并引导登录，仍请求组件刷新', () async {
    final service = _Service();
    final result = await service.synchronize(
      const SyncDiagnosticsSnapshot(account: '20260001', hasCredential: false),
    );
    expect(result.needsLogin, isTrue);
    expect(service.controller.loads, 0);
    expect(service.widgetCalls, 1);
  });

  test('提醒已关闭不检查精确闹钟、不申请权限、不重建提醒', () async {
    preferences(reminders: false, enhancement: true);
    final service = _Service();
    final snapshot = await service.load();
    expect(snapshot.reminderCondition, DiagnosticCondition.off);
    await service.synchronize(snapshot);
    expect(service.permissionRequests, 0);
    expect(service.exactReads, 0);
    expect(service.reschedules, 0);
    expect(
      service.notificationReads,
      1,
    ); // Enhancement checks notifications only.
  });

  test('同步时重新读取开关，旧快照不能重建已关闭的提醒', () async {
    final service = _Service();
    final snapshot = await service.load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ScheduleSettingsManager.remindersEnabledKey, false);
    await service.synchronize(snapshot);
    expect(service.reschedules, 0);
  });

  test('修复权限拒绝时停止重建，提供可操作结果', () async {
    final service = _Service()..permissionGranted = false;
    final result = await service.synchronize(
      await service.load(),
      repairReminders: true,
    );
    expect(result.permissionDenied, isTrue);
    expect(result.hasFailure, isTrue);
    expect(service.controller.loads, 0);
    expect(service.reschedules, 0);
    expect(service.permissionRequests, 1);
  });

  test('正常同步不会弹权限申请，拒绝状态保留其余阶段完成', () async {
    final service = _Service()..notificationPermission = false;
    final result = await service.synchronize(await service.load());
    expect(result.permissionDenied, isTrue);
    expect(service.permissionRequests, 0);
    expect(service.reschedules, 0);
    expect(result.completedStages, 3);
  });

  test('权限请求异常保留未知状态并停止重建，不伪称用户已拒绝', () async {
    final service = _Service()..failPermissionRequest = true;
    final result = await service.synchronize(
      await service.load(),
      repairReminders: true,
    );
    expect(result.hasFailure, isTrue);
    expect(result.permissionDenied, isFalse);
    expect(result.details.any((detail) => detail.contains('暂时无法获取')), isTrue);
    expect(result.details.any((detail) => detail.contains('未授予')), isFalse);
    expect(service.permissionRequests, 1);
    expect(service.controller.loads, 0);
    expect(service.reschedules, 0);
  });

  test('未来无课且计划就绪属于正常', () async {
    final service = _Service();
    expect(
      (await service.load()).reminderCondition,
      DiagnosticCondition.normal,
    );
    final result = await service.synchronize(await service.load());
    expect(result.hasFailure, isFalse);
    expect(
      result.details.any((detail) => detail.contains('没有需要提醒的课程')),
      isTrue,
    );
  });

  test('读取局部失败保留其他状态，重试能恢复', () async {
    final service = _Service()
      ..failCache = true
      ..failCredential = true;
    var snapshot = await service.load();
    expect(
      snapshot.failures,
      containsAll([DiagnosticRead.cache, DiagnosticRead.credential]),
    );
    expect(snapshot.reminderCondition, DiagnosticCondition.normal);
    expect(snapshot.accountCondition, DiagnosticCondition.pending);
    expect(snapshot.credentialInvalid, isFalse);
    service
      ..failCache = false
      ..failCredential = false;
    snapshot = await service.load();
    expect(snapshot.failures, isEmpty);
    expect(snapshot.cachedWeeks, 20);
    expect(snapshot.accountCondition, DiagnosticCondition.normal);
  });

  test('设置类型错误不会吞掉其他读取结果', () async {
    SharedPreferences.setMockInitialValues({
      'account': '20260001',
      ScheduleSettingsManager.remindersEnabledKey: 'invalid',
    });
    final snapshot = await _Service().load();
    expect(snapshot.failures, contains(DiagnosticRead.settings));
    expect(snapshot.account, '20260001');
    expect(snapshot.cachedWeeks, 20);
    expect(snapshot.reminders, isNotNull);
    expect(snapshot.remindersEnabled, isNull);
  });

  testWidgets('仅真正启用增强时显示后台组，详情默认折叠', (tester) async {
    preferences(enhancement: true, consent: false);
    await pumpPage(tester, _Service());
    expect(find.text('调课通知增强'), findsNothing);
    expect(find.text('查看详情'), findsOneWidget);
    expect(find.textContaining('缓存课表：'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    preferences(enhancement: true);
    await pumpPage(tester, _Service());
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('调课通知增强'), findsOneWidget);
  });

  testWidgets('系统恢复前台会重新读取，并丢弃更旧的异步结果', (tester) async {
    final first = Completer<SyncDiagnosticsSnapshot>();
    final second = Completer<SyncDiagnosticsSnapshot>();
    final service = _Service()..queuedReads = [first, second];
    await tester.pumpWidget(
      MaterialApp(home: SyncDiagnosticsPage(service: service)),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(service.reads, 2);
    second.complete(
      const SyncDiagnosticsSnapshot(
        account: 'new',
        hasCredential: true,
        remindersEnabled: false,
      ),
    );
    await tester.pumpAndSettle();
    first.complete(
      const SyncDiagnosticsSnapshot(account: '', remindersEnabled: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('重新登录'), findsNothing);
    expect(find.text('登录后可同步课表与更新提醒'), findsNothing);
  });

  testWidgets('同步期间按钮禁用，重复点击不会启动第二次刷新', (tester) async {
    final service = _Service()..pendingWidget = Completer<WidgetUpdateResult>();
    await pumpPage(tester, service);
    await tapSync(tester);
    await tester.pump();
    expect(service.widgetCalls, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    service.pendingWidget!.complete(WidgetUpdateResult.accepted);
    await tester.pumpAndSettle();
    expect(service.widgetCalls, 1);
  });

  testWidgets('读取失败可重试，页面保留正常提醒信息', (tester) async {
    final service = _Service()..failCredential = true;
    await pumpPage(tester, service);
    expect(find.text('登录信息暂时无法获取，可重试或重新登录'), findsOneWidget);
    expect(find.text('未来 60 天没有需要提醒的课程'), findsOneWidget);
    service.failCredential = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('登录信息暂时无法获取，可重试或重新登录'), findsNothing);
  });

  testWidgets('首次同步已知失败显示异常，不因缺少历史成功时间变成待确认', (tester) async {
    final service = _Service()
      ..refresh = const ScheduleRefreshSnapshot(
        lastSuccessfulRefreshAt: null,
        widgetState: ScheduleWidgetRefreshState.failed,
        failure: ScheduleWidgetRefreshFailure.generic,
      );
    await pumpPage(tester, service);
    final syncRow = find.ancestor(
      of: find.text('最近同步'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: syncRow, matching: find.text('异常')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: syncRow, matching: find.text('待确认')),
      findsNothing,
    );
  });

  testWidgets('打开系统设置失败有反馈，且保留先前组件请求结果', (tester) async {
    final service = _Service()..notificationPermission = false;
    await pumpPage(tester, service);
    await tapSync(tester);
    await tester.pumpAndSettle();
    // Select the reminder card's stable entry. Scrolling can lazily build an
    // additional entry in the result card, changing the meaning of `.last`.
    final settingsEntry = find.text('打开系统设置').first;
    await tester.ensureVisible(settingsEntry);
    await tester.pumpAndSettle();
    expect(settingsEntry.hitTestable(), findsOneWidget);
    await tester.tap(settingsEntry);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('暂时无法打开该设置'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('暂时无法打开该设置'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 1500));
    await tester.pumpAndSettle();
    expect(find.text('本页最近刷新请求已提交，显示结果请查看桌面'), findsOneWidget);
  });
}
