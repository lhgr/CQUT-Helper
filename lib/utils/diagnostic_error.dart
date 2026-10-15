import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

const diagnosticAttemptZoneKey = 'cqut.diagnostic.attempt';
const diagnosticMaxAttemptsZoneKey = 'cqut.diagnostic.max_attempts';
const diagnosticFallbackZoneKey = 'cqut.diagnostic.fallback';

Future<T> runWithDiagnosticContext<T>({
  int? attempt,
  int? maxAttempts,
  bool? fallback,
  required Future<T> Function() action,
}) async {
  return runZoned<Future<T>>(
    action,
    zoneValues: {
      diagnosticAttemptZoneKey: ?attempt,
      diagnosticMaxAttemptsZoneKey: ?maxAttempts,
      diagnosticFallbackZoneKey: ?fallback,
    },
  );
}

/// Returns a stable, low-cardinality diagnostic category without changing the
/// exception that callers receive.
String? classifyDiagnosticError(
  Object? error, {
  String? stage,
  int? statusCode,
  String? module,
  String? platform,
}) {
  if (error == null) return null;

  if (error is Response) {
    final status = statusCode ?? error.statusCode;
    if (status != null && status >= 500) return 'HTTP_SERVER_ERROR';
    if (status != null && status >= 400) return 'HTTP_CLIENT_ERROR';
    return null;
  }

  if (error is DioException) {
    if (error.type == DioExceptionType.cancel) return null;
    final status = statusCode ?? error.response?.statusCode;
    final nested = error.error;
    if (error.type == DioExceptionType.connectionTimeout) {
      return 'NETWORK_CONNECT_TIMEOUT';
    }
    if (error.type == DioExceptionType.receiveTimeout) {
      return 'NETWORK_RECEIVE_TIMEOUT';
    }
    if (error.type == DioExceptionType.sendTimeout) {
      return 'NETWORK_SEND_TIMEOUT';
    }
    if (error.type == DioExceptionType.transformTimeout) {
      return 'NETWORK_TRANSFORM_TIMEOUT';
    }
    if (error.type == DioExceptionType.badCertificate) {
      return 'NETWORK_TLS_FAILED';
    }
    if (status != null && status >= 500) return 'HTTP_SERVER_ERROR';
    if (status != null && status >= 400) return 'HTTP_CLIENT_ERROR';
    if (nested is SocketException) {
      return _socketCategory(nested, platform: platform);
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown) {
      return 'NETWORK_CONNECTION_FAILED';
    }
    return 'NETWORK_REQUEST_FAILED';
  }

  if (error is SocketException) {
    return _socketCategory(error, platform: platform);
  }
  if (error is HttpException || error is HandshakeException) {
    return 'NETWORK_CONNECTION_FAILED';
  }
  if (error is FormatException) {
    final normalizedStage = (stage ?? '').toLowerCase();
    if (normalizedStage.contains('cache_read')) return 'CACHE_READ_FAILED';
    if (normalizedStage.contains('cache_write')) return 'CACHE_WRITE_FAILED';
    return 'DATA_PARSE_FAILED';
  }

  // API-specific exceptions expose a typed `kind`. Read it defensively to keep
  // this shared classifier independent of API modules.
  final kind = _businessKind(error);
  if (kind == 'authentication') return 'AUTH_FAILED';
  final dioType = _businessDiagnostic(error, 'dio_type');
  if (kind == 'timeout') {
    return switch (dioType) {
      'connectionTimeout' => 'NETWORK_CONNECT_TIMEOUT',
      'sendTimeout' => 'NETWORK_SEND_TIMEOUT',
      'receiveTimeout' => 'NETWORK_RECEIVE_TIMEOUT',
      'transformTimeout' => 'NETWORK_TRANSFORM_TIMEOUT',
      _ => 'NETWORK_TIMEOUT',
    };
  }
  if (kind == 'network') return 'NETWORK_CONNECTION_FAILED';
  if (kind == 'server') return 'HTTP_SERVER_ERROR';
  if (kind == 'invalidResponse') return 'DATA_PARSE_FAILED';

  final normalizedStage = (stage ?? '').toLowerCase();
  if (normalizedStage.contains('cache_read')) return 'CACHE_READ_FAILED';
  if (normalizedStage.contains('cache_write')) return 'CACHE_WRITE_FAILED';
  if (normalizedStage.contains('parse') ||
      normalizedStage.contains('decode') ||
      normalizedStage.contains('response')) {
    return 'DATA_PARSE_FAILED';
  }
  return 'UNKNOWN_ERROR';
}

String? _businessKind(Object error) {
  try {
    final kind = (error as dynamic).kind;
    if (kind is Enum) return kind.name;
    if (kind is String) return kind;
  } catch (_) {
    // Most errors have no business kind.
  }
  return null;
}

String? _businessDiagnostic(Object error, String key) {
  try {
    final diagnostics = (error as dynamic).diagnostics;
    final value = diagnostics is Map ? diagnostics[key] : null;
    return value is String ? value : null;
  } catch (_) {
    return null;
  }
}

String _socketCategory(SocketException error, {String? platform}) {
  final code = error.osError?.errorCode;
  // getaddrinfo errno values differ across Android's bionic, Darwin, Linux,
  // and Winsock. Only classify codes known for the requested OS.
  final os = platform ?? Platform.operatingSystem;
  final isDns = switch (os) {
    'android' => code == 2 || code == 7 || code == 8,
    'ios' || 'macos' => code == 2 || code == 8,
    'linux' => code == -2 || code == -3 || code == -5,
    'windows' => code == 11001 || code == 11002 || code == 11004,
    _ => false,
  };
  if (isDns) {
    return 'NETWORK_DNS_FAILED';
  }
  return 'NETWORK_CONNECTION_FAILED';
}

/// Structured fields retained for diagnosis without serializing request/response
/// data or the exception's full representation.
Map<String, Object?> diagnosticErrorDetails(Object? error) {
  if (error is DioException) {
    final nested = error.error;
    return {
      'error_type': error.runtimeType.toString(),
      'dio_type': error.type.name,
      if (error.message != null && error.message!.trim().isNotEmpty)
        'dio_message': sanitizeDiagnosticText(error.message!.trim()),
      'status_code': ?error.response?.statusCode,
      if (nested != null) 'cause_type': nested.runtimeType.toString(),
      if (nested is SocketException && nested.osError != null)
        'os_error_code': nested.osError!.errorCode,
    };
  }
  if (error is SocketException) {
    return {
      'error_type': error.runtimeType.toString(),
      if (error.osError != null) 'os_error_code': error.osError!.errorCode,
    };
  }
  return error == null
      ? const {}
      : {'error_type': error.runtimeType.toString()};
}

/// Stable summary used for the top-level reason field; never calls Dio's
/// `toString()`, which may include request or response payloads.
String safeDiagnosticErrorSummary(Object? error) {
  if (error is DioException) {
    final nested = error.error;
    final message = error.message?.trim();
    final safeMessage = message == null || message.isEmpty
        ? null
        : sanitizeDiagnosticText(message);
    final status = error.response?.statusCode;
    final socketSummary = nested is SocketException && nested.osError != null
        ? 'OS ${nested.osError!.errorCode}'
        : null;
    return [
      'DioException(${error.type.name})',
      if (status != null) 'HTTP $status',
      ?socketSummary,
      ?safeMessage,
    ].join(': ');
  }
  if (error is SocketException) {
    final code = error.osError == null
        ? ''
        : ' (OS ${error.osError!.errorCode})';
    return sanitizeDiagnosticText(
      '${error.runtimeType}$code: ${error.message}',
    );
  }
  if (error is FormatException) {
    return sanitizeDiagnosticText(error.message.toString());
  }
  return error == null
      ? 'UnknownError'
      : sanitizeDiagnosticText(error.toString());
}

String sanitizeDiagnosticText(String value) => value
    .replaceAll(
      RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false),
      'Bearer <redacted>',
    )
    .replaceAllMapped(
      RegExp(r'([?&][A-Za-z0-9_.~-]+)=([^&#\s]*)'),
      (match) => '${match[1]}=<redacted>',
    )
    .replaceAllMapped(
      RegExp(r'(https?://)[^\s/@]+@', caseSensitive: false),
      (match) => '${match[1]}<redacted>@',
    )
    .replaceAllMapped(
      RegExp(
        r"""(["']?(?:password|passwd|pwd|pass|token|secret|cookie|authorization|csrf)[\w-]*["']?\s*:\s*["'])(.*?)(["'])""",
        caseSensitive: false,
      ),
      (match) => '${match[1]}<redacted>${match[3]}',
    )
    .replaceAllMapped(
      RegExp(
        r'((?:password|passwd|pwd|pass|token|secret|cookie|authorization|csrf)[\w-]*\s*[:=]\s*)[^\s,;&]+',
        caseSensitive: false,
      ),
      (match) => '${match[1]}<redacted>',
    );
