import 'package:cqut_helper/model/daily_quote_model.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:dio/dio.dart';

class DailyQuoteApi {
  static const String _baseUrl = 'https://api.dawndrizzle.top';
  static const String _tag = 'DailyQuoteApi';

  late final Dio _dio;

  DailyQuoteApi() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 5),
      ),
    );
    AppLogger.I.attachToDio(_dio, tag: _tag);
  }

  Future<DailyQuoteConfig> getConfig() async {
    try {
      final response = await _dio.get('/announcements/daily-quotes/config');
      final data = response.data;
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return DailyQuoteConfig.fromJson(data);
      }
      throw const FormatException('Invalid daily quote response');
    } catch (error, stackTrace) {
      AppLogger.I.warn(
        _tag,
        'Get daily quote config failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
