import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'diagnostics_storage.dart';

const diagnosticExportBytes = 1024 * 1024;

abstract class DiagnosticExport {
  Future<String> publish(String fileName, String content);
  Future<void> prune();
  Future<int> bytes();
  Future<int> clear();
}

/// Scoped storage exports belong to Android's MediaStore. Dart never writes a
/// duplicate private file or attempts direct public Downloads file access.
class AndroidDiagnosticExport extends DiagnosticExport {
  static const _timeout = Duration(seconds: 5);
  @override
  Future<String> publish(String fileName, String content) async {
    if (utf8.encode(content).length > diagnosticExportBytes) {
      throw ArgumentError('Diagnostic export exceeds 1 MiB');
    }
    final path = await AndroidDiagnosticStorage.channel
        .invokeMethod<String>('publishExport', {
          'fileName': fileName,
          'content': content,
        })
        .timeout(_timeout);
    if (path == null || path.isEmpty) {
      throw const FileSystemException('Diagnostic export failed');
    }
    return path;
  }

  @override
  Future<void> prune() async {
    await AndroidDiagnosticStorage.channel
        .invokeMethod<int>('pruneExports')
        .timeout(_timeout);
  }

  @override
  Future<int> bytes() async =>
      (await AndroidDiagnosticStorage.channel
              .invokeMapMethod<String, Object?>('exportStats')
              .timeout(_timeout))?['bytes']
          as int? ??
      0;
  @override
  Future<int> clear() async =>
      await AndroidDiagnosticStorage.channel
          .invokeMethod<int>('clearExports')
          .timeout(_timeout) ??
      0;
}

class FileDiagnosticExport extends DiagnosticExport {
  FileDiagnosticExport(this.directory, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;
  final Directory directory;
  final DateTime Function() _now;
  Future<void> _tail = Future<void>.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<String> publish(String fileName, String content) => _serial(() async {
    final bytes = utf8.encode(content).length;
    if (bytes > diagnosticExportBytes) {
      throw ArgumentError('Diagnostic export exceeds 1 MiB');
    }
    await directory.create(recursive: true);
    await _prune(reserveFiles: 1, reserveBytes: bytes);
    final file = File('${directory.path}/$fileName');
    try {
      await file.writeAsString(content, encoding: utf8, flush: true);
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    }
    await _prune();
    return file.path;
  });
  Future<List<File>> _files() async {
    if (!await directory.exists()) return [];
    return directory
        .list(followLinks: false)
        .where(
          (entry) =>
              entry is File &&
              RegExp(
                r'^cqut_diagnostic_.*\.log$',
              ).hasMatch(entry.uri.pathSegments.last),
        )
        .cast<File>()
        .toList();
  }

  Future<void> _prune({int reserveFiles = 0, int reserveBytes = 0}) async {
    final files = await _files();
    final stats = <File, FileStat>{};
    for (final file in files) {
      stats[file] = await file.stat();
    }
    files.sort((a, b) => stats[b]!.modified.compareTo(stats[a]!.modified));
    final cutoff = _now().subtract(diagnosticRetention);
    var retained = 0, total = 0;
    for (final file in files) {
      final stat = stats[file]!;
      if (stat.modified.isBefore(cutoff) ||
          stat.size > diagnosticExportBytes ||
          retained >= 3 - reserveFiles ||
          total + stat.size > 3 * diagnosticExportBytes - reserveBytes) {
        await file.delete();
      } else {
        retained++;
        total += stat.size;
      }
    }
  }

  @override
  Future<void> prune() => _serial(_prune);
  @override
  Future<int> bytes() => _serial(() async {
    var total = 0;
    for (final file in await _files()) {
      total += await file.length();
    }
    return total;
  });
  @override
  Future<int> clear() => _serial(() async {
    var count = 0;
    Object? failure;
    for (final file in await _files()) {
      try {
        await file.delete();
        count++;
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) {
      throw FileSystemException('Diagnostic export cleanup failed: $failure');
    }
    return count;
  });
}
