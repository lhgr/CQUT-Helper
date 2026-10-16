import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/diagnostics_storage.dart';
import 'package:cqut_helper/utils/diagnostics_export.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryStorage extends DiagnosticStorage {
  final rows = <Map<String, Object?>>[];
  Completer<void>? gate;
  bool fail = false;
  @override
  String get path => 'memory';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> prune() async {}
  @override
  Future<void> write(Map<String, Object?> event) async {
    await gate?.future;
    if (fail) throw const FileSystemException('disk unavailable');
    rows.add(Map<String, Object?>.from(jsonDecode(jsonEncode(event)) as Map));
  }

  @override
  Future<List<Map<String, Object?>>> snapshot() async => rows.toList();
  @override
  Future<int> bytes() async =>
      rows.fold<int>(0, (n, r) => n + utf8.encode(jsonEncode(r)).length + 1);
  @override
  Future<int> clear() async {
    final count = rows.length;
    rows.clear();
    return count;
  }
}

class ObservedErrorHandler extends ErrorInterceptorHandler {
  ObservedErrorHandler() {
    // Receive the interceptor hand-off exactly as Dio's internal pipeline does.
    future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final logger = AppLogger.I;
  late MemoryStorage storage;
  late Directory root;
  late DateTime now;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cqut_diagnostic_test_');
    storage = MemoryStorage();
    now = DateTime.now().toUtc();
    await logger.init(
      enableConsole: false,
      storage: storage,
      exportDirectory: Directory('${root.path}/exports'),
      clock: () => now,
    );
  });
  tearDown(() async {
    storage.gate?.complete();
    storage.gate = null;
    await logger.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('routine traffic stays in a time/count/byte bounded ring and never persists', () async {
    for (var i = 0; i < 400; i++) {
      logger.info('Schedule', '正常刷新 $i', fields: {'detail': '中文' * 500});
    }
    await logger.flush();
    expect(storage.rows, isEmpty);
    expect(logger.recent.length, lessThanOrEqualTo(64));
    expect(
      utf8
          .encode(jsonEncode(logger.recent.map((e) => e.fields).toList()))
          .length,
      lessThanOrEqualTo(64 * 1024),
    );
    now = now.add(const Duration(minutes: 3));
    expect(logger.recent, isEmpty);
  });

  test('failure contains trace, sanitized metadata, stack and relevant breadcrumbs', () async {
    logger.runWithTraceId('load-1', () {
      logger.info('Schedule', '准备读取缓存', fields: {'action': 'cache_read'});
      logger.error(
        'Schedule',
        '课表解析失败',
        error: const FormatException('invalid response'),
        stackTrace: StackTrace.fromString(
          '#0 parse (package:app/schedule.dart:42:3)',
        ),
        fields: {
          'action': 'parse',
          'status': 'failed',
          'token': 'secret',
          'response_body': 'do not persist',
          'uri': 'https://example.test/path?token=secret&page=2',
        },
      );
    });
    await logger.flush();
    final row = storage.rows.single;
    expect(row['operationId'], 'load-1');
    expect(row['sessionId'], hasLength(16));
    expect(row['errorType'], 'FormatException');
    expect(row['stackTrace'], contains('schedule.dart:42'));
    expect((row['context'] as List).single['message'], '准备读取缓存');
    expect((row['fields'] as Map)['token'], '<redacted>');
    expect((row['fields'] as Map)['response_body'], '<omitted>');
    expect(jsonEncode(row), isNot(contains('=secret')));
  });

  test(
    'UTF-8 and escaped controls remain within 16KiB while stack takes priority',
    () async {
      logger.error(
        '模块' * 5000,
        '消息' * 10000,
        error: StateError('错误' * 10000),
        stackTrace: StackTrace.fromString(
          '#0 important_source.dart:12\n${'\t错误' * 10000}',
        ),
        fields: {
          'action': '阶段' * 10000,
          'details': '\t' * 10000,
          'trace_id': '操作' * 10000,
        },
      );
      await logger.flush();
      final row = storage.rows.single;
      expect(
        utf8.encode(jsonEncode(row)).length + 1,
        lessThanOrEqualTo(16 * 1024),
      );
      expect(
        utf8.encode(row['stackTrace'] as String).length,
        lessThanOrEqualTo(8 * 1024),
      );
      expect(row['stackTrace'], startsWith('#0 important_source.dart:12'));
      expect(row['stackTrace'], contains('[截断]'));
    },
  );

  test(
    'raw credentials in exception, message and stack are redacted',
    () async {
      logger.error(
        'Login',
        'token=secret-one https://student:password@example.test/login',
        error: StateError('password:secret-two cookie=secret-three'),
        stackTrace: StackTrace.fromString('#0 user token=secret-four'),
      );
      await logger.flush();
      final text = jsonEncode(storage.rows);
      for (final credential in [
        'secret-one',
        'secret-two',
        'secret-three',
        'secret-four',
        'student:password',
      ]) {
        expect(text, isNot(contains(credential)));
      }
      expect(text, contains('<redacted>'));
    },
  );

  test(
    'network failure causes and outcomes do not collapse into one fingerprint',
    () async {
      for (final type in ['connectionTimeout', 'connectionError']) {
        logger.error(
          'HTTP',
          '网络请求失败',
          error: StateError(type),
          stackTrace: StackTrace.fromString('#0 client'),
          fields: {
            'method': 'GET',
            'uri': 'https://example.test/data',
            'error_type': type,
            'outcome': 'cache_ignored',
          },
        );
      }
      await logger.flush();
      expect(storage.rows.length, 2);
      expect(
        storage.rows.first['fingerprint'],
        isNot(storage.rows.last['fingerprint']),
      );
      expect(storage.rows.first['outcome'], 'cache_ignored');
    },
  );

  test('pre-init failure is preserved and normal breadcrumbs ignore console threshold', () async {
    await logger.dispose();
    logger.fatal(
      'Startup',
      'early failure',
      error: StateError('early'),
      stackTrace: StackTrace.fromString('#0 startup'),
    );
    await logger.init(
      source: 'background',
      minLevel: LogLevel.fatal,
      enableConsole: false,
      storage: storage,
      exportDirectory: Directory('${root.path}/exports'),
      clock: () => now,
    );
    logger.runWithTraceId('background-startup', () {
      logger.debug('Worker', '正常上下文');
      logger.error('Worker', '失败', error: StateError('later'));
    });
    await logger.flush();
    expect(storage.rows.first['source'], 'background');
    expect((storage.rows.last['context'] as List).single['message'], '正常上下文');
  });

  test('independent occurrences retain unique roots while only sharing stack templates', () async {
    void report() => logger.warn(
      'HTTP',
      'request failed',
      error: StateError('bad'),
      stackTrace: StackTrace.fromString('#0 send (network.dart:5:3)'),
    );
    report();
    report();
    report();
    await logger.flush();
    expect(storage.rows.length, 3);
    expect(storage.rows.map((row) => row['rootEventId']).toSet().length, 3);
    expect(
      storage.rows.last['stackReferenceEventId'],
      storage.rows.first['eventId'],
    );
    report();
    report();
    now = now.add(const Duration(seconds: 61));
    report();
    await logger.flush();
    expect(storage.rows.where((r) => r['kind'] == 'summary'), isEmpty);
    expect(storage.rows.last['kind'], 'error');
    expect(storage.rows.last['stackTrace'], isNotEmpty);
  });

  test(
    'mapped and upper layer failures share root without repeated stack',
    () async {
      final cause = StateError('transport');
      final mapped = FormatException('business');
      logger.error(
        'HTTP',
        'network failed',
        error: cause,
        stackTrace: StackTrace.fromString('#0 send'),
      );
      logger.linkFailure(mapped, cause);
      logger.runWithTraceId(
        'login',
        () => logger.logOperationFailure(
          'Login',
          '登录失败',
          error: mapped,
          stackTrace: StackTrace.fromString('#0 login'),
          fields: {'action': 'authenticate'},
        ),
      );
      await logger.flush();
      expect(storage.rows.length, 2);
      expect(storage.rows.last['rootEventId'], storage.rows.first['eventId']);
      expect(storage.rows.last['stackTrace'], '');
      expect(storage.rows.last['kind'], 'outcome');
    },
  );

  test('trace propagation rethrows handled failures without inventing fatal errors', () async {
    await expectLater(
      logger.runWithTraceIdAsync<void>('test-trace', () async {
        expect(logger.currentTraceId, 'test-trace');
        throw ArgumentError('handled');
      }),
      throwsArgumentError,
    );
    await logger.flush();
    expect(storage.rows, isEmpty);
  });

  test('saturated queue honors both budgets, prioritizes errors and reports losses', () async {
    storage.gate = Completer<void>();
    logger.error('App', 'initial');
    for (var i = 0; i < 250; i++) {
      logger.warn(
        'Warning',
        'warning $i',
        stackTrace: StackTrace.fromString('stack $i ${'中' * 3000}'),
      );
    }
    for (var i = 0; i < 20; i++) {
      logger.error('App', 'critical $i');
    }
    expect(logger.metrics.queueDepth, lessThanOrEqualTo(128));
    expect(logger.metrics.queueBytes, lessThanOrEqualTo(512 * 1024));
    expect(logger.metrics.dropped, greaterThan(0));
    storage.gate!.complete();
    storage.gate = null;
    await logger.flush();
    expect(
      storage.rows
          .where((r) => r['message'].toString().startsWith('critical'))
          .length,
      20,
    );
    expect(storage.rows.last['kind'], 'dropped');
    expect(storage.rows.last['droppedCount'], logger.metrics.dropped);
  });

  test(
    'write errors cannot escape into the business operation or recurse',
    () async {
      storage.fail = true;
      logger.error('App', 'disk failure');
      await logger.flush();
      expect(logger.metrics.writeErrors, 1);
      expect(logger.metrics.queueDepth, 0);
      expect(storage.rows, isEmpty);
    },
  );

  test('Dio logs cancellation and successes in memory, failure has request metadata only', () async {
    final interceptor = logger.dioInterceptor();
    final options = RequestOptions(
      path: 'https://user:secret@example.test/data?account=123',
      data: {'password': 'sensitive'},
    );
    interceptor.onRequest(options, RequestInterceptorHandler());
    interceptor.onResponse(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: {'data': 'private'},
      ),
      ResponseInterceptorHandler(),
    );
    interceptor.onError(
      DioException(requestOptions: options, type: DioExceptionType.cancel),
      ObservedErrorHandler(),
    );
    await logger.flush();
    expect(storage.rows, isEmpty);
    interceptor.onError(
      DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
        message: 'timed out',
        stackTrace: StackTrace.fromString('#0 client'),
      ),
      ObservedErrorHandler(),
    );
    await logger.flush();
    final fields = storage.rows.single['fields'] as Map;
    expect(fields['uri'], 'https://example.test/data');
    expect(fields['method'], 'GET');
    expect(fields['duration_ms'], isA<int>());
    expect(storage.rows.single['errorType'], 'DioException');
    expect(fields['dio_type'], 'connectionTimeout');
    expect(jsonEncode(storage.rows), isNot(contains('sensitive')));
  });

  test('export keeps complete newest records, counts all bytes and enforces count/age', () async {
    for (var i = 0; i < 160; i++) {
      logger.error(
        '故障',
        '异常编号 $i',
        error: StateError('failure $i'),
        stackTrace: StackTrace.fromString('#0 source $i\n${'中文' * 2000}'),
      );
    }
    await logger.flush();
    storage.rows.add({
      'timestamp': now.subtract(const Duration(days: 4)).toIso8601String(),
      'level': 'error',
      'module': 'old',
      'message': 'EXPIRED_MARKER',
    });
    final first = await logger.exportLogs();
    final file = File(first);
    final text = await file.readAsString();
    expect(await file.length(), lessThanOrEqualTo(1024 * 1024));
    expect(text, contains('异常编号 159'));
    expect(text, contains('[截断]'));
    expect(text, isNot(contains('EXPIRED_MARKER')));
    expect(text, contains('"stackTrace":"#0 source 159\\n'));
    for (var i = 0; i < 4; i++) {
      await logger.exportLogs();
    }
    final directory = Directory('${root.path}/exports');
    expect(await directory.list().length, 3);
    final oldest = (await directory.list().toList()).cast<File>().first;
    await oldest.setLastModified(now.subtract(const Duration(days: 4)));
    await logger.pruneLogs();
    expect(await oldest.exists(), isFalse);
    await logger.clearLogFiles();
    expect(await directory.list().length, 0);
    expect(storage.rows, isEmpty);
  });

  test('export orders mixed native timestamp precision and retains outcome root atomically', () async {
    final second = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    ).toUtc();
    storage.rows.addAll([
      {
        'timestamp': second.toIso8601String().replaceFirst('.000Z', 'Z'),
        'level': 'error',
        'eventId': 'root',
        'kind': 'error',
        'message': 'ROOT_MARKER',
        'stackTrace': '#0 native root\n${'中' * 2000}',
      },
      {
        'timestamp': second
            .add(const Duration(milliseconds: 1))
            .toIso8601String(),
        'level': 'error',
        'eventId': 'outcome',
        'rootEventId': 'root',
        'kind': 'outcome',
        'message': 'OUTCOME_MARKER',
      },
      {
        'timestamp': second
            .add(const Duration(milliseconds: 2))
            .toIso8601String(),
        'level': 'error',
        'eventId': 'summary',
        'rootEventId': 'root',
        'kind': 'summary',
        'message': 'SUMMARY_MARKER',
        'repeatCount': 2,
      },
    ]);
    final full = await File(await logger.exportLogs()).readAsString();
    expect(
      full.indexOf('ROOT_MARKER'),
      lessThan(full.indexOf('OUTCOME_MARKER')),
    );
    expect(
      full.indexOf('OUTCOME_MARKER'),
      lessThan(full.indexOf('SUMMARY_MARKER')),
    );
    expect(
      full,
      contains('error=1'),
    ); // Legacy summary lacks summarizedKind and remains explicitly unknown.
    expect(full, contains('"unknownEventCount":2'));
    final bounded = File(await logger.exportLogs(maxTotalBytes: 1024));
    expect(await bounded.length(), lessThanOrEqualTo(1024));
    final text = await bounded.readAsString();
    expect(text, isNot(contains('OUTCOME_MARKER')));
    expect(text, isNot(contains('SUMMARY_MARKER')));
  });

  test('fixed file slots include current files and retain at most 2MiB across roles', () async {
    final directory = Directory('${root.path}/runtime');
    final writers = [
      for (final role in ['foreground', 'background', 'native'])
        FileDiagnosticStorage(directory, role),
    ];
    for (final writer in writers) {
      await writer.initialize();
    }
    final row = {
      'timestamp': now.toIso8601String(),
      'level': 'error',
      'message': '中' * 4800,
    };
    await Future.wait([
      for (final writer in writers)
        () async {
          for (var i = 0; i < 150; i++) {
            await writer.write({...row, 'eventId': '$i'});
          }
        }(),
    ]);
    final files = (await directory.list().toList()).cast<File>();
    expect(files.length, 8);
    expect(
      files
          .where((f) => f.uri.pathSegments.last.startsWith('foreground'))
          .length,
      4,
    );
    var total = 0;
    for (final file in files) {
      final bytes = await file.length();
      total += bytes;
      expect(bytes, lessThanOrEqualTo(256 * 1024));
      for (final line in await file.readAsLines()) {
        expect(jsonDecode(line), isA<Map>());
      }
    }
    expect(total, lessThanOrEqualTo(2 * 1024 * 1024));
    final expired = files.first;
    await expired.setLastModified(now.subtract(const Duration(days: 4)));
    await writers.first.prune();
    expect(await expired.exists(), isFalse);
    final outdated = File('${directory.path}/foreground-0.jsonl');
    await outdated.writeAsString(
      '${jsonEncode({...row, 'timestamp': now.subtract(const Duration(days: 4)).toIso8601String()})}\n',
    );
    expect(
      (await writers.first.snapshot()).any(
        (r) =>
            r['timestamp'] ==
            now.subtract(const Duration(days: 4)).toIso8601String(),
      ),
      isFalse,
    );
  });

  test('a failed root write can recover with the same error and full stack immediately', () async {
    final error = StateError('network lost');
    final stack = StackTrace.fromString('#0 original_throw_site');
    storage.fail = true;
    logger.error('HTTP', '网络错误', error: error, stackTrace: stack);
    await logger.flush();
    expect(storage.rows, isEmpty);
    storage.fail = false;
    logger.error('HTTP', '网络错误', error: error, stackTrace: stack);
    await logger.flush();
    expect(storage.rows.single['kind'], 'error');
    expect(storage.rows.single['stackTrace'], contains('original_throw_site'));
    expect(storage.rows.single['rootEventId'], storage.rows.single['eventId']);
  });

  test(
    'explicit expected HTTP statuses and all cancellations remain breadcrumbs',
    () async {
      final interceptor = logger.dioInterceptor();
      final options = RequestOptions(
        path: 'https://example.test/notice',
        extra: {
          'diagnostic_expected_statuses': [403],
        },
      );
      interceptor.onError(
        DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 403),
          type: DioExceptionType.badResponse,
        ),
        ObservedErrorHandler(),
      );
      interceptor.onResponse(
        Response(requestOptions: options, statusCode: 403),
        ResponseInterceptorHandler(),
      );
      logger.warn(
        'Upper',
        'cancelled',
        error: DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        ),
      );
      await logger.flush();
      expect(storage.rows, isEmpty);
      final ordinary = RequestOptions(path: 'https://example.test/notice');
      interceptor.onError(
        DioException(
          requestOptions: ordinary,
          response: Response(requestOptions: ordinary, statusCode: 403),
          type: DioExceptionType.badResponse,
        ),
        ObservedErrorHandler(),
      );
      await logger.flush();
      expect(storage.rows.single['level'], 'error');
    },
  );

  test('Android exports publish through MediaStore without private duplicate files', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var pruneCalls = 0;
    var clearCalls = 0;
    String? content;
    messenger.setMockMethodCallHandler(AndroidDiagnosticStorage.channel, (
      call,
    ) async {
      switch (call.method) {
        case 'pruneExports':
          pruneCalls++;
          return 0;
        case 'publishExport':
          final args = call.arguments as Map;
          content = args['content'] as String;
          expect(
            args['fileName'],
            matches(RegExp(r'^cqut_diagnostic_.*\.log$')),
          );
          return '/storage/emulated/0/Download/CQUT-Helper/log/${args['fileName']}';
        case 'exportStats':
          return {'bytes': 1234, 'files': 1};
        case 'clearExports':
          clearCalls++;
          return 2;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        AndroidDiagnosticStorage.channel,
        null,
      ),
    );
    await logger.init(
      enableConsole: false,
      storage: storage,
      exportStorage: AndroidDiagnosticExport(),
      clock: () => now,
    );
    for (var i = 0; i < 150; i++) {
      storage.rows.add({
        'timestamp': now.toIso8601String(),
        'level': 'error',
        'eventId': 'event-$i',
        'kind': 'error',
        'message': '异常 $i',
        'stackTrace': '#0 source\n${'中' * 2500}',
      });
    }
    final path = await logger.exportLogs();
    expect(path, startsWith('/storage/emulated/0/Download/CQUT-Helper/log/'));
    expect(utf8.encode(content!).length, lessThanOrEqualTo(1024 * 1024));
    expect(content, contains('[截断]'));
    expect(await root.list().length, 0);
    final expectedBytes = await storage.bytes() + 1234;
    expect(await logger.getLogBytes(), expectedBytes);
    expect(await logger.clearLogFiles(), 152);
    expect(clearCalls, 1);
    expect(pruneCalls, greaterThanOrEqualTo(3));
    await expectLater(
      AndroidDiagnosticExport().publish(
        'cqut_diagnostic_huge.log',
        'x' * (1024 * 1024 + 1),
      ),
      throwsArgumentError,
    );
  });

  test(
    'Android writer rejection is observable and snapshot schema is shared',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(AndroidDiagnosticStorage.channel, (
        call,
      ) async {
        switch (call.method) {
          case 'init':
            return null;
          case 'stats':
            return {
              'path': '/files/logs/diagnostics',
              'bytes': 100,
              'files': 1,
            };
          case 'write':
            return false;
          case 'snapshot':
            return [
              {'timestamp': now.toIso8601String(), 'level': 'error'},
            ];
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          AndroidDiagnosticStorage.channel,
          null,
        ),
      );
      final writer = AndroidDiagnosticStorage('background');
      await writer.initialize();
      expect(writer.path, '/files/logs/diagnostics');
      expect(await writer.bytes(), 100);
      await expectLater(
        writer.write({'level': 'error'}),
        throwsA(isA<FileSystemException>()),
      );
      expect((await writer.snapshot()).single['level'], 'error');
    },
  );
}
