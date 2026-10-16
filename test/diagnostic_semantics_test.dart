import 'dart:convert';
import 'dart:io';

import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/diagnostic_operation.dart';
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

  test(
    'fingerprint grouping never aliases independent operation roots',
    () async {
      for (final operation in ['A', 'B']) {
        logger.runWithTraceId(operation, () => failure(StateError('offline')));
      }
      await logger.flush();
      final a = storage.rows[0], b = storage.rows[1];
      expect(a['kind'], 'error');
      expect(b['kind'], 'error');
      expect(a['fingerprint'], b['fingerprint']);
      expect(a['rootEventId'], a['eventId']);
      expect(b['rootEventId'], b['eventId']);
      expect(a['rootEventId'], isNot(b['rootEventId']));
      expect(b['operationId'], 'B');
      expect(b['stackReferenceEventId'], a['eventId']);
      expect(b['stackTrace'], '');
      final stats = diagnosticReportStatistics(storage.rows);
      expect(stats['rootErrorCount'], 2);
      expect(stats['repeatedOccurrenceCount'], 1);
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
    expect(storage.rows.map((r) => r['kind']), ['error', 'outcome', 'summary']);
    final summary = storage.rows.last;
    expect(summary['summarizedKind'], 'outcome');
    expect(summary['repeatCount'], 1);
    expect(summary['totalCount'], 2);
    expect(summary['rootEventId'], storage.rows.first['eventId']);
    final stats = diagnosticReportStatistics(storage.rows);
    expect(stats['originalEventCount'], 3);
    expect(stats['rootErrorCount'], 1);
    expect(stats['error'], 1);
    expect(stats['allEventErrorCount'], 3);
  });

  test('automatic Throwable identity is isolated by operation', () async {
    final error = StateError('reused');
    logger.runWithTraceId('A', () => failure(error));
    logger.runWithTraceId('B', () => failure(error));
    await logger.flush();
    expect(storage.rows.map((r) => r['kind']), ['error', 'error']);
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
            .where((row) => row['kind'] == 'outcome')
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
      expect(storage.rows.last['kind'], 'outcome');
      expect(storage.rows.last['errorCategory'], 'NETWORK_DNS_FAILED');
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
      expect(storage.rows.where((r) => r['kind'] == 'outcome').length, 2);
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
      1,
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
