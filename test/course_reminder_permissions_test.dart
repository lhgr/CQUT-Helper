import 'dart:async';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <String>[];
  bool notifications = true;
  bool exact = true;
  bool notificationAfterRequest = true;
  bool exactAfterRequest = true;
  bool revokeNotificationsDuringExact = false;
  Object? notificationResponse;
  Object? exactResponse;
  Completer<void>? exactRequestGate;

  setUp(() {
    calls.clear();
    notifications = exact = notificationAfterRequest = exactAfterRequest = true;
    revokeNotificationsDuringExact = false;
    notificationResponse = exactResponse = true;
    exactRequestGate = null;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    LocalNotifications.debugIsAndroidOverride = true;
    LocalNotifications.debugResetInitialization();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'initialize':
              return true;
            case 'areNotificationsEnabled':
              return notifications;
            case 'canScheduleExactNotifications':
              return exact;
            case 'requestNotificationsPermission':
              notifications = notificationAfterRequest;
              return notificationResponse;
            case 'requestExactAlarmsPermission':
              await exactRequestGate?.future;
              exact = exactAfterRequest;
              if (revokeNotificationsDuringExact) notifications = false;
              return exactResponse;
            default:
              return null;
          }
        });
  });
  tearDown(() {
    LocalNotifications.debugIsAndroidOverride = null;
    LocalNotifications.debugResetInitialization();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  List<String> requests() =>
      calls.where((method) => method.startsWith('request')).toList();
  test('已授权时不重复请求通知与精确闹钟', () async {
    expect(await LocalNotifications.ensureCourseReminderPermissions(), isTrue);
    expect(requests(), isEmpty);
  });
  test('缺少通知权限时先请求并以实际状态确认授权', () async {
    notifications = false;
    notificationResponse = null;
    expect(await LocalNotifications.ensureCourseReminderPermissions(), isTrue);
    expect(requests(), ['requestNotificationsPermission']);
  });
  test('通知拒绝后不继续请求精确闹钟', () async {
    notifications = exact = false;
    notificationAfterRequest = false;
    expect(await LocalNotifications.ensureCourseReminderPermissions(), isFalse);
    expect(requests(), ['requestNotificationsPermission']);
  });
  test('精确闹钟缺失时等待请求返回并复核实际授权', () async {
    notifications = exact = false;
    exactResponse = false;
    expect(await LocalNotifications.ensureCourseReminderPermissions(), isTrue);
    expect(requests(), [
      'requestNotificationsPermission',
      'requestExactAlarmsPermission',
    ]);
  });
  test('精确闹钟拒绝即使请求声称成功仍不允许启用', () async {
    exact = false;
    exactAfterRequest = false;
    expect(await LocalNotifications.ensureCourseReminderPermissions(), isFalse);
    expect(requests(), ['requestExactAlarmsPermission']);
  });
  test('等待精确闹钟设置返回后才完成授权检查', () async {
    exact = false;
    exactRequestGate = Completer<void>();
    var completed = false;
    final permission = LocalNotifications.ensureCourseReminderPermissions()
        .then((value) {
          completed = true;
          return value;
        });
    await Future<void>.delayed(Duration.zero);
    expect(calls, contains('requestExactAlarmsPermission'));
    expect(completed, isFalse);
    exactRequestGate!.complete();
    expect(await permission, isTrue);
  });
  test('离开应用请求精确权限期间撤销通知权限仍禁止启用', () async {
    exact = false;
    revokeNotificationsDuringExact = true;
    expect(await LocalNotifications.ensureCourseReminderPermissions(), isFalse);
  });
}
