import 'dart:convert';
import 'dart:io';

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

  test('图片缓存占用包含所有网络图片缓存且排除背景图', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cqut_image_cache_usage_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final cacheDirs = CacheCleanupManager.imageCacheDirectoriesIn(
      tempDir,
    ).toList(growable: false);
    expect(cacheDirs, hasLength(2));
    await cacheDirs[0].create(recursive: true);
    await cacheDirs[1].create(recursive: true);
    await File(
      '${cacheDirs[0].path}${Platform.pathSeparator}default.img',
    ).writeAsBytes(<int>[1, 2, 3]);
    await File(
      '${cacheDirs[1].path}${Platform.pathSeparator}avatar.img',
    ).writeAsBytes(<int>[4, 5, 6, 7, 8]);

    // A selected background is persisted outside the registered network image
    // caches and must never be included in their usage.
    await File(
      '${tempDir.path}${Platform.pathSeparator}schedule_background.jpg',
    ).writeAsBytes(List<int>.filled(16, 9));

    expect(await CacheCleanupManager.getImageCacheBytesIn(tempDir), 8);
  });
}
