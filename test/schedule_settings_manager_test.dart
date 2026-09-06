import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(WidgetUpdater.resetDebugOverrides);

  test('调课通知开关持久化后立即更新组件，重复保存不触发', () async {
    SharedPreferences.setMockInitialValues({});
    final manager = ScheduleSettingsManager();
    final received = <bool>[];
    WidgetUpdater.debugIsAndroidOverride = true;
    WidgetUpdater.debugMethodInvoker = (method, arguments) async {
      final prefs = await SharedPreferences.getInstance();
      received.add(
        prefs.getBool(ScheduleSettingsManager.backgroundPollingEnabledKey)!,
      );
      expect(arguments['trigger'], 'notice_polling_changed');
    };
    for (final enabled in [true, true, false]) {
      await manager.save(
        showWeekend: true,
        timeInfoEnabled: true,
        backgroundPollingEnabled: enabled,
        noticeApiBaseUrl: ScheduleSettingsManager.officialNoticeApiBaseUrl,
      );
    }
    expect(received, [true, false]);
  });

  group('ScheduleSettingsManager 调课通知增强授权', () {
    test('旧版仅开启轮询但没有新版隐私同意时会自动关闭', () async {
      SharedPreferences.setMockInitialValues({
        ScheduleSettingsManager.backgroundPollingEnabledKey: true,
        ScheduleSettingsManager.noticePrivacyConsentVersionKey:
            ScheduleSettingsManager.currentNoticePrivacyConsentVersion - 1,
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
      expect(ScheduleSettingsManager.isOfficialNoticeApiBaseUrl(''), isTrue);
      expect(
        ScheduleSettingsManager.isOfficialNoticeApiBaseUrl(
          'https://notice.example.com',
        ),
        isFalse,
      );
    });

    test('自定义服务风险提示可按版本设为不再提示', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        await ScheduleSettingsManager.shouldShowCustomServiceRiskWarning(),
        isTrue,
      );

      await ScheduleSettingsManager.suppressCustomServiceRiskWarning();

      expect(
        await ScheduleSettingsManager.shouldShowCustomServiceRiskWarning(),
        isFalse,
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

  test('课表布局设置会持久化并限制异常数值', () async {
    SharedPreferences.setMockInitialValues({});
    final manager = ScheduleSettingsManager();
    await manager.load();

    await manager.saveLayoutSettings(
      const ScheduleLayoutSettings(
        gridCellWidth: 200,
        gridCellHeight: 20,
        showGridLines: false,
        backgroundImagePath: '  /tmp/background.jpg  ',
        backgroundOpacity: 2,
        backgroundBlur: 99,
        hideLocation: true,
        hideTeacher: true,
        removeCampusPrefix: true,
        horizontalCenter: true,
        verticalCenter: true,
        cardRadius: 50,
        textScale: 3,
        cardOpacity: 0,
      ),
    );

    final reloaded = ScheduleSettingsManager();
    await reloaded.load();
    final layout = reloaded.layoutSettings;
    expect(layout.gridCellWidth, ScheduleLayoutSettings.maxGridCellWidth);
    expect(layout.gridCellHeight, ScheduleLayoutSettings.minGridCellHeight);
    expect(layout.showGridLines, isFalse);
    expect(layout.backgroundImagePath, '/tmp/background.jpg');
    expect(layout.backgroundOpacity, 1);
    expect(layout.backgroundBlur, 20);
    expect(layout.hideLocation, isTrue);
    expect(layout.hideTeacher, isTrue);
    expect(layout.removeCampusPrefix, isTrue);
    expect(layout.horizontalCenter, isTrue);
    expect(layout.verticalCenter, isTrue);
    expect(layout.cardRadius, 28);
    expect(layout.textScale, 1.5);
    expect(layout.cardOpacity, 0.1);
  });

  test('启动预读后新管理器可同步获取课表背景设置', () async {
    SharedPreferences.setMockInitialValues({
      ScheduleSettingsManager.backgroundImagePathKey: '/tmp/background.jpg',
    });
    final bootstrapManager = ScheduleSettingsManager();
    await bootstrapManager.load();

    final pageManager = ScheduleSettingsManager();

    expect(
      pageManager.layoutSettings.backgroundImagePath,
      '/tmp/background.jpg',
    );
    expect(
      ScheduleSettingsManager.cachedLayoutSettings.backgroundImagePath,
      '/tmp/background.jpg',
    );
  });
}
