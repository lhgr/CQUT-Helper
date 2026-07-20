import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:cqut_helper/manager/schedule_notice_refresh_pipeline.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/schedule_notice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeScheduleApi extends ScheduleApi {
  _FakeScheduleApi({required this.response});

  final ScheduleNoticePollData response;
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
    test('透传当前学期到调课通知接口', () async {
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
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
        refreshWeek: (_, __) async {},
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
    });

    test('轮询返回学期与当前学期不一致时抛异常', () async {
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
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
        refreshWeek: (_, __) async {},
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
  });
}
