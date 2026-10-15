import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/diagnostic_error.dart';
import 'package:cqut_helper/utils/diagnostics_storage.dart';
import 'package:cqut_helper/utils/retry_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

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
            initialDelay: Duration.zero,
            jitterMs: 0,
          );

      try {
        await logger.runWithTraceIdAsync('network-operation', () async {
          await Future.wait([
            request(firstDio, '/first'),
            request(secondDio, '/second'),
          ]);
        });
        await logger.flush();
        final rows = await storage.snapshot();
        final failures = rows.where((row) => row['kind'] == 'error').toList();
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
      } finally {
        await logger.dispose();
        await temporary.delete(recursive: true);
      }
    },
  );

  test(
    'exhausted retries preserve each cause and never emit recovery',
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
        final failures = rows.where((row) => row['kind'] == 'error').toList();
        final recoveries = rows
            .where((row) => row['kind'] == 'recovery')
            .toList();

        expect(adapter.attempts, 3);
        expect(retryAttempts, [1, 2, 3]);
        expect(caught, same(adapter.errors.last));
        expect(failures, hasLength(3));
        expect(recoveries, isEmpty);
        final operationIds = failures
            .map((row) => row['operationId'] as String?)
            .toSet();
        expect(operationIds, hasLength(1));
        expect(operationIds.single, isNotEmpty);
        expect(
          failures.map((row) => (row['fields'] as Map)['request_id']).toSet(),
          hasLength(3),
        );
      } finally {
        await logger.dispose();
        await temporary.delete(recursive: true);
      }
    },
  );
}
