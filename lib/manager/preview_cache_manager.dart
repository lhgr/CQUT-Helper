import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class PreviewCacheManager {
  static const String _dirName = 'cqut_preview';
  static const String _cleanupAtKey = 'preview_cache_cleanup_at';

  static Duration defaultTtl() => const Duration(days: 7);
  static int defaultMaxBytes() => 200 * 1024 * 1024;
  static Duration defaultMinInterval() => const Duration(hours: 24);

  static Future<Directory> resolveDir() async {
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}${Platform.pathSeparator}$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<void> cleanupIfNeeded({
    Duration? ttl,
    int? maxBytes,
    Duration? minInterval,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = prefs.getInt(_cleanupAtKey) ?? 0;
    final interval = minInterval ?? defaultMinInterval();
    if (last > 0 && now - last < interval.inMilliseconds) return;

    try {
      final dir = await resolveDir();
      await cleanupDir(
        dir,
        ttl: ttl ?? defaultTtl(),
        maxBytes: maxBytes ?? defaultMaxBytes(),
      );
    } finally {
      await prefs.setInt(_cleanupAtKey, now);
      unawaited(_reloadPrefsSafely(prefs));
    }
  }

  static Future<void> cleanupDir(
    Directory dir, {
    required Duration ttl,
    required int maxBytes,
  }) async {
    if (!await dir.exists()) return;
    final now = DateTime.now();
    final entries = <_CacheEntry>[];
    int totalBytes = 0;

    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (path.endsWith('.part')) {
        try {
          final stat = await entity.stat();
          if (now.difference(stat.modified) > const Duration(hours: 2)) {
            await entity.delete();
          }
        } catch (_) {}
        continue;
      }

      try {
        final stat = await entity.stat();
        final bytes = stat.size;
        totalBytes += bytes;
        entries.add(_CacheEntry(file: entity, modified: stat.modified, bytes: bytes));
      } catch (_) {}
    }

    final cutoff = now.subtract(ttl);
    for (final e in entries) {
      if (!e.modified.isAfter(cutoff)) {
        try {
          await e.file.delete();
          totalBytes -= e.bytes;
        } catch (_) {}
      }
    }

    if (totalBytes <= maxBytes) return;

    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final e in entries) {
      if (totalBytes <= maxBytes) break;
      try {
        if (await e.file.exists()) {
          await e.file.delete();
          totalBytes -= e.bytes;
        }
      } catch (_) {}
    }
  }

  static Future<void> _reloadPrefsSafely(SharedPreferences prefs) async {
    try {
      await prefs.reload();
    } catch (_) {}
  }
  static Future<int> getCacheSize() async {
    try {
      final dir = await resolveDir();
      if (!await dir.exists()) return 0;
      int total = 0;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clearCache() async {
    try {
      final dir = await resolveDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (_) {}
  }
}

class _CacheEntry {
  final File file;
  final DateTime modified;
  final int bytes;

  const _CacheEntry({
    required this.file,
    required this.modified,
    required this.bytes,
  });
}

