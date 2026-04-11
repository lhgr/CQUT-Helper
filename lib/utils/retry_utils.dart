import 'dart:math';

Future<T> retryWithExponentialBackoff<T>(
  Future<T> Function() run, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(milliseconds: 400),
  double factor = 2.0,
  Duration maxDelay = const Duration(seconds: 4),
  bool Function(Object error)? shouldRetry,
  int jitterMs = 250,
  void Function(int attempt, Object error)? onError,
}) async {
  Object? lastError;

  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await run();
    } catch (e) {
      lastError = e;
      onError?.call(attempt, e);
      final ok = shouldRetry == null ? true : shouldRetry(e);
      if (!ok || attempt == maxAttempts) rethrow;

      final exp = initialDelay.inMilliseconds * pow(factor, attempt - 1);
      final capped = min(exp.round(), maxDelay.inMilliseconds);
      final jitter = jitterMs <= 0 ? 0 : Random().nextInt(jitterMs + 1);
      await Future.delayed(Duration(milliseconds: capped + jitter));
    }
  }

  throw lastError ?? StateError('retry failed');
}
