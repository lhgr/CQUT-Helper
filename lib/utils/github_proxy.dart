import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

class GithubProxy {
  static const String workerBaseUrl = 'https://dawndrizzle.xyz';

  static final Dio _healthDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 2),
      receiveTimeout: const Duration(seconds: 3),
      sendTimeout: const Duration(seconds: 3),
      responseType: ResponseType.json,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  );

  static DateTime? _healthUpdatedAt;
  static bool? _healthOk;

  static bool isGithubUri(Uri uri) {
    final host = uri.host.toLowerCase();
    return host == 'api.github.com' ||
        host == 'github.com' ||
        host.endsWith('.github.com') ||
        host == 'raw.githubusercontent.com' ||
        host == 'gist.github.com' ||
        host == 'gist.githubusercontent.com' ||
        host == 'codeload.github.com' ||
        host == 'objects.githubusercontent.com' ||
        host == 'github-releases.githubusercontent.com';
  }

  static bool isWorkerUri(Uri uri) {
    final base = Uri.parse(workerBaseUrl);
    return uri.scheme == base.scheme && uri.host == base.host;
  }

  static Uri proxyUriOf(Uri raw) {
    if (isWorkerUri(raw)) return raw;
    final base = workerBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    return Uri.parse('$base/${raw.toString()}');
  }

  static String proxyUrlOf(String rawUrl) {
    final raw = Uri.tryParse(rawUrl);
    if (raw == null) return rawUrl;
    if (!isGithubUri(raw)) return rawUrl;
    return proxyUriOf(raw).toString();
  }

  static Duration _defaultHealthTtl() => const Duration(minutes: 2);

  static Future<bool> isWorkerHealthy({Duration? ttl}) async {
    final effectiveTtl = ttl ?? _defaultHealthTtl();
    final updatedAt = _healthUpdatedAt;
    final cached = _healthOk;
    if (updatedAt != null &&
        cached != null &&
        DateTime.now().difference(updatedAt) <= effectiveTtl) {
      return cached;
    }

    final healthUri = Uri.parse('$workerBaseUrl/__health');
    try {
      final resp = await _healthDio.getUri(healthUri);
      final data = resp.data;
      bool ok = false;
      if (data is Map) {
        ok = data['ok'] == true;
      } else if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is Map) ok = decoded['ok'] == true;
      }
      _healthUpdatedAt = DateTime.now();
      _healthOk = ok;
      return ok;
    } catch (_) {
      _healthUpdatedAt = DateTime.now();
      _healthOk = false;
      return false;
    }
  }

  static Future<Uri> preferUri(Uri raw) async {
    if (!isGithubUri(raw) || isWorkerUri(raw)) return raw;
    if (await isWorkerHealthy()) return proxyUriOf(raw);
    return raw;
  }

  static Future<String> preferUrl(String rawUrl) async {
    final raw = Uri.tryParse(rawUrl);
    if (raw == null) return rawUrl;
    return (await preferUri(raw)).toString();
  }

  static Future<Response<T>> getWithFallback<T>(
    Dio dio,
    Uri raw, {
    Options? options,
  }) async {
    if (!isGithubUri(raw) || isWorkerUri(raw)) {
      return dio.getUri<T>(raw, options: options);
    }

    final proxied = proxyUriOf(raw);
    try {
      final resp = await dio.getUri<T>(proxied, options: options);
      _healthUpdatedAt = DateTime.now();
      _healthOk = true;
      return resp;
    } catch (_) {
      _healthUpdatedAt = DateTime.now();
      _healthOk = false;
      return dio.getUri<T>(raw, options: options);
    }
  }

  static Future<void> downloadWithFallback(
    Dio dio,
    Uri raw,
    String savePath, {
    ProgressCallback? onReceiveProgress,
    Options? options,
  }) async {
    if (!isGithubUri(raw) || isWorkerUri(raw)) {
      await dio.downloadUri(
        raw,
        savePath,
        onReceiveProgress: onReceiveProgress,
        options: options,
      );
      return;
    }

    final proxied = proxyUriOf(raw);
    try {
      await dio.downloadUri(
        proxied,
        savePath,
        onReceiveProgress: onReceiveProgress,
        options: options,
      );
      _healthUpdatedAt = DateTime.now();
      _healthOk = true;
    } catch (_) {
      _healthUpdatedAt = DateTime.now();
      _healthOk = false;
      await dio.downloadUri(
        raw,
        savePath,
        onReceiveProgress: onReceiveProgress,
        options: options,
      );
    }
  }

  static Future<bool> launchExternalUrlString(String urlString) async {
    final raw = Uri.tryParse(urlString);
    if (raw == null) return false;

    if (!isGithubUri(raw) || isWorkerUri(raw)) {
      return launchUrl(raw);
    }

    final healthy = await isWorkerHealthy();
    final primary = healthy ? proxyUriOf(raw) : raw;
    final fallback = healthy ? raw : proxyUriOf(raw);

    if (await launchUrl(primary)) return true;
    if (healthy) return launchUrl(fallback);
    return false;
  }
}
