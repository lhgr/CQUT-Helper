import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppCacheType {
  timetable,
  userInfo,
  imageCache,
  favorites,
}

@immutable
class AppCacheUsage {
  final AppCacheType type;
  final String title;
  final String description;
  final int? bytes;
  final bool supported;

  const AppCacheUsage({
    required this.type,
    required this.title,
    required this.description,
    required this.bytes,
    required this.supported,
  });
}

class CacheCleanupManager {
  static Future<List<AppCacheUsage>> getUsages() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    final timetableKeys = keys.where(_isTimetableCacheKey);
    final timetableBytes = _estimatePrefsBytes(prefs, timetableKeys);

    final userInfoKeys = keys.where((k) => k.startsWith('user_info_'));
    final userInfoBytes = _estimatePrefsBytes(prefs, userInfoKeys);

    final favoritesKeys = keys.where(
      (k) => k == 'repo_favorites_guest' || k.startsWith('repo_favorites_'),
    );
    final favoritesBytes = _estimatePrefsBytes(prefs, favoritesKeys);

    final imageCacheBytes = await _getImageCacheBytes();

    return [
      AppCacheUsage(
        type: AppCacheType.timetable,
        title: '课表缓存',
        description: '周课表缓存、提醒/对比状态、待处理变更',
        bytes: timetableBytes,
        supported: true,
      ),
      AppCacheUsage(
        type: AppCacheType.userInfo,
        title: '个人信息缓存',
        description: '“我的”页面用户信息缓存',
        bytes: userInfoBytes,
        supported: true,
      ),
      AppCacheUsage(
        type: AppCacheType.imageCache,
        title: '图片缓存',
        description: '网络图片磁盘缓存与内存缓存',
        bytes: imageCacheBytes,
        supported: true,
      ),
      AppCacheUsage(
        type: AppCacheType.favorites,
        title: '收藏数据',
        description: '资料页收藏列表（本地保存）',
        bytes: favoritesBytes,
        supported: true,
      ),
    ];
  }

  static Future<void> clear(Set<AppCacheType> types) async {
    if (types.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    if (types.contains(AppCacheType.timetable)) {
      final toRemove = keys.where(_isTimetableCacheKey).toList(growable: false);
      for (final k in toRemove) {
        await prefs.remove(k);
      }
    }

    if (types.contains(AppCacheType.userInfo)) {
      final toRemove = keys
          .where((k) => k.startsWith('user_info_'))
          .toList(growable: false);
      for (final k in toRemove) {
        await prefs.remove(k);
      }
    }

    if (types.contains(AppCacheType.favorites)) {
      final toRemove = keys
          .where(
            (k) =>
                k == 'repo_favorites_guest' || k.startsWith('repo_favorites_'),
          )
          .toList(growable: false);
      for (final k in toRemove) {
        await prefs.remove(k);
      }
    }

    if (types.contains(AppCacheType.imageCache)) {
      await DefaultCacheManager().emptyCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
  }

  static bool _isTimetableCacheKey(String key) {
    if (key == 'schedule_show_weekend') return false;
    if (key.startsWith('schedule_update_')) return false;
    if (key == 'schedule_open_update_from_notification') return false;

    if (key.startsWith('schedule_pending_changes_')) return true;
    if (key.startsWith('schedule_notified_')) return true;
    if (key.startsWith('schedule_last_week_')) return true;
    if (key.startsWith('schedule_last_term_')) return true;

    return key.startsWith('schedule_');
  }

  static int _estimatePrefsBytes(
    SharedPreferences prefs,
    Iterable<String> keys,
  ) {
    int total = 0;
    for (final k in keys) {
      final v = prefs.get(k);
      if (v == null) continue;
      total += _estimateValueBytes(v);
    }
    return total;
  }

  static int _estimateValueBytes(Object value) {
    if (value is String) {
      return utf8.encode(value).length;
    }
    if (value is bool) return 1;
    if (value is int) return 8;
    if (value is double) return 8;
    if (value is List<String>) {
      int total = 0;
      for (final s in value) {
        total += utf8.encode(s).length;
      }
      return total;
    }
    return utf8.encode(value.toString()).length;
  }

  static Future<int?> _getImageCacheBytes() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(
        '${tempDir.path}${Platform.pathSeparator}libCachedImageData',
      );
      if (!await dir.exists()) return 0;
      return await _getDirectoryBytes(dir);
    } catch (_) {
      return null;
    }
  }

  static Future<int> _getDirectoryBytes(Directory dir) async {
    int total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }
}
