import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

const diagnosticFileBytes = 256 * 1024;
const diagnosticRetention = Duration(days: 3);

abstract class DiagnosticStorage {
  String? get path;
  Future<void> initialize();
  Future<void> write(Map<String, Object?> event);
  Future<List<Map<String, Object?>>> snapshot();
  Future<int> bytes();
  Future<int> clear();
  Future<void> prune();
  Future<void> flush() async {}
}

/// Android owns the writer so all Flutter isolates and native widgets share
/// the same lock, rotation rules and snapshot boundary.
class AndroidDiagnosticStorage extends DiagnosticStorage {
  AndroidDiagnosticStorage(this.source);
  final String source;
  static const channel = MethodChannel('cqut/diagnostics');
  String? _path;
  @override
  String? get path => _path;
  @override
  Future<void> initialize() async {
    await channel
        .invokeMethod<Object?>('init', {'source': source})
        .timeout(const Duration(seconds: 5));
    final stats = await channel
        .invokeMapMethod<String, Object?>('stats')
        .timeout(const Duration(seconds: 5));
    _path = stats?['path'] as String?;
  }

  @override
  Future<void> write(Map<String, Object?> event) async {
    final written = await channel
        .invokeMethod<bool>('write', {'source': source, 'event': event})
        .timeout(const Duration(seconds: 2));
    if (written == false) {
      throw const FileSystemException('Diagnostic write failed');
    }
  }

  @override
  Future<List<Map<String, Object?>>> snapshot() async {
    final rows =
        await channel
            .invokeListMethod<Object?>('snapshot')
            .timeout(const Duration(seconds: 5)) ??
        [];
    return rows.map((row) {
      final decoded = row is String ? jsonDecode(row) : row;
      return Map<String, Object?>.from(decoded as Map);
    }).toList();
  }

  @override
  Future<int> bytes() async =>
      (await channel
              .invokeMapMethod<String, Object?>('stats')
              .timeout(const Duration(seconds: 5)))?['bytes']
          as int? ??
      0;
  @override
  Future<int> clear() async =>
      await channel
          .invokeMethod<int>('clear')
          .timeout(const Duration(seconds: 5)) ??
      0;
  @override
  Future<void> prune() =>
      channel.invokeMethod<void>('prune').timeout(const Duration(seconds: 5));
  @override
  Future<void> flush() => prune();
}

/// Fixed slots include the current file. Every action is serialized, including
/// read/clear/prune, so a snapshot cannot observe a partly rotated file.
class FileDiagnosticStorage extends DiagnosticStorage {
  FileDiagnosticStorage(this.directory, this.source, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final Directory directory;
  final String source;
  final DateTime Function() _now;
  static final Map<String, Future<void>> _tails = {};
  int get slots => source == 'foreground' ? 4 : 2;
  @override
  String get path => directory.path;
  File _slot(int i) => File('${directory.path}/$source-$i.jsonl');
  Future<T> _serial<T>(Future<T> Function() action) {
    final key = directory.absolute.path;
    final result = (_tails[key] ?? Future<void>.value()).then((_) => action());
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[key] = settled;
    unawaited(
      settled.whenComplete(() {
        if (identical(_tails[key], settled)) _tails.remove(key);
      }),
    );
    return result;
  }

  @override
  Future<void> initialize() => _serial(() async {
    await directory.create(recursive: true);
    await _prune();
  });
  @override
  Future<void> write(Map<String, Object?> event) => _serial(() async {
    await directory.create(recursive: true);
    await _prune();
    final data = utf8.encode('${jsonEncode(event)}\n');
    if (data.length > 16 * 1024) return;
    final current = _slot(0);
    if (await current.exists()) {
      final stat = await current.stat();
      final now = _now();
      final previous = stat.modified.toLocal();
      final sameDay =
          previous.year == now.year &&
          previous.month == now.month &&
          previous.day == now.day;
      if (stat.size + data.length > diagnosticFileBytes || !sameDay) {
        final oldest = _slot(slots - 1);
        if (await oldest.exists()) await oldest.delete();
        for (var i = slots - 2; i >= 0; i--) {
          final older = _slot(i);
          if (await older.exists()) await older.rename(_slot(i + 1).path);
        }
      }
    }
    await current.writeAsBytes(data, mode: FileMode.append, flush: true);
  });

  Future<void> _prune() async {
    if (!await directory.exists()) return;
    final cutoff = _now().subtract(diagnosticRetention);
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final match = RegExp(
        r'^(foreground|background|native)-(\d+)\.jsonl$',
      ).firstMatch(name);
      if (match == null) continue;
      final count = match[1] == 'foreground' ? 4 : 2;
      final stat = await entity.stat();
      if (int.parse(match[2]!) >= count ||
          stat.size > diagnosticFileBytes ||
          stat.modified.isBefore(cutoff)) {
        await entity.delete();
      }
    }
  }

  @override
  Future<void> prune() => _serial(_prune);
  @override
  Future<List<Map<String, Object?>>> snapshot() => _serial(() async {
    await _prune();
    final rows = <Map<String, Object?>>[];
    if (!await directory.exists()) return rows;
    final cutoff = _now().subtract(diagnosticRetention);
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          !RegExp(
            r'^(foreground|background|native)-[0-3]\.jsonl$',
          ).hasMatch(entity.uri.pathSegments.last)) {
        continue;
      }
      await for (final line
          in entity
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        try {
          final event = Map<String, Object?>.from(jsonDecode(line) as Map);
          final at = DateTime.tryParse(event['timestamp']?.toString() ?? '');
          if (at != null && !at.isBefore(cutoff)) rows.add(event);
        } catch (_) {
          /* Ignore only an incomplete/corrupt individual record. */
        }
      }
    }
    return rows;
  });
  @override
  Future<int> bytes() => _serial(() async {
    var total = 0;
    if (!await directory.exists()) return total;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File &&
          RegExp(
            r'^(foreground|background|native)-[0-3]\.jsonl$',
          ).hasMatch(entity.uri.pathSegments.last)) {
        total += await entity.length();
      }
    }
    return total;
  });
  @override
  Future<int> clear() => _serial(() async {
    var count = 0;
    if (!await directory.exists()) return count;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File &&
          RegExp(
            r'^(foreground|background|native)-\d+\.jsonl$',
          ).hasMatch(entity.uri.pathSegments.last)) {
        await entity.delete();
        count++;
      }
    }
    return count;
  });
}
