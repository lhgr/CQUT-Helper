import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show FlutterError, debugPrint, kDebugMode, kProfileMode, kReleaseMode;
import 'package:cqut/utils/local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LogLevel {
  debug(10),
  info(20),
  warn(30),
  error(40),
  fatal(50);

  const LogLevel(this.priority);
  final int priority;
}

enum LogExportKind { network, other, all }

class LogEvent {
  LogEvent({
    required this.at,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
    this.fields,
  });

  final DateTime at;
  final LogLevel level;
  final String tag;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, Object?>? fields;
}

abstract class LogSink {
  Future<void> emit(LogEvent event);
  Future<void> flush();
  Future<void> dispose();
}

class FilteredLogSink implements LogSink {
  FilteredLogSink({required this.inner, required this.predicate});
  final LogSink inner;
  final bool Function(LogEvent event) predicate;

  @override
  Future<void> emit(LogEvent event) async {
    if (!predicate(event)) return;
    await inner.emit(event);
  }

  @override
  Future<void> flush() => inner.flush();

  @override
  Future<void> dispose() => inner.dispose();
}

class ConsoleLogSink implements LogSink {
  @override
  Future<void> emit(LogEvent event) async {
    debugPrint(_formatLine(event));
    if (event.stackTrace != null) {
      debugPrint(event.stackTrace.toString());
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> dispose() async {}

  String _formatLine(LogEvent e) {
    final iso = e.at.toIso8601String();
    final base = '$iso [${e.level.name.toUpperCase()}] ${e.tag} - ${e.message}';
    final fields = e.fields;
    if (fields == null || fields.isEmpty) return base;
    return '$base ${_safeJson(fields)}';
  }
}

class FileLogSink implements LogSink {
  FileLogSink({
    required this.fileName,
    required this.maxBytes,
    required this.maxAge,
    required this.maxTotalBytes,
    required this.maxFiles,
    required this.enableGzipArchive,
    required this.directoryProvider,
    required this.onWriteError,
  });

  final String fileName;
  final int maxBytes;
  final Duration maxAge;
  final int maxTotalBytes;
  final int maxFiles;
  final bool enableGzipArchive;
  final Future<Directory> Function() directoryProvider;
  final void Function(Object error, StackTrace stackTrace) onWriteError;

  File? _file;
  RandomAccessFile? _raf;
  Future<void>? _opening;
  int _consecutiveWriteFailures = 0;
  DateTime? _disabledUntil;
  DateTime _lastFsyncAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _bytesSinceFsync = 0;

  @override
  Future<void> emit(LogEvent event) async {
    if (_raf == null) {
      await _ensureOpen();
    }
    if (_disabledUntil != null && DateTime.now().isBefore(_disabledUntil!)) {
      return;
    }
    final f0 = _file;
    if (f0 == null) return;

    await _rotateIfNeeded(f0);
    final raf = _raf;
    final f = _file;
    if (raf == null || f == null) return;

    final line = _formatLine(event);
    try {
      await raf.writeString('$line\n', encoding: utf8);
      _bytesSinceFsync += utf8.encode(line).length + 1;
      _consecutiveWriteFailures = 0;
      final now = DateTime.now();
      final mustFsync = event.level.priority >= LogLevel.error.priority;
      final fsyncDue =
          now.difference(_lastFsyncAt) >= const Duration(seconds: 2) ||
          _bytesSinceFsync >= 64 * 1024;
      if (mustFsync || fsyncDue) {
        await raf.flush();
        _lastFsyncAt = now;
        _bytesSinceFsync = 0;
      }
    } catch (e, st) {
      _consecutiveWriteFailures++;
      onWriteError(e, st);
      if (_consecutiveWriteFailures >= 3) {
        _disabledUntil = DateTime.now().add(const Duration(seconds: 30));
        await flush();
      }
    }
  }

  @override
  Future<void> flush() async {
    final raf = _raf;
    if (raf == null) return;
    try {
      await raf.flush();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    _file = null;
    final raf = _raf;
    _raf = null;
    if (raf != null) {
      try {
        await raf.flush();
      } catch (_) {}
      try {
        await raf.close();
      } catch (_) {}
    }
  }

  String? get currentPath => _file?.path;

  Future<void> _ensureOpen() async {
    if (_raf != null) return;
    final opening = _opening;
    if (opening != null) return opening;

    final future = _open();
    _opening = future;
    try {
      await future;
    } finally {
      _opening = null;
    }
  }

  Future<void> _open() async {
    final dir = await directoryProvider();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.parent.create(recursive: true);
    _file = file;
    _raf = await file.open(mode: FileMode.append);
  }

  Future<void> _rotateIfNeeded(File file) async {
    try {
      final stat = await file.stat();
      if (stat.size < maxBytes) return;
      await flush();
      final raf = _raf;
      _raf = null;
      if (raf != null) {
        try {
          await raf.close();
        } catch (_) {}
      }

      final base = fileName.replaceFirst(
        RegExp(r'\.log$', caseSensitive: false),
        '',
      );
      final ts = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[:\.]'),
        '-',
      );
      final rotated = File(
        '${file.parent.path}${Platform.pathSeparator}${base}_$ts.log',
      );
      await file.rename(rotated.path);

      unawaited(_finalizeRotated(rotated, base: base));

      await _open();
    } catch (_) {}
  }

  Future<void> _finalizeRotated(File rotated, {required String base}) async {
    try {
      if (enableGzipArchive) {
        final gz = File('${rotated.path}.gz');
        final out = gz.openWrite(mode: FileMode.write);
        try {
          await out.addStream(rotated.openRead().transform(gzip.encoder));
        } finally {
          try {
            await out.flush();
          } catch (_) {}
          await out.close();
        }
        try {
          await rotated.delete();
        } catch (_) {}
        await _writeSha256(gz);
      } else {
        await _writeSha256(rotated);
      }
    } catch (e, st) {
      onWriteError(e, st);
    }
    await _enforceRetention(base: base, dir: rotated.parent);
  }

  Future<void> _writeSha256(File f) async {
    final digest = await _sha256File(f);
    if (digest == null) return;
    final out = File('${f.path}.sha256');
    try {
      await out.writeAsString(digest, flush: true);
    } catch (_) {}
  }

  Future<String?> _sha256File(File f) async {
    try {
      final sink = _DigestSink();
      final conv = sha256.startChunkedConversion(sink);
      await for (final chunk in f.openRead()) {
        conv.add(chunk);
      }
      conv.close();
      final out = sink._out;
      return out?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _enforceRetention({
    required String base,
    required Directory dir,
  }) async {
    try {
      final cutoff = DateTime.now().subtract(maxAge);
      final candidates = <File>[];
      final logRegex = RegExp(
        '^${RegExp.escape(base)}_.*\\.log(\\.gz)?\$',
        caseSensitive: false,
      );
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = pBasename(entity.path);
        if (!logRegex.hasMatch(name)) continue;
        candidates.add(entity);
      }
      candidates.sort((a, b) => a.path.compareTo(b.path));

      for (final f in List<File>.from(candidates)) {
        try {
          final st = await f.stat();
          if (st.modified.isBefore(cutoff)) {
            await f.delete();
            candidates.remove(f);
            final sha = File('${f.path}.sha256');
            if (await sha.exists()) {
              try {
                await sha.delete();
              } catch (_) {}
            }
          }
        } catch (_) {}
      }

      while (candidates.length > maxFiles) {
        final f = candidates.removeAt(0);
        try {
          await f.delete();
        } catch (_) {}
        final sha = File('${f.path}.sha256');
        if (await sha.exists()) {
          try {
            await sha.delete();
          } catch (_) {}
        }
      }

      int total = 0;
      for (final f in candidates) {
        try {
          total += await f.length();
        } catch (_) {}
      }
      while (total > maxTotalBytes && candidates.isNotEmpty) {
        final f = candidates.removeAt(0);
        try {
          total -= await f.length();
        } catch (_) {}
        try {
          await f.delete();
        } catch (_) {}
        final sha = File('${f.path}.sha256');
        if (await sha.exists()) {
          try {
            await sha.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  String _formatLine(LogEvent e) {
    final iso = e.at.toIso8601String();
    final base = '$iso [${e.level.name.toUpperCase()}] ${e.tag} - ${e.message}';
    final fields = e.fields;
    if (fields == null || fields.isEmpty) return base;
    return '$base ${_safeJson(fields)}';
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? _out;
  @override
  void add(Digest data) {
    _out = data;
  }

  @override
  void close() {}
}

class LogMetricsSnapshot {
  LogMetricsSnapshot({
    required this.queueDepth,
    required this.queueCapacity,
    required this.enqueued,
    required this.emitted,
    required this.dropped,
    required this.writeErrors,
    required this.dropRate,
    required this.avgEmitMs,
    required this.p95EmitMs,
  });

  final int queueDepth;
  final int queueCapacity;
  final int enqueued;
  final int emitted;
  final int dropped;
  final int writeErrors;
  final double dropRate;
  final double avgEmitMs;
  final int p95EmitMs;
}

class _LogMetrics {
  int queueDepth = 0;
  int queueCapacity = 0;
  int enqueued = 0;
  int emitted = 0;
  int dropped = 0;
  int writeErrors = 0;

  double _emaEmitMs = 0;
  final ListQueue<int> _emitMsWindow = ListQueue();

  void recordEmitMs(int v) {
    const alpha = 0.1;
    _emaEmitMs = _emaEmitMs == 0
        ? v.toDouble()
        : _emaEmitMs * (1 - alpha) + v * alpha;
    _emitMsWindow.addLast(v);
    while (_emitMsWindow.length > 200) {
      _emitMsWindow.removeFirst();
    }
  }

  int p95EmitMs() {
    if (_emitMsWindow.isEmpty) return 0;
    final list = _emitMsWindow.toList()..sort();
    final idx = ((list.length - 1) * 0.95).round();
    return list[idx];
  }

  LogMetricsSnapshot snapshot() {
    final total = enqueued + dropped;
    final rate = total == 0 ? 0.0 : dropped / total;
    return LogMetricsSnapshot(
      queueDepth: queueDepth,
      queueCapacity: queueCapacity,
      enqueued: enqueued,
      emitted: emitted,
      dropped: dropped,
      writeErrors: writeErrors,
      dropRate: rate,
      avgEmitMs: _emaEmitMs,
      p95EmitMs: p95EmitMs(),
    );
  }
}

class _QueuedLogEvent {
  _QueuedLogEvent(this.event, this.enqueuedAt);
  final LogEvent event;
  final int enqueuedAt;
}

class _LogDispatcher {
  _LogDispatcher({
    required List<LogSink> sinks,
    required int capacity,
    required _LogMetrics metrics,
  }) : _sinks = sinks,
       _capacity = capacity,
       _metrics = metrics;

  final List<LogSink> _sinks;
  final int _capacity;
  final _LogMetrics _metrics;
  final ListQueue<_QueuedLogEvent> _q = ListQueue();
  bool _pumping = false;
  Completer<void>? _idleCompleter;

  void enqueue(LogEvent event) {
    _metrics.enqueued++;
    if (_q.length >= _capacity) {
      if (event.level.priority < LogLevel.warn.priority) {
        _metrics.dropped++;
        return;
      }
      final dropped = _dropOldestLowPriority() ?? _dropOldestAny();
      if (dropped != null) {
        _metrics.dropped++;
      }
    }
    _q.addLast(_QueuedLogEvent(event, DateTime.now().millisecondsSinceEpoch));
    _metrics.queueDepth = _q.length;
    _metrics.queueCapacity = _capacity;
    _idleCompleter ??= Completer<void>();
    if (_pumping) return;
    _pumping = true;
    scheduleMicrotask(_pump);
  }

  _QueuedLogEvent? _dropOldestLowPriority() {
    if (_q.isEmpty) return null;
    _QueuedLogEvent? dropped;
    final n = _q.length;
    for (int i = 0; i < n; i++) {
      final e = _q.removeFirst();
      if (dropped == null && e.event.level.priority < LogLevel.warn.priority) {
        dropped = e;
        continue;
      }
      _q.addLast(e);
    }
    return dropped;
  }

  _QueuedLogEvent? _dropOldestAny() {
    if (_q.isEmpty) return null;
    return _q.removeFirst();
  }

  Future<void> flush({Duration timeout = const Duration(seconds: 2)}) async {
    final c = _idleCompleter;
    if (c == null) {
      for (final s in _sinks) {
        await s.flush();
      }
      return;
    }
    try {
      await c.future.timeout(timeout);
    } catch (_) {}
    for (final s in _sinks) {
      await s.flush();
    }
  }

  Future<void> dispose() async {
    await flush(timeout: const Duration(seconds: 2));
    for (final s in _sinks) {
      await s.dispose();
    }
    _sinks.clear();
    _q.clear();
    _metrics.queueDepth = 0;
    _idleCompleter = null;
  }

  Future<void> _pump() async {
    while (_q.isNotEmpty) {
      final item = _q.removeFirst();
      _metrics.queueDepth = _q.length;
      final sw = Stopwatch()..start();
      for (final s in _sinks) {
        await s.emit(item.event);
      }
      sw.stop();
      _metrics.recordEmitMs(sw.elapsedMilliseconds);
      _metrics.emitted++;
    }
    _metrics.queueDepth = 0;
    final c = _idleCompleter;
    _idleCompleter = null;
    c?.complete();
    _pumping = false;
  }
}

class AppLogger {
  AppLogger._();
  static final AppLogger I = AppLogger._();

  LogLevel _minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;
  final ListQueue<LogEvent> _buffer = ListQueue();
  int _bufferSize = 400;
  FileLogSink? _fileSink;
  FileLogSink? _networkFileSink;
  List<LogSink> _fileSinkWrappers = const [];
  bool _initialized = false;
  String _fileName = 'cqut.log';
  String _networkFileName = 'cqut_net.log';
  int _maxFileBytes = 2 * 1024 * 1024;
  bool _enableFile = true;
  final String _exportDirName = 'exports';
  final String _downloadExportDirName = 'CQUT-Helper';
  final String _runtimeDirName = '.runtime';
  _LogDispatcher? _dispatcher;
  int _queueCapacity = 2000;
  int _maxFieldsChars = 4000;
  int _maxMessageChars = 2000;
  final _LogMetrics _metrics = _LogMetrics();
  final Object _traceZoneKey = Object();
  String? _integrityKey;
  DateTime _lastSinkErrorAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastAlertAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init({
    LogLevel? minLevel,
    bool enableConsole = true,
    bool enableFile = true,
    String fileName = 'cqut.log',
    int maxFileBytes = 2 * 1024 * 1024,
    int bufferSize = 400,
    int queueCapacity = 2000,
    int maxFieldsChars = 4000,
    int maxMessageChars = 2000,
    Duration maxAge = const Duration(days: 2),
    int maxFiles = 40,
    int maxTotalBytes = 64 * 1024 * 1024,
    bool enableGzipArchive = true,
    bool enableIntegrity = true,
  }) async {
    _minLevel = minLevel ?? _minLevel;
    _bufferSize = bufferSize;
    _fileName = fileName;
    _networkFileName = _deriveNetworkFileName(fileName);
    _maxFileBytes = maxFileBytes;
    _enableFile = enableFile;
    _queueCapacity = queueCapacity;
    _maxFieldsChars = maxFieldsChars;
    _maxMessageChars = maxMessageChars;
    if (enableIntegrity) {
      _integrityKey = await _loadOrCreateIntegrityKey();
    } else {
      _integrityKey = null;
    }

    await dispose();
    final sinks = <LogSink>[];
    if (enableConsole) sinks.add(ConsoleLogSink());
    if (enableFile) {
      final otherSink = FileLogSink(
        fileName: fileName,
        maxBytes: maxFileBytes,
        maxAge: maxAge,
        maxTotalBytes: maxTotalBytes,
        maxFiles: maxFiles,
        enableGzipArchive: enableGzipArchive,
        directoryProvider: _resolveRuntimeLogDirectory,
        onWriteError: _onSinkWriteError,
      );
      final netSink = FileLogSink(
        fileName: _networkFileName,
        maxBytes: maxFileBytes,
        maxAge: maxAge,
        maxTotalBytes: maxTotalBytes,
        maxFiles: maxFiles,
        enableGzipArchive: enableGzipArchive,
        directoryProvider: _resolveRuntimeLogDirectory,
        onWriteError: _onSinkWriteError,
      );
      _fileSink = otherSink;
      _networkFileSink = netSink;
      final wrappedOther = FilteredLogSink(
        inner: otherSink,
        predicate: (e) => !_isNetworkEvent(e),
      );
      final wrappedNet = FilteredLogSink(
        inner: netSink,
        predicate: _isNetworkEvent,
      );
      _fileSinkWrappers = [wrappedOther, wrappedNet];
      sinks.addAll(_fileSinkWrappers);
    }
    _dispatcher = _LogDispatcher(
      sinks: sinks,
      capacity: _queueCapacity,
      metrics: _metrics,
    );
    _initialized = true;
    info('Logger', 'initialized', fields: {'file': fileName});
    await flush(timeout: const Duration(seconds: 2));
  }

  Future<void> dispose() async {
    _fileSink = null;
    _networkFileSink = null;
    _fileSinkWrappers = const [];
    final d = _dispatcher;
    _dispatcher = null;
    if (d != null) {
      await d.dispose();
    }
    _initialized = false;
  }

  String? get logFilePath => _fileSink?.currentPath;
  String? get networkLogFilePath => _networkFileSink?.currentPath;

  List<LogEvent> get recent => List.unmodifiable(_buffer);

  LogMetricsSnapshot get metrics => _metrics.snapshot();

  String? get currentTraceId => Zone.current[_traceZoneKey] as String?;

  T runWithTraceId<T>(String traceId, T Function() fn) {
    return runZoned(fn, zoneValues: {_traceZoneKey: traceId});
  }

  Future<T> runWithTraceIdAsync<T>(String traceId, Future<T> Function() fn) {
    return runZoned(() {
      final f = fn();
      unawaited(
        f.catchError((Object e, StackTrace st) {
          fatal('Zone', e.toString(), error: e, stackTrace: st);
          throw e;
        }),
      );
      return f;
    }, zoneValues: {_traceZoneKey: traceId});
  }

  String newTraceId({int bytes = 16}) {
    final rnd = Random.secure();
    final buf = StringBuffer();
    for (int i = 0; i < bytes; i++) {
      final v = rnd.nextInt(256);
      buf.write(v.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  Future<void> flush({Duration timeout = const Duration(seconds: 2)}) async {
    final d = _dispatcher;
    if (d == null) return;
    await d.flush(timeout: timeout);
  }

  static bool _isNetworkEvent(LogEvent e) {
    final f = e.fields;
    if (f != null) {
      final v = f['net'];
      if (v == 1 || v == true) return true;
    }
    return false;
  }

  static String _deriveNetworkFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.startsWith('cqut_') && lower.endsWith('.log')) {
      return 'cqut_net_${fileName.substring(5)}';
    }
    if (lower == 'cqut.log') return 'cqut_net.log';
    return 'cqut_net_$fileName';
  }

  Future<int?> getLogBytes() async {
    try {
      final files = await _listLogFiles(includeExports: true);
      final exports = await _listExportFiles();
      int total = 0;
      for (final f in files) {
        try {
          total += await f.length();
        } catch (_) {}
      }
      for (final f in exports) {
        try {
          total += await f.length();
        } catch (_) {}
      }
      return total;
    } catch (_) {
      return null;
    }
  }

  Future<int> clearLogFiles() async {
    await _detachFileSink();
    try {
      final files = await _listLogFiles(includeExports: true);
      final exports = await _listExportFiles();
      int count = 0;
      for (final f in files) {
        try {
          await f.delete();
          count++;
        } catch (_) {}
        final sha = File('${f.path}.sha256');
        if (await sha.exists()) {
          try {
            await sha.delete();
          } catch (_) {}
        }
      }
      for (final f in exports) {
        try {
          await f.delete();
          count++;
        } catch (_) {}
      }
      return count;
    } finally {
      if (_enableFile) {
        await _ensureFileSink();
      }
    }
  }

  Future<void> pruneLogs({Duration maxAge = const Duration(days: 1)}) async {
    final cutoff = DateTime.now().subtract(maxAge);
    await _detachFileSink();
    try {
      final logFiles = await _listLogFiles(includeExports: false);
      for (final f in logFiles) {
        final name = pBasename(f.path).toLowerCase();
        if (name == _fileName.toLowerCase() ||
            name == _networkFileName.toLowerCase()) {
          continue;
        }
        try {
          final st = await f.stat();
          if (st.modified.isBefore(cutoff)) {
            await f.delete();
            final sha = File('${f.path}.sha256');
            if (await sha.exists()) {
              try {
                await sha.delete();
              } catch (_) {}
            }
          }
        } catch (_) {}
      }

      final currentOther = await _resolveCurrentLogFile(_fileName);
      if (await currentOther.exists()) {
        await _rewriteLogFileKeepingSince(currentOther, cutoff);
      }
      final currentNet = await _resolveCurrentLogFile(_networkFileName);
      if (await currentNet.exists()) {
        await _rewriteLogFileKeepingSince(currentNet, cutoff);
      }

      final exports = await _listExportFiles();
      for (final f in exports) {
        try {
          final st = await f.stat();
          if (st.modified.isBefore(cutoff)) {
            await f.delete();
          }
        } catch (_) {}
      }
    } finally {
      if (_enableFile) {
        await _ensureFileSink();
      }
    }
  }

  Future<String> exportLogs({int maxTotalBytes = 8 * 1024 * 1024}) async {
    return exportLogsWithKind(
      maxTotalBytes: maxTotalBytes,
      kind: LogExportKind.all,
    );
  }

  Future<String> exportLogsWithKind({
    required LogExportKind kind,
    int maxTotalBytes = 8 * 1024 * 1024,
  }) async {
    await flush(timeout: const Duration(seconds: 2));
    if (_enableFile) {
      await _ensureFileSink();
      await flush(timeout: const Duration(seconds: 2));
    }

    final dir = await _resolveExportDirectory();
    await dir.create(recursive: true);
    final ts = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:\.]'),
      '-',
    );
    final exportPath =
        '${dir.path}${Platform.pathSeparator}cqut_export_$ts.log';
    return exportLogsToPath(
      exportPath,
      kind: kind,
      maxTotalBytes: maxTotalBytes,
    );
  }

  Future<String> exportLogsToPath(
    String outputPath, {
    int maxTotalBytes = 8 * 1024 * 1024,
    LogExportKind kind = LogExportKind.all,
  }) async {
    await _detachFileSink();
    try {
      final outFile = File(outputPath);
      await outFile.parent.create(recursive: true);

      final currentOther = await _resolveCurrentLogFile(_fileName);
      final currentNet = await _resolveCurrentLogFile(_networkFileName);
      final currentOtherLower = currentOther.path.toLowerCase();
      final currentNetLower = currentNet.path.toLowerCase();
      final outputLower = outFile.path.toLowerCase();
      final otherBase = _logBaseName(_fileName).toLowerCase();
      final netBase = _logBaseName(_networkFileName).toLowerCase();
      final otherRegex = RegExp(
        '^${RegExp.escape(otherBase)}(_.*)?\\.log(\\.gz)?\$',
        caseSensitive: false,
      );
      final netRegex = RegExp(
        '^${RegExp.escape(netBase)}(_.*)?\\.log(\\.gz)?\$',
        caseSensitive: false,
      );
      final files = (await _listLogFiles(includeExports: false)).where((f) {
        final p = f.path.toLowerCase();
        if (p == outputLower) return false;
        final name = pBasename(p);
        if (name.startsWith('cqut_export')) return false;
        final isOther = otherRegex.hasMatch(name);
        final isNet = netRegex.hasMatch(name);
        if (!isOther && !isNet) return false;
        if (kind == LogExportKind.network && !isNet) return false;
        if (kind == LogExportKind.other && !isOther) return false;
        return true;
      }).toList()..sort((a, b) => a.path.compareTo(b.path));

      int written = 0;
      final sink = outFile.openWrite(mode: FileMode.write, encoding: utf8);
      try {
        try {
          final packageInfo = await PackageInfo.fromPlatform();
          sink.writeln('app_name=${packageInfo.appName}');
          sink.writeln('package_name=${packageInfo.packageName}');
          sink.writeln('version=${packageInfo.version}');
          sink.writeln('build_number=${packageInfo.buildNumber}');
          sink.writeln(
            'build_mode=${kReleaseMode
                ? 'release'
                : kProfileMode
                ? 'profile'
                : 'debug'}',
          );
          sink.writeln('os=${Platform.operatingSystem}');
          sink.writeln('os_version=${Platform.operatingSystemVersion}');
        } catch (_) {}
        sink.writeln('exported_at=${DateTime.now().toIso8601String()}');
        sink.writeln('export_kind=${kind.name}');
        sink.writeln('files=${files.length}');
        sink.writeln('');
        for (final f in files) {
          final pLower = f.path.toLowerCase();
          final isCurrent =
              pLower == currentOtherLower || pLower == currentNetLower;
          if (!isCurrent) {
            sink.writeln('===== ${pBasename(f.path)} =====');
          }
          final ok = await _verifySha256IfPresent(f);
          if (!ok) {
            sink.writeln('integrity=failed');
            unawaited(
              _maybeAlert(
                title: '日志完整性异常',
                body: pBasename(f.path),
                minInterval: const Duration(hours: 6),
              ),
            );
          }
          try {
            Stream<List<int>> bytes = f.openRead();
            if (f.path.toLowerCase().endsWith('.gz')) {
              bytes = bytes.transform(gzip.decoder);
            }
            final stream = bytes.transform(utf8.decoder);
            await for (final chunk in stream) {
              written += utf8.encode(chunk).length;
              if (written > maxTotalBytes) {
                sink.writeln('');
                sink.writeln('===== truncated =====');
                await sink.flush();
                return outFile.path;
              }
              sink.write(chunk);
            }
          } catch (_) {
            sink.writeln('<read_failed>');
          }
          sink.writeln('');
        }
        await sink.flush();
        return outFile.path;
      } finally {
        await sink.close();
      }
    } finally {
      if (_enableFile) {
        await _ensureFileSink();
      }
    }
  }

  Future<bool> _verifySha256IfPresent(File f) async {
    final sha = File('${f.path}.sha256');
    if (!await sha.exists()) return true;
    try {
      final expected = (await sha.readAsString()).trim();
      if (expected.isEmpty) return true;
      final actual = await _sha256HexFile(f);
      if (actual == null) return false;
      return expected == actual;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _sha256HexFile(File f) async {
    try {
      final sink = _DigestSink();
      final conv = sha256.startChunkedConversion(sink);
      await for (final chunk in f.openRead()) {
        conv.add(chunk);
      }
      conv.close();
      return sink._out?.toString();
    } catch (_) {
      return null;
    }
  }

  void debug(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    log(
      LogLevel.debug,
      tag,
      message,
      error: error,
      stackTrace: stackTrace,
      fields: fields,
    );
  }

  void info(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    log(
      LogLevel.info,
      tag,
      message,
      error: error,
      stackTrace: stackTrace,
      fields: fields,
    );
  }

  void warn(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    log(
      LogLevel.warn,
      tag,
      message,
      error: error,
      stackTrace: stackTrace,
      fields: fields,
    );
  }

  void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    log(
      LogLevel.error,
      tag,
      message,
      error: error,
      stackTrace: stackTrace,
      fields: fields,
    );
  }

  void fatal(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    log(
      LogLevel.fatal,
      tag,
      message,
      error: error,
      stackTrace: stackTrace,
      fields: fields,
    );
  }

  void log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    if (level.priority < _minLevel.priority) return;

    final event = _buildEvent(
      level: level,
      tag: tag,
      message: message,
      error: error,
      stackTrace: stackTrace,
      fields: fields,
    );

    _buffer.add(event);
    while (_buffer.length > _bufferSize) {
      _buffer.removeFirst();
    }

    final d = _dispatcher;
    if (d == null && !_initialized) {
      debugPrint(
        '${event.at.toIso8601String()} [${event.level.name.toUpperCase()}] ${event.tag} - ${event.message}',
      );
      return;
    }
    d?.enqueue(event);
    if (level == LogLevel.fatal) {
      unawaited(flush(timeout: const Duration(seconds: 2)));
      unawaited(
        _maybeAlert(
          title: '应用异常',
          body: '${event.tag}: ${event.message}',
          minInterval: const Duration(minutes: 10),
        ),
      );
    }
  }

  LogEvent _buildEvent({
    required LogLevel level,
    required String tag,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    final at = DateTime.now();
    final traceId = currentTraceId;

    final outFields = <String, Object?>{};
    if (fields != null && fields.isNotEmpty) {
      outFields.addAll(_sanitizeFields(fields));
    }
    if (traceId != null && !outFields.containsKey('trace_id')) {
      outFields['trace_id'] = traceId;
    }
    if (error != null && !outFields.containsKey('error')) {
      outFields['error'] = _redactString(error.toString());
    }
    if (stackTrace != null && !outFields.containsKey('stack')) {
      outFields['stack'] = stackTrace.toString();
    }
    if (_integrityKey != null && !outFields.containsKey('sig')) {
      final base = '$at|${level.name}|$tag|$message';
      outFields['sig'] = _hmacSig(base, _integrityKey!);
    }

    final msg = _truncate(_redactString(message), _maxMessageChars);
    final normalizedFields = outFields.isEmpty
        ? null
        : _truncateJsonObject(outFields, _maxFieldsChars);

    return LogEvent(
      at: at,
      level: level,
      tag: tag,
      message: msg,
      error: error,
      stackTrace: stackTrace,
      fields: normalizedFields,
    );
  }

  void _onSinkWriteError(Object error, StackTrace stackTrace) {
    _metrics.writeErrors++;
    final now = DateTime.now();
    if (now.difference(_lastSinkErrorAt) < const Duration(minutes: 1)) return;
    _lastSinkErrorAt = now;
    debugPrint(
      '${now.toIso8601String()} [WARN] Logger - sink_write_error ${_redactString(error.toString())}',
    );
    unawaited(
      _maybeAlert(
        title: '日志写入异常',
        body: _truncate(_redactString(error.toString()), 200),
        minInterval: const Duration(minutes: 30),
      ),
    );
  }

  Future<void> _maybeAlert({
    required String title,
    required String body,
    required Duration minInterval,
  }) async {
    if (!Platform.isAndroid) return;
    final now = DateTime.now();
    if (now.difference(_lastAlertAt) < minInterval) return;
    _lastAlertAt = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      const k = 'log_alert_last_at_v1';
      final last = prefs.getInt(k) ?? 0;
      if (last > 0 &&
          now.millisecondsSinceEpoch - last < minInterval.inMilliseconds) {
        return;
      }
      await prefs.setInt(k, now.millisecondsSinceEpoch);
    } catch (_) {}
    try {
      await LocalNotifications.showSystemAlert(title: title, body: body);
    } catch (_) {}
  }

  void installGlobalErrorHandlers() {
    FlutterError.onError = (details) {
      fatal(
        'FlutterError',
        details.exceptionAsString(),
        error: details.exception,
        stackTrace: details.stack,
        fields: {
          'library': details.library,
          'context': details.context?.toDescription(),
        },
      );
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      fatal(
        'PlatformDispatcher',
        error.toString(),
        error: error,
        stackTrace: stack,
      );
      return true;
    };
  }

  DioLogInterceptor dioInterceptor({
    String tag = 'HTTP',
    int maxBodyChars = 4000,
  }) {
    return DioLogInterceptor(
      logger: this,
      tag: tag,
      maxBodyChars: maxBodyChars,
    );
  }

  void attachToDio(Dio dio, {String tag = 'HTTP', int maxBodyChars = 4000}) {
    final exists = dio.interceptors.any((i) => i is DioLogInterceptor);
    if (exists) return;
    dio.interceptors.add(dioInterceptor(tag: tag, maxBodyChars: maxBodyChars));
  }

  Future<void> _detachFileSink() async {
    final other = _fileSink;
    final net = _networkFileSink;
    final wrappers = _fileSinkWrappers;
    _fileSink = null;
    _networkFileSink = null;
    _fileSinkWrappers = const [];
    if (wrappers.isNotEmpty) {
      _dispatcher?._sinks.removeWhere(
        (s) => wrappers.any((w) => identical(s, w)),
      );
    }
    if (other != null) await other.dispose();
    if (net != null) await net.dispose();
  }

  Future<void> _ensureFileSink() async {
    if (_fileSink != null && _networkFileSink != null) return;
    final d = _dispatcher;
    if (d == null) return;

    final otherSink = FileLogSink(
      fileName: _fileName,
      maxBytes: _maxFileBytes,
      maxAge: const Duration(days: 2),
      maxTotalBytes: 64 * 1024 * 1024,
      maxFiles: 40,
      enableGzipArchive: true,
      directoryProvider: _resolveRuntimeLogDirectory,
      onWriteError: _onSinkWriteError,
    );
    final netSink = FileLogSink(
      fileName: _networkFileName,
      maxBytes: _maxFileBytes,
      maxAge: const Duration(days: 2),
      maxTotalBytes: 64 * 1024 * 1024,
      maxFiles: 40,
      enableGzipArchive: true,
      directoryProvider: _resolveRuntimeLogDirectory,
      onWriteError: _onSinkWriteError,
    );
    _fileSink = otherSink;
    _networkFileSink = netSink;
    final wrappedOther = FilteredLogSink(
      inner: otherSink,
      predicate: (e) => !_isNetworkEvent(e),
    );
    final wrappedNet = FilteredLogSink(
      inner: netSink,
      predicate: _isNetworkEvent,
    );
    _fileSinkWrappers = [wrappedOther, wrappedNet];
    d._sinks.addAll(_fileSinkWrappers);
    info('Logger', 'file_sink_reopened');
  }

  Future<List<File>> _listLogFiles({required bool includeExports}) async {
    final docs = await getApplicationDocumentsDirectory();
    final runtimeDir = await _resolveRuntimeLogDirectory();
    final exportDir = await _resolveExportDirectory();

    final out = <File>[];
    final dirs = <String, Directory>{
      runtimeDir.path: runtimeDir,
      if (includeExports) exportDir.path: exportDir,
      if (includeExports) docs.path: docs,
    };
    if (includeExports) {
      dirs['${exportDir.path}${Platform.pathSeparator}$_runtimeDirName'] =
          Directory(
            '${exportDir.path}${Platform.pathSeparator}$_runtimeDirName',
          );
    }
    for (final d in dirs.values) {
      if (!await d.exists()) continue;
      await for (final entity in d.list(followLinks: false)) {
        if (entity is File) {
          final name = pBasename(entity.path);
          final lower = name.toLowerCase();
          if (!lower.startsWith('cqut')) continue;
          final isLog = lower.endsWith('.log') || lower.endsWith('.log.gz');
          if (!isLog) continue;
          if (!includeExports && lower.startsWith('cqut_export')) continue;
          out.add(entity);
        }
      }
    }

    if (includeExports) {
      final exportDir = Directory(
        '${docs.path}${Platform.pathSeparator}$_exportDirName',
      );
      if (await exportDir.exists()) {
        final exportRegex = RegExp(
          r'^cqut.*_export_.*\.txt$',
          caseSensitive: false,
        );
        await for (final entity in exportDir.list(followLinks: false)) {
          if (entity is File) {
            final name = pBasename(entity.path);
            if (exportRegex.hasMatch(name)) out.add(entity);
          }
        }
      }
    }

    return out;
  }

  Future<List<File>> _listExportFiles() async {
    final docs = await getApplicationDocumentsDirectory();
    final exportRegex = RegExp(
      r'^cqut.*_export_.*\.txt$',
      caseSensitive: false,
    );

    final out = <File>[];

    final legacyDir = Directory(
      '${docs.path}${Platform.pathSeparator}$_exportDirName',
    );
    if (await legacyDir.exists()) {
      await for (final entity in legacyDir.list(followLinks: false)) {
        if (entity is File) {
          final name = pBasename(entity.path);
          if (exportRegex.hasMatch(name)) out.add(entity);
        }
      }
    }

    final downloadDir = await _resolveDownloadExportDirectory();
    if (await downloadDir.exists()) {
      await for (final entity in downloadDir.list(followLinks: false)) {
        if (entity is File) {
          final name = pBasename(entity.path);
          if (exportRegex.hasMatch(name)) out.add(entity);
        }
      }
    }

    return out;
  }

  Future<Directory> _resolveExportDirectory() async {
    if (Platform.isAndroid) {
      final candidates = <String>[
        '${Platform.pathSeparator}storage${Platform.pathSeparator}emulated${Platform.pathSeparator}0${Platform.pathSeparator}Download',
        '${Platform.pathSeparator}storage${Platform.pathSeparator}emulated${Platform.pathSeparator}0${Platform.pathSeparator}Downloads',
      ];
      for (final c in candidates) {
        final d = Directory(c);
        if (await d.exists()) {
          return Directory(
            '${d.path}${Platform.pathSeparator}$_downloadExportDirName${Platform.pathSeparator}log',
          );
        }
      }
      return Directory(
        '${candidates.first}${Platform.pathSeparator}$_downloadExportDirName${Platform.pathSeparator}log',
      );
    }

    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return Directory(
        '${downloads.path}${Platform.pathSeparator}$_downloadExportDirName${Platform.pathSeparator}log',
      );
    }

    final docs = await getApplicationDocumentsDirectory();
    return Directory(
      '${docs.path}${Platform.pathSeparator}$_downloadExportDirName${Platform.pathSeparator}log',
    );
  }

  Future<Directory> _resolveRuntimeLogDirectory() async {
    final exportDir = await getApplicationDocumentsDirectory();
    return Directory(
      '${exportDir.path}${Platform.pathSeparator}$_runtimeDirName',
    );
  }

  Future<Directory> _resolveDownloadExportDirectory() async {
    return _resolveExportDirectory();
  }

  Future<File> _resolveCurrentLogFile([String? fileName]) async {
    final dir = await _resolveRuntimeLogDirectory();
    return File('${dir.path}${Platform.pathSeparator}${fileName ?? _fileName}');
  }

  Future<void> _rewriteLogFileKeepingSince(File file, DateTime cutoff) async {
    final tmp = File('${file.path}.tmp');
    await tmp.parent.create(recursive: true);

    final out = tmp.openWrite(mode: FileMode.write, encoding: utf8);
    bool keepBlock = false;
    try {
      final lines = file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        final ts = _tryParseLogLineTimestamp(line);
        if (ts != null) {
          keepBlock = !ts.isBefore(cutoff);
        }
        if (keepBlock) {
          out.writeln(line);
        }
      }
      await out.flush();
    } catch (_) {
      await out.flush();
    } finally {
      await out.close();
    }

    try {
      await file.delete();
    } catch (_) {}
    try {
      await tmp.rename(file.path);
    } catch (_) {
      try {
        final bytes = await tmp.readAsBytes();
        await file.writeAsBytes(bytes, flush: true);
        await tmp.delete();
      } catch (_) {}
    }
  }
}

DateTime? _tryParseLogLineTimestamp(String line) {
  final i = line.indexOf(' ');
  if (i <= 0) return null;
  final head = line.substring(0, i);
  return DateTime.tryParse(head);
}

String _logBaseName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.log')) return fileName.substring(0, fileName.length - 4);
  return fileName;
}

String pBasename(String path) {
  final sep = Platform.pathSeparator;
  final i = path.lastIndexOf(sep);
  if (i < 0) return path;
  return path.substring(i + 1);
}

class DioLogInterceptor extends Interceptor {
  DioLogInterceptor({
    required this.logger,
    required this.tag,
    required this.maxBodyChars,
  });

  final AppLogger logger;
  final String tag;
  final int maxBodyChars;

  static const _startKey = '__log_start';
  static const _traceKey = '__log_trace_id';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now().millisecondsSinceEpoch;
    final headerTrace =
        options.headers['x-trace-id'] ?? options.headers['X-Trace-Id'];
    final traceId =
        headerTrace?.toString() ?? logger.currentTraceId ?? logger.newTraceId();
    options.headers['x-trace-id'] = traceId;
    options.extra[_traceKey] = traceId;
    logger.debug(
      tag,
      '${options.method} ${options.uri}',
      fields: {'net': 1, 'type': 'request', 'trace_id': traceId},
    );
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final ms = _elapsedMs(response.requestOptions);
    final status = response.statusCode ?? 0;
    final traceId = _traceId(response.requestOptions);
    final ok = status >= 200 && status < 400;
    final level = status >= 500
        ? LogLevel.error
        : status >= 400
        ? LogLevel.warn
        : LogLevel.info;

    logger.log(
      level,
      tag,
      '${response.requestOptions.method} ${response.realUri}',
      fields: {
        'net': 1,
        'type': 'response',
        if (traceId != null) 'trace_id': traceId,
        'ok': ok,
        'status': status,
        if (ms != null) 'duration_ms': ms,
      },
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final ms = _elapsedMs(err.requestOptions);
    final status = err.response?.statusCode;
    final traceId = _traceId(err.requestOptions);
    final msgMax = maxBodyChars < 200 ? maxBodyChars : 200;
    logger.error(
      tag,
      '${err.requestOptions.method} ${err.requestOptions.uri}',
      error: err,
      stackTrace: err.stackTrace,
      fields: {
        'net': 1,
        'type': 'error',
        if (traceId != null) 'trace_id': traceId,
        'ok': false,
        if (status != null) 'status': status,
        if (ms != null) 'duration_ms': ms,
        'dio_type': err.type.name,
        if (err.message != null)
          'message': _sanitizeObject(err.message, msgMax),
      },
    );
    handler.next(err);
  }

  int? _elapsedMs(RequestOptions options) {
    final start = options.extra[_startKey];
    if (start is int) {
      return DateTime.now().millisecondsSinceEpoch - start;
    }
    return null;
  }

  String? _traceId(RequestOptions options) {
    final v = options.extra[_traceKey];
    if (v is String) return v;
    final h = options.headers['x-trace-id'] ?? options.headers['X-Trace-Id'];
    return h?.toString();
  }

  static Object? _sanitizeObject(Object? value, int maxChars) {
    final sanitized = _sanitizeSecrets(value);
    final str = _safeJson(sanitized);
    if (str.length <= maxChars) return sanitized;
    return '${str.substring(0, maxChars)}…(${str.length})';
  }

  static Object? _sanitizeSecrets(Object? value) {
    if (value == null) return null;
    if (value is String) return _maskTokenLike(value);
    if (value is num || value is bool) return value;
    if (value is List) {
      return value.map(_sanitizeSecrets).toList();
    }
    if (value is Map) {
      final out = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final lower = key.toLowerCase();
        if (lower.contains('password') ||
            lower == 'pwd' ||
            lower == 'pass' ||
            lower.contains('token') ||
            lower.contains('secret') ||
            lower.contains('cookie')) {
          out[key] = '<redacted>';
        } else {
          out[key] = _sanitizeSecrets(entry.value);
        }
      }
      return out;
    }
    return value.toString();
  }

  static String _maskTokenLike(String s) {
    if (s.length <= 10) return s;
    final lower = s.toLowerCase();
    if (lower.startsWith('bearer ')) return 'Bearer <redacted>';
    if (lower.contains('eyj') && s.length > 40) return '<jwt:redacted>';
    return s;
  }
}

String _safeJson(Object? value) {
  try {
    return jsonEncode(value);
  } catch (_) {
    return jsonEncode(value?.toString());
  }
}

String _truncate(String s, int maxChars) {
  if (s.length <= maxChars) return s;
  return '${s.substring(0, maxChars)}…(${s.length})';
}

String _redactString(String s) {
  final lower = s.toLowerCase();
  if (lower.startsWith('bearer ')) return 'Bearer <redacted>';
  if (lower.contains('eyj') && s.length > 40) return '<jwt:redacted>';
  return s;
}

Map<String, Object?> _sanitizeFields(Map<String, Object?> fields) {
  Object? walk(Object? value, {String? key}) {
    if (key != null) {
      final lk = key.toLowerCase();
      if (lk.contains('password') ||
          lk == 'pwd' ||
          lk == 'pass' ||
          lk.contains('token') ||
          lk.contains('secret') ||
          lk.contains('cookie') ||
          lk == 'authorization' ||
          lk == 'set-cookie' ||
          lk == 'x-auth-token' ||
          lk == 'x-csrf-token') {
        return '<redacted>';
      }
    }
    if (value == null) return null;
    if (value is String) return _redactString(value);
    if (value is num || value is bool) return value;
    if (value is List) return value.map((e) => walk(e)).toList();
    if (value is Map) {
      final out = <String, Object?>{};
      for (final entry in value.entries) {
        final k = entry.key.toString();
        out[k] = walk(entry.value, key: k);
      }
      return out;
    }
    return _redactString(value.toString());
  }

  final out = <String, Object?>{};
  for (final entry in fields.entries) {
    out[entry.key] = walk(entry.value, key: entry.key);
  }
  return out;
}

Map<String, Object?> _truncateJsonObject(
  Map<String, Object?> obj,
  int maxChars,
) {
  final json = _safeJson(obj);
  if (json.length <= maxChars) return obj;
  return <String, Object?>{
    'truncated': true,
    'preview': _truncate(json, maxChars),
    'len': json.length,
  };
}

String _hmacSig(String data, String key) {
  final h = Hmac(sha256, utf8.encode(key));
  final d = h.convert(utf8.encode(data));
  return base64UrlEncode(d.bytes);
}

Future<String?> _loadOrCreateIntegrityKey() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    const k = 'log_integrity_key_v1';
    final existing = prefs.getString(k);
    if (existing != null && existing.isNotEmpty) return existing;
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    final v = base64UrlEncode(bytes);
    await prefs.setString(k, v);
    return v;
  } catch (_) {
    return null;
  }
}
