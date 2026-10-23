import 'dart:math';

import 'app_logger.dart';
import 'diagnostic_error.dart';

Future<T> retryWithExponentialBackoff<T>(
  Future<T> Function() run, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(milliseconds: 400),
  double factor = 2.0,
  Duration maxDelay = const Duration(seconds: 4),
  bool Function(Object error)? shouldRetry,
  int jitterMs = 250,
  void Function(int attempt, Object error)? onError,
}) => AppLogger.I.runWithTraceIdAsync<T>(
  AppLogger.I.currentTraceId ?? AppLogger.I.newTraceId(),
  () => AppLogger.I.runWithRetryGroup<T>(() async {
    Object? lastError;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await runWithDiagnosticContext<T>(
          attempt: attempt,
          maxAttempts: maxAttempts,
          action: run,
        );
      } catch (e) {
        lastError = e;
        onError?.call(attempt, e);
        final ok = shouldRetry == null ? true : shouldRetry(e);
        final willRetry = ok && attempt < maxAttempts;
        var backoffMs = 0;
        if (willRetry) {
          final exp = initialDelay.inMilliseconds * pow(factor, attempt - 1);
          final capped = min(exp.round(), maxDelay.inMilliseconds);
          final jitter = jitterMs <= 0 ? 0 : Random().nextInt(jitterMs + 1);
          backoffMs = capped + jitter;
        }
        AppLogger.I.info(
          'Retry',
          '请求重试决策',
          error: e,
          fields: {
            'diagnostic_kind': 'retry_decision',
            'action': 'retry_decision',
            'retry_group_id': ?AppLogger.I.currentRetryGroupId,
            'attempt': attempt,
            'max_attempts': maxAttempts,
            'will_retry': willRetry,
            'retry_reason': !ok
                ? 'retry_rejected'
                : willRetry
                ? 'retry_allowed'
                : 'attempts_exhausted',
            'backoff_ms': backoffMs,
          },
        );
        if (!willRetry) rethrow;
        await Future.delayed(Duration(milliseconds: backoffMs));
      }
    }

    throw lastError ?? StateError('retry failed');
  }),
);
