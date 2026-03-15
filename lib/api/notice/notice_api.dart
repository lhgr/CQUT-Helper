import 'package:cqut/model/schedule_notice.dart';
import 'package:cqut/utils/app_logger.dart';
import 'package:dio/dio.dart';

class NoticeApiForbiddenException implements Exception {
  final String message;

  NoticeApiForbiddenException(this.message);

  @override
  String toString() => message;
}

class NoticeApi {
  static const String _baseUrl = 'https://notice.dawndrizzle.top';
  static const String _path = '/api/jwxt/term-schedule-notices';
  static const String _tag = 'NoticeApi';
  late final Dio _dio;

  NoticeApi({Dio? dio}) {
    _dio = dio ??
        Dio(
          BaseOptions(
            baseUrl: _baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 15),
            headers: const {'Content-Type': 'application/json'},
          ),
        );
    AppLogger.I.attachToDio(_dio, tag: _tag);
  }

  Future<ScheduleNoticePollData> fetchTermScheduleNotices({
    required String username,
    required String encryptedPassword,
    String env = 'prod',
    bool headless = true,
  }) async {
    try {
      final response = await _dio.post(
        _path,
        data: {
          'username': username,
          'encrypted_password': encryptedPassword,
          'env': env,
          'headless': headless,
        },
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('调课通知响应格式错误');
      }
      if (data['success'] != true) {
        throw Exception('调课通知响应失败');
      }
      final payload = data['data'];
      if (payload is! Map<String, dynamic>) {
        throw Exception('调课通知数据缺失');
      }
      final envName = (payload['env'] ?? env).toString().trim();
      final generatedAt = (payload['generated_at'] ?? '').toString().trim();
      final rawNotices = payload['term_schedule_notices'];
      final notices = <ScheduleNotice>[];
      if (rawNotices is List) {
        for (final item in rawNotices) {
          if (item is Map<String, dynamic>) {
            notices.add(ScheduleNotice.fromJson(item));
          } else if (item is Map) {
            notices.add(ScheduleNotice.fromJson(item.cast<String, dynamic>()));
          }
        }
      }
      return ScheduleNoticePollData(
        env: envName,
        generatedAt: generatedAt,
        notices: notices,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403) {
        throw NoticeApiForbiddenException('调课通知接口夜间关闭(403)');
      }
      rethrow;
    }
  }
}
