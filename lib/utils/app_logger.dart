import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show FlutterError, debugPrint, kDebugMode;
import 'package:path_provider/path_provider.dart';

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
  Future<void> dispose();
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
  FileLogSink({required this.fileName, required this.maxBytes});

  final String fileName;
  final int maxBytes;
  static const Duration _maxAge = Duration(days: 1);

  IOSink? _sink;
  File? _file;
  Future<void>? _opening;

  @override
  Future<void> emit(LogEvent event) async {
    await _ensureOpen();
    final sink = _sink;
    final file = _file;
    if (sink == null || file == null) return;

    await _rotateIfNeeded(file);

    sink.writeln(_formatLine(event));
    if (event.stackTrace != null) {
      sink.writeln(event.stackTrace.toString());
    }
  }

  @override
  Future<void> dispose() async {
    final sink = _sink;
    _sink = null;
    _file = null;
    if (sink != null) {
      await sink.flush();
      await sink.close();
    }
  }

  String? get currentPath => _file?.path;

  Future<void> _ensureOpen() async {
    if (_sink != null) return;
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
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.parent.create(recursive: true);
    _file = file;
    _sink = file.openWrite(mode: FileMode.append, encoding: utf8);
  }

  Future<void> _rotateIfNeeded(File file) async {
    try {
      final stat = await file.stat();
      if (stat.size < maxBytes) return;
      await _sink?.flush();
      await _sink?.close();
      _sink = null;

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

      try {
        final cutoff = DateTime.now().subtract(_maxAge);
        final dir = Directory(rotated.parent.path);
        final rotatedRegex = RegExp(
          '^${RegExp.escape(base)}_.*\\.log\$',
          caseSensitive: false,
        );
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = pBasename(entity.path);
          if (!rotatedRegex.hasMatch(name)) continue;
          try {
            final st = await entity.stat();
            if (st.modified.isBefore(cutoff)) {
              await entity.delete();
            }
          } catch (_) {}
        }
      } catch (_) {}

      await _open();
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

class AppLogger {
  AppLogger._();
  static final AppLogger I = AppLogger._();

  LogLevel _minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;
  final List<LogSink> _sinks = [];
  final ListQueue<LogEvent> _buffer = ListQueue();
  int _bufferSize = 400;
  FileLogSink? _fileSink;
  bool _initialized = false;
  String _fileName = 'cqut.log';
  int _maxFileBytes = 2 * 1024 * 1024;
  bool _enableFile = true;
  final String _exportDirName = 'exports';
  final String _downloadExportDirName = 'CQUT-Helper';

  Future<void> init({
    LogLevel? minLevel,
    bool enableConsole = true,
    bool enableFile = true,
    String fileName = 'cqut.log',
    int maxFileBytes = 2 * 1024 * 1024,
    int bufferSize = 400,
  }) async {
    _minLevel = minLevel ?? _minLevel;
    _bufferSize = bufferSize;
    _fileName = fileName;
    _maxFileBytes = maxFileBytes;
    _enableFile = enableFile;

    await dispose();
    if (enableConsole) {
      _sinks.add(ConsoleLogSink());
    }
    if (enableFile) {
      final sink = FileLogSink(fileName: fileName, maxBytes: maxFileBytes);
      _fileSink = sink;
      _sinks.add(sink);
      await sink.emit(
        LogEvent(
          at: DateTime.now(),
          level: LogLevel.info,
          tag: 'Logger',
          message: 'initialized',
          fields: {'file': fileName},
        ),
      );
    }

    _initialized = true;
  }

  Future<void> dispose() async {
    final sinks = List<LogSink>.from(_sinks);
    _sinks.clear();
    _fileSink = null;
    for (final s in sinks) {
      await s.dispose();
    }
  }

  String? get logFilePath => _fileSink?.currentPath;

  List<LogEvent> get recent => List.unmodifiable(_buffer);

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
        try {
          final st = await f.stat();
          if (st.modified.isBefore(cutoff)) {
            await f.delete();
          }
        } catch (_) {}
      }

      final current = await _resolveCurrentLogFile();
      if (await current.exists()) {
        await _rewriteLogFileKeepingSince(current, cutoff);
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
    await pruneLogs();
    final ts = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:\.]'),
      '-',
    );
    final base = _logBaseName(_fileName);
    final dir = await _resolveDownloadExportDirectory();
    await dir.create(recursive: true);
    final outPath =
        '${dir.path}${Platform.pathSeparator}${base}_export_$ts.txt';
    return exportLogsToPath(outPath, maxTotalBytes: maxTotalBytes);
  }

  Future<String> exportLogsToPath(
    String outputPath, {
    int maxTotalBytes = 8 * 1024 * 1024,
  }) async {
    await _detachFileSink();
    try {
      final outFile = File(outputPath);
      await outFile.parent.create(recursive: true);

      final files = await _listLogFiles(includeExports: false);
      files.sort((a, b) => a.path.compareTo(b.path));

      int written = 0;
      final sink = outFile.openWrite(mode: FileMode.write, encoding: utf8);
      try {
        sink.writeln('exported_at=${DateTime.now().toIso8601String()}');
        sink.writeln('files=${files.length}');
        sink.writeln('');
        for (final f in files) {
          sink.writeln('===== ${pBasename(f.path)} =====');
          try {
            final stream = f.openRead().transform(utf8.decoder);
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

    final event = LogEvent(
      at: DateTime.now(),
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

    final sinks = List<LogSink>.from(_sinks);
    if (sinks.isEmpty && !_initialized) {
      debugPrint(
        '${event.at.toIso8601String()} [${event.level.name.toUpperCase()}] ${event.tag} - ${event.message}',
      );
      return;
    }
    for (final s in sinks) {
      unawaited(s.emit(event));
    }
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

  Future<FileLogSink?> _detachFileSink() async {
    final sink = _fileSink;
    if (sink == null) return null;
    _fileSink = null;
    _sinks.removeWhere((s) => identical(s, sink));
    await sink.dispose();
    return sink;
  }

  Future<void> _ensureFileSink() async {
    if (_fileSink != null) return;
    final sink = FileLogSink(fileName: _fileName, maxBytes: _maxFileBytes);
    _fileSink = sink;
    _sinks.add(sink);
    await sink.emit(
      LogEvent(
        at: DateTime.now(),
        level: LogLevel.info,
        tag: 'Logger',
        message: 'file_sink_reopened',
      ),
    );
  }

  Future<List<File>> _listLogFiles({required bool includeExports}) async {
    final docs = await getApplicationDocumentsDirectory();
    final base = _logBaseName(_fileName);
    final logRegex = RegExp('^${RegExp.escape(base)}(_.*)?\\.log\$');

    final out = <File>[];
    await for (final entity in docs.list(followLinks: false)) {
      if (entity is File) {
        final name = pBasename(entity.path);
        if (logRegex.hasMatch(name)) out.add(entity);
      }
    }

    if (includeExports) {
      final exportDir = Directory(
        '${docs.path}${Platform.pathSeparator}$_exportDirName',
      );
      if (await exportDir.exists()) {
        final exportRegex = RegExp('^${RegExp.escape(base)}_export_.*\\.txt\$');
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
    final base = _logBaseName(_fileName);
    final exportRegex = RegExp('^${RegExp.escape(base)}_export_.*\\.txt\$');

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

  Future<Directory> _resolveDownloadExportDirectory() async {
    if (Platform.isAndroid) {
      final candidates = <String>[
        '${Platform.pathSeparator}storage${Platform.pathSeparator}emulated${Platform.pathSeparator}0${Platform.pathSeparator}Download',
        '${Platform.pathSeparator}storage${Platform.pathSeparator}emulated${Platform.pathSeparator}0${Platform.pathSeparator}Downloads',
      ];
      for (final c in candidates) {
        final d = Directory(c);
        if (await d.exists()) {
          return Directory(
            '${d.path}${Platform.pathSeparator}$_downloadExportDirName',
          );
        }
      }
      return Directory(
        '${candidates.first}${Platform.pathSeparator}$_downloadExportDirName',
      );
    }

    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return Directory(
        '${downloads.path}${Platform.pathSeparator}$_downloadExportDirName',
      );
    }

    final docs = await getApplicationDocumentsDirectory();
    return Directory(
      '${docs.path}${Platform.pathSeparator}$_downloadExportDirName',
    );
  }

  Future<File> _resolveCurrentLogFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}${Platform.pathSeparator}$_fileName');
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

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now().millisecondsSinceEpoch;
    logger.debug(
      tag,
      '${options.method} ${options.uri}',
      fields: {
        'type': 'request',
        'headers': _redactHeaders(options.headers),
        if (options.queryParameters.isNotEmpty)
          'query': _sanitizeObject(options.queryParameters, maxBodyChars),
        if (options.data != null)
          'body': _sanitizeObject(options.data, maxBodyChars),
      },
    );
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final ms = _elapsedMs(response.requestOptions);
    final status = response.statusCode ?? 0;
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
        'type': 'response',
        'status': status,
        if (ms != null) 'duration_ms': ms,
        'headers': _redactHeaders(response.headers.map),
        if (_shouldLogResponseBody(response))
          'body': _sanitizeObject(response.data, maxBodyChars),
      },
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final ms = _elapsedMs(err.requestOptions);
    final status = err.response?.statusCode;
    logger.error(
      tag,
      '${err.requestOptions.method} ${err.requestOptions.uri}',
      error: err,
      stackTrace: err.stackTrace,
      fields: {
        'type': 'error',
        if (status != null) 'status': status,
        if (ms != null) 'duration_ms': ms,
        'dio_type': err.type.name,
        if (err.message != null) 'message': err.message,
        'headers': _redactHeaders(err.requestOptions.headers),
        if (err.requestOptions.queryParameters.isNotEmpty)
          'query': _sanitizeObject(
            err.requestOptions.queryParameters,
            maxBodyChars,
          ),
        if (err.requestOptions.data != null)
          'body': _sanitizeObject(err.requestOptions.data, maxBodyChars),
        if (err.response != null && _shouldLogResponseBody(err.response!))
          'response': _sanitizeObject(err.response?.data, maxBodyChars),
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

  bool _shouldLogResponseBody(Response response) {
    final type = response.requestOptions.responseType;
    if (type == ResponseType.stream || type == ResponseType.bytes) return false;
    return true;
  }

  static Map<String, Object?> _redactHeaders(Map headers) {
    final out = <String, Object?>{};
    for (final entry in headers.entries) {
      final key = entry.key.toString();
      final k = key.toLowerCase();
      if (k == 'authorization' ||
          k == 'cookie' ||
          k == 'set-cookie' ||
          k == 'x-auth-token' ||
          k == 'x-csrf-token') {
        out[key] = '<redacted>';
        continue;
      }
      out[key] = entry.value;
    }
    return out;
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
