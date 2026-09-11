import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:flutter/material.dart';
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
        gridLineOpacity: 2,
        backgroundImagePath: '  /tmp/background.jpg  ',
        backgroundOpacity: 2,
        backgroundBlur: 99,
        colorMode: ScheduleColorMode.dark,
        analyzedBackgroundBrightness: Brightness.light,
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
    expect(layout.gridLineOpacity, 1);
    expect(layout.backgroundImagePath, '/tmp/background.jpg');
    expect(layout.backgroundOpacity, 1);
    expect(layout.backgroundBlur, 20);
    expect(layout.colorMode, ScheduleColorMode.dark);
    expect(layout.analyzedBackgroundBrightness, Brightness.light);
    expect(layout.hideLocation, isTrue);
    expect(layout.hideTeacher, isTrue);
    expect(layout.removeCampusPrefix, isTrue);
    expect(layout.horizontalCenter, isTrue);
    expect(layout.verticalCenter, isTrue);
    expect(layout.cardRadius, 28);
    expect(layout.textScale, 1.5);
    expect(layout.cardOpacity, 0.1);
  });

  test('未保存过背景设置时默认自动配色并跟随应用', () async {
    SharedPreferences.setMockInitialValues({});

    final manager = ScheduleSettingsManager();
    await manager.load();

    expect(manager.layoutSettings.backgroundOpacity, 0.68);
    expect(manager.layoutSettings.colorMode, ScheduleColorMode.auto);
    expect(manager.layoutSettings.analyzedBackgroundBrightness, isNull);
    expect(
      manager.layoutSettings.resolveBrightness(
        appBrightness: Brightness.dark,
        hasBackground: false,
      ),
      Brightness.dark,
    );
  });

  test('课表配色模式按背景存在状态解析并持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final manager = ScheduleSettingsManager();
    await manager.load();

    final automatic = manager.layoutSettings.copyWith(
      backgroundImagePath: '/tmp/background.jpg',
      colorMode: ScheduleColorMode.auto,
      analyzedBackgroundBrightness: Brightness.light,
    );
    expect(
      automatic.resolveBrightness(
        appBrightness: Brightness.dark,
        hasBackground: true,
      ),
      Brightness.light,
    );
    expect(
      automatic.resolveBrightness(
        appBrightness: Brightness.dark,
        hasBackground: false,
      ),
      Brightness.dark,
    );

    final manual = automatic.copyWith(colorMode: ScheduleColorMode.dark);
    await manager.saveLayoutSettings(manual);
    final reloaded = ScheduleSettingsManager();
    await reloaded.load();

    expect(reloaded.layoutSettings.colorMode, ScheduleColorMode.dark);
    expect(
      reloaded.layoutSettings.analyzedBackgroundBrightness,
      Brightness.light,
    );
  });

  test('保存新设置时清理已移除的导航表面强度字段', () async {
    SharedPreferences.setMockInitialValues({
      'schedule_top_bar_surface_opacity': 0.3,
      'schedule_side_bar_surface_opacity': 0.5,
      'schedule_bottom_bar_surface_opacity': 0.7,
      'schedule_navigation_surface_opacity': 0.4,
      'schedule_navigation_surface_advanced_mode': true,
      'schedule_navigation_surface_advanced_initialized': true,
    });

    final manager = ScheduleSettingsManager();
    await manager.load();
    await manager.saveLayoutSettings(manager.layoutSettings);
    final prefs = await SharedPreferences.getInstance();

    expect(
      prefs.getKeys().where((key) => key.contains('surface_opacity')),
      isEmpty,
    );
    expect(
      prefs.containsKey('schedule_navigation_surface_advanced_mode'),
      isFalse,
    );
    expect(
      prefs.containsKey('schedule_navigation_surface_advanced_initialized'),
      isFalse,
    );
  });

  test('旧版图片不透明度升级为互补的覆盖层不透明度', () async {
    SharedPreferences.setMockInitialValues({
      ScheduleSettingsManager.backgroundOpacityKey: 0.73,
    });

    final manager = ScheduleSettingsManager();
    await manager.load();
    final prefs = await SharedPreferences.getInstance();

    expect(manager.layoutSettings.backgroundOpacity, closeTo(0.27, 0.0001));
    expect(prefs.getDouble(ScheduleSettingsManager.backgroundOpacityKey), 0.73);
    expect(
      prefs.getInt(
        ScheduleSettingsManager.backgroundOpacitySemanticsVersionKey,
      ),
      isNull,
    );

    await manager.saveLayoutSettings(
      manager.layoutSettings.copyWith(backgroundOpacity: 0.6),
    );

    expect(prefs.getDouble(ScheduleSettingsManager.backgroundOpacityKey), 0.6);
    expect(
      prefs.getInt(
        ScheduleSettingsManager.backgroundOpacitySemanticsVersionKey,
      ),
      ScheduleSettingsManager.currentBackgroundOpacitySemanticsVersion,
    );

    final reloaded = ScheduleSettingsManager();
    await reloaded.load();
    expect(reloaded.layoutSettings.backgroundOpacity, 0.6);
  });

  test('新版背景图片不透明度不会被重复反转', () async {
    SharedPreferences.setMockInitialValues({
      ScheduleSettingsManager.backgroundOpacityKey: 0.73,
      ScheduleSettingsManager.backgroundOpacitySemanticsVersionKey:
          ScheduleSettingsManager.currentBackgroundOpacitySemanticsVersion,
    });

    final manager = ScheduleSettingsManager();
    await manager.load();

    expect(manager.layoutSettings.backgroundOpacity, 0.73);
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
