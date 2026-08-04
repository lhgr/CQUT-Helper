import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ScheduleSettingsManager 调课通知增强授权', () {
    test('旧版仅开启轮询但没有新版隐私同意时会自动关闭', () async {
      SharedPreferences.setMockInitialValues({
        ScheduleSettingsManager.backgroundPollingEnabledKey: true,
      });

      final manager = ScheduleSettingsManager();
      await manager.load();
      final prefs = await SharedPreferences.getInstance();

      expect(manager.backgroundPollingEnabled, isFalse);
      expect(
        prefs.getBool(ScheduleSettingsManager.backgroundPollingEnabledKey),
        isFalse,
      );
    });

    test('开关与当前隐私同意版本同时存在时保持开启', () async {
      SharedPreferences.setMockInitialValues({
        ScheduleSettingsManager.backgroundPollingEnabledKey: true,
        ScheduleSettingsManager.noticePrivacyConsentVersionKey:
            ScheduleSettingsManager.currentNoticePrivacyConsentVersion,
      });

      final manager = ScheduleSettingsManager();
      await manager.load();

      expect(manager.backgroundPollingEnabled, isTrue);
    });

    test('远程调课服务只接受 HTTPS 地址', () {
      expect(
        ScheduleSettingsManager.isValidNoticeApiBaseUrl(
          'https://notice.example.com',
        ),
        isTrue,
      );
      expect(
        ScheduleSettingsManager.isValidNoticeApiBaseUrl(
          'http://notice.example.com',
        ),
        isFalse,
      );
      expect(
        ScheduleSettingsManager.normalizeNoticeApiBaseUrl(
          'http://notice.example.com',
        ),
        ScheduleSettingsManager.officialNoticeApiBaseUrl,
      );
    });
  });

  test('保存任意课表设置会通知统一设置监听器', () async {
    SharedPreferences.setMockInitialValues({});
    final manager = ScheduleSettingsManager();
    await manager.load();
    final before = ScheduleSettingsManager.settingsEpoch.value;

    await manager.save(
      showWeekend: true,
      timeInfoEnabled: true,
      backgroundPollingEnabled: false,
      noticeApiBaseUrl: ScheduleSettingsManager.officialNoticeApiBaseUrl,
    );

    expect(ScheduleSettingsManager.settingsEpoch.value, before + 1);
  });
}
