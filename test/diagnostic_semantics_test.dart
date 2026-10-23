import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/diagnostic_operation.dart';
import 'package:cqut_helper/utils/diagnostic_error.dart';
import 'package:cqut_helper/utils/diagnostic_report.dart';
import 'package:cqut_helper/utils/diagnostics_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage extends DiagnosticStorage {
  final rows = <Map<String, Object?>>[];
  @override
  String? get path => null;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> prune() async {}
  @override
  Future<void> write(Map<String, Object?> event) async {
    rows.add(jsonDecode(jsonEncode(event)) as Map<String, Object?>);
  }

  @override
  Future<List<Map<String, Object?>>> snapshot() async => rows;
  @override
  Future<int> bytes() async => 0;
  @override
  Future<int> clear() async {
    final n = rows.length;
    rows.clear();
    return n;
  }
}

class _BrokenString {
  @override
  String toString() => throw StateError('broken string conversion');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final logger = AppLogger.I;
  late _MemoryStorage storage;
  late DateTime now;
  late Directory exports;
  setUp(() async {
    storage = _MemoryStorage();
    now = DateTime.utc(2026, 10, 15);
    exports = await Directory.systemTemp.createTemp('diagnostic_semantics_');
    await logger.init(
      storage: storage,
      enableConsole: false,
      exportDirectory: exports,
      clock: () => now,
    );
  });
  tearDown(() async {
    await logger.dispose();
    await exports.delete(recursive: true);
  });
  void failure(Object error, {String stage = 'transport'}) =>
      logger.logOperationFailure(
        'API',
        'request failed',
        error: error,
        stackTrace: StackTrace.fromString('#0 request (api.dart:10)'),
        fields: {'stage': stage},
      );

  void attempt(int number, {Object? error, String path = '/schedule'}) =>
      logger.info(
        'HTTP',
        'request result',
        error: error,
        stackTrace: StackTrace.fromString('#0 request (client.dart:10)'),
        fields: {
          'diagnostic_kind': 'attempt',
          'method': 'GET',
          'uri': 'https://example.test$path',
          'attempt': number,
          'max_attempts': 3,
          'status_code': error == null ? 200 : 502,
          'outcome': error == null ? 'succeeded' : 'failed',
          if (error != null) 'error_category': 'HTTP_SERVER_ERROR',
        },
      );

  test(
    'retry group records every failed attempt and one terminal incident',
    () async {
      final finalError = StateError('upstream');
      final startedAt = now;
      await expectLater(
        logger.runWithTraceIdAsync(
          'operation',
          () => logger.runWithRetryGroup<void>(() async {
            attempt(1, error: StateError('upstream'));
            now = now.add(const Duration(seconds: 1));
            attempt(2, error: finalError);
            now = now.add(const Duration(seconds: 2));
            failure(finalError, stage: 'business');
            throw finalError;
          }),
        ),
        throwsStateError,
      );
      await logger.flush();
      final root = storage.rows.singleWhere((r) => r['kind'] == 'incident');
      final attempts = storage.rows
          .where((r) => r['kind'] == 'attempt')
          .toList();
      expect(root['schema'], 5);
      expect(root['attempts'], 2);
      expect(root['firstAttemptEventId'], attempts.first['eventId']);
      expect(root['lastAttemptEventId'], attempts.last['eventId']);
      expect(root['timestamp'], now.toIso8601String());
      expect(root['firstSeen'], startedAt.toIso8601String());
      expect(
        root['lastSeen'],
        startedAt.add(const Duration(seconds: 1)).toIso8601String(),
      );
      for (final row in storage.rows.where((r) => r['kind'] != 'incident')) {
        expect(row['rootEventId'], root['eventId']);
        expect(row.containsKey('errorCategory'), isFalse);
        expect(row.containsKey('reason'), isFalse);
        expect(row['stackTrace'], '');
      }
      final stats = diagnosticReportStatistics(storage.rows);
      expect(stats['rootErrorCount'], 1);
      expect(stats['failedAttemptCount'], 2);
      expect(stats['repeatedOccurrenceCount'], 1);
      expect(stats['allEventErrorCount'], 1);
      final sequences = storage.rows.map((r) => r['sequence'] as int).toList();
      expect(sequences, orderedEquals(sequences.toList()..sort()));
      expect(sequences.toSet().length, sequences.length);
    },
  );

  test(
    'independent requests in one operation and retry invocation stay separate',
    () async {
      await logger.runWithTraceIdAsync('operation', () async {
        for (var group = 0; group < 2; group++) {
          await logger.runWithRetryGroup(() async {
            // Two calls to the same endpoint in each iteration are independent.
            for (var number = 1; number <= 2; number++) {
              attempt(number, error: StateError('first'));
              attempt(number, error: StateError('second'));
            }
          });
        }
      });
      await logger.flush();
      final roots = storage.rows.where((r) => r['kind'] == 'incident').toList();
      expect(roots.length, 4);
      expect(roots.map((r) => r['rootEventId']).toSet().length, 4);
      expect(roots.map((r) => r['attempts']), everyElement(2));
      expect(storage.rows.where((r) => r['kind'] == 'recovery'), isEmpty);
    },
  );

  test('failed attempt persists before retry terminates', () async {
    final gate = Completer<void>();
    final action = logger.runWithRetryGroup(() async {
      attempt(1, error: StateError('upstream'));
      await gate.future;
    });
    await logger.flush();
    expect(storage.rows.single['kind'], 'attempt');
    final stats = diagnosticReportStatistics(storage.rows);
    expect(stats['rootErrorCount'], 0);
    expect(stats['failedAttemptCount'], 1);
    expect(stats['unknownEventCount'], 0);
    gate.complete();
    await action;
  });

  test('concurrent retry invocations never share causal roots', () async {
    final gate = Completer<void>();
    final actions = <Future<void>>[];
    for (var i = 0; i < 2; i++) {
      actions.add(
        logger.runWithTraceIdAsync(
          'shared-operation',
          () => logger.runWithRetryGroup(() async {
            attempt(1, error: StateError('upstream'));
            await gate.future;
            attempt(2, error: StateError('upstream'));
          }),
        ),
      );
    }
    gate.complete();
    await Future.wait(actions);
    await logger.flush();
    final roots = storage.rows.where((r) => r['kind'] == 'incident').toList();
    expect(roots.length, 2);
    expect(roots.map((r) => r['rootEventId']).toSet().length, 2);
    expect(roots.map((r) => r['attempts']), everyElement(2));
  });

  test(
    'recovery requires a later successful request within the same group',
    () async {
      await logger.runWithRetryGroup(() async {
        attempt(1, error: StateError('upstream'));
        attempt(2);
      });
      await logger.runWithRetryGroup(() async {
        attempt(1, error: StateError('upstream'));
        attempt(2, path: '/unrelated');
      });
      await logger.flush();
      final roots = storage.rows.where((r) => r['kind'] == 'incident').toList();
      expect(roots.map((r) => r['level']), ['warn', 'error']);
      final recovery = storage.rows.singleWhere((r) => r['kind'] == 'recovery');
      expect(recovery['resolvesIncidentId'], roots.first['eventId']);
      expect(
        (recovery['fields'] as Map)['related_root_event_id'],
        roots.first['eventId'],
      );
    },
  );

  test(
    'operation outcomes persist reason without adding affected operations',
    () async {
      for (final outcome in ['succeeded', 'failed', 'skipped']) {
        logger.info(
          'Worker',
          'task completed',
          fields: {
            'diagnostic_kind': 'operation_outcome',
            'operation_id': outcome,
            'outcome': outcome,
            'reason': 'task_$outcome',
          },
        );
      }
      await logger.flush();
      expect(storage.rows.length, 3);
      expect(storage.rows.last['reason'], 'task_skipped');
      final stats = diagnosticReportStatistics(storage.rows);
      expect(stats['rootErrorCount'], 0);
      expect(stats['affectedOperationCount'], 0);
    },
  );

  test('new successful outcomes cannot displace an older root in export', () {
    final rows = <Map<String, Object?>>[
      {
        'timestamp': now.toIso8601String(),
        'kind': 'incident',
        'level': 'error',
        'eventId': 'root',
        'rootEventId': 'root',
        'message': 'ROOT_MUST_SURVIVE',
        'stackTrace': '#0 original',
      },
      for (var i = 1; i <= 100; i++)
        {
          'timestamp': now.add(Duration(seconds: i)).toIso8601String(),
          'kind': 'operation_outcome',
          'level': 'info',
          'eventId': 'outcome-$i',
          'message': 'TASK_SUCCEEDED_$i',
          'fields': {'details': 'x' * 200},
        },
    ];
    final report = renderDiagnosticReport(
      DiagnosticReportInput(
        records: rows,
        budget: 2048,
        now: now,
        version: 'test',
        device: 'test',
        sessionId: 'test',
        dropped: 0,
        writeErrors: 0,
      ),
    );
    expect(report.split('三、原始数据（JSONL）').last, contains('ROOT_MUST_SURVIVE'));
    expect(utf8.encode(report).length, lessThanOrEqualTo(2048));
  });

  test(
    'bad response summaries omit Dio templates and redact student credentials',
    () {
      final options = RequestOptions(path: '/schedule');
      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: options, statusCode: 502),
        message: 'LONG_DIO_BAD_RESPONSE_TEMPLATE',
      );
      expect(
        safeDiagnosticErrorSummary(error),
        'DioException(badResponse): HTTP 502',
      );
      expect(diagnosticErrorDetails(error).containsKey('dio_message'), isFalse);
      final safe = sanitizeDiagnosticText(
        '{"stuNo":123456,"ticket":"secret-ticket",'
        '"password":"secret-pass"}',
      );
      for (final secret in ['123456', 'secret-ticket', 'secret-pass']) {
        expect(safe, isNot(contains(secret)));
      }
    },
  );

  test(
    'fingerprint grouping never aliases independent operation roots',
    () async {
      for (final operation in ['A', 'B']) {
        logger.runWithTraceId(operation, () => failure(StateError('offline')));
      }
      await logger.flush();
      final a = storage.rows[0], b = storage.rows[1];
      expect(a['kind'], 'incident');
      expect(b['kind'], 'incident');
      expect(a['fingerprint'], b['fingerprint']);
      expect(a['rootEventId'], a['eventId']);
      expect(b['rootEventId'], b['eventId']);
      expect(a['rootEventId'], isNot(b['rootEventId']));
      expect(b['operationId'], 'B');
      expect(b['stackReferenceEventId'], a['eventId']);
      expect(b['stackTrace'], '');
      final stats = diagnosticReportStatistics(storage.rows);
      expect(stats['rootErrorCount'], 2);
      expect(stats['repeatedOccurrenceCount'], 0);
      expect(stats['affectedOperationCount'], 2);
    },
  );

  test('same root preserves first stage outcome and summarizes only repeated propagation', () async {
    final error = StateError('offline');
    logger.runWithTraceId('A', () {
      failure(error);
      failure(error, stage: 'load');
      failure(error, stage: 'load');
    });
    await logger.flush();
    expect(storage.rows.map((r) => r['kind']), [
      'incident',
      'derived',
      'summary',
    ]);
    final summary = storage.rows.last;
    expect(summary['summarizedKind'], 'derived');
    expect(summary['repeatCount'], 1);
    expect(summary['totalCount'], 2);
    expect(summary['rootEventId'], storage.rows.first['eventId']);
    final stats = diagnosticReportStatistics(storage.rows);
    expect(stats['originalEventCount'], 3);
    expect(stats['rootErrorCount'], 1);
    expect(stats['error'], 1);
    expect(stats['allEventErrorCount'], 1);
    final sequences = storage.rows.map((r) => r['sequence'] as int).toList();
    expect(sequences, orderedEquals(sequences.toList()..sort()));
    expect(sequences.toSet().length, sequences.length);
    expect(stats['allEventWarningCount'], 2);
  });

  test('automatic Throwable identity is isolated by operation', () async {
    final error = StateError('reused');
    logger.runWithTraceId('A', () => failure(error));
    logger.runWithTraceId('B', () => failure(error));
    await logger.flush();
    expect(storage.rows.map((r) => r['kind']), ['incident', 'incident']);
    expect(
      storage.rows[0]['rootEventId'],
      isNot(storage.rows[1]['rootEventId']),
    );
  });

  test(
    'different business outcomes at the same stage remain distinct',
    () async {
      final error = StateError('offline');
      logger.runWithTraceId('A', () {
        failure(error);
        for (final outcome in ['cache_used', 'failed']) {
          logger.logOperationFailure(
            'Business',
            'load result',
            error: error,
            fields: {'stage': 'load', 'outcome': outcome},
          );
        }
      });
      await logger.flush();
      expect(
        storage.rows
            .where((row) => row['kind'] == 'derived')
            .map((row) => row['outcome']),
        ['cache_used', 'failed'],
      );
    },
  );

  test('unscoped propagation shares inferred operation without merging independent roots', () async {
    final error = StateError('offline');
    failure(error);
    failure(error, stage: 'load');
    failure(StateError('offline'));
    await logger.flush();
    expect(storage.rows[1]['operationId'], storage.rows[0]['operationId']);
    expect(
      storage.rows[2]['operationId'],
      isNot(storage.rows[0]['operationId']),
    );
    final stats = diagnosticReportStatistics(storage.rows);
    expect(stats['affectedOperationCount'], 0);
    expect(stats['inferredOperationCount'], 2);
  });

  test(
    'explicit mapped cause inherits classification across business layers',
    () async {
      final cause = DioException(
        requestOptions: RequestOptions(path: '/schedule'),
        type: DioExceptionType.connectionError,
        error: const SocketException(
          'lookup failed',
          osError: OSError('DNS', 11001),
        ),
      );
      final mapped = FormatException('invalid response');
      logger.runWithTraceId('A', () {
        logger.logOperationFailure(
          'API',
          'request failed',
          error: cause,
          fields: {
            'stage': 'transport',
            'error_category': 'NETWORK_DNS_FAILED',
          },
        );
        logger.linkFailure(mapped, cause);
      });
      logger.runWithTraceId(
        'B',
        () => logger.logOperationFailure(
          'Business',
          'load failed',
          error: mapped,
          fields: {'stage': 'load', 'error_category': 'AUTH_FAILED'},
        ),
      );
      await logger.flush();
      expect(storage.rows.last['kind'], 'derived');
      expect(storage.rows.last.containsKey('errorCategory'), isFalse);
      expect(storage.rows.first['errorCategory'], 'NETWORK_DNS_FAILED');
      expect(storage.rows.last.containsKey('reason'), isFalse);
      expect(storage.rows.last['causeEventId'], storage.rows.first['eventId']);
      expect(storage.rows.last['operationId'], 'B');
      expect(storage.rows.last['rootEventId'], storage.rows.first['eventId']);
      logger.runWithTraceId(
        'C',
        () => logger.logOperationFailure(
          'Business',
          'load failed',
          error: mapped,
          fields: {'stage': 'load', 'error_category': 'AUTH_FAILED'},
        ),
      );
      await logger.flush();
      expect(storage.rows.where((r) => r['kind'] == 'derived').length, 2);
      expect(storage.rows.last['operationId'], 'C');
      expect(storage.rows.where((r) => r['kind'] == 'summary'), isEmpty);
    },
  );

  test(
    'normal operation stays in ring and has no invented failure type',
    () async {
      await runDiagnosticOperation(
        'API',
        'load',
        () async => 42,
        fields: {'error_type': 'DiagnosticFailure'},
      );
      await logger.flush();
      expect(storage.rows, isEmpty);
      expect(logger.recent.last.fields?['outcome'], 'succeeded');
      expect(logger.recent.last.fields?.containsKey('error_type'), isFalse);
    },
  );

  test(
    'success needs an explicit causal exception to record recovery',
    () async {
      final error = StateError('offline');
      await expectLater(
        logger.runWithTraceIdAsync(
          'A',
          () => runDiagnosticOperation<void>(
            'API',
            'load',
            () async => throw error,
          ),
        ),
        throwsStateError,
      );
      await logger.runWithTraceIdAsync(
        'B',
        () => runDiagnosticOperation('API', 'load', () async => 1),
      );
      await logger.flush();
      expect(storage.rows.where((r) => r['kind'] == 'recovery'), isEmpty);
      await logger.runWithTraceIdAsync(
        'A',
        () => runDiagnosticOperation('API', 'load', () async => 1),
      );
      await logger.flush();
      expect(storage.rows.where((r) => r['kind'] == 'recovery'), isEmpty);
      logger.runWithTraceId(
        'A',
        () => logger.logRecovery('API', 'retry succeeded', cause: error),
      );
      await logger.flush();
      final recovery = storage.rows.singleWhere((r) => r['kind'] == 'recovery');
      expect(recovery['operationId'], 'A');
      expect(
        (recovery['fields'] as Map)['related_root_event_id'],
        storage.rows.first['eventId'],
      );
    },
  );

  test(
    'diagnostic formatting failures never escape the business action',
    () async {
      final errorsBefore = logger.metrics.writeErrors;
      expect(() => failure(_BrokenString()), returnsNormally);
      expect(
        () => logger.warn('API', 'metadata', fields: {'bad': _BrokenString()}),
        returnsNormally,
      );
      failure(StateError('recoverable logger'));
      await logger.flush();
      expect(storage.rows.length, 1);
      expect(logger.metrics.writeErrors, errorsBefore + 2);
    },
  );

  test(
    'ordinary warning has diagnostic semantics without a fabricated root',
    () async {
      logger.warn(
        'API',
        'using cached calendar',
        fields: {'outcome': 'cache_used'},
      );
      await logger.flush();
      final row = storage.rows.single;
      expect(row['kind'], 'diagnostic');
      expect(row.containsKey('rootEventId'), isFalse);
      expect(row.containsKey('errorType'), isFalse);
    },
  );

  test('repeat statistics span stack template windows', () async {
    logger.runWithTraceId('A', () => failure(StateError('offline')));
    now = now.add(const Duration(seconds: 61));
    logger.runWithTraceId('B', () => failure(StateError('offline')));
    await logger.flush();
    expect(storage.rows.last.containsKey('stackReferenceEventId'), isFalse);
    expect(
      diagnosticReportStatistics(storage.rows)['repeatedOccurrenceCount'],
      0,
    );
  });

  test('JSONL export retains unknown fields and atomically includes recovery cause', () {
    final rows = <Map<String, Object?>>[
      {
        'timestamp': now.toIso8601String(),
        'kind': 'error',
        'level': 'error',
        'eventId': 'root',
        'message': 'ROOT_MARKER',
        'stackTrace': '中' * 1400,
        'customFutureField': {'retained': true},
      },
      {
        'timestamp': now.add(const Duration(seconds: 1)).toIso8601String(),
        'kind': 'recovery',
        'level': 'info',
        'eventId': 'recovered',
        'message': 'RECOVERY_MARKER',
        'fields': {'related_root_event_id': 'root'},
      },
    ];
    String render(int budget) => renderDiagnosticReport(
      DiagnosticReportInput(
        records: rows,
        budget: budget,
        now: now,
        version: 'test',
        device: 'test',
        sessionId: 'test',
        dropped: 0,
        writeErrors: 0,
      ),
    );
    final full = render(1024 * 1024);
    expect(full, contains('"customFutureField":{"retained":true}'));
    final bounded = render(1024), raw = bounded.split('三、原始数据（JSONL）').last;
    expect(utf8.encode(bounded).length, lessThanOrEqualTo(1024));
    expect(raw.contains('RECOVERY_MARKER'), raw.contains('ROOT_MARKER'));
    expect(bounded, contains('[截断]'));
  });
}
