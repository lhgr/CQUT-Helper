import 'package:cqut_helper/api/notice/notice_api.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('调课通知增强未开启时可用性检查不会创建网络客户端', () async {
    var requestClientCreated = false;
    final api = NoticeApi(
      accessEnabled: () async => false,
      dioFactory: (baseUrl) {
        requestClientCreated = true;
        throw StateError('不应创建网络客户端');
      },
    );

    final result = await api.testAvailability(
      baseUrl: ScheduleSettingsManager.officialNoticeApiBaseUrl,
      username: '20260001',
      encryptedPassword: 'encrypted-password',
      yearTerm: '2026-2027-1',
    );

    expect(result.success, isFalse);
    expect(result.message, '调课通知增强未开启，未访问调课服务');
    expect(requestClientCreated, isFalse);
  });

  test('调课通知增强未开启时正式查询也不会创建网络客户端', () async {
    var requestClientCreated = false;
    final api = NoticeApi(
      accessEnabled: () async => false,
      dioFactory: (baseUrl) {
        requestClientCreated = true;
        throw StateError('不应创建网络客户端');
      },
    );

    await expectLater(
      api.fetchTermScheduleNotices(
        username: '20260001',
        encryptedPassword: 'encrypted-password',
        yearTerm: '2026-2027-1',
      ),
      throwsA(isA<NoticeApiForbiddenException>()),
    );
    expect(requestClientCreated, isFalse);
  });

  test('custom notice service never falls back to the official service', () {
    final candidates = NoticeApi.serviceCandidates(
      'https://self-hosted.example.com/',
    );

    expect(candidates, <String>['https://self-hosted.example.com']);
    expect(
      candidates,
      isNot(contains(ScheduleSettingsManager.officialNoticeApiBaseUrl)),
    );
  });

  test('empty selection resolves only to the official service', () {
    expect(NoticeApi.serviceCandidates(''), <String>[
      ScheduleSettingsManager.officialNoticeApiBaseUrl,
    ]);
  });
}
