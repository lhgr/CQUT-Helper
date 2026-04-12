import 'package:cqut_helper/model/announcement_model.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:dio/dio.dart';

class AnnouncementApi {
  static const String _baseUrl = 'https://api.dawndrizzle.top';
  static const String _tag = 'AnnouncementApi';

  late final Dio _dio;

  AnnouncementApi() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
      ),
    );
    AppLogger.I.attachToDio(_dio, tag: _tag);
  }

  Future<AnnouncementModel?> getLatest({String? appVersion}) async {
    try {
      final response = await _dio.get(
        '/announcements/latest',
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
      AppLogger.I.warn(_tag, 'Get latest announcement failed', error: e);
    }
    return null;
  }

  Future<bool> health() async {
    try {
      final response = await _dio.get('/announcements/health');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return data['ok'] == true;
        }
      }
      return false;
    } on DioException catch (e) {
      AppLogger.I.warn(
        _tag,
        'Health check failed',
        error: e,
        stackTrace: e.stackTrace,
      );
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
        '/announcements',
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
      AppLogger.I.warn(
        _tag,
        'Get announcements failed',
        error: e,
        stackTrace: e.stackTrace,
      );
      rethrow;
    }
    return const [];
  }

  Future<AnnouncementModel?> getDetail(String id) async {
    try {
      final response = await _dio.get('/announcements/$id');
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final item = data['item'];
        if (item == null) return null;
        return AnnouncementModel.fromJson(item as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      AppLogger.I.warn(
        _tag,
        'Get announcement detail failed',
        error: e,
        stackTrace: e.stackTrace,
      );
      rethrow;
    }
  }
}
