import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('course reminders declare and use exact alarm scheduling', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final notifications = File(
      'lib/utils/local_notifications.dart',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(manifest, contains('ScheduledNotificationReceiver'));
    expect(manifest, contains('ScheduledNotificationBootReceiver'));
    expect(notifications, contains('AndroidScheduleMode.exactAllowWhileIdle'));
    expect(notifications, contains('requestExactAlarmsPermission()'));
    expect(notifications, contains('canScheduleExactNotifications()'));
  });
}
