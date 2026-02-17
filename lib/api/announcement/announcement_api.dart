import 'package:cqut/model/announcement_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

class AnnouncementApi {
  static const String _baseUrl = 'https://dawndrizzle.top';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
    ),
  );

  Future<AnnouncementModel?> getLatest({String? appVersion}) async {
    try {
      final response = await _dio.get(
        '/v1/announcements/latest',
        queryParameters: {
          if (appVersion != null && appVersion.isNotEmpty)
            'appVersion': appVersion,
        },
      );
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final item = data['item'];
        if (item == null) return null;
        return AnnouncementModel.fromJson(item as Map<String, dynamic>);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Get latest announcement failed: $e');
      }
    }
    return null;
  }

  Future<bool> health() async {
    try {
      final response = await _dio.get('/v1/health');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return data['ok'] == true;
        }
      }
      return false;
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('Health check failed: $e');
      }
      rethrow;
    }
  }

  Future<List<AnnouncementModel>> getList({
    String? appVersion,
    bool activeOnly = true,
    int limit = 200,
  }) async {
    try {
      final response = await _dio.get(
        '/v1/announcements',
        queryParameters: {
          if (appVersion != null && appVersion.isNotEmpty)
            'appVersion': appVersion,
          'active': activeOnly ? '1' : '0',
          'limit': limit,
        },
      );
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final items = (data['items'] as List<dynamic>?) ?? const [];
        return items
            .map((e) => AnnouncementModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('Get announcements failed: $e');
      }
      rethrow;
    }
    return const [];
  }

  Future<AnnouncementModel?> getDetail(String id) async {
    try {
      final response = await _dio.get('/v1/announcements/$id');
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final item = data['item'];
        if (item == null) return null;
        return AnnouncementModel.fromJson(item as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('Get announcement detail failed: $e');
      }
      rethrow;
    }
  }
}
