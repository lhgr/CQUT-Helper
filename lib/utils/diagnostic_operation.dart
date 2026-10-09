import 'package:cqut_helper/utils/app_logger.dart';
import 'package:dio/dio.dart';

/// Carries the same operation through authentication, requests and cache work.
Future<T> runDiagnosticOperation<T>(
  String module,
  String stage,
  Future<T> Function() action, {
  Map<String, Object?> fields = const {},
}) {
  final logger = AppLogger.I;
  return logger.runWithTraceIdAsync(
    logger.currentTraceId ?? logger.newTraceId(),
    () async {
      logger.info(
        module,
        '$stage started',
        fields: {'module': module, 'stage': stage, ...fields},
      );
      try {
        final result = await action();
        logger.info(
          module,
          '$stage completed',
          fields: {
            'module': module,
            'stage': stage,
            'outcome': 'succeeded',
            ...fields,
          },
        );
        return result;
      } catch (error, stackTrace) {
        if (error is DioException && error.type == DioExceptionType.cancel) {
          logger.info(
            module,
            '$stage cancelled',
            fields: {'stage': stage, 'outcome': 'cancelled', ...fields},
          );
        } else {
          logger.logOperationFailure(
            module,
            '$stage failed',
            error: error,
            stackTrace: stackTrace,
            fields: {
              'module': module,
              'stage': stage,
              'outcome': 'failed',
              ...fields,
            },
          );
        }
        rethrow;
      }
    },
  );
}
