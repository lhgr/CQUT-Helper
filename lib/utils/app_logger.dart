import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show
        FlutterError,
        FlutterErrorDetails,
        debugPrint,
        kDebugMode,
        kProfileMode,
        kReleaseMode,
        visibleForTesting;
import 'package:cqut_helper/utils/local_notifications.dart';
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
    required this.sessionId,
    required this.eventId,
    required this.sequence,
    this.error,
    this.stackTrace,
    this.fields,
  });

  final DateTime at;
  final LogLevel level;
  final String tag;
  final String message;
  final String sessionId;
  final String eventId;
  final int sequence;
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
    final fields = e.fields == null
        ? null
        : (Map<String, Object?>.from(e.fields!)..remove('stack'));
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
  final Set<Future<void>> _pendingFinalizers = {};
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
    final pending = _pendingFinalizers.toList(growable: false);
    if (pending.isNotEmpty) {
      try {
        await Future.wait(pending);
      } catch (_) {}
    }
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
    final pending = _pendingFinalizers.toList(growable: false);
    if (pending.isNotEmpty) {
      try {
        await Future.wait(pending);
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

      final f = _finalizeRotated(rotated, base: base);
      _pendingFinalizers.add(f);
      unawaited(
        f.whenComplete(() {
          _pendingFinalizers.remove(f);
        }),
      );

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
  String _sessionId = '';
  int _sequence = 0;
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

    await dispose();
    _sessionId = newTraceId(bytes: 8);
    _sequence = 0;
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
    info('Logger', 'initialized', fields: {'file': fileName, 'log_schema': 2});
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

  String get sessionId => _ensureSessionId();

  String? get currentTraceId => Zone.current[_traceZoneKey] as String?;

  T runWithTraceId<T>(String traceId, T Function() fn) {
    return runZoned(fn, zoneValues: {_traceZoneKey: traceId});
  }

  Future<T> runWithTraceIdAsync<T>(String traceId, Future<T> Function() fn) {
    return runZoned(() async {
      try {
        return await fn();
      } catch (e, st) {
        fatal('Zone', e.toString(), error: e, stackTrace: st);
        rethrow;
      }
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

  String _ensureSessionId() {
    if (_sessionId.isEmpty) {
      _sessionId = newTraceId(bytes: 8);
    }
    return _sessionId;
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
      for (final f in _uniqueFiles(<File>[...files, ...exports])) {
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
      for (final f in _uniqueFiles(<File>[...files, ...exports])) {
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
    await flush(timeout: const Duration(seconds: 2));
    await _detachFileSink();
    try {
      final outFile = File(outputPath);
      await outFile.parent.create(recursive: true);

      final currentOther = await _resolveCurrentLogFile(_fileName);
      final currentNet = await _resolveCurrentLogFile(_networkFileName);
      final currentOtherLower = currentOther.path.toLowerCase();
      final currentNetLower = currentNet.path.toLowerCase();
      final outputLower = outFile.path.toLowerCase();
      final files =
          (await _listLogFiles(includeExports: false)).where((f) {
            final p = f.path.toLowerCase();
            if (p == outputLower) return false;
            return debugIsLogFileSelectedForExport(
              fileName: pBasename(p),
              primaryFileName: _fileName,
              networkFileName: _networkFileName,
              kind: kind,
            );
          }).toList()..sort((a, b) {
            final byTime = _lastModifiedMillis(
              b,
            ).compareTo(_lastModifiedMillis(a));
            return byTime != 0 ? byTime : b.path.compareTo(a.path);
          });
      final nativeWidgetLogFiles = files
          .where((file) => debugIsNativeWidgetLogFile(pBasename(file.path)))
          .length;

      final summary = await _buildExportSummary(files);
      final logMetrics = metrics;
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
        sink.writeln('log_schema=2');
        sink.writeln('log_session_id=$sessionId');
        sink.writeln('file_order=newest_first');
        sink.writeln('entry_order=oldest_first');
        sink.writeln('files=${files.length}');
        sink.writeln('widget_native_log_files=$nativeWidgetLogFiles');
        sink.writeln('logger_queue_depth=${logMetrics.queueDepth}');
        sink.writeln('logger_dropped=${logMetrics.dropped}');
        sink.writeln('logger_write_errors=${logMetrics.writeErrors}');
        sink.writeln('logger_p95_emit_ms=${logMetrics.p95EmitMs}');
        sink.writeln('');
        sink.writeln('===== summary =====');
        for (final line in summary.toLines()) {
          sink.writeln(line);
        }
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

  Future<_ExportSummary> _buildExportSummary(List<File> files) async {
    final summary = _ExportSummary();
    for (final f in files) {
      try {
        Stream<List<int>> bytes = f.openRead();
        if (f.path.toLowerCase().endsWith('.gz')) {
          bytes = bytes.transform(gzip.decoder);
        }
        final lines = bytes
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        await for (final line in lines) {
          summary.consume(line);
        }
      } catch (_) {}
    }
    return summary;
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

  void event(
    LogLevel level,
    String tag, {
    required String event,
    required String messageZh,
    String? message,
    String? module,
    String? action,
    String? status,
    String? reason,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    final mergedFields = <String, Object?>{
      'event': event,
      'message_zh': messageZh,
      if (module != null && module.isNotEmpty) 'module': module,
      if (action != null && action.isNotEmpty) 'action': action,
      if (status != null && status.isNotEmpty) 'status': status,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      ...?fields,
    };
    log(
      level,
      tag,
      message ?? event,
      error: error,
      stackTrace: stackTrace,
      fields: mergedFields,
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
    final activeSessionId = _ensureSessionId();
    final sequence = ++_sequence;
    final eventId =
        '$activeSessionId-${sequence.toRadixString(36).padLeft(4, '0')}';
    final sanitizedMessage = _truncate(
      _redactString(message),
      _maxMessageChars,
    );

    final userFields = <String, Object?>{};
    if (fields != null && fields.isNotEmpty) {
      userFields.addAll(_sanitizeFields(fields));
    }
    userFields.remove('schema');
    userFields.remove('session_id');
    userFields.remove('event_id');
    userFields.remove('sequence');
    final outFields = <String, Object?>{
      'schema': 2,
      'session_id': activeSessionId,
      'event_id': eventId,
      'sequence': sequence,
      ...userFields,
    };
    if (traceId != null && !outFields.containsKey('trace_id')) {
      outFields['trace_id'] = traceId;
    }
    if (error != null && !outFields.containsKey('error')) {
      outFields['error'] = _redactString(error.toString());
    }
    if (stackTrace != null && !outFields.containsKey('stack')) {
      outFields['stack'] = stackTrace.toString();
    }
    if (error != null && !outFields.containsKey('error_type')) {
      outFields['error_type'] = error.runtimeType.toString();
    }
    if (level.priority >= LogLevel.warn.priority &&
        !outFields.containsKey('fingerprint')) {
      outFields['fingerprint'] = _issueFingerprint(
        tag: tag,
        message: sanitizedMessage,
        error: error,
        stackTrace: stackTrace,
        fields: outFields,
      );
    }

    final normalizedFields = outFields.isEmpty
        ? null
        : _truncateJsonObject(outFields, _maxFieldsChars);

    return LogEvent(
      at: at,
      level: level,
      tag: tag,
      message: sanitizedMessage,
      sessionId: activeSessionId,
      eventId: eventId,
      sequence: sequence,
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
      if (_isRecoverableNetworkImageError(details)) {
        warn(
          'FlutterImage',
          details.exceptionAsString(),
          error: details.exception,
          stackTrace: details.stack,
          fields: {
            'library': details.library,
            'context': details.context?.toDescription(),
            'recoverable': true,
          },
        );
        return;
      }
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

  bool _isRecoverableNetworkImageError(FlutterErrorDetails details) {
    if (details.library != 'image resource service') return false;
    final context = details.context?.toDescription().toLowerCase() ?? '';
    if (!context.contains('image failed')) return false;
    final error = details.exceptionAsString().toLowerCase();
    return error.contains('clientexception') ||
        error.contains('socketexception') ||
        error.contains('failed host lookup') ||
        error.contains('connection closed') ||
        error.contains('connection reset') ||
        error.contains('timed out');
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
          if (!debugIsLogFileDiscovered(
            fileName: name,
            includeExports: includeExports,
          )) {
            continue;
          }
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

  List<File> _uniqueFiles(Iterable<File> files) {
    final seen = <String>{};
    final result = <File>[];
    for (final file in files) {
      final absolutePath = file.absolute.path;
      final key = Platform.isWindows
          ? absolutePath.toLowerCase()
          : absolutePath;
      if (seen.add(key)) result.add(file);
    }
    return result;
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

@visibleForTesting
bool debugIsLogFileSelectedForExport({
  required String fileName,
  required String primaryFileName,
  required String networkFileName,
  required LogExportKind kind,
}) {
  final name = fileName.toLowerCase();
  if (name.startsWith('cqut_export')) return false;
  final otherBase = _logBaseName(primaryFileName).toLowerCase();
  final netBase = _logBaseName(networkFileName).toLowerCase();
  final otherRegex = RegExp(
    '^${RegExp.escape(otherBase)}(_.*)?\\.log(\\.gz)?\$',
    caseSensitive: false,
  );
  final netRegex = RegExp(
    '^${RegExp.escape(netBase)}(_.*)?\\.log(\\.gz)?\$',
    caseSensitive: false,
  );
  final isNetwork = netRegex.hasMatch(name);
  final isOther =
      (otherRegex.hasMatch(name) && !isNetwork) ||
      debugIsNativeWidgetLogFile(name);
  return switch (kind) {
    LogExportKind.network => isNetwork,
    LogExportKind.other => isOther,
    LogExportKind.all => isOther || isNetwork,
  };
}

@visibleForTesting
bool debugIsNativeWidgetLogFile(String fileName) {
  return RegExp(
    r'^cqut_widget(?:_\d+)?\.log(?:\.gz)?$',
    caseSensitive: false,
  ).hasMatch(fileName);
}

@visibleForTesting
bool debugIsLogFileDiscovered({
  required String fileName,
  required bool includeExports,
}) {
  final lower = fileName.toLowerCase();
  if (!lower.startsWith('cqut')) return false;
  if (!lower.endsWith('.log') && !lower.endsWith('.log.gz')) return false;
  return includeExports || !lower.startsWith('cqut_export');
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

int _lastModifiedMillis(File file) {
  try {
    return file.lastModifiedSync().millisecondsSinceEpoch;
  } catch (_) {
    return 0;
  }
}

class _SuppressedNetError {
  _SuppressedNetError({
    required this.signature,
    required this.windowStartedAt,
    required this.lastAt,
  });

  final String signature;
  final DateTime windowStartedAt;
  DateTime lastAt;
  int count = 1;
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
  final Map<String, _SuppressedNetError> _suppressedErrors = {};

  static const _startKey = '__log_start';
  static const _traceKey = '__log_trace_id';
  static const _requestKey = '__log_request_id';
  static const _dedupeWindow = Duration(seconds: 15);
  static const _dedupeSummaryThreshold = 3;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now().millisecondsSinceEpoch;
    final headerTrace =
        options.headers['x-trace-id'] ?? options.headers['X-Trace-Id'];
    final traceId =
        headerTrace?.toString() ?? logger.currentTraceId ?? logger.newTraceId();
    final requestId = logger.newTraceId(bytes: 8);
    options.headers['x-trace-id'] = traceId;
    options.extra[_traceKey] = traceId;
    options.extra[_requestKey] = requestId;
    final safeUri = sanitizeUriForLogging(options.uri);
    logger.debug(
      tag,
      '${options.method} $safeUri',
      fields: {
        'net': 1,
        'type': 'request',
        'method': options.method,
        'uri': safeUri,
        if (options.uri.queryParameters.isNotEmpty)
          'query_keys': options.uri.queryParameters.keys.toList()..sort(),
        'trace_id': traceId,
        'request_id': requestId,
      },
    );
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final ms = _elapsedMs(response.requestOptions);
    final status = response.statusCode ?? 0;
    final traceId = _traceId(response.requestOptions);
    final requestId = _requestId(response.requestOptions);
    final safeUri = sanitizeUriForLogging(response.realUri);
    final ok = status >= 200 && status < 400;
    final level = status >= 500
        ? LogLevel.error
        : status >= 400
        ? LogLevel.warn
        : LogLevel.info;

    logger.log(
      level,
      tag,
      '${response.requestOptions.method} $safeUri',
      fields: {
        'net': 1,
        'type': 'response',
        'method': response.requestOptions.method,
        'uri': safeUri,
        'trace_id': ?traceId,
        'request_id': ?requestId,
        'ok': ok,
        'status': status,
        'duration_ms': ?ms,
      },
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final ms = _elapsedMs(err.requestOptions);
    final status = err.response?.statusCode;
    final traceId = _traceId(err.requestOptions);
    final requestId = _requestId(err.requestOptions);
    final safeUri = sanitizeUriForLogging(err.requestOptions.uri);
    final msgMax = maxBodyChars < 200 ? maxBodyChars : 200;
    final now = DateTime.now();
    final signature = _errorSignature(err);
    final suppression = _suppressedErrors[signature];
    if (suppression != null &&
        now.difference(suppression.windowStartedAt) <= _dedupeWindow) {
      suppression.count += 1;
      suppression.lastAt = now;
      if (suppression.count == _dedupeSummaryThreshold) {
        logger.warn(
          tag,
          'suppressed repeated network errors',
          fields: {
            'net': 1,
            'type': 'error_summary',
            'suppressed': suppression.count - 1,
            'window_seconds': _dedupeWindow.inSeconds,
            'signature': suppression.signature,
            'method': err.requestOptions.method,
            'uri': safeUri,
            'dio_type': err.type.name,
            'status': ?status,
            if (err.message != null)
              'message': _sanitizeObject(err.message, msgMax),
          },
        );
      }
      handler.next(err);
      return;
    }

    _suppressedErrors[signature] = _SuppressedNetError(
      signature: signature,
      windowStartedAt: now,
      lastAt: now,
    );
    _pruneSuppressedErrors(now);

    logger.error(
      tag,
      '${err.requestOptions.method} $safeUri',
      error: err,
      stackTrace: err.stackTrace,
      fields: {
        'net': 1,
        'type': 'error',
        'method': err.requestOptions.method,
        'uri': safeUri,
        'trace_id': ?traceId,
        'request_id': ?requestId,
        'ok': false,
        'status': ?status,
        'duration_ms': ?ms,
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

  String _errorSignature(DioException err) {
    final method = err.requestOptions.method;
    final uri = err.requestOptions.uri;
    final status = err.response?.statusCode?.toString() ?? '-';
    final dioType = err.type.name;
    return '$tag|$method|${sanitizeUriForLogging(uri)}|$status|$dioType';
  }

  void _pruneSuppressedErrors(DateTime now) {
    _suppressedErrors.removeWhere(
      (_, value) => now.difference(value.lastAt) > _dedupeWindow,
    );
  }

  String? _traceId(RequestOptions options) {
    final v = options.extra[_traceKey];
    if (v is String) return v;
    final h = options.headers['x-trace-id'] ?? options.headers['X-Trace-Id'];
    return h?.toString();
  }

  String? _requestId(RequestOptions options) {
    final v = options.extra[_requestKey];
    if (v is String) return v;
    return null;
  }

  static Object? _sanitizeObject(Object? value, int maxChars) {
    final sanitized = _sanitizeSecrets(value);
    final str = _safeJson(sanitized);
    if (str.length <= maxChars) return sanitized;
    return '${str.substring(0, maxChars)}...(length=${str.length})';
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
    return _redactString(s);
  }
}

class _ExportSummary {
  int errors = 0;
  int fatals = 0;
  int warnings = 0;
  int networkErrors = 0;
  int errorSummaries = 0;
  int timeInfoRefreshFailures = 0;
  int scheduleUpdateFailures = 0;
  int? slowestRequestMs;
  String? slowestRequestLabel;
  DateTime? latestErrorAt;
  String? latestErrorLabel;
  final Set<String> _sessions = {};
  final Set<String> _traces = {};
  final Map<String, _IssueAggregate> _issues = {};
  final Map<int, int> _networkStatuses = {};

  void consume(String line) {
    if (line.isEmpty) return;
    final parsed = _ParsedLogLine.tryParse(line);
    if (parsed == null) {
      _consumeLegacy(line);
      return;
    }

    final fields = parsed.fields;
    final level = parsed.level;
    if (level == 'ERROR') errors += 1;
    if (level == 'FATAL') fatals += 1;
    if (level == 'WARN') warnings += 1;

    final sessionId = fields['session_id']?.toString();
    if (sessionId != null && sessionId.isNotEmpty) _sessions.add(sessionId);
    final traceId = fields['trace_id']?.toString();
    if (traceId != null && traceId.isNotEmpty) _traces.add(traceId);

    final isNetwork = fields['net'] == 1 || fields['net'] == true;
    final type = fields['type']?.toString();
    if (isNetwork && type == 'error') {
      networkErrors += 1;
    }
    if (isNetwork && type == 'error_summary') {
      errorSummaries += 1;
    }
    final status = _asInt(fields['status']);
    if (isNetwork && status != null) {
      _networkStatuses.update(status, (count) => count + 1, ifAbsent: () => 1);
    }

    final event = fields['event']?.toString();
    if (event == 'schedule_time_info_refresh_fail' ||
        parsed.message.contains('schedule_time_info_refresh_fail')) {
      timeInfoRefreshFailures += 1;
    }
    if (parsed.tag == 'ScheduleUpdate' && parsed.message == 'failure') {
      scheduleUpdateFailures += 1;
    }

    final duration = _asInt(fields['duration_ms']);
    if (duration != null &&
        (slowestRequestMs == null || duration > slowestRequestMs!)) {
      slowestRequestMs = duration;
      slowestRequestLabel = _requestLabel(parsed);
    }

    if (level == 'ERROR' || level == 'FATAL') {
      if (latestErrorAt == null ||
          (parsed.at != null && parsed.at!.isAfter(latestErrorAt!))) {
        latestErrorAt = parsed.at;
        latestErrorLabel = '${parsed.tag}: ${parsed.message}';
      }
    }

    if (level == 'WARN' || level == 'ERROR' || level == 'FATAL') {
      final rawFingerprint = fields['fingerprint']?.toString();
      final fingerprint = rawFingerprint == null || rawFingerprint.isEmpty
          ? sha256
                .convert(
                  utf8.encode(
                    '${parsed.tag}|${event ?? type ?? parsed.message}',
                  ),
                )
                .toString()
                .substring(0, 16)
          : rawFingerprint;
      final issue = _issues.putIfAbsent(
        fingerprint,
        () => _IssueAggregate(
          fingerprint: fingerprint,
          level: level,
          tag: parsed.tag,
          event: event ?? type,
          message: _truncate(_redactString(parsed.message), 160),
          firstAt: parsed.at,
        ),
      );
      issue.count += 1;
      issue.lastAt = parsed.at ?? issue.lastAt;
    }
  }

  List<String> toLines() {
    final issues = _issues.values.toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        return (b.lastAt?.millisecondsSinceEpoch ?? 0).compareTo(
          a.lastAt?.millisecondsSinceEpoch ?? 0,
        );
      });
    final lines = <String>[
      'errors=$errors',
      'fatals=$fatals',
      'warnings=$warnings',
      'network_errors=$networkErrors',
      'network_error_summaries=$errorSummaries',
      'sessions=${_sessions.length}',
      'traces=${_traces.length}',
      'time_info_refresh_failures=$timeInfoRefreshFailures',
      'schedule_update_failures=$scheduleUpdateFailures',
      'slowest_request_ms=${slowestRequestMs ?? 0}',
      if (slowestRequestLabel != null && slowestRequestLabel!.isNotEmpty)
        'slowest_request=${slowestRequestLabel!}',
      if (latestErrorAt != null)
        'latest_error_at=${latestErrorAt!.toIso8601String()}',
      if (latestErrorLabel != null)
        'latest_error=${_truncate(_redactString(latestErrorLabel!), 240)}',
    ];
    for (int i = 0; i < issues.length && i < 5; i++) {
      lines.add('top_issue_${i + 1}=${_safeJson(issues[i].toJson())}');
    }
    lines.addAll(_diagnosisHints());
    return lines;
  }

  void _consumeLegacy(String line) {
    if (line.contains('[ERROR]')) errors += 1;
    if (line.contains('[FATAL]')) fatals += 1;
    if (line.contains('[WARN]')) warnings += 1;
    if (line.contains('"type":"error"') && line.contains('"net":1')) {
      networkErrors += 1;
    }
    if (line.contains('"type":"error_summary"') && line.contains('"net":1')) {
      errorSummaries += 1;
    }
    if (line.contains('schedule_time_info_refresh_fail')) {
      timeInfoRefreshFailures += 1;
    }
    if (line.contains('[WARN] ScheduleUpdate - failure')) {
      scheduleUpdateFailures += 1;
    }
  }

  List<String> _diagnosisHints() {
    final hints = <String>[];
    final authenticationFailures =
        (_networkStatuses[401] ?? 0) + (_networkStatuses[403] ?? 0);
    final serverFailures = _networkStatuses.entries
        .where((entry) => entry.key >= 500)
        .fold<int>(0, (sum, entry) => sum + entry.value);
    if (authenticationFailures > 0) {
      hints.add('diagnosis_hint=authentication_or_session_expired');
    }
    if (serverFailures > 0) {
      hints.add('diagnosis_hint=remote_server_failure');
    }
    if (networkErrors > 0 && _networkStatuses.isEmpty) {
      hints.add('diagnosis_hint=network_connectivity_or_timeout');
    }
    if (fatals > 0) {
      hints.add('diagnosis_hint=application_crash');
    }
    return hints;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static String _requestLabel(_ParsedLogLine line) {
    final method = line.fields['method']?.toString();
    final uri = line.fields['uri']?.toString();
    if (method != null && uri != null) return '${line.tag} $method $uri';
    return '${line.tag} ${line.message}';
  }
}

class _ParsedLogLine {
  _ParsedLogLine({
    required this.at,
    required this.level,
    required this.tag,
    required this.message,
    required this.fields,
  });

  final DateTime? at;
  final String level;
  final String tag;
  final String message;
  final Map<String, Object?> fields;

  static _ParsedLogLine? tryParse(String line) {
    final match = RegExp(
      r'^(\S+) \[(DEBUG|INFO|WARN|ERROR|FATAL)\] (\S+) - (.*)$',
    ).firstMatch(line);
    if (match == null) return null;
    var message = match.group(4)!;
    var fields = <String, Object?>{};
    var fieldsStart = message.lastIndexOf(' {');
    while (fieldsStart >= 0) {
      final candidate = message.substring(fieldsStart + 1);
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) {
          fields = decoded.map((key, value) => MapEntry(key.toString(), value));
          message = message.substring(0, fieldsStart);
          break;
        }
      } catch (_) {}
      fieldsStart = fieldsStart <= 0
          ? -1
          : message.lastIndexOf(' {', fieldsStart - 1);
    }
    return _ParsedLogLine(
      at: DateTime.tryParse(match.group(1)!),
      level: match.group(2)!,
      tag: match.group(3)!,
      message: message,
      fields: fields,
    );
  }
}

class _IssueAggregate {
  _IssueAggregate({
    required this.fingerprint,
    required this.level,
    required this.tag,
    required this.event,
    required this.message,
    required this.firstAt,
  }) : lastAt = firstAt;

  final String fingerprint;
  final String level;
  final String tag;
  final String? event;
  final String message;
  final DateTime? firstAt;
  DateTime? lastAt;
  int count = 0;

  Map<String, Object?> toJson() {
    return {
      'fingerprint': fingerprint,
      'count': count,
      'level': level,
      'tag': tag,
      if (event != null && event!.isNotEmpty) 'event': event,
      'message': message,
      if (firstAt != null) 'first_at': firstAt!.toIso8601String(),
      if (lastAt != null) 'last_at': lastAt!.toIso8601String(),
    };
  }
}

String sanitizeUriForLogging(Uri uri) {
  final sanitized = uri
      .replace(userInfo: '', queryParameters: const <String, String>{})
      .removeFragment()
      .toString();
  return sanitized.endsWith('?')
      ? sanitized.substring(0, sanitized.length - 1)
      : sanitized;
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
  return '${s.substring(0, maxChars)}...(length=${s.length})';
}

String _redactString(String s) {
  var out = s.replaceAll(
    RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false),
    'Bearer <redacted>',
  );
  out = out.replaceAll(
    RegExp(r'eyJ[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
    '<jwt:redacted>',
  );
  out = out.replaceAllMapped(
    RegExp(r'([?&][A-Za-z0-9_.~-]+)=([^&#\s]*)', caseSensitive: false),
    (match) => '${match.group(1)}=<redacted>',
  );
  return out;
}

String _issueFingerprint({
  required String tag,
  required String message,
  required Object? error,
  required StackTrace? stackTrace,
  required Map<String, Object?> fields,
}) {
  final event = fields['event'] ?? fields['type'] ?? '';
  final reason = fields['reason'] ?? '';
  final status = fields['status'] ?? '';
  final errorType = error?.runtimeType.toString() ?? fields['error_type'] ?? '';
  final normalizedMessage = message
      .replaceAll(RegExp(r'[0-9a-f]{16,}', caseSensitive: false), '<id>')
      .replaceAll(RegExp(r'\b\d{4,}\b'), '<number>');
  final stackHead = _firstUsefulStackFrame(
    stackTrace,
  ).replaceAll(RegExp(r':\d+(?::\d+)?'), ':<line>');
  final source = [
    tag,
    event,
    reason,
    status,
    errorType,
    normalizedMessage,
    stackHead,
  ].join('|');
  return sha256.convert(utf8.encode(source)).toString().substring(0, 16);
}

String _firstUsefulStackFrame(StackTrace? stackTrace) {
  if (stackTrace == null) return '';
  final lines = stackTrace.toString().split('\n');
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.contains('dart:async') || trimmed.contains('dart:ui')) continue;
    return trimmed;
  }
  return '';
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
  const diagnosticKeys = <String>{
    'schema',
    'session_id',
    'event_id',
    'sequence',
    'trace_id',
    'request_id',
    'fingerprint',
    'event',
    'module',
    'action',
    'status',
    'reason',
    'error_type',
    'net',
    'type',
    'method',
    'uri',
    'duration_ms',
  };
  final envelope = <String, Object?>{};
  for (final key in diagnosticKeys) {
    if (obj.containsKey(key)) envelope[key] = obj[key];
  }
  final previewChars = max(0, min(1000, maxChars - 500));
  return <String, Object?>{
    ...envelope,
    'fields_truncated': true,
    'fields_original_chars': json.length,
    if (previewChars > 0) 'fields_preview': _truncate(json, previewChars),
  };
}
