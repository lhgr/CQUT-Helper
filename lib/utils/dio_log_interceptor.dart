import 'package:dio/dio.dart';

import 'app_logger.dart';
import 'diagnostic_error.dart';

import 'dart:async';

class DioLogInterceptor extends Interceptor {
  DioLogInterceptor({required this.logger, this.tag = 'HTTP'});

  final AppLogger logger;
  final String tag;
  static const _startKey = '__diagnostic_start';
  static const _traceKey = '__diagnostic_operation';
  static const _requestKey = '__diagnostic_request';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = Stopwatch()..start();
    options.extra[_traceKey] = logger.currentTraceId ?? logger.newTraceId();
    options.extra[_requestKey] = logger.newTraceId();
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
    'request_id': options.extra[_requestKey],
    'attempt': options.extra['diagnostic_attempt'] is int
        ? options.extra['diagnostic_attempt']
        : Zone.current[diagnosticAttemptZoneKey] is int
        ? Zone.current[diagnosticAttemptZoneKey]
        : 'unknown',
    'max_attempts': options.extra['diagnostic_max_attempts'] is int
        ? options.extra['diagnostic_max_attempts']
        : Zone.current[diagnosticMaxAttemptsZoneKey] is int
        ? Zone.current[diagnosticMaxAttemptsZoneKey]
        : 'unknown',
    'auth_attempt': options.extra['diagnostic_auth_attempt'] ?? 'unknown',
    'auth_max_attempts':
        options.extra['diagnostic_auth_max_attempts'] ?? 'unknown',
    'fallback': options.extra['diagnostic_fallback'] is bool
        ? options.extra['diagnostic_fallback']
        : Zone.current[diagnosticFallbackZoneKey] is bool
        ? Zone.current[diagnosticFallbackZoneKey]
        : 'unknown',
    'network_status': 'unknown',
    'network_type': 'unknown',
    'connect_timeout_ms': options.connectTimeout?.inMilliseconds,
    'send_timeout_ms': options.sendTimeout?.inMilliseconds,
    'receive_timeout_ms': options.receiveTimeout?.inMilliseconds,
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
          'error_category': classifyDiagnosticError(
            response,
            stage: 'http_response',
            statusCode: status,
            module: tag,
          ),
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
    final options = err.requestOptions;
    final details = diagnosticErrorDetails(err);
    final fields = {
      ..._fields(options, status: err.response?.statusCode),
      ...details,
      'dio_type': err.type.name,
      'error_category': classifyDiagnosticError(
        err,
        stage: 'http_request',
        module: tag,
      ),
      'status': err.type == DioExceptionType.cancel ? 'cancelled' : 'failed',
    };
    if (err.type == DioExceptionType.cancel ||
        _expectedStatus(options, err.response?.statusCode)) {
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
        fields: {...fields, 'reason': safeDiagnosticErrorSummary(err)},
      );
    }
    handler.next(err);
  }

  bool _expectedStatus(RequestOptions options, int? status) {
    final expected = options.extra['diagnostic_expected_statuses'];
    return status != null && expected is List && expected.contains(status);
  }
}
