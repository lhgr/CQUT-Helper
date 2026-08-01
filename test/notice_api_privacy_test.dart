import 'package:cqut_helper/api/notice/notice_api.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
