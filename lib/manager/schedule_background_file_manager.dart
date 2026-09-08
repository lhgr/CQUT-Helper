import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract final class ScheduleBackgroundFileManager {
  static const String persistedBaseName = 'schedule_background';

  static Future<String> copyToDocuments(String sourcePath) async {
    final directory = await getApplicationDocumentsDirectory();
    return copyToDirectory(sourcePath, directory);
  }

  static Future<int> removeObsolete({String? keeping}) async {
    try {
      return removeObsoleteIn(
        await getApplicationDocumentsDirectory(),
        keeping: keeping,
      );
    } catch (_) {
      return 0;
    }
  }

  static Future<String> copyToDirectory(
    String sourcePath,
    Directory directory,
  ) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Background source does not exist', sourcePath);
    }
    await directory.create(recursive: true);
    final rawExtension = p.extension(sourcePath).toLowerCase();
    final extension = RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(rawExtension)
        ? rawExtension
        : '.jpg';
    final target = File(p.join(directory.path, '$persistedBaseName$extension'));
    if (!p.equals(p.normalize(source.path), p.normalize(target.path))) {
      await source.copy(target.path);
    }
    return target.path;
  }

  static Future<int> removeObsoleteIn(
    Directory directory, {
    String? keeping,
  }) async {
    if (!await directory.exists()) return 0;
    final keptPath = keeping == null ? null : p.normalize(p.absolute(keeping));
    final filePattern = RegExp(
      '^${RegExp.escape(persistedBaseName)}\\.[a-z0-9]{1,5}\$',
      caseSensitive: false,
    );
    var removed = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !filePattern.hasMatch(p.basename(entity.path))) {
        continue;
      }
      if (keptPath != null &&
          p.equals(p.normalize(entity.absolute.path), keptPath)) {
        continue;
      }
      try {
        await entity.delete();
        removed++;
      } catch (_) {}
    }
    return removed;
  }
}
