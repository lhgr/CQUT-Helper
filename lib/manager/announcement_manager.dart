import 'dart:convert';

import 'package:cqut_helper/api/api_service.dart';
import 'package:cqut_helper/model/announcement_model.dart';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cqut_helper/widgets/announcement_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AnnouncementFailureType { backend, network, request }

class AnnouncementFailure {
  final AnnouncementFailureType type;
  final String message;
  final int? statusCode;

  const AnnouncementFailure({
    required this.type,
    required this.message,
    this.statusCode,
  });
}

AnnouncementFailure announcementFailureFromDio(DioException error) {
  final statusCode = error.response?.statusCode;
  final data = error.response?.data;
  final serverError = data is Map<String, dynamic> ? data['error'] : null;
  final serverErrorText = serverError is String && serverError.isNotEmpty
      ? serverError
      : null;

  if (statusCode != null) {
    final type = statusCode >= 500
        ? AnnouncementFailureType.backend
        : AnnouncementFailureType.request;
    return AnnouncementFailure(
      type: type,
      message: serverErrorText ?? '请求失败（$statusCode）',
      statusCode: statusCode,
    );
  }

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return const AnnouncementFailure(
        type: AnnouncementFailureType.network,
        message: '连接超时，请稍后重试',
      );
    case DioExceptionType.connectionError:
    case DioExceptionType.badCertificate:
      return const AnnouncementFailure(
        type: AnnouncementFailureType.network,
        message: '连接未建立，请稍后重试',
      );
    case DioExceptionType.cancel:
      return const AnnouncementFailure(
        type: AnnouncementFailureType.request,
        message: '请求已取消',
      );
    case DioExceptionType.badResponse:
      return const AnnouncementFailure(
        type: AnnouncementFailureType.backend,
        message: '公告服务返回了异常响应',
      );
    case DioExceptionType.unknown:
      return const AnnouncementFailure(
        type: AnnouncementFailureType.network,
        message: '连接未建立，请稍后重试',
      );
  }
}

String announcementFailureDisplayText(AnnouncementFailure failure) {
  return switch (failure.type) {
    AnnouncementFailureType.backend => '公告服务问题：${failure.message}',
    AnnouncementFailureType.network => '公告服务连接失败：${failure.message}',
    AnnouncementFailureType.request => '公告请求未完成：${failure.message}',
  };
}

class AnnouncementHealthResult {
  final bool ok;
  final AnnouncementFailure? failure;

  const AnnouncementHealthResult({required this.ok, this.failure});
}

class AnnouncementListResult {
  final List<AnnouncementModel> items;
  final AnnouncementFailure? failure;
  final bool fromCache;

  const AnnouncementListResult({
    required this.items,
    this.failure,
    required this.fromCache,
  });
}

class AnnouncementDetailResult {
  final AnnouncementModel? item;
  final AnnouncementFailure? failure;

  const AnnouncementDetailResult({required this.item, this.failure});
}

class AnnouncementManager {
  static final AnnouncementManager _instance = AnnouncementManager._internal();
  factory AnnouncementManager() => _instance;
  AnnouncementManager._internal();

  @visibleForTesting
  AnnouncementManager.forTesting({
    required Future<AnnouncementModel?> Function() loadLatest,
  }) : _loadLatestOverride = loadLatest;

  Future<AnnouncementModel?> Function()? _loadLatestOverride;
  Future<AnnouncementModel?>? _pendingRequest;
  bool _showingAnnouncement = false;

  final ApiService _apiService = ApiService();

  static const _cacheItemsKey = 'announcement_cache_items_v1';
  static const _cacheTsKey = 'announcement_cache_ts_v1';
  static const _latestPopupIdKey = 'announcement_latest_popup_id_v1';
  static const _readIdsKey = 'announcement_read_ids_v1';
  static const _cacheTtlMs = 6 * 60 * 60 * 1000;

  Future<void> _purgeExpiredCache(SharedPreferences prefs, int nowMs) async {
    final cachedTs = prefs.getInt(_cacheTsKey) ?? 0;
    if (cachedTs > 0 && nowMs - cachedTs >= _cacheTtlMs) {
      await prefs.remove(_cacheItemsKey);
      await prefs.remove(_cacheTsKey);
    }
  }

  Future<AnnouncementHealthResult> checkHealth() async {
    try {
      final ok = await _apiService.announcement.health();
      if (ok) return const AnnouncementHealthResult(ok: true);
      return const AnnouncementHealthResult(
        ok: false,
        failure: AnnouncementFailure(
          type: AnnouncementFailureType.backend,
          message: '公告服务异常，请稍后再试',
        ),
      );
    } on DioException catch (e) {
      return AnnouncementHealthResult(
        ok: false,
        failure: announcementFailureFromDio(e),
      );
    }
  }

  Future<AnnouncementListResult> getAnnouncements({
    bool forceRefresh = false,
    bool activeOnly = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _purgeExpiredCache(prefs, now);
    final cachedTs = prefs.getInt(_cacheTsKey) ?? 0;
    final cachedRaw = prefs.getString(_cacheItemsKey);

    if (!forceRefresh &&
        cachedRaw != null &&
        cachedRaw.isNotEmpty &&
        now - cachedTs < _cacheTtlMs) {
      final cached = _parseCachedList(cachedRaw);
      if (cached != null) {
        return AnnouncementListResult(items: cached, fromCache: true);
      }
    }

    List<AnnouncementModel>? cachedFallback;
    if (cachedRaw != null && cachedRaw.isNotEmpty) {
      cachedFallback = _parseCachedList(cachedRaw);
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final items = await _apiService.announcement.getList(
        appVersion: packageInfo.version,
        activeOnly: activeOnly,
        limit: 200,
      );

      await prefs.setString(
        _cacheItemsKey,
        jsonEncode(items.map((e) => e.toJson()).toList()),
      );
      await prefs.setInt(_cacheTsKey, now);

      return AnnouncementListResult(items: items, fromCache: false);
    } on DioException catch (e) {
      final failure = announcementFailureFromDio(e);
      if (cachedFallback != null) {
        return AnnouncementListResult(
          items: cachedFallback,
          failure: failure,
          fromCache: true,
        );
      }
      return AnnouncementListResult(
        items: const [],
        failure: failure,
        fromCache: false,
      );
    } catch (_) {
      if (cachedFallback != null) {
        return AnnouncementListResult(
          items: cachedFallback,
          failure: const AnnouncementFailure(
            type: AnnouncementFailureType.backend,
            message: '公告数据处理失败，请稍后重试',
          ),
          fromCache: true,
        );
      }
      return const AnnouncementListResult(
        items: [],
        failure: AnnouncementFailure(
          type: AnnouncementFailureType.backend,
          message: '公告数据处理失败，请稍后重试',
        ),
        fromCache: false,
      );
    }
  }

  List<AnnouncementModel>? _parseCachedList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .map(
            (e) =>
                AnnouncementModel.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<AnnouncementDetailResult> getAnnouncementDetail(String id) async {
    try {
      final item = await _apiService.announcement.getDetail(id);
      return AnnouncementDetailResult(item: item);
    } on DioException catch (e) {
      return AnnouncementDetailResult(
        item: null,
        failure: announcementFailureFromDio(e),
      );
    }
  }

  Future<Set<String>> _readAnnouncementIds() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      ...?prefs.getStringList(_readIdsKey),
      if (prefs.getString(_latestPopupIdKey) case final String id) id,
    };
  }

  Future<AnnouncementModel?> fetchPendingAnnouncement() {
    return _pendingRequest ??= _fetchPendingAnnouncement().whenComplete(() {
      _pendingRequest = null;
    });
  }

  Future<AnnouncementModel?> _fetchPendingAnnouncement() async {
    final AnnouncementModel? latest;
    final loadLatest = _loadLatestOverride;
    if (loadLatest != null) {
      latest = await loadLatest();
    } else {
      final packageInfo = await PackageInfo.fromPlatform();
      latest = await _apiService.announcement.getLatest(
        appVersion: packageInfo.version,
      );
    }
    if (latest == null) return null;
    final readIds = await _readAnnouncementIds();
    return readIds.contains(latest.id) ? null : latest;
  }

  Future<bool> showPendingAnnouncement(
    BuildContext context,
    AnnouncementModel item, {
    bool Function()? canShow,
  }) async {
    if (_showingAnnouncement) return false;
    _showingAnnouncement = true;
    try {
      final readIds = await _readAnnouncementIds();
      if (readIds.contains(item.id)) return true;
      if (!context.mounted ||
          ModalRoute.of(context)?.isCurrent != true ||
          (canShow != null && !canShow())) {
        return false;
      }
      final confirmed = await showAnnouncementDialog(
        context: context,
        item: item,
        requireAcknowledgement: item.force == true,
      );
      if (item.force == true && confirmed != true) return false;
      final prefs = await SharedPreferences.getInstance();
      final currentReadIds = await _readAnnouncementIds();
      currentReadIds.add(item.id);
      await prefs.setStringList(_readIdsKey, currentReadIds.toList());
      return true;
    } finally {
      _showingAnnouncement = false;
    }
  }
}
