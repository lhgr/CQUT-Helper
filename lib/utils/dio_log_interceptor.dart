import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'app_logger.dart';
import 'diagnostic_error.dart';

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
    // Capture context here: asynchronous Dio callbacks need not run in the
    // caller's zone, and each physical request still keeps its own request ID.
    for (final entry in {
      'diagnostic_attempt': Zone.current[diagnosticAttemptZoneKey],
      'diagnostic_max_attempts': Zone.current[diagnosticMaxAttemptsZoneKey],
      'diagnostic_fallback': Zone.current[diagnosticFallbackZoneKey],
      'diagnostic_retry_group_id': Zone.current[diagnosticRetryGroupZoneKey],
    }.entries) {
      if (entry.value != null) {
        options.extra.putIfAbsent(entry.key, () => entry.value);
      }
    }
    final retryGroupId = options.extra['diagnostic_retry_group_id'];
    if (retryGroupId is String) {
      options.extra['diagnostic_retry_request_slot'] = logger
          .captureRetryRequestSlot(
            retryGroupId: retryGroupId,
            attempt: options.extra['diagnostic_attempt'] is int
                ? options.extra['diagnostic_attempt'] as int
                : null,
            method: options.method,
            uri: sanitizeUriForLogging(options.uri),
          );
    }
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
        ?(options.extra[_startKey] as Stopwatch?)?.elapsedMilliseconds,
    'trace_id': options.extra[_traceKey],
    'request_id': options.extra[_requestKey],
    if (options.extra['diagnostic_retry_group_id'] is String)
      'retry_group_id': options.extra['diagnostic_retry_group_id'],
    if (options.extra['diagnostic_retry_request_slot'] is int)
      'retry_request_slot': options.extra['diagnostic_retry_request_slot'],
    if (options.extra['diagnostic_attempt'] is int)
      'attempt': options.extra['diagnostic_attempt'],
    if (options.extra['diagnostic_max_attempts'] is int)
      'max_attempts': options.extra['diagnostic_max_attempts'],
    if ({
          'none',
          'cached',
          'refreshed',
          'failed',
        }.contains(options.extra['diagnostic_auth_attempt']) ||
        options.extra['diagnostic_auth_attempt'] is int)
      'auth_attempt': options.extra['diagnostic_auth_attempt'],
    if (options.extra['diagnostic_auth_max_attempts'] is int)
      'auth_max_attempts': options.extra['diagnostic_auth_max_attempts'],
    if (options.extra['diagnostic_fallback'] is bool)
      'fallback': options.extra['diagnostic_fallback'],
    'connect_timeout_ms': ?options.connectTimeout?.inMilliseconds,
    'send_timeout_ms': ?options.sendTimeout?.inMilliseconds,
    'receive_timeout_ms': ?options.receiveTimeout?.inMilliseconds,
    'status_code': ?status,
    'action': 'request',
  };

  Map<String, Object?> _responseFields(Response? response) {
    if (response == null) return const {};
    final headers = <String, String>{};
    for (final name in const [
      'server',
      'cf-ray',
      'via',
      'x-request-id',
      'content-type',
    ]) {
      final values = response.headers[name];
      if (values == null || values.isEmpty) continue;
      // Never copy arbitrary headers, cookies, body text, or unlimited values.
      final safe = sanitizeDiagnosticText(values.take(2).join(', '));
      final bounded = StringBuffer();
      var bytes = 0;
      for (final rune in safe.runes) {
        final part = String.fromCharCode(rune);
        final length = utf8.encode(part).length;
        if (bytes + length > 256) break;
        bounded.write(part);
        bytes += length;
      }
      headers[name] = bounded.toString();
    }
    return {
      if (headers.isNotEmpty) 'response_headers': headers,
      'body_omitted_reason': 'privacy_policy',
    };
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    final status = response.statusCode;
    if (status != null && status >= 400 && !_expectedStatus(options, status)) {
      logger.info(
        tag,
        'HTTP 请求失败',
        fields: {
          ..._fields(options, status: status),
          ..._responseFields(response),
          'diagnostic_kind': 'attempt',
          'outcome': 'failed',
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
          if (!_expectedStatus(options, status)) 'diagnostic_kind': 'attempt',
          'outcome': 'succeeded',
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
      ..._responseFields(err.response),
      ...details,
      'dio_type': err.type.name,
      if (!_expectedStatus(options, err.response?.statusCode))
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
      logger.info(
        tag,
        '网络请求失败',
        error: err,
        stackTrace: err.stackTrace,
        fields: {
          ...fields,
          'diagnostic_kind': 'attempt',
          'reason': safeDiagnosticErrorSummary(err),
        },
      );
    }
    handler.next(err);
  }

  bool _expectedStatus(RequestOptions options, int? status) {
    final expected = options.extra['diagnostic_expected_statuses'];
    return status != null && expected is List && expected.contains(status);
  }
}
