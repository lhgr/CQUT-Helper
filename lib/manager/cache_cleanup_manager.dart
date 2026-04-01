import 'dart:convert';
import 'dart:io';

import 'package:cqut/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cqut/manager/preview_cache_manager.dart';

enum AppCacheType { timetable, userInfo, imageCache, favorites, logs, preview }

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
  static final ValueNotifier<int> timetableCacheEpoch = ValueNotifier(0);
  static final ValueNotifier<int> userInfoCacheEpoch = ValueNotifier(0);
  static final ValueNotifier<int> favoritesCacheEpoch = ValueNotifier(0);
  static final ValueNotifier<int> imageCacheEpoch = ValueNotifier(0);
  static final ValueNotifier<int> logCacheEpoch = ValueNotifier(0);
  static final ValueNotifier<int> previewCacheEpoch = ValueNotifier(0);

  static const Map<AppCacheType, String> _titles = {
    AppCacheType.timetable: '课表缓存',
    AppCacheType.userInfo: '个人信息缓存',
    AppCacheType.imageCache: '图片缓存',
    AppCacheType.favorites: '收藏缓存',
    AppCacheType.logs: '日志缓存',
    AppCacheType.preview: '预览缓存',
  };

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
    final logBytes = await AppLogger.I.getLogBytes();
    final previewBytes = await PreviewCacheManager.getCacheSize();

    return [
      AppCacheUsage(
        type: AppCacheType.timetable,
        title: titleOf(AppCacheType.timetable),
        description: '包含周课表、提醒状态与待处理调课信息',
        bytes: timetableBytes,
        supported: true,
      ),
      AppCacheUsage(
        type: AppCacheType.userInfo,
        title: titleOf(AppCacheType.userInfo),
        description: '包含“我的”页面的用户资料与展示状态',
        bytes: userInfoBytes,
        supported: true,
      ),
      AppCacheUsage(
        type: AppCacheType.imageCache,
        title: titleOf(AppCacheType.imageCache),
        description: '包含网络图片的磁盘缓存与内存缓存',
        bytes: imageCacheBytes,
        supported: true,
      ),
      AppCacheUsage(
        type: AppCacheType.preview,
        title: titleOf(AppCacheType.preview),
        description: '包含资料预览生成的临时文件',
        bytes: previewBytes,
        supported: true,
      ),
      AppCacheUsage(
        type: AppCacheType.favorites,
        title: titleOf(AppCacheType.favorites),
        description: '包含资料页的本地收藏列表数据',
        bytes: favoritesBytes,
        supported: true,
      ),
      AppCacheUsage(
        type: AppCacheType.logs,
        title: titleOf(AppCacheType.logs),
        description: '包含调试、错误与网络请求日志文件',
        bytes: logBytes,
        supported: true,
      ),
    ];
  }

  static Future<Map<AppCacheType, int>> clear(Set<AppCacheType> types) async {
    if (types.isEmpty) return {};

    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final clearedCounts = <AppCacheType, int>{};

    if (types.contains(AppCacheType.timetable)) {
      final toRemove = keys.where(_isTimetableCacheKey).toList(growable: false);
      for (final k in toRemove) {
        await prefs.remove(k);
      }
      clearedCounts[AppCacheType.timetable] = toRemove.length;
      timetableCacheEpoch.value = timetableCacheEpoch.value + 1;
    }

    if (types.contains(AppCacheType.userInfo)) {
      final toRemove = keys
          .where((k) => k.startsWith('user_info_'))
          .toList(growable: false);
      for (final k in toRemove) {
        await prefs.remove(k);
      }
      clearedCounts[AppCacheType.userInfo] = toRemove.length;
      userInfoCacheEpoch.value = userInfoCacheEpoch.value + 1;
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
      clearedCounts[AppCacheType.favorites] = toRemove.length;
      favoritesCacheEpoch.value = favoritesCacheEpoch.value + 1;
    }

    if (types.contains(AppCacheType.imageCache)) {
      await DefaultCacheManager().emptyCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      try {
        final tempDir = await getTemporaryDirectory();
        final dir = Directory(
          '${tempDir.path}${Platform.pathSeparator}libCachedImageData',
        );
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
      clearedCounts[AppCacheType.imageCache] = 1;
      imageCacheEpoch.value = imageCacheEpoch.value + 1;
    }

    if (types.contains(AppCacheType.logs)) {
      final removed = await AppLogger.I.clearLogFiles();
      clearedCounts[AppCacheType.logs] = removed;
      logCacheEpoch.value = logCacheEpoch.value + 1;
    }

    if (types.contains(AppCacheType.preview)) {
      await PreviewCacheManager.clearCache();
      clearedCounts[AppCacheType.preview] = 1;
      previewCacheEpoch.value = previewCacheEpoch.value + 1;
    }

    try {
      await prefs.reload();
    } catch (_) {}

    return clearedCounts;
  }

  static String titleOf(AppCacheType type) {
    return _titles[type] ?? type.name;
  }

  static bool _isTimetableCacheKey(String key) {
    if (key == 'schedule_show_weekend') return false;
    if (key == 'schedule_time_info_enabled') return false;
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
