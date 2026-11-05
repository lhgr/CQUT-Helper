import 'dart:async';
import 'dart:convert';

import 'package:cqut_helper/model/update_model.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/github_proxy.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateFetchResult {
  const UpdateFetchResult({
    required this.info,
    required this.fromCache,
    this.validatedAt,
    this.failure,
  });

  final UpdateModel? info;
  final bool fromCache;
  final DateTime? validatedAt;
  final Object? failure;

  bool get networkValidated => !fromCache && failure == null && info != null;
}

class UpdateApi {
  UpdateApi({
    Dio? dio,
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? now,
    this.proxyBudget = const Duration(seconds: 6),
    this.directBudget = const Duration(seconds: 8),
  }) : _dio = dio ?? Dio(),
       _preferences = preferences ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now {
    _dio.options = _dio.options.copyWith(
      connectTimeout: const Duration(seconds: 3),
      sendTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 5),
      responseType: ResponseType.json,
      validateStatus: (status) => status == 200 || status == 304,
    );
    AppLogger.I.attachToDio(_dio, tag: _tag);
  }

  static const _tag = 'UpdateApi';
  static const cacheKey = 'update_latest_release_cache_v1';
  static const cacheTtl = Duration(hours: 6);
  static final _releaseUri = Uri.parse(
    'https://api.github.com/repos/lhgr/CQUT-Helper/releases/latest',
  );

  final Dio _dio;
  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _now;
  final Duration proxyBudget;
  final Duration directBudget;
  Future<UpdateFetchResult>? _inFlight;

  Future<UpdateFetchResult> fetchLatest({bool forceRefresh = false}) {
    final existing = _inFlight;
    if (existing != null) {
      return existing.then((result) {
        // A manual check must still reach the network if it joined a cache hit.
        if (forceRefresh && result.fromCache && result.failure == null) {
          return fetchLatest(forceRefresh: true);
        }
        return result;
      });
    }
    final future = _fetchLatest(forceRefresh: forceRefresh);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<UpdateFetchResult> _fetchLatest({required bool forceRefresh}) async {
    _ReleaseCache? cached;
    try {
      final prefs = await _preferences();
      cached = _readCache(prefs);
      final age = cached == null ? null : _now().difference(cached.validatedAt);
      if (!forceRefresh &&
          cached != null &&
          age != null &&
          !age.isNegative &&
          age < cacheTtl) {
        return UpdateFetchResult(
          info: cached.info,
          fromCache: true,
          validatedAt: cached.validatedAt,
        );
      }

      final endpoints = [GithubProxy.proxyUriOf(_releaseUri), _releaseUri];
      for (var index = 0; index < endpoints.length; index++) {
        try {
          final uri = endpoints[index];
          final response = await _request(
            uri,
            cached,
            index == 0 ? proxyBudget : directBudget,
          );
          final Map<String, dynamic> release;
          if (response.statusCode == 304) {
            if (cached == null ||
                cached.etagUri != uri.toString() ||
                cached.etag == null ||
                cached.etag!.isEmpty) {
              throw const FormatException('发行版返回 304，但没有对应的有效缓存');
            }
            release = cached.release;
          } else if (response.statusCode == 200) {
            release = _parseRelease(response.data);
          } else {
            throw FormatException('发行版响应状态异常 ${response.statusCode}');
          }
          final entry = _ReleaseCache(
            release: release,
            info: UpdateModel.fromJson(release),
            validatedAt: _now(),
            etag:
                response.headers.value('etag')?.trim() ??
                (response.statusCode == 304 ? cached?.etag : null),
            etagUri: uri.toString(),
          );
          await _saveCache(prefs, entry);
          return UpdateFetchResult(
            info: entry.info,
            fromCache: false,
            validatedAt: entry.validatedAt,
          );
        } catch (_) {
          if (index == endpoints.length - 1) rethrow;
        }
      }
      throw StateError('没有可用的发行版请求地址');
    } catch (error, stackTrace) {
      AppLogger.I.warn(
        _tag,
        'Check update failed',
        error: error,
        stackTrace: stackTrace,
      );
      return UpdateFetchResult(
        info: cached?.info,
        fromCache: cached != null,
        validatedAt: cached?.validatedAt,
        failure: error,
      );
    }
  }

  Future<Response<dynamic>> _request(
    Uri uri,
    _ReleaseCache? cached,
    Duration budget,
  ) async {
    final token = CancelToken();
    final timer = Timer(budget, () => token.cancel('发行版请求超时'));
    try {
      return await _dio.getUri<dynamic>(
        uri,
        cancelToken: token,
        options: Options(
          headers: {
            if (cached?.etagUri == uri.toString() &&
                cached?.etag?.isNotEmpty == true)
              'If-None-Match': cached!.etag!,
          },
        ),
      );
    } finally {
      timer.cancel();
    }
  }

  _ReleaseCache? _readCache(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(cacheKey);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final release = _parseRelease(json['release']);
      return _ReleaseCache(
        release: release,
        info: UpdateModel.fromJson(release),
        validatedAt: DateTime.fromMillisecondsSinceEpoch(
          json['validatedAt'] as int,
        ),
        etag: json['etag'] as String?,
        etagUri: json['etagUri'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _parseRelease(dynamic data) {
    if (data is! Map) throw const FormatException('发行版数据格式无效');
    final release = data.cast<String, dynamic>();
    final tag = release['tag_name'];
    final url = release['html_url'];
    if (tag is! String ||
        tag.trim().isEmpty ||
        url is! String ||
        url.trim().isEmpty ||
        (release['body'] != null && release['body'] is! String)) {
      throw const FormatException('发行版信息不完整');
    }
    // Parse assets before replacing the persisted snapshot.
    UpdateModel.fromJson(release);
    return release;
  }

  Future<void> _saveCache(SharedPreferences prefs, _ReleaseCache entry) async {
    try {
      final saved = await prefs.setString(
        cacheKey,
        jsonEncode({
          'release': entry.release,
          'validatedAt': entry.validatedAt.millisecondsSinceEpoch,
          'etag': entry.etag,
          'etagUri': entry.etagUri,
        }),
      );
      if (!saved) throw StateError('发行版缓存保存失败');
    } catch (error, stackTrace) {
      AppLogger.I.warn(
        _tag,
        'Save update cache failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

class _ReleaseCache {
  const _ReleaseCache({
    required this.release,
    required this.info,
    required this.validatedAt,
    this.etag,
    this.etagUri,
  });

  final Map<String, dynamic> release;
  final UpdateModel info;
  final DateTime validatedAt;
  final String? etag;
  final String? etagUri;
}
