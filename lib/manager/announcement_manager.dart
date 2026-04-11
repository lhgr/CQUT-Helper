import 'dart:convert';

import 'package:cqut/api/api_service.dart';
import 'package:cqut/model/announcement_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum AnnouncementFailureType { backend, user }

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

  final ApiService _apiService = ApiService();

  static const _cacheItemsKey = 'announcement_cache_items_v1';
  static const _cacheTsKey = 'announcement_cache_ts_v1';
  static const _latestPopupIdKey = 'announcement_latest_popup_id_v1';
  static const _cacheTtlMs = 6 * 60 * 60 * 1000;

  AnnouncementFailure _failureFromDio(DioException e) {
    final statusCode = e.response?.statusCode;
    final data = e.response?.data;
    final serverError = data is Map<String, dynamic> ? data['error'] : null;
    final serverErrorText = serverError is String && serverError.isNotEmpty
        ? serverError
        : null;

    if (statusCode != null) {
      final type = statusCode >= 500
          ? AnnouncementFailureType.backend
          : AnnouncementFailureType.user;
      final message = serverErrorText ?? '请求失败（$statusCode）';
      return AnnouncementFailure(
        type: type,
        message: message,
        statusCode: statusCode,
      );
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const AnnouncementFailure(
          type: AnnouncementFailureType.user,
          message: '网络超时，请检查网络后重试',
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return const AnnouncementFailure(
          type: AnnouncementFailureType.user,
          message: '网络异常，请检查网络后重试',
        );
      case DioExceptionType.cancel:
        return const AnnouncementFailure(
          type: AnnouncementFailureType.user,
          message: '请求已取消',
        );
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return const AnnouncementFailure(
          type: AnnouncementFailureType.user,
          message: '网络异常，请稍后重试',
        );
    }
  }

  Future<void> _purgeExpiredCache(SharedPreferences prefs, int nowMs) async {
    final cachedTs = prefs.getInt(_cacheTsKey) ?? 0;
    if (cachedTs > 0 && nowMs - cachedTs >= _cacheTtlMs) {
      await prefs.remove(_cacheItemsKey);
      await prefs.remove(_cacheTsKey);
    }
  }

  String _formatMarkdown(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final buffer = StringBuffer();
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isNotEmpty && !line.endsWith('  ')) {
        buffer.write(line);
        buffer.write('  ');
      } else {
        buffer.write(line);
      }
      if (i != lines.length - 1) buffer.write('\n');
    }
    return buffer.toString();
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
      return AnnouncementHealthResult(ok: false, failure: _failureFromDio(e));
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
      final healthOk = await _apiService.announcement.health();
      if (!healthOk) {
        return AnnouncementListResult(
          items: cachedFallback ?? const [],
          failure: const AnnouncementFailure(
            type: AnnouncementFailureType.backend,
            message: '公告服务异常，请稍后再试',
          ),
          fromCache: cachedFallback != null,
        );
      }

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
      final failure = _failureFromDio(e);
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
            type: AnnouncementFailureType.user,
            message: '获取公告失败，请稍后重试',
          ),
          fromCache: true,
        );
      }
      return const AnnouncementListResult(
        items: [],
        failure: AnnouncementFailure(
          type: AnnouncementFailureType.user,
          message: '获取公告失败，请稍后重试',
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
      return AnnouncementDetailResult(item: null, failure: _failureFromDio(e));
    }
  }

  Future<void> checkAndShow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final packageInfo = await PackageInfo.fromPlatform();
    final latest = await _apiService.announcement.getLatest(
      appVersion: packageInfo.version,
    );
    if (latest == null) return;
    final lastPopupId = prefs.getString(_latestPopupIdKey);
    if (lastPopupId == latest.id) return;
    if (!context.mounted) return;

    await _showAnnouncementDialog(context, latest);
    await prefs.setString(_latestPopupIdKey, latest.id);
  }

  Future<void> _showAnnouncementDialog(
    BuildContext context,
    AnnouncementModel item,
  ) async {
    final force = item.force == true;

    await showDialog(
      context: context,
      barrierDismissible: !force,
      builder: (context) {
        return AlertDialog(
          title: Text(item.title),
          content: SingleChildScrollView(
            child: MarkdownBody(
              data: _formatMarkdown(item.contentMarkdown),
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
              onTapLink: (text, href, title) {
                if (href == null || href.isEmpty) return;
                _launchExternalUrl(context, href);
              },
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(force ? '我已知晓' : '关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _launchExternalUrl(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开链接')));
      }
    }
  }
}
