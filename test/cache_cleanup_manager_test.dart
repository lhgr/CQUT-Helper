import 'dart:convert';
import 'dart:io';

import 'package:cqut_helper/manager/background_image_temp_manager.dart';
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

  test('图片缓存占用包含网络缓存和背景处理临时文件且排除已保存背景', () async {
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

    await File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${BackgroundImageTempManager.legacyCropFilePrefix}old.png',
    ).writeAsBytes(List<int>.filled(7, 1));
    await File(
      '${tempDir.path}${Platform.pathSeparator}scaled_selected.jpg',
    ).writeAsBytes(List<int>.filled(11, 2));
    final pickerDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}'
      '123e4567-e89b-12d3-a456-426614174000',
    );
    await pickerDir.create();
    await File(
      '${pickerDir.path}${Platform.pathSeparator}selected.jpg',
    ).writeAsBytes(List<int>.filled(13, 3));
    final cropDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}'
      '${BackgroundImageTempManager.directoryName}',
    );
    await cropDir.create();
    await File(
      '${cropDir.path}${Platform.pathSeparator}'
      '${BackgroundImageTempManager.cropFilePrefix}new.jpg',
    ).writeAsBytes(List<int>.filled(17, 4));

    // A selected background is persisted outside the registered network image
    // caches and must never be included in their usage.
    await File(
      '${tempDir.path}${Platform.pathSeparator}schedule_background.jpg',
    ).writeAsBytes(List<int>.filled(16, 9));

    expect(await CacheCleanupManager.getImageCacheBytesIn(tempDir), 56);
  });

  test('背景临时文件清理只移除应用拥有的缓存工件', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cqut_background_temp_cleanup_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final legacyCrop = File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${BackgroundImageTempManager.legacyCropFilePrefix}old.png',
    );
    final scaled = File(
      '${tempDir.path}${Platform.pathSeparator}scaled_selected.jpg',
    );
    final pickerDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}'
      '123e4567-e89b-12d3-a456-426614174000',
    );
    final unrelated = File('${tempDir.path}${Platform.pathSeparator}keep.tmp');
    await legacyCrop.writeAsBytes([1]);
    await scaled.writeAsBytes([2]);
    await pickerDir.create();
    await File(
      '${pickerDir.path}${Platform.pathSeparator}picked.jpg',
    ).writeAsBytes([3]);
    await unrelated.writeAsBytes([4]);

    expect(await BackgroundImageTempManager.cleanupIn(tempDir), 3);
    expect(await legacyCrop.exists(), isFalse);
    expect(await scaled.exists(), isFalse);
    expect(await pickerDir.exists(), isFalse);
    expect(await unrelated.exists(), isTrue);
  });

  test('单文件清理拒绝删除缓存目录之外的文件', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cqut_background_temp_boundary_',
    );
    final outsideDir = await Directory.systemTemp.createTemp(
      'cqut_background_outside_boundary_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
      if (await outsideDir.exists()) await outsideDir.delete(recursive: true);
    });
    final outside = File(
      '${outsideDir.path}${Platform.pathSeparator}schedule_background_crop.png',
    );
    await outside.writeAsBytes([1, 2, 3]);

    expect(
      await BackgroundImageTempManager.deleteTemporaryPathIn(
        outside.path,
        tempDir,
      ),
      isFalse,
    );
    expect(await outside.exists(), isTrue);
  });
}
