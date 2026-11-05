import 'dart:convert';

import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:cqut_helper/manager/schedule_notice_refresh_pipeline.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/schedule_notice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeScheduleApi extends ScheduleApi {
  _FakeScheduleApi({required this.response, this.failure, this.beforeResponse});

  final ScheduleNoticePollData response;
  final Object? failure;
  final Future<void> Function()? beforeResponse;
  String? requestedYearTerm;
  String? requestedEncryptedPassword;

  @override
  Future<ScheduleNoticePollData> fetchTermScheduleNotices({
    required String userId,
    required String encryptedPassword,
    required String yearTerm,
    String envName = 'prod',
    bool headless = true,
  }) async {
    requestedYearTerm = yearTerm;
    requestedEncryptedPassword = encryptedPassword;
    if (failure != null) throw failure!;
    await beforeResponse?.call();
    return response;
  }
}

class _FakePipelineCredentialStore extends CredentialStore {
  _FakePipelineCredentialStore({this.value})
    : super(secureStore: _NoopSecureSecretStore());

  final String? value;
  int readCalls = 0;

  @override
  Future<String?> readEncryptedPassword() async {
    readCalls++;
    return value;
  }
}

class _NoopSecureSecretStore implements SecureSecretStore {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write({required String key, required String value}) async {}
}

void main() {
  group('ScheduleNoticeRefreshPipeline', () {
    test('iOS前台主动同步在深夜仍查询，后台保留夜间暂停', () async {
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        ScheduleSettingsManager.backgroundPollingEnabledKey: true,
        ScheduleSettingsManager.noticePrivacyConsentVersionKey:
            ScheduleSettingsManager.currentNoticePrivacyConsentVersion,
      });
      final api = _FakeScheduleApi(
        response: const ScheduleNoticePollData(
          env: 'prod',
          yearTerm: '2026-2027-1',
          generatedAt: '',
          notices: [],
        ),
      );
      final pipeline = ScheduleNoticeRefreshPipeline(
        scheduleApi: api,
        credentialStore: _FakePipelineCredentialStore(value: 'secret'),
        refreshWeek: (_, _) async {},
        nowProvider: () => DateTime(2026, 11, 5, 2),
      );
      final data = ScheduleData(yearTerm: '2026-2027-1', weekList: ['1']);
      expect((await pipeline.run(currentData: data)).skipReason, 'deep_night');
      expect(api.requestedYearTerm, isNull);
      expect(
        (await pipeline.run(
          currentData: data,
          respectQuietHours: false,
        )).skipReason,
        isNull,
      );
      expect(api.requestedYearTerm, '2026-2027-1');
    });

    test('调课请求期间退出账号不落地旧账号通知快照', () async {
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        ScheduleSettingsManager.backgroundPollingEnabledKey: true,
        ScheduleSettingsManager.noticePrivacyConsentVersionKey:
            ScheduleSettingsManager.currentNoticePrivacyConsentVersion,
      });
      final prefs = await SharedPreferences.getInstance();
      final api = _FakeScheduleApi(
        response: const ScheduleNoticePollData(
          env: 'prod',
          yearTerm: '2026-2027-1',
          generatedAt: '',
          notices: [],
        ),
        beforeResponse: () => prefs.remove('account'),
      );
      final pipeline = ScheduleNoticeRefreshPipeline(
        scheduleApi: api,
        credentialStore: _FakePipelineCredentialStore(value: 'secret'),
        refreshWeek: (_, _) async =>
            fail('stale account must not refresh weeks'),
        nowProvider: () => DateTime(2026, 11, 5, 10),
      );
      final result = await pipeline.run(
        currentData: ScheduleData(yearTerm: '2026-2027-1', weekList: ['1']),
      );
      expect(result.skipReason, 'stale_account');
      expect(
        prefs.containsKey('schedule_notice_state_u1_2026-2027-1'),
        isFalse,
      );
    });

    test('透传当前学期到调课通知接口', () async {
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        ScheduleSettingsManager.backgroundPollingEnabledKey: true,
        ScheduleSettingsManager.noticePrivacyConsentVersionKey:
            ScheduleSettingsManager.currentNoticePrivacyConsentVersion,
      });
      final fakeApi = _FakeScheduleApi(
        response: const ScheduleNoticePollData(
          env: 'prod',
          yearTerm: '2024-2025-2',
          generatedAt: '2026-01-01 10:00:00',
          notices: <ScheduleNotice>[],
        ),
      );
      final credentialStore = _FakePipelineCredentialStore(value: 'secure-p1');
      final pipeline = ScheduleNoticeRefreshPipeline(
        scheduleApi: fakeApi,
        credentialStore: credentialStore,
        refreshWeek: (_, _) async {},
        nowProvider: () => DateTime(2026, 4, 14, 10),
      );

      final result = await pipeline.run(
        currentData: ScheduleData(
          yearTerm: '2024-2025-2',
          weekNum: '1',
          weekList: const <String>['1'],
        ),
      );

      expect(fakeApi.requestedYearTerm, '2024-2025-2');
      expect(fakeApi.requestedEncryptedPassword, 'secure-p1');
      expect(credentialStore.readCalls, 1);
      expect(result.apiClosed, isFalse);
      expect(pipeline.diagnosticProgress['pipeline_stage'], 'completed');
    });

    test('轮询返回学期与当前学期不一致时抛异常', () async {
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        ScheduleSettingsManager.backgroundPollingEnabledKey: true,
        ScheduleSettingsManager.noticePrivacyConsentVersionKey:
            ScheduleSettingsManager.currentNoticePrivacyConsentVersion,
      });
      final fakeApi = _FakeScheduleApi(
        response: const ScheduleNoticePollData(
          env: 'prod',
          yearTerm: '2023-2024-1',
          generatedAt: '2026-01-01 10:00:00',
          notices: <ScheduleNotice>[],
        ),
      );
      final pipeline = ScheduleNoticeRefreshPipeline(
        scheduleApi: fakeApi,
        credentialStore: _FakePipelineCredentialStore(value: 'secure-p1'),
        refreshWeek: (_, _) async {},
        nowProvider: () => DateTime(2026, 4, 14, 10),
      );

      expect(
        () => pipeline.run(
          currentData: ScheduleData(
            yearTerm: '2024-2025-2',
            weekNum: '1',
            weekList: const <String>['1'],
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('通知获取失败只证明验证已完成，不误报课表刷新成功', () async {
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        ScheduleSettingsManager.backgroundPollingEnabledKey: true,
        ScheduleSettingsManager.noticePrivacyConsentVersionKey:
            ScheduleSettingsManager.currentNoticePrivacyConsentVersion,
      });
      final failure = StateError('notice service unavailable');
      var refreshCalls = 0;
      final pipeline = ScheduleNoticeRefreshPipeline(
        scheduleApi: _FakeScheduleApi(
          response: const ScheduleNoticePollData(
            env: 'prod',
            yearTerm: '2024-2025-2',
            generatedAt: '',
            notices: [],
          ),
          failure: failure,
        ),
        credentialStore: _FakePipelineCredentialStore(value: 'secure-p1'),
        refreshWeek: (_, _) async {
          refreshCalls++;
        },
        nowProvider: () => DateTime(2026, 4, 14, 10),
      );
      await expectLater(
        pipeline.run(
          currentData: ScheduleData(
            yearTerm: '2024-2025-2',
            weekList: const ['1'],
          ),
        ),
        throwsA(same(failure)),
      );
      final progress = pipeline.diagnosticProgress;
      expect(progress['pipeline_stage'], 'fetch_notices');
      expect(progress['pipeline_completed_stages'], [
        'validate_schedule',
        'validate_credentials',
      ]);
      expect(progress['refreshed_week_count'], 0);
      expect(progress['network_outcome'], 'failed');
      expect(progress['network_attempted'], isTrue);
      expect(
        (progress['stage_durations_ms'] as Map).keys,
        containsAll([
          'validate_schedule',
          'validate_credentials',
          'fetch_notices',
        ]),
      );
      expect(
        (progress['stage_durations_ms'] as Map).values,
        everyElement(isNonNegative),
      );
      expect(refreshCalls, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('schedule_notice_state_u1_2024-2025-2'), isNull);
    });

    test('周刷新中途失败保留真实完成数且不提交通知快照', () async {
      final originalState = jsonEncode({
        'notices': {
          'removed': {
            'noticeId': 'removed',
            'noticeVersion': 'old',
            'weeks': ['1', '2'],
            'keys': [],
            'line': 'private notice',
          },
        },
      });
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        ScheduleSettingsManager.backgroundPollingEnabledKey: true,
        ScheduleSettingsManager.noticePrivacyConsentVersionKey:
            ScheduleSettingsManager.currentNoticePrivacyConsentVersion,
        'schedule_notice_state_u1_2024-2025-2': originalState,
      });
      final failure = StateError('second week failed');
      final pipeline = ScheduleNoticeRefreshPipeline(
        scheduleApi: _FakeScheduleApi(
          response: const ScheduleNoticePollData(
            env: 'prod',
            yearTerm: '2024-2025-2',
            generatedAt: '',
            notices: [],
          ),
        ),
        credentialStore: _FakePipelineCredentialStore(value: 'secure-p1'),
        refreshWeek: (week, _) async {
          if (week == '2') throw failure;
        },
        nowProvider: () => DateTime(2026, 4, 14, 10),
      );
      await expectLater(
        pipeline.run(
          currentData: ScheduleData(
            yearTerm: '2024-2025-2',
            weekList: const ['1', '2'],
          ),
        ),
        throwsA(same(failure)),
      );
      expect(
        pipeline.diagnosticProgress['pipeline_stage'],
        'refresh_affected_weeks',
      );
      expect(pipeline.diagnosticProgress['refreshed_week_count'], 1);
      expect(
        pipeline.diagnosticProgress['pipeline_completed_stages'],
        isNot(contains('refresh_affected_weeks')),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('schedule_notice_state_u1_2024-2025-2'),
        originalState,
      );
      expect(
        jsonEncode(pipeline.diagnosticProgress),
        isNot(contains('private notice')),
      );
    });

    test('未明确开启时不读取凭证且不访问调课服务', () async {
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        ScheduleSettingsManager.backgroundPollingEnabledKey: false,
      });
      final fakeApi = _FakeScheduleApi(
        response: const ScheduleNoticePollData(
          env: 'prod',
          yearTerm: '2024-2025-2',
          generatedAt: '2026-01-01 10:00:00',
          notices: <ScheduleNotice>[],
        ),
      );
      final credentialStore = _FakePipelineCredentialStore(value: 'secure-p1');
      final pipeline = ScheduleNoticeRefreshPipeline(
        scheduleApi: fakeApi,
        credentialStore: credentialStore,
        refreshWeek: (_, _) async {},
        nowProvider: () => DateTime(2026, 4, 14, 10),
      );

      final result = await pipeline.run(
        currentData: ScheduleData(
          yearTerm: '2024-2025-2',
          weekNum: '1',
          weekList: const <String>['1'],
        ),
      );

      expect(fakeApi.requestedYearTerm, isNull);
      expect(fakeApi.requestedEncryptedPassword, isNull);
      expect(credentialStore.readCalls, 0);
      expect(result.changes, isEmpty);
      expect(result.apiClosed, isFalse);
      expect(result.skipReason, 'disabled');
    });

    test('旧版开关没有新版隐私同意时不访问调课服务', () async {
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        ScheduleSettingsManager.backgroundPollingEnabledKey: true,
      });
      final fakeApi = _FakeScheduleApi(
        response: const ScheduleNoticePollData(
          env: 'prod',
          yearTerm: '2024-2025-2',
          generatedAt: '2026-01-01 10:00:00',
          notices: <ScheduleNotice>[],
        ),
      );
      final credentialStore = _FakePipelineCredentialStore(value: 'secure-p1');
      final pipeline = ScheduleNoticeRefreshPipeline(
        scheduleApi: fakeApi,
        credentialStore: credentialStore,
        refreshWeek: (_, _) async {},
        nowProvider: () => DateTime(2026, 4, 14, 10),
      );

      await pipeline.run(
        currentData: ScheduleData(
          yearTerm: '2024-2025-2',
          weekNum: '1',
          weekList: const <String>['1'],
        ),
      );

      expect(fakeApi.requestedYearTerm, isNull);
      expect(credentialStore.readCalls, 0);
    });
  });
}
