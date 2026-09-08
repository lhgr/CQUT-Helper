import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns temporary files created while selecting and cropping a schedule
/// background.
///
/// The Android image picker copies selected media into the app cache and can
/// create a second `scaled_` copy. Keeping all cleanup rules here lets the
/// settings flow and the storage screen account for the same files.
abstract final class BackgroundImageTempManager {
  static const String directoryName = 'cqut_schedule_background';
  static const String cropFilePrefix = 'crop_';
  static const String legacyCropFilePrefix = 'schedule_background_crop_';

  static final RegExp _imagePickerDirectory = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static Future<File> createCropFile() async {
    final tempDir = await getTemporaryDirectory();
    final directory = Directory(p.join(tempDir.path, directoryName));
    await directory.create(recursive: true);
    return File(
      p.join(
        directory.path,
        '$cropFilePrefix${DateTime.now().microsecondsSinceEpoch}.jpg',
      ),
    );
  }

  static Future<int> bytes() async {
    try {
      return bytesIn(await getTemporaryDirectory());
    } catch (_) {
      return 0;
    }
  }

  static Future<int> cleanup({Iterable<String> excluding = const []}) async {
    try {
      return cleanupIn(await getTemporaryDirectory(), excluding: excluding);
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> deleteTemporaryPath(String? path) async {
    if (path == null || path.trim().isEmpty) return false;
    try {
      return deleteTemporaryPathIn(path, await getTemporaryDirectory());
    } catch (_) {
      return false;
    }
  }

  static Future<int> bytesIn(Directory tempDir) async {
    var total = 0;
    for (final entity in await ownedArtifactsIn(tempDir)) {
      total += await _entityBytes(entity);
    }
    return total;
  }

  static Future<int> cleanupIn(
    Directory tempDir, {
    Iterable<String> excluding = const [],
  }) async {
    var removed = 0;
    for (final entity in await ownedArtifactsIn(
      tempDir,
      excluding: excluding,
    )) {
      try {
        await entity.delete(recursive: entity is Directory);
        removed++;
      } catch (_) {}
    }
    return removed;
  }

  @visibleForTesting
  static Future<List<FileSystemEntity>> ownedArtifactsIn(
    Directory tempDir, {
    Iterable<String> excluding = const [],
  }) async {
    if (!await tempDir.exists()) return const [];
    final excluded = excluding
        .where((value) => value.trim().isNotEmpty)
        .map(_normalizedAbsolute)
        .toSet();
    final artifacts = <FileSystemEntity>[];
    await for (final entity in tempDir.list(followLinks: false)) {
      if (!_isOwnedTopLevelArtifact(entity)) continue;
      final entityPath = _normalizedAbsolute(entity.path);
      final containsExcludedPath = excluded.any(
        (path) => path == entityPath || p.isWithin(entityPath, path),
      );
      if (!containsExcludedPath) artifacts.add(entity);
    }
    return artifacts;
  }

  static Future<bool> deleteTemporaryPathIn(
    String path,
    Directory tempDir,
  ) async {
    final tempPath = _normalizedAbsolute(tempDir.path);
    final candidatePath = _normalizedAbsolute(path);
    if (!p.isWithin(tempPath, candidatePath)) return false;

    final type = await FileSystemEntity.type(candidatePath, followLinks: false);
    if (type == FileSystemEntityType.notFound ||
        type == FileSystemEntityType.link) {
      return false;
    }

    try {
      if (type == FileSystemEntityType.directory) {
        await Directory(candidatePath).delete(recursive: true);
      } else {
        await File(candidatePath).delete();
      }
    } catch (_) {
      return false;
    }

    final parent = Directory(p.dirname(candidatePath));
    if (_normalizedAbsolute(parent.path) != tempPath &&
        _isOwnedDirectoryName(p.basename(parent.path))) {
      try {
        if (await parent.exists() && await parent.list().isEmpty) {
          await parent.delete();
        }
      } catch (_) {}
    }
    return true;
  }

  static bool _isOwnedTopLevelArtifact(FileSystemEntity entity) {
    final name = p.basename(entity.path);
    if (entity is Directory) return _isOwnedDirectoryName(name);
    if (entity is! File) return false;
    return name.startsWith(legacyCropFilePrefix) || name.startsWith('scaled_');
  }

  static bool _isOwnedDirectoryName(String name) {
    return name == directoryName || _imagePickerDirectory.hasMatch(name);
  }

  static Future<int> _entityBytes(FileSystemEntity entity) async {
    if (entity is File) {
      try {
        return await entity.length();
      } catch (_) {
        return 0;
      }
    }
    if (entity is! Directory) return 0;
    var total = 0;
    try {
      await for (final child in entity.list(
        recursive: true,
        followLinks: false,
      )) {
        if (child is File) {
          try {
            total += await child.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  static String _normalizedAbsolute(String value) =>
      p.normalize(p.absolute(value));
}
