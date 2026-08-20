import 'dart:convert';

import 'package:cqut_helper/manager/cache_cleanup_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('偏好缓存占用同时统计键和值的字节数', () async {
    const timetableKey = 'schedule_test_cache';
    const timetableValue = '课表缓存';
    const userInfoKey = 'user_info_test';
    const userInfoValue = 'student';
    SharedPreferences.setMockInitialValues({
      timetableKey: timetableValue,
      userInfoKey: userInfoValue,
    });

    final usages = await CacheCleanupManager.getUsages();
    final timetable = usages.singleWhere(
      (usage) => usage.type == AppCacheType.timetable,
    );
    final userInfo = usages.singleWhere(
      (usage) => usage.type == AppCacheType.userInfo,
    );

    expect(
      timetable.bytes,
      utf8.encode(timetableKey).length + utf8.encode(timetableValue).length,
    );
    expect(
      userInfo.bytes,
      utf8.encode(userInfoKey).length + utf8.encode(userInfoValue).length,
    );
  });
}
