import 'dart:convert';

import 'package:cqut_helper/manager/app_backup_service.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('备份预览只读取元数据和项目数量', () {
    final content = jsonEncode({
      'format': 'cqut-helper-backup',
      'version': 1,
      'createdAt': '2026-08-20T12:00:00.000',
      'sourceAccount': '20260001',
      'settings': {'schedule_show_weekend': true, 'theme_mode': 'dark'},
      'coursePreferences': [
        {'year_term': '2026-2027-1', 'course_key': 'course:高等数学|张老师'},
      ],
    });

    final preview = AppBackupService.preview(content);
    expect(preview.version, 1);
    expect(preview.sourceAccount, '20260001');
    expect(preview.preferenceCount, 2);
    expect(preview.coursePreferenceCount, 1);
  });

  test('拒绝非 CQUT Helper 或未来版本备份', () {
    expect(
      () => AppBackupService.preview(
        jsonEncode({'format': 'other', 'version': 1}),
      ),
      throwsFormatException,
    );
    expect(
      () => AppBackupService.preview(
        jsonEncode({'format': 'cqut-helper-backup', 'version': 99}),
      ),
      throwsFormatException,
    );
  });

  test('网格线透明度可被备份识别并完整恢复', () async {
    SharedPreferences.setMockInitialValues({
      'account': 'source-account',
      'schedule_grid_line_opacity': 0.65,
      'not_allowed': 'must-not-be-backed-up',
    });
    final sourcePreferences = await SharedPreferences.getInstance();
    final backedUpSettings = AppBackupService.collectSettingsForTesting(
      sourcePreferences,
      'source-account',
    );

    expect(backedUpSettings['schedule_grid_line_opacity'], 0.65);
    expect(backedUpSettings, isNot(contains('not_allowed')));

    final serializedSettings = (jsonDecode(jsonEncode(backedUpSettings)) as Map)
        .cast<String, dynamic>();
    SharedPreferences.setMockInitialValues({'account': 'target-account'});
    final targetPreferences = await SharedPreferences.getInstance();
    final restoredCount = await AppBackupService.restoreSettingsForTesting(
      prefs: targetPreferences,
      settings: serializedSettings,
      sourceAccount: 'source-account',
      account: 'target-account',
    );

    expect(restoredCount, 1);
    expect(targetPreferences.getDouble('schedule_grid_line_opacity'), 0.65);

    final manager = ScheduleSettingsManager();
    await manager.load();
    expect(manager.layoutSettings.gridLineOpacity, 0.65);
  });
}
