import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'diagnostics_storage.dart';
import 'diagnostics_export.dart';

enum LogLevel {
  debug(10),
  info(20),
  warn(30),
  error(40),
  fatal(50);

  const LogLevel(this.priority);
  final int priority;
}

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
  final String tag, message, sessionId, eventId;
  final int sequence;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, Object?>? fields;
}

class LogMetricsSnapshot {
  const LogMetricsSnapshot({
    required this.queueDepth,
    required this.queueBytes,
    required this.enqueued,
    required this.emitted,
    required this.dropped,
    required this.writeErrors,
  });
  final int queueDepth, queueBytes, enqueued, emitted, dropped, writeErrors;
  int get queueCapacity => 128;
}

class _QueuedRecord {
  _QueuedRecord(this.event, {this.rootLink})
    : bytes = utf8.encode(jsonEncode(event)).length + 1;
  final Map<String, Object?> event;
  final _RootLink? rootLink;
  final int bytes;
  int get priority => LogLevel.values
      .firstWhere(
        (level) => level.name == event['level'],
        orElse: () => LogLevel.warn,
      )
      .priority;
}

class _RootLink {
  _RootLink(this.eventId);
  final String eventId;
  bool valid = true;
}

class _RepeatedIssue {
  _RepeatedIssue(this.record, this.first, this.rootLink) : last = first;
  final Map<String, Object?> record;
  final DateTime first;
  final _RootLink? rootLink;
  DateTime last;
  int repeated = 0;
}

/// Diagnostic policy: routine events are short-lived breadcrumbs; only actual
/// failures enter a bounded writer. All budgets are measured in UTF-8 bytes.
class AppLogger {
  AppLogger._();
  static final AppLogger I = AppLogger._();
  static const maxRecordBytes = 16 * 1024;
  static const maxStackBytes = 8 * 1024;
  static const maxExportBytes = 1024 * 1024;
  static const _contextLifetime = Duration(minutes: 2);
  static const _repeatWindow = Duration(seconds: 60);
  final Object _traceZoneKey = Object();
  final ListQueue<LogEvent> _recent = ListQueue();
  final ListQueue<_QueuedRecord> _queue = ListQueue();
  final LinkedHashMap<String, _RepeatedIssue> _issues = LinkedHashMap();
  Expando<_RootLink> _rootEvents = Expando<_RootLink>();
  DiagnosticStorage? _storage;
  Directory? _exportDirectory;
  DiagnosticExport? _exportStorage;
  DateTime Function() _now = DateTime.now;
  String _source = 'foreground', _version = 'unknown', _sessionId = '';
  int _sequence = 0, _recentBytes = 0, _queueBytes = 0;
  int _enqueued = 0, _emitted = 0, _dropped = 0, _writeErrors = 0;
  int _reportedDrops = 0;
  bool _initialized = false,
      _enableFile = true,
      _console = false,
      _pumping = false;
  LogLevel _minLevel = LogLevel.debug;
  Completer<void>? _idle;
  Timer? _repeatTimer;

  Future<void> init({
    String source = 'foreground',
    LogLevel? minLevel,
    bool enableConsole = true,
    bool enableFile = true,
    DiagnosticStorage? storage,
    Directory? exportDirectory,
    DiagnosticExport? exportStorage,
    DateTime Function()? clock,
  }) async {
    if (source != 'foreground' && source != 'background') {
      throw ArgumentError.value(source, 'source');
    }
    if (_initialized) await dispose();
    _source = source;
    _console = enableConsole;
    _enableFile = enableFile;
    _minLevel = minLevel ?? LogLevel.debug;
    _now = clock ?? DateTime.now;
    _exportDirectory = exportDirectory;
    _exportStorage = exportStorage;
    try {
      final package = await PackageInfo.fromPlatform();
      _version = '${package.version}+${package.buildNumber}';
    } catch (_) {}
    if (enableFile) {
      try {
        if (storage != null) {
          _storage = storage;
        } else if (Platform.isAndroid) {
          _storage = AndroidDiagnosticStorage(source);
        } else {
          final support = await getApplicationSupportDirectory();
          _storage = FileDiagnosticStorage(
            Directory('${support.path}/logs/diagnostics'),
            source,
          );
        }
        await _storage!.initialize();
        if (storage == null) await _removeLegacyFiles();
        await _pruneExports();
      } catch (error) {
        _writeErrors++;
        if (_console) {
          debugPrint(
            'Diagnostic initialization failed: ${_redact(error.toString())}',
          );
        }
      }
    }
    final pending = _queue.toList();
    _queue.clear();
    _queueBytes = 0;
    _enqueued -= pending.length;
    for (final item in pending) {
      item.event['source'] = source;
      item.event['version'] = _version;
      _enqueue(item.event, rootLink: item.rootLink);
    }
    for (final issue in _issues.values) {
      issue.record['source'] = source;
      issue.record['version'] = _version;
    }
    _initialized = true;
    _repeatTimer = Timer.periodic(_repeatWindow, (_) => _flushExpiredIssues());
    _startPump();
  }

  String? get logFilePath => _storage?.path;
  String get sessionId =>
      _sessionId.isEmpty ? (_sessionId = newTraceId(bytes: 8)) : _sessionId;
  String? get currentTraceId => Zone.current[_traceZoneKey] as String?;
  List<LogEvent> get recent {
    _pruneRecent();
    return List.unmodifiable(_recent);
  }

  LogMetricsSnapshot get metrics => LogMetricsSnapshot(
    queueDepth: _queue.length,
    queueBytes: _queueBytes,
    enqueued: _enqueued,
    emitted: _emitted,
    dropped: _dropped,
    writeErrors: _writeErrors,
  );
  String newTraceId({int bytes = 16}) => List.generate(
    bytes,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  T runWithTraceId<T>(String id, T Function() fn) =>
      runZoned(fn, zoneValues: {_traceZoneKey: id});
  Future<T> runWithTraceIdAsync<T>(String id, Future<T> Function() fn) =>
      runZoned(fn, zoneValues: {_traceZoneKey: id});

  void debug(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => log(
    LogLevel.debug,
    tag,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );
  void info(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => log(
    LogLevel.info,
    tag,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );
  void warn(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => log(
    LogLevel.warn,
    tag,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );
  void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => log(
    LogLevel.error,
    tag,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );
  void fatal(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => log(
    LogLevel.fatal,
    tag,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );
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
  }) => log(
    level,
    tag,
    message ?? messageZh,
    error: error,
    stackTrace: stackTrace,
    fields: {
      ...?fields,
      'event': event,
      'module': ?module,
      'action': ?action,
      'status': ?status,
      'reason': ?reason,
    },
  );

  /// Map a transport exception to a business exception without duplicating its
  /// already recorded root stack at the next layer.
  void linkFailure(Object mapped, Object cause) {
    if (!_expandoKey(mapped) || !_expandoKey(cause)) return;
    final id = _rootEvents[cause];
    if (id != null) _rootEvents[mapped] = id;
  }

  void logOperationFailure(
    String tag,
    String message, {
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
    LogLevel level = LogLevel.error,
  }) => log(
    level,
    tag,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  void log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    final at = _now();
    _flushExpiredIssues();
    _pruneRecent();
    final sequence = ++_sequence;
    final eventId = '$sessionId-${sequence.toRadixString(36).padLeft(4, '0')}';
    final safeFields = _sanitize(fields ?? {});
    final operation =
        currentTraceId ?? safeFields['operation_id'] ?? safeFields['trace_id'];
    if (error is DioException && error.type == DioExceptionType.cancel) {
      level = LogLevel.info;
    }
    final previousRoot = error != null && _expandoKey(error)
        ? _rootEvents[error]
        : null;
    final root = previousRoot?.valid == true ? previousRoot!.eventId : null;
    final effectiveStack =
        level.priority >= LogLevel.warn.priority && root == null
        ? stackTrace ?? StackTrace.current
        : null;
    final stack = root == null
        ? _clip(_redact(effectiveStack?.toString() ?? ''), maxStackBytes)
        : '';
    final record = <String, Object?>{
      'timestamp': at.toUtc().toIso8601String(),
      'level': level.name,
      'version': _version,
      'source': _source,
      'module': _clip(tag, 256),
      'stage': _clip(
        (safeFields['action'] ??
                safeFields['stage'] ??
                safeFields['event'] ??
                'unspecified')
            .toString(),
        256,
      ),
      'sessionId': sessionId,
      'eventId': eventId,
      'sequence': sequence,
      'operationId': _clip((operation ?? eventId).toString(), 256),
      'errorType': _clip(
        (error?.runtimeType ?? safeFields['error_type'] ?? 'DiagnosticFailure')
            .toString(),
        256,
      ),
      'message': _clip(_redact(message), 2048),
      'reason': _clip(
        _redact((safeFields['reason'] ?? error ?? message).toString()),
        2048,
      ),
      'stackTrace': stack,
      'outcome': _clip(
        (safeFields['outcome'] ?? safeFields['status'] ?? 'failed').toString(),
        256,
      ),
      'kind': root == null ? 'error' : 'outcome',
      'fields': safeFields,
      'rootEventId': ?root,
      if (level.priority >= LogLevel.warn.priority && root == null)
        'context': _recent
            .where((e) => e.level.priority < LogLevel.warn.priority)
            .where(
              (e) => operation == null || e.fields?['trace_id'] == operation,
            )
            .map(_breadcrumb)
            .toList(),
    };
    _bound(record);
    final fingerprint = _fingerprint(record);
    if (level.priority >= LogLevel.warn.priority) {
      record['fingerprint'] = fingerprint;
    }
    // These fields are protected from caller spoofing and useful to consumers
    // of the small in-memory ring, while the on-disk schema uses camelCase.
    final recentFields = <String, Object?>{
      ...safeFields,
      'schema': 3,
      'session_id': sessionId,
      'event_id': eventId,
      'sequence': sequence,
      'trace_id': ?operation,
      'root_event_id': ?root,
      'error_type': record['errorType'],
      if (level.priority >= LogLevel.warn.priority) 'fingerprint': fingerprint,
    };
    final entry = LogEvent(
      at: at,
      level: level,
      tag: record['module'] as String,
      message: record['message'] as String,
      sessionId: sessionId,
      eventId: eventId,
      sequence: sequence,
      error: error == null ? null : record['reason'],
      stackTrace: stack.isEmpty ? null : StackTrace.fromString(stack),
      fields: _boundedFields(recentFields),
    );
    _recent.add(entry);
    _recentBytes += _recentSize(entry);
    _pruneRecent();
    if (level.priority < LogLevel.warn.priority) return;
    final issue = _issues[fingerprint];
    if (issue != null) {
      issue.repeated++;
      issue.last = at;
      // Associate duplicate instances with the persisted first failure too.
      if (root == null && error != null && _expandoKey(error)) {
        _rootEvents[error] = issue.rootLink;
      }
      return;
    }
    if (_issues.length >= 128) _flushIssue(_issues.keys.first);
    final rootLink = root == null ? _RootLink(eventId) : previousRoot;
    _issues[fingerprint] = _RepeatedIssue(record, at, rootLink);
    if (root == null && error != null && _expandoKey(error)) {
      _rootEvents[error] = rootLink;
    }
    _enqueue(record, rootLink: rootLink);
  }

  void _pruneRecent() {
    final cutoff = _now().subtract(_contextLifetime);
    while (_recent.isNotEmpty &&
        (_recent.length > 64 ||
            _recentBytes > 64 * 1024 ||
            _recent.first.at.isBefore(cutoff))) {
      _recentBytes -= _recentSize(_recent.removeFirst());
    }
  }

  int _recentSize(LogEvent e) => utf8.encode(jsonEncode(_breadcrumb(e))).length;
  Map<String, Object?> _breadcrumb(LogEvent e) => {
    'timestamp': e.at.toUtc().toIso8601String(),
    'module': e.tag,
    'message': e.message,
    'operationId': e.fields?['trace_id'],
    'fields': e.fields,
    if (e.stackTrace != null) 'stackTrace': e.stackTrace.toString(),
  };
  void _flushExpiredIssues() {
    final now = _now();
    for (final key in _issues.keys.toList()) {
      if (now.difference(_issues[key]!.first) >= _repeatWindow) {
        _flushIssue(key);
      }
    }
  }

  void _flushIssue(String key) {
    final issue = _issues.remove(key);
    if (issue == null || issue.repeated == 0) return;
    _enqueue({
      ...issue.record,
      'timestamp': issue.last.toUtc().toIso8601String(),
      'eventId': '${issue.record['eventId']}-summary',
      'kind': 'summary',
      'rootEventId': issue.record['rootEventId'] ?? issue.record['eventId'],
      'message': '重复错误汇总',
      'stackTrace': '',
      'context': <Object?>[],
      'repeatCount': issue.repeated,
      'totalCount': issue.repeated + 1,
      'firstSeen': issue.first.toUtc().toIso8601String(),
      'lastSeen': issue.last.toUtc().toIso8601String(),
    }, rootLink: issue.rootLink);
  }

  void _invalidateRecord(_QueuedRecord item) {
    if (item.event['eventId'] == item.rootLink?.eventId) {
      item.rootLink?.valid = false;
    }
    final fingerprint = item.event['fingerprint'];
    if (_issues[fingerprint]?.record['eventId'] == item.event['eventId']) {
      _issues.remove(fingerprint);
    }
  }

  void _enqueue(Map<String, Object?> record, {_RootLink? rootLink}) {
    _bound(record);
    final item = _QueuedRecord(record, rootLink: rootLink);
    _enqueued++;
    while (_queue.length >= 128 || _queueBytes + item.bytes > 512 * 1024) {
      if (_queue.isEmpty) {
        _dropped++;
        _invalidateRecord(item);
        return;
      }
      var index = _queue.toList().indexWhere(
        (r) => r.priority < LogLevel.error.priority,
      );
      if (index < 0 && item.priority < LogLevel.error.priority) {
        _dropped++;
        _invalidateRecord(item);
        return;
      }
      final removed = index < 0
          ? _queue.removeFirst()
          : _queue.elementAt(index);
      if (index >= 0) _queue.remove(removed);
      _queueBytes -= removed.bytes;
      _invalidateRecord(removed);
      _dropped++;
    }
    _queue.add(item);
    _queueBytes += item.bytes;
    _startPump();
  }

  void _startPump() {
    if (!_initialized || _pumping || _queue.isEmpty) return;
    _pumping = true;
    _idle ??= Completer<void>();
    unawaited(_pump());
  }

  Future<void> _pump() async {
    while (_queue.isNotEmpty) {
      final item = _queue.removeFirst();
      _queueBytes -= item.bytes;
      try {
        if (_enableFile && _storage != null) await _storage!.write(item.event);
        if (_console && item.priority >= _minLevel.priority) {
          debugPrint(jsonEncode(item.event));
        }
        _emitted++;
      } catch (error) {
        _invalidateRecord(item);
        _writeErrors++;
        if (_console) {
          debugPrint('Diagnostic write failed: ${_redact(error.toString())}');
        }
      }
    }
    if (_dropped > _reportedDrops) {
      final count = _dropped - _reportedDrops;
      _reportedDrops = _dropped;
      final report = <String, Object?>{
        'timestamp': _now().toUtc().toIso8601String(),
        'level': 'warn',
        'source': _source,
        'module': 'Logger',
        'stage': 'queue',
        'sessionId': sessionId,
        'operationId': sessionId,
        'version': _version,
        'kind': 'dropped',
        'message': '写入队列拥塞，丢弃 $count 条记录',
        'droppedCount': count,
      };
      try {
        if (_enableFile && _storage != null) await _storage!.write(report);
      } catch (_) {
        _writeErrors++;
      }
      // Calls arriving while this report was written must be drained too.
      if (_queue.isNotEmpty) {
        await _pump();
        return;
      }
    }
    _pumping = false;
    final idle = _idle;
    _idle = null;
    idle?.complete();
  }

  Future<void> flush({Duration timeout = const Duration(seconds: 2)}) async {
    for (final key in _issues.keys.toList()) {
      _flushIssue(key);
    }
    _startPump();
    final idle = _idle;
    if (idle != null) {
      await idle.future; // Never race export/clear with a writer.
    }
    try {
      await _storage?.flush();
    } catch (_) {
      _writeErrors++;
    }
  }

  Future<void> pruneLogs() async {
    await flush();
    try {
      await _storage?.prune();
      await _pruneExports();
    } catch (_) {
      _writeErrors++;
    }
  }

  Future<void> dispose() async {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    await flush();
    _initialized = false;
    _storage = null;
    _recent.clear();
    _recentBytes = 0;
    _queue.clear();
    _queueBytes = 0;
    _issues.clear();
    _rootEvents = Expando<_RootLink>();
    _sessionId = '';
    _sequence = 0;
    _enqueued = _emitted = _dropped = _reportedDrops = _writeErrors = 0;
  }

  Future<int?> getLogBytes() async {
    try {
      await flush();
      await _storage?.prune();
      await _pruneExports();
      return (await _storage?.bytes() ?? 0) +
          await (await _resolveExportStorage()).bytes();
    } catch (_) {
      return null;
    }
  }

  Future<int> clearLogFiles() async {
    await flush();
    var count = 0;
    Object? failure;
    try {
      count = await _storage?.clear() ?? 0;
    } catch (error) {
      failure = error;
    }
    try {
      count += await (await _resolveExportStorage()).clear();
    } catch (error) {
      failure ??= error;
    }
    _recent.clear();
    _recentBytes = 0;
    _rootEvents = Expando<_RootLink>();
    if (failure != null) {
      _writeErrors++;
      throw FileSystemException('诊断文件未全部清理: ${_redact(failure.toString())}');
    }
    return count;
  }

  Future<String> exportLogs({int maxTotalBytes = maxExportBytes}) async {
    await flush();
    await _storage?.prune();
    await _pruneExports();
    final name =
        'cqut_diagnostic_${_now().millisecondsSinceEpoch}_${newTraceId(bytes: 3)}.log';
    final content = await _renderExport(min(maxExportBytes, maxTotalBytes));
    return (await _resolveExportStorage()).publish(name, content);
  }

  Future<String> _renderExport(int budget) async {
    if (budget < 1024) throw ArgumentError('诊断导出上限至少需要 1 KiB');
    final cutoff = _now().subtract(diagnosticRetention);
    final records = (await _storage?.snapshot() ?? <Map<String, Object?>>[])
        .where(
          (e) =>
              DateTime.tryParse(
                e['timestamp']?.toString() ?? '',
              )?.isBefore(cutoff) ==
              false,
        )
        .toList();
    records.sort(_compareRecords);
    var warnings = 0, errors = 0, fatals = 0;
    for (final row in records) {
      if (row['kind'] == 'outcome') continue;
      final count = row['kind'] == 'summary'
          ? (row['repeatCount'] as num?)?.toInt() ?? 0
          : 1;
      switch (row['level']) {
        case 'warn':
          warnings += count;
        case 'error':
          errors += count;
        case 'fatal':
          fatals += count;
      }
    }
    final header =
        'CQUT 完整诊断\n导出时间: ${_now().toIso8601String()}\n版本: $_version\n'
        '设备: ${Platform.operatingSystem} ${_clip(Platform.operatingSystemVersion, 512)}\n'
        '会话: $sessionId\n保留期限: 3 天\n'
        '错误汇总: warning=$warnings error=$errors fatal=$fatals\n'
        '队列丢弃: $_dropped 写入失败: $_writeErrors\n'
        '记录按时间排列；搜索 operationId 可查找操作关联，rootEventId 指向根因。\n\n';
    final omission = '\n[截断] 体积达到上限，已优先保留最近完整异常记录。\n';
    var used = utf8.encode(header).length + utf8.encode(omission).length;
    final roots = {
      for (final row in records)
        if (row['eventId'] is String) row['eventId'] as String: row,
    };
    final selected = <Map<String, Object?>>[];
    final included = <Map<String, Object?>>{};
    for (final row in records.reversed) {
      if (included.contains(row)) continue;
      final root = roots[row['rootEventId']];
      final group = [
        if (root != null && !included.contains(root) && !identical(root, row))
          root,
        row,
      ];
      final bytes = group.fold<int>(
        0,
        (sum, entry) =>
            sum + utf8.encode(_readableWithRoot(entry, roots)).length,
      );
      if (used + bytes > budget) continue;
      selected.addAll(group);
      included.addAll(group);
      used += bytes;
    }
    selected.sort(_compareRecords);
    final truncated = selected.length < records.length;
    final text =
        '$header${selected.map((row) => _readableWithRoot(row, roots)).join()}${truncated ? omission : ''}';
    return text;
  }

  int _compareRecords(Map<String, Object?> a, Map<String, Object?> b) {
    final order = DateTime.parse(
      a['timestamp'].toString(),
    ).compareTo(DateTime.parse(b['timestamp'].toString()));
    return order != 0
        ? order
        : (a['eventId'] ?? '').toString().compareTo(
            (b['eventId'] ?? '').toString(),
          );
  }

  String _readableWithRoot(
    Map<String, Object?> row,
    Map<String, Map<String, Object?>> roots,
  ) => _readable({
    ...row,
    if (row['rootEventId'] != null && !roots.containsKey(row['rootEventId']))
      'rootMissing': '根因已超出运行日志保留范围',
  });

  String _readable(Map<String, Object?> row) {
    final out = StringBuffer(
      '[${row['timestamp']}] ${row['level']} ${row['module']} / ${row['stage']}\n',
    );
    for (final key in [
      'version',
      'source',
      'sessionId',
      'eventId',
      'operationId',
      'kind',
      'errorType',
      'message',
      'reason',
      'outcome',
      'rootEventId',
      'rootMissing',
      'fingerprint',
      'repeatCount',
      'totalCount',
      'firstSeen',
      'lastSeen',
      'droppedCount',
    ]) {
      if (row[key] != null) out.writeln('$key: ${row[key]}');
    }
    if (row['fields'] != null) {
      out.writeln('fields: ${jsonEncode(row['fields'])}');
    }
    if (row['context'] != null) {
      out.writeln('context: ${jsonEncode(row['context'])}');
    }
    if ((row['stackTrace']?.toString() ?? '').isNotEmpty) {
      out.writeln('stackTrace:\n${row['stackTrace']}');
    }
    if (row['truncated'] != null) out.writeln('truncated: ${row['truncated']}');
    out.writeln();
    return out.toString();
  }

  Future<DiagnosticExport> _resolveExportStorage() async {
    if (_exportStorage != null) return _exportStorage!;
    if (Platform.isAndroid && _exportDirectory == null) {
      return _exportStorage = AndroidDiagnosticExport();
    }
    return _exportStorage = FileDiagnosticExport(
      await _resolveExports(),
      clock: () => _now(),
    );
  }

  Future<Directory> _resolveExports() async {
    if (_exportDirectory != null) return _exportDirectory!;
    final root =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    return _exportDirectory = Directory('${root.path}/CQUT-Helper/log');
  }

  Future<void> _pruneExports() async {
    await (await _resolveExportStorage()).prune();
  }

  Future<void> _removeLegacyFiles() async {
    final docs = await getApplicationDocumentsDirectory();
    final export = Platform.isAndroid ? null : await _resolveExports();
    final directories = [
      docs,
      Directory('${docs.path}/.runtime'),
      Directory('${docs.path}/exports'),
      ?export,
      if (export != null) Directory('${export.path}/.runtime'),
    ];
    final pattern = RegExp(
      r'^cqut(?:_.*)?\.log(?:\.gz)?(?:\.sha256)?$|^cqut.*_export_.*\.(?:txt|log)(?:\.sha256)?$',
      caseSensitive: false,
    );
    for (final directory in directories) {
      try {
        if (!await directory.exists()) continue;
        await for (final entry in directory.list(followLinks: false)) {
          if (entry is File && pattern.hasMatch(entry.uri.pathSegments.last)) {
            try {
              await entry.delete();
            } catch (_) {
              _writeErrors++;
            }
          }
        }
      } catch (_) {
        _writeErrors++;
      }
    }
  }

  void installGlobalErrorHandlers() {
    FlutterError.onError = (details) {
      final recoverable = details.library == 'image resource service';
      log(
        recoverable ? LogLevel.warn : LogLevel.fatal,
        recoverable ? 'FlutterImage' : 'FlutterError',
        details.exceptionAsString(),
        error: details.exception,
        stackTrace: details.stack,
        fields: {
          'library': details.library,
          'context': details.context?.toDescription(),
          'status': recoverable ? 'recoverable' : 'uncaught',
        },
      );
      if (!recoverable) FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      fatal(
        'PlatformDispatcher',
        error.toString(),
        error: error,
        stackTrace: stack,
        fields: {'status': 'uncaught'},
      );
      return true;
    };
  }

  DioLogInterceptor dioInterceptor({
    String tag = 'HTTP',
    int maxBodyChars = 0,
  }) => DioLogInterceptor(logger: this, tag: tag);
  void attachToDio(Dio dio, {String tag = 'HTTP', int maxBodyChars = 0}) {
    if (!dio.interceptors.any((i) => i is DioLogInterceptor)) {
      dio.interceptors.add(dioInterceptor(tag: tag));
    }
  }
}

class DioLogInterceptor extends Interceptor {
  DioLogInterceptor({required this.logger, this.tag = 'HTTP'});
  final AppLogger logger;
  final String tag;
  static const _startKey = '__diagnostic_start';
  static const _traceKey = '__diagnostic_operation';
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = Stopwatch()..start();
    options.extra[_traceKey] = logger.currentTraceId ?? logger.newTraceId();
    logger.runWithTraceId(
      options.extra[_traceKey] as String,
      () => logger.debug(tag, '请求开始', fields: _fields(options)),
    );
    handler.next(options);
  }

  Map<String, Object?> _fields(RequestOptions options, {int? status}) => {
    'net': true,
    'method': options.method,
    'uri': sanitizeUriForLogging(options.uri),
    'duration_ms':
        (options.extra[_startKey] as Stopwatch?)?.elapsedMilliseconds,
    'trace_id': options.extra[_traceKey],
    'status_code': ?status,
    'action': 'request',
  };
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    final status = response.statusCode ?? 0;
    if (status >= 400 && !_expectedStatus(options, status)) {
      logger.warn(
        tag,
        'HTTP 请求失败',
        fields: {
          ..._fields(options, status: status),
          'reason': 'HTTP $status',
        },
      );
    } else {
      logger.debug(
        tag,
        '请求完成',
        fields: {
          ..._fields(options, status: status),
          'status': 'success',
        },
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final fields = {
      ..._fields(err.requestOptions, status: err.response?.statusCode),
      'error_type': err.type.name,
      'status': err.type == DioExceptionType.cancel ? 'cancelled' : 'failed',
    };
    if (err.type == DioExceptionType.cancel ||
        _expectedStatus(err.requestOptions, err.response?.statusCode)) {
      logger.info(
        tag,
        err.type == DioExceptionType.cancel ? '请求取消' : '服务处于预期关闭状态',
        fields: fields,
      );
    } else {
      logger.logOperationFailure(
        tag,
        '网络请求失败',
        error: err,
        stackTrace: err.stackTrace,
        fields: {...fields, 'reason': err.message ?? err.type.name},
      );
    }
    handler.next(err);
  }

  bool _expectedStatus(RequestOptions options, int? status) {
    final expected = options.extra['diagnostic_expected_statuses'];
    return status != null && expected is List && expected.contains(status);
  }
}

String sanitizeUriForLogging(Uri uri) {
  final clean = uri
      .replace(userInfo: '', queryParameters: const <String, String>{})
      .removeFragment()
      .toString();
  return clean.endsWith('?') ? clean.substring(0, clean.length - 1) : clean;
}

bool _expandoKey(Object value) =>
    value is! String && value is! num && value is! bool && value is! Record;
String _redact(String value) => value
    .replaceAll(
      RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false),
      'Bearer <redacted>',
    )
    .replaceAll(
      RegExp(r'eyJ[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
      '<jwt:redacted>',
    )
    .replaceAllMapped(
      RegExp(r'([?&][A-Za-z0-9_.~-]+)=([^&#\s]*)'),
      (m) => '${m[1]}=<redacted>',
    )
    .replaceAllMapped(
      RegExp(r'(https?://)[^\s/@]+@', caseSensitive: false),
      (m) => '${m[1]}<redacted>@',
    )
    .replaceAllMapped(
      RegExp(
        r'((?:password|passwd|pwd|pass|token|secret|cookie|authorization|csrf)[\w-]*\s*[:=]\s*)[^\s,;&]+',
        caseSensitive: false,
      ),
      (m) => '${m[1]}<redacted>',
    );
String _clip(String value, int maxBytes) {
  if (utf8.encode(value).length <= maxBytes) return value;
  const marker = '…[截断]';
  final available = max(0, maxBytes - utf8.encode(marker).length);
  final out = StringBuffer();
  var used = 0;
  for (final rune in value.runes) {
    final part = String.fromCharCode(rune);
    final bytes = utf8.encode(part).length;
    if (used + bytes > available) break;
    out.write(part);
    used += bytes;
  }
  return '$out$marker';
}

Map<String, Object?> _sanitize(Map<String, Object?> fields) {
  Object? walk(Object? value, String key, int depth) {
    final lower = key.toLowerCase();
    if (RegExp(
      r'password|token|secret|cookie|authorization|csrf|^pwd$|^pass$',
    ).hasMatch(lower)) {
      return '<redacted>';
    }
    if (RegExp(
      r'^(request_body|response_body|body|payload|data|courses|schedule_data|stack)$',
    ).hasMatch(lower)) {
      return '<omitted>';
    }
    if (depth > 4) return '<depth limited>';
    if (value == null || value is num || value is bool) return value;
    if (value is Map) {
      return {
        for (final entry in value.entries.take(32))
          _clip(entry.key.toString(), 128): walk(
            entry.value,
            entry.key.toString(),
            depth + 1,
          ),
      };
    }
    if (value is Iterable) {
      return value.take(16).map((v) => walk(v, '', depth + 1)).toList();
    }
    return _clip(_redact(value.toString()), 1024);
  }

  return {
    for (final entry in fields.entries.take(32))
      _clip(entry.key, 128): walk(entry.value, entry.key, 0),
  };
}

Map<String, Object?> _boundedFields(Map<String, Object?> fields) {
  if (utf8.encode(jsonEncode(fields)).length < 4096) return fields;
  return {
    for (final key in [
      'schema',
      'session_id',
      'event_id',
      'sequence',
      'trace_id',
      'root_event_id',
      'error_type',
      'fingerprint',
      'action',
      'status',
      'reason',
      'method',
      'uri',
      'duration_ms',
      'status_code',
    ])
      if (fields.containsKey(key)) key: fields[key],
    'fields_truncated': true,
  };
}

void _bound(Map<String, Object?> record) {
  for (final key in record.keys.toList()) {
    final value = record[key];
    if (value is String) {
      final budget = key == 'stackTrace'
          ? AppLogger.maxStackBytes
          : key == 'message' || key == 'reason'
          ? 2048
          : 256;
      record[key] = _clipSerialized(value, budget);
    }
  }
  var size = utf8.encode(jsonEncode(record)).length + 1;
  if (size <= AppLogger.maxRecordBytes - 64) return;
  record['truncated'] = true;
  final context = record['context'];
  if (context is List) {
    while (context.isNotEmpty && size > AppLogger.maxRecordBytes - 64) {
      context.removeAt(0);
      size = utf8.encode(jsonEncode(record)).length + 1;
    }
  }
  if (size > AppLogger.maxRecordBytes - 64) {
    record['fields'] = _boundedFields(
      Map<String, Object?>.from(record['fields'] as Map? ?? {}),
    );
    size = utf8.encode(jsonEncode(record)).length + 1;
  }
  // JSON escaping can multiply stack length (tabs/newlines). Cut by serialized
  // size, keeping stack and the essential diagnostic envelope ahead of fields.
  if (size > AppLogger.maxRecordBytes - 64) {
    record['fields'] = {'fields_truncated': true};
  }
  while (utf8.encode(jsonEncode(record)).length + 1 >
      AppLogger.maxRecordBytes - 64) {
    final stack = record['stackTrace']?.toString() ?? '';
    if (utf8.encode(stack).length > 256) {
      record['stackTrace'] = _clip(stack, utf8.encode(stack).length - 256);
    } else {
      record['reason'] = _clip(record['reason']?.toString() ?? '', 512);
      record['message'] = _clip(record['message']?.toString() ?? '', 512);
      break;
    }
  }
}

String _clipSerialized(String value, int budget) {
  if (utf8.encode(jsonEncode(value)).length <= budget) return value;
  const marker = '…[截断]';
  var used = utf8.encode(jsonEncode(marker)).length;
  final result = StringBuffer();
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final bytes = utf8.encode(jsonEncode(character)).length - 2;
    if (used + bytes > budget) break;
    used += bytes;
    result.write(character);
  }
  return '$result$marker';
}

String _fingerprint(Map<String, Object?> record) {
  final fields = record['fields'] as Map? ?? {};
  final message = record['message']
      .toString()
      .replaceAll(RegExp(r'[0-9a-f]{16,}', caseSensitive: false), '<id>')
      .replaceAll(RegExp(r'\b\d{4,}\b'), '<number>');
  final stack = (record['stackTrace']?.toString() ?? '')
      .split('\n')
      .firstWhere(
        (s) =>
            s.trim().isNotEmpty &&
            !s.contains('dart:async') &&
            !s.contains('utils/app_logger.dart'),
        orElse: () => '',
      )
      .replaceAll(RegExp(r':\d+(?::\d+)?'), ':<line>');
  return sha256
      .convert(
        utf8.encode(
          [
            record['module'],
            record['stage'],
            record['kind'],
            record['errorType'],
            fields['status_code'],
            fields['method'],
            fields['uri'],
            fields['error_type'],
            record['reason'].toString().replaceAll(
              RegExp(r'\b\d{4,}\b'),
              '<number>',
            ),
            message,
            stack,
          ].join('|'),
        ),
      )
      .toString()
      .substring(0, 16);
}
