import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cqut_helper/api/notice/notice_api.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/diagnostic_error.dart';
import 'package:cqut_helper/utils/diagnostics_storage.dart';
import 'package:cqut_helper/utils/retry_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RetryOnceAdapter implements HttpClientAdapter {
  _RetryOnceAdapter({this.failuresBeforeSuccess = 1});

  final int failuresBeforeSuccess;
  int attempts = 0;
  final List<DioException> errors = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts++;
    if (attempts <= failuresBeforeSuccess) {
      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
        message: 'connection timeout',
      );
      errors.add(error);
      throw error;
    }
    return ResponseBody.fromString(
      jsonEncode({'ok': true}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ServerFailureAdapter implements HttpClientAdapter {
  int attempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts++;
    return ResponseBody.fromString(
      '<html>private-response-body stuNo=20260001</html>',
      502,
      headers: {
        'server': ['cloudflare'],
        'cf-ray': ['ray-identifier'],
        'via': [
          'gateway',
          List.filled(300, '界').join(),
          'private-third-header-value',
        ],
        'x-request-id': ['request-identifier token=private-header-token'],
        'content-type': ['text/html'],
        'set-cookie': ['private-response-cookie'],
        'authorization': ['Bearer private-response-authorization'],
        'x-unlisted': ['private-unlisted-header'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ReorderedPairAdapter implements HttpClientAdapter {
  final pending = <String, Completer<ResponseBody>>{};
  final pairsStarted = <int, Completer<void>>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final attempt = options.extra['diagnostic_attempt'] as int;
    final request = options.extra['test_request'] as String;
    final result = Completer<ResponseBody>();
    pending['$attempt:$request'] = result;
    if (pending.containsKey('$attempt:a') &&
        pending.containsKey('$attempt:b')) {
      pairsStarted.putIfAbsent(attempt, Completer<void>.new).complete();
    }
    return result.future;
  }

  Future<void> waitForPair(int attempt) =>
      pairsStarted.putIfAbsent(attempt, Completer<void>.new).future;

  void complete(int attempt, String request) {
    pending['$attempt:$request']!.complete(
      ResponseBody.fromString(
        'response',
        attempt == 2 && request == 'a' ? 200 : 502,
        headers: {
          'content-type': ['text/plain'],
          'x-request-id': ['$request-$attempt'],
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('network categories use typed errors and platform DNS codes', () {
    DioException dioError(DioExceptionType type) => DioException(
      requestOptions: RequestOptions(path: '/'),
      type: type,
    );

    expect(
      classifyDiagnosticError(dioError(DioExceptionType.connectionTimeout)),
      'NETWORK_CONNECT_TIMEOUT',
    );
    expect(
      classifyDiagnosticError(dioError(DioExceptionType.receiveTimeout)),
      'NETWORK_RECEIVE_TIMEOUT',
    );
    expect(
      classifyDiagnosticError(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.receiveTimeout,
          error: SocketException(
            'timed out',
            osError: OSError('timeout', 10060),
          ),
        ),
      ),
      'NETWORK_RECEIVE_TIMEOUT',
    );
    expect(
      classifyDiagnosticError(dioError(DioExceptionType.sendTimeout)),
      'NETWORK_SEND_TIMEOUT',
    );
    expect(
      classifyDiagnosticError(dioError(DioExceptionType.transformTimeout)),
      'NETWORK_TRANSFORM_TIMEOUT',
    );
    expect(
      classifyDiagnosticError(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.unknown,
          error: SocketException(
            'Failed host lookup',
            osError: OSError('lookup', 8),
          ),
        ),
        platform: 'android',
      ),
      'NETWORK_DNS_FAILED',
    );
    expect(
      classifyDiagnosticError(
        SocketException('unclassified', osError: OSError('unknown', 8)),
        platform: 'linux',
      ),
      'NETWORK_CONNECTION_FAILED',
    );
    expect(
      classifyDiagnosticError(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 403,
          ),
        ),
      ),
      'HTTP_CLIENT_ERROR',
    );
    expect(
      classifyDiagnosticError(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 503,
          ),
        ),
      ),
      'HTTP_SERVER_ERROR',
    );
  });

  test(
    'diagnostic summaries omit FormatException source and redact secrets',
    () {
      final summary = safeDiagnosticErrorSummary(
        FormatException(
          'invalid JSON',
          '{"password":"private-password","token":"private-token"}',
        ),
      );
      expect(summary, 'invalid JSON');

      final text = sanitizeDiagnosticText(
        '{"token":"private-token","password":"private-password",'
        '"authorization":"Bearer private-bearer"}',
      );
      expect(text, isNot(contains('private-token')));
      expect(text, isNot(contains('private-password')));
      expect(text, isNot(contains('private-bearer')));
    },
  );

  test(
    'actual retry helper records per-request attempt and related recovery',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cqut-network-diagnostics-',
      );
      final logger = AppLogger.I;
      final storage = FileDiagnosticStorage(
        Directory('${temporary.path}/records'),
        'foreground',
      );
      await logger.init(
        enableConsole: false,
        storage: storage,
        exportDirectory: Directory('${temporary.path}/exports'),
      );

      final firstAdapter = _RetryOnceAdapter();
      final secondAdapter = _RetryOnceAdapter();
      final firstDio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = firstAdapter;
      final secondDio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = secondAdapter;
      logger.attachToDio(firstDio, tag: 'NetworkFirst');
      logger.attachToDio(secondDio, tag: 'NetworkSecond');

      Future<Response<Map<String, dynamic>>> request(Dio dio, String path) =>
          retryWithExponentialBackoff<Response<Map<String, dynamic>>>(
            () => dio.get<Map<String, dynamic>>(
              path,
              queryParameters: {'token': 'private-query-token'},
            ),
            maxAttempts: 2,
            initialDelay: const Duration(milliseconds: 7),
            jitterMs: 0,
          );

      try {
        await logger.runWithTraceIdAsync('network-operation', () async {
          await Future.wait([
            request(firstDio, '/same-endpoint'),
            request(secondDio, '/same-endpoint'),
          ]);
        });
        await logger.flush();
        final rows = await storage.snapshot();
        final failures = rows
            .where((row) => row['kind'] == 'incident')
            .toList();
        final recoveries = rows
            .where((row) => row['kind'] == 'recovery')
            .toList();

        expect(firstAdapter.attempts, 2);
        expect(secondAdapter.attempts, 2);
        expect(failures, hasLength(2));
        expect(recoveries, hasLength(2));
        expect(failures.map((row) => row['errorCategory']).toSet(), {
          'NETWORK_CONNECT_TIMEOUT',
        });
        expect(
          recoveries
              .map((row) => (row['fields'] as Map)['related_root_event_id'])
              .toSet(),
          failures.map((row) => row['eventId']).toSet(),
        );
        expect(recoveries.map((row) => row['operationId']).toSet(), {
          'network-operation',
        });

        final starts = logger.recent
            .where((event) => event.message == '请求开始')
            .toList();
        expect(starts, hasLength(4));
        expect(starts.map((event) => event.fields?['attempt']).toSet(), {1, 2});
        expect(starts.map((event) => event.fields?['max_attempts']).toSet(), {
          2,
        });
        expect(starts.map((event) => event.fields?['trace_id']).toSet(), {
          'network-operation',
        });
        expect(
          starts.map((event) => event.fields?['request_id']).toSet(),
          hasLength(4),
        );
        expect(jsonEncode(rows), isNot(contains('private-query-token')));
        final decisions = rows
            .where((row) => row['kind'] == 'retry_decision')
            .toList();
        expect(decisions, hasLength(2));
        expect(
          decisions.every(
            (row) => (row['fields'] as Map)['will_retry'] == true,
          ),
          isTrue,
        );
        expect(
          decisions.every((row) => (row['fields'] as Map)['backoff_ms'] == 7),
          isTrue,
        );
        expect(
          starts.map((event) => event.fields?['retry_group_id']).toSet(),
          hasLength(2),
        );
      } finally {
        await logger.dispose();
        await temporary.delete(recursive: true);
      }
    },
  );

  test('same endpoint retry slots follow request start order despite reversed responses', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cqut-network-reordered-',
    );
    final logger = AppLogger.I;
    final storage = FileDiagnosticStorage(
      Directory('${temporary.path}/records'),
      'foreground',
    );
    await logger.init(
      enableConsole: false,
      storage: storage,
      exportDirectory: Directory('${temporary.path}/exports'),
    );
    final adapter = _ReorderedPairAdapter();
    final dio = Dio(
      BaseOptions(baseUrl: 'https://example.test', validateStatus: (_) => true),
    )..httpClientAdapter = adapter;
    logger.attachToDio(dio, tag: 'NetworkReordered');
    try {
      await logger.runWithTraceIdAsync(
        'reordered-operation',
        () => logger.runWithRetryGroup(() async {
          for (var attempt = 1; attempt <= 2; attempt++) {
            await runWithDiagnosticContext(
              attempt: attempt,
              maxAttempts: 2,
              action: () async {
                final a = dio.get<String>(
                  '/same-endpoint',
                  options: Options(extra: {'test_request': 'a'}),
                );
                final b = dio.get<String>(
                  '/same-endpoint',
                  options: Options(extra: {'test_request': 'b'}),
                );
                await adapter.waitForPair(attempt);
                if (attempt == 1) {
                  adapter.complete(attempt, 'b');
                  await b;
                  adapter.complete(attempt, 'a');
                  await a;
                } else {
                  adapter.complete(attempt, 'a');
                  await a;
                  adapter.complete(attempt, 'b');
                  await b;
                }
              },
            );
          }
        }),
      );
      await logger.flush();
      final rows = await storage.snapshot();
      final attempts = rows.where((row) => row['kind'] == 'attempt').toList();
      final incidents = rows.where((row) => row['kind'] == 'incident').toList();
      final recoveries = rows
          .where((row) => row['kind'] == 'recovery')
          .toList();
      Map<String, Object?> responseAttempt(String id) => attempts.singleWhere(
        (row) =>
            ((row['fields'] as Map)['response_headers']
                as Map)['x-request-id'] ==
            id,
      );
      final a1 = responseAttempt('a-1');
      final b1 = responseAttempt('b-1');
      final b2 = responseAttempt('b-2');
      expect(attempts, hasLength(3));
      expect(incidents, hasLength(2));
      expect(
        attempts.map(
          (row) =>
              ((row['fields'] as Map)['response_headers']
                  as Map)['x-request-id'],
        ),
        ['b-1', 'a-1', 'b-2'],
      );
      expect(b2['rootEventId'], b1['rootEventId']);
      expect(b2['rootEventId'], isNot(a1['rootEventId']));
      expect(
        (b2['fields'] as Map)['retry_request_slot'],
        (b1['fields'] as Map)['retry_request_slot'],
      );
      expect(
        (a1['fields'] as Map)['retry_request_slot'],
        isNot((b1['fields'] as Map)['retry_request_slot']),
      );
      final recovered = incidents.singleWhere(
        (row) => row['eventId'] == a1['rootEventId'],
      );
      final failed = incidents.singleWhere(
        (row) => row['eventId'] == b1['rootEventId'],
      );
      expect(recovered['outcome'], 'recovered');
      expect(recovered['attempts'], 1);
      expect(failed['outcome'], 'failed');
      expect(failed['attempts'], 2);
      expect(failed['firstAttemptEventId'], b1['eventId']);
      expect(failed['lastAttemptEventId'], b2['eventId']);
      expect(recoveries, hasLength(1));
      expect(
        (recoveries.single['fields'] as Map)['related_root_event_id'],
        recovered['eventId'],
      );
    } finally {
      await logger.dispose();
      await temporary.delete(recursive: true);
    }
  });

  test(
    'exhausted retries retain attempts and decisions under one incident',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cqut-network-exhaustion-',
      );
      final logger = AppLogger.I;
      final storage = FileDiagnosticStorage(
        Directory('${temporary.path}/records'),
        'foreground',
      );
      await logger.init(
        enableConsole: false,
        storage: storage,
        exportDirectory: Directory('${temporary.path}/exports'),
      );

      final adapter = _RetryOnceAdapter(failuresBeforeSuccess: 3);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter;
      logger.attachToDio(dio, tag: 'NetworkExhausted');
      final retryAttempts = <int>[];

      try {
        Object? caught;
        try {
          await retryWithExponentialBackoff(
            () => dio.get<void>('/fails'),
            maxAttempts: 3,
            initialDelay: Duration.zero,
            jitterMs: 0,
            onError: (attempt, _) => retryAttempts.add(attempt),
          );
        } catch (error) {
          caught = error;
        }
        await logger.flush();
        final rows = await storage.snapshot();
        final failures = rows
            .where((row) => row['kind'] == 'incident')
            .toList();
        final attempts = rows.where((row) => row['kind'] == 'attempt').toList();
        final decisions = rows
            .where((row) => row['kind'] == 'retry_decision')
            .toList();
        final recoveries = rows
            .where((row) => row['kind'] == 'recovery')
            .toList();

        expect(adapter.attempts, 3);
        expect(retryAttempts, [1, 2, 3]);
        expect(caught, same(adapter.errors.last));
        expect(failures, hasLength(1));
        expect(failures.single['attempts'], 3);
        expect(attempts, hasLength(3));
        expect(decisions, hasLength(3));
        expect(decisions.map((row) => (row['fields'] as Map)['will_retry']), [
          true,
          true,
          false,
        ]);
        expect(
          (decisions.last['fields'] as Map)['retry_reason'],
          'attempts_exhausted',
        );
        expect(recoveries, isEmpty);
        final operationIds = failures
            .map((row) => row['operationId'] as String?)
            .toSet();
        expect(operationIds, hasLength(1));
        expect(operationIds.single, isNotEmpty);
        expect(
          attempts.map((row) => (row['fields'] as Map)['request_id']).toSet(),
          hasLength(3),
        );
      } finally {
        await logger.dispose();
        await temporary.delete(recursive: true);
      }
    },
  );

  test('retry rejection records a final decision without changing callbacks or error', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cqut-network-rejected-',
    );
    final logger = AppLogger.I;
    final storage = FileDiagnosticStorage(
      Directory('${temporary.path}/records'),
      'foreground',
    );
    await logger.init(
      enableConsole: false,
      storage: storage,
      exportDirectory: Directory('${temporary.path}/exports'),
    );
    final adapter = _RetryOnceAdapter(failuresBeforeSuccess: 3);
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    logger.attachToDio(dio, tag: 'NetworkRejected');
    final callbacks = <String>[];
    try {
      Object? caught;
      try {
        await retryWithExponentialBackoff(
          () => dio.get<void>('/rejected'),
          maxAttempts: 3,
          onError: (attempt, _) => callbacks.add('error:$attempt'),
          shouldRetry: (_) {
            callbacks.add('predicate');
            return false;
          },
        );
      } catch (error) {
        caught = error;
      }
      await logger.flush();
      final rows = await storage.snapshot();
      final decision = rows.singleWhere(
        (row) => row['kind'] == 'retry_decision',
      );
      expect(adapter.attempts, 1);
      expect(caught, same(adapter.errors.single));
      expect(callbacks, ['error:1', 'predicate']);
      expect((decision['fields'] as Map)['will_retry'], isFalse);
      expect((decision['fields'] as Map)['retry_reason'], 'retry_rejected');
      expect((decision['fields'] as Map)['backoff_ms'], 0);
    } finally {
      await logger.dispose();
      await temporary.delete(recursive: true);
    }
  });

  test(
    'notice API immediate retry records one incident and both decisions',
    () async {
      SharedPreferences.setMockInitialValues({});
      final temporary = await Directory.systemTemp.createTemp(
        'cqut-notice-network-',
      );
      final logger = AppLogger.I;
      final storage = FileDiagnosticStorage(
        Directory('${temporary.path}/records'),
        'foreground',
      );
      await logger.init(
        enableConsole: false,
        storage: storage,
        exportDirectory: Directory('${temporary.path}/exports'),
      );
      final adapter = _ServerFailureAdapter();
      final api = NoticeApi(
        accessEnabled: () async => true,
        dioFactory: (baseUrl) {
          final dio = Dio(BaseOptions(baseUrl: baseUrl))
            ..httpClientAdapter = adapter;
          logger.attachToDio(dio, tag: 'NoticeApi');
          return dio;
        },
      );
      try {
        await expectLater(
          api.fetchTermScheduleNotices(
            username: '20260001',
            encryptedPassword: 'private-password',
            yearTerm: '2026-2027-1',
          ),
          throwsA(isA<DioException>()),
        );
        await logger.flush();
        final rows = await storage.snapshot();
        final incidents = rows
            .where((row) => row['kind'] == 'incident')
            .toList();
        final attempts = rows.where((row) => row['kind'] == 'attempt').toList();
        final decisions = rows
            .where((row) => row['kind'] == 'retry_decision')
            .toList();
        expect(adapter.attempts, 2);
        expect(incidents, hasLength(1));
        expect(incidents.single['attempts'], 2);
        expect(attempts, hasLength(2));
        expect(decisions, hasLength(2));
        expect(decisions.map((row) => (row['fields'] as Map)['will_retry']), [
          true,
          false,
        ]);
        expect(
          decisions.every((row) => (row['fields'] as Map)['backoff_ms'] == 0),
          isTrue,
        );
        expect(attempts.map((row) => row['rootEventId']).toSet(), {
          incidents.single['eventId'],
        });
        expect(rows.where((row) => row['kind'] == 'recovery'), isEmpty);
        expect(jsonEncode(rows), isNot(contains('private-password')));
        expect(jsonEncode(rows), isNot(contains('20260001')));
      } finally {
        await logger.dispose();
        await temporary.delete(recursive: true);
      }
    },
  );

  for (final acceptErrorStatus in [false, true]) {
    test(
      'standalone HTTP failure keeps bounded safe headers and omits body (accepted=$acceptErrorStatus)',
      () async {
        final temporary = await Directory.systemTemp.createTemp(
          'cqut-network-headers-',
        );
        final logger = AppLogger.I;
        final storage = FileDiagnosticStorage(
          Directory('${temporary.path}/records'),
          'foreground',
        );
        await logger.init(
          enableConsole: false,
          storage: storage,
          exportDirectory: Directory('${temporary.path}/exports'),
        );
        final dio = Dio(
          BaseOptions(
            baseUrl: 'https://example.test',
            validateStatus: acceptErrorStatus ? (_) => true : null,
          ),
        )..httpClientAdapter = _ServerFailureAdapter();
        logger.attachToDio(dio, tag: 'NetworkHeaders');
        try {
          try {
            await dio.get<String>(
              '/fails',
              queryParameters: {
                'token': 'private-query-token',
                'sid': 'private-session-id',
                'ticket': 'private-ticket',
              },
            );
          } on DioException {
            expect(acceptErrorStatus, isFalse);
          }
          await logger.flush();
          final rows = await storage.snapshot();
          final incidents = rows
              .where((row) => row['kind'] == 'incident')
              .toList();
          final attempts = rows
              .where((row) => row['kind'] == 'attempt')
              .toList();
          expect(incidents, hasLength(1));
          expect(attempts, hasLength(1));
          final fields = attempts.single['fields'] as Map;
          expect(fields['status_code'], 502);
          expect(fields['body_omitted_reason'], 'privacy_policy');
          final headers = fields['response_headers'] as Map;
          expect(headers.keys.toSet(), {
            'server',
            'cf-ray',
            'via',
            'x-request-id',
            'content-type',
          });
          expect(headers['server'], 'cloudflare');
          expect(headers['cf-ray'], 'ray-identifier');
          expect(
            headers.values.every(
              (value) => utf8.encode(value as String).length <= 256,
            ),
            isTrue,
          );
          for (final key in [
            'auth_attempt',
            'auth_max_attempts',
            'network_status',
            'network_type',
            'fallback',
          ]) {
            expect(fields.containsKey(key), isFalse);
          }
          final encoded = jsonEncode(rows);
          for (final secret in [
            'private-response-body',
            '20260001',
            'private-header-token',
            'private-response-cookie',
            'private-response-authorization',
            'private-unlisted-header',
            'private-third-header-value',
            'private-query-token',
            'private-session-id',
            'private-ticket',
          ]) {
            expect(encoded, isNot(contains(secret)));
          }
          expect(encoded, isNot(contains('This exception was thrown')));
          expect(encoded, isNot(contains('dio_message')));
          expect(fields.values, isNot(contains('unknown')));
        } finally {
          await logger.dispose();
          await temporary.delete(recursive: true);
        }
      },
    );
  }
}
