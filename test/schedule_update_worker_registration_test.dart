import 'dart:async';

import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

class _Jobs extends WorkmanagerPlatform {
  final requests =
      <({String name, ExistingWorkPolicy? policy, String? user})>[];
  final cancelled = <String>[];
  final pending = <String, int>{};
  var nextIdentity = 0;

  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
    ForegroundServiceConfig? foregroundServiceConfig,
    bool expedited = false,
  }) async {
    requests.add((
      name: uniqueName,
      policy: existingWorkPolicy,
      user: inputData?['userId'] as String?,
    ));
    if (existingWorkPolicy != ExistingWorkPolicy.keep ||
        !pending.containsKey(uniqueName)) {
      pending[uniqueName] = ++nextIdentity;
    }
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    cancelled.add(uniqueName);
    pending.remove(uniqueName);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Jobs jobs;
  late WorkmanagerPlatform original;
  Completer<void>? credentialsGate;
  Completer<void>? credentialsStarted;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() {
    // The first construction selects the host implementation (including Linux
    // on CI), so initialize the facade before installing the test platform.
    Workmanager();
    original = WorkmanagerPlatform.instance;
    jobs = _Jobs();
    WorkmanagerPlatform.instance = jobs;
    ScheduleUpdateWorker.debugIsAndroidOverride = true;
    credentialsGate = credentialsStarted = null;
    SharedPreferences.setMockInitialValues({
      'account': 'student',
      ScheduleSettingsManager.backgroundPollingEnabledKey: true,
      ScheduleSettingsManager.noticePrivacyConsentVersionKey:
          ScheduleSettingsManager.currentNoticePrivacyConsentVersion,
    });
    messenger.setMockMethodCallHandler(secure, (_) async {
      if (credentialsGate != null) {
        final gate = credentialsGate!;
        credentialsGate = null;
        credentialsStarted?.complete();
        await gate.future;
      }
      return 'secret';
    });
  });
  tearDown(() {
    WorkmanagerPlatform.instance = original;
    ScheduleUpdateWorker.debugIsAndroidOverride = null;
    messenger.setMockMethodCallHandler(secure, null);
  });

  test('resume keeps pending daily and immediate jobs; account changes replace them', () async {
    await ScheduleUpdateWorker.syncFromPreferences();
    final first = Map<String, int>.of(jobs.pending);
    expect(
      first.keys,
      unorderedEquals([
        'academic_calendar_poll_daily',
        'schedule_notice_poll_task_immediate',
        'schedule_notice_poll_task_daily',
      ]),
    );
    jobs.cancelled.clear();
    jobs.requests.clear();
    await ScheduleUpdateWorker.syncFromPreferences();
    expect(jobs.pending, first);
    expect(
      jobs.requests.map((request) => request.policy),
      everyElement(ExistingWorkPolicy.keep),
    );
    expect(jobs.cancelled, isNot(contains('schedule_notice_poll_task_daily')));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account', 'other');
    await ScheduleUpdateWorker.syncFromPreferences();
    expect(
      jobs.pending['schedule_notice_poll_task_daily'],
      isNot(first['schedule_notice_poll_task_daily']),
    );
    expect(
      jobs.requests
          .lastWhere(
            (request) => request.name == 'schedule_notice_poll_task_daily',
          )
          .user,
      'other',
    );
    await prefs.setBool(
      ScheduleSettingsManager.backgroundPollingEnabledKey,
      false,
    );
    await ScheduleUpdateWorker.syncFromPreferences();
    expect(jobs.pending.keys, ['academic_calendar_poll_daily']);
  });

  test(
    'running calendar task replaces itself to register the following day',
    () async {
      await ScheduleUpdateWorker.syncFromPreferences();
      final before = jobs.pending['academic_calendar_poll_daily'];
      await ScheduleUpdateWorker.runTaskForTesting(
        'academic_calendar_poll_task',
        {'trigger': 'academic_calendar_daily'},
      );
      expect(jobs.requests.last.policy, ExistingWorkPolicy.replace);
      expect(jobs.pending['academic_calendar_poll_daily'], isNot(before));
    },
  );

  test(
    'account change during credentials read cannot restore stale jobs',
    () async {
      final gate = Completer<void>();
      credentialsGate = gate;
      credentialsStarted = Completer<void>();
      final first = ScheduleUpdateWorker.syncFromPreferences();
      await credentialsStarted!.future;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account', 'new-student');
      final second = ScheduleUpdateWorker.syncFromPreferences();
      gate.complete();
      await Future.wait([first, second]);
      expect(
        jobs.requests
            .where((request) => request.user != null)
            .map((request) => request.user),
        everyElement('new-student'),
      );
      expect(
        prefs.getString('schedule_worker_registration_config_v1'),
        contains('new-student'),
      );
      expect(jobs.pending.keys, contains('schedule_notice_poll_task_daily'));
    },
  );
}
