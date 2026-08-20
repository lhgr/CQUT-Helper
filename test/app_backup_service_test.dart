import 'dart:convert';

import 'package:cqut_helper/manager/app_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
