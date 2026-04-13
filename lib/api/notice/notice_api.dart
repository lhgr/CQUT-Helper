import 'package:cqut_helper/model/schedule_notice.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:dio/dio.dart';

class NoticeApiForbiddenException implements Exception {
  final String message;

  NoticeApiForbiddenException(this.message);

  @override
  String toString() => message;
}

class NoticeApiConnectivityResult {
  final bool success;
  final int elapsedMs;
  final String message;

  const NoticeApiConnectivityResult({
    required this.success,
    required this.elapsedMs,
    required this.message,
  });
}

class NoticeApi {
  static const String _officialBaseUrl =
      ScheduleSettingsManager.officialNoticeApiBaseUrl;
  static const String _path = '/api/jwxt/term-schedule-notices';
  static const String _healthPath = '/health';
  static const String _tag = 'NoticeApi';
  static const int _maxRetryPerDomain = 2;

  NoticeApi();

  static Dio _buildDio(String baseUrl) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 15),
        headers: const {'Content-Type': 'application/json'},
      ),
    );
    AppLogger.I.attachToDio(dio, tag: _tag);
    return dio;
  }

  static Future<NoticeApiConnectivityResult> testConnectivity(String baseUrl) async {
    final normalizedBaseUrl = ScheduleSettingsManager.normalizeNoticeApiBaseUrl(
      baseUrl,
    );
    final stopwatch = Stopwatch()..start();
    final dio = _buildDio(normalizedBaseUrl);
    try {
      final response = await dio.get(_healthPath);
      stopwatch.stop();
      final ok = response.statusCode == 200;
      if (!ok) {
        return NoticeApiConnectivityResult(
          success: false,
          elapsedMs: stopwatch.elapsedMilliseconds,
          message: '健康检查失败(${response.statusCode ?? 0})',
        );
      }
      return NoticeApiConnectivityResult(
        success: true,
        elapsedMs: stopwatch.elapsedMilliseconds,
        message: '连通成功',
      );
    } on DioException catch (e, st) {
      stopwatch.stop();
      AppLogger.I.warn(
        _tag,
        'connectivity test failed',
        error: e,
        stackTrace: st,
        fields: {'baseUrl': normalizedBaseUrl},
      );
      return NoticeApiConnectivityResult(
        success: false,
        elapsedMs: stopwatch.elapsedMilliseconds,
        message: '连通失败，请检查网络或域名配置',
      );
    } catch (e, st) {
      stopwatch.stop();
      AppLogger.I.warn(
        _tag,
        'connectivity test unexpected error',
        error: e,
        stackTrace: st,
        fields: {'baseUrl': normalizedBaseUrl},
      );
      return NoticeApiConnectivityResult(
        success: false,
        elapsedMs: stopwatch.elapsedMilliseconds,
        message: '连通失败，请检查网络或域名配置',
      );
    }
  }

  Future<ScheduleNoticePollData> fetchTermScheduleNotices({
    required String username,
    required String encryptedPassword,
    required String yearTerm,
    String env = 'prod',
    bool headless = true,
  }) async {
    final normalizedYearTerm = yearTerm.trim();
    if (!RegExp(r'^\d{4}-\d{4}-[12]$').hasMatch(normalizedYearTerm)) {
      throw ArgumentError.value(yearTerm, 'yearTerm', '学期格式应为YYYY-YYYY-1/2');
    }
    final customBaseUrl = await ScheduleSettingsManager.loadNoticeApiBaseUrl();
    final candidates = <String>[
      customBaseUrl,
      if (customBaseUrl != _officialBaseUrl) _officialBaseUrl,
    ];
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var i = 0; i < candidates.length; i++) {
      final baseUrl = candidates[i];
      final isFallback = i > 0;
      final dio = _buildDio(baseUrl);
      for (var attempt = 1; attempt <= _maxRetryPerDomain; attempt++) {
        try {
          final response = await dio.post(
            _path,
            data: {
              'username': username,
              'encrypted_password': encryptedPassword,
              'year_term': normalizedYearTerm,
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
          final responseYearTerm = (payload['year_term'] ?? '')
              .toString()
              .trim();
          if (responseYearTerm.isNotEmpty &&
              responseYearTerm != normalizedYearTerm) {
            throw StateError(
              '调课通知学期不一致: request=$normalizedYearTerm, response=$responseYearTerm',
            );
          }
          final generatedAt = (payload['generated_at'] ?? '').toString().trim();
          final rawNotices = payload['term_schedule_notices'];
          final notices = <ScheduleNotice>[];
          if (rawNotices is List) {
            for (final item in rawNotices) {
              if (item is Map<String, dynamic>) {
                notices.add(ScheduleNotice.fromJson(item));
              } else if (item is Map) {
                notices.add(
                  ScheduleNotice.fromJson(item.cast<String, dynamic>()),
                );
              }
            }
          }
          if (isFallback) {
            AppLogger.I.warn(
              _tag,
              'fallback to official notice domain success',
              fields: {'fromBaseUrl': customBaseUrl, 'toBaseUrl': baseUrl},
            );
          }
          return ScheduleNoticePollData(
            env: envName,
            yearTerm: responseYearTerm.isEmpty
                ? normalizedYearTerm
                : responseYearTerm,
            generatedAt: generatedAt,
            notices: notices,
          );
        } on DioException catch (e, st) {
          final code = e.response?.statusCode;
          if (code == 403) {
            throw NoticeApiForbiddenException('调课通知接口夜间关闭(403)');
          }
          lastError = e;
          lastStackTrace = st;
          AppLogger.I.warn(
            _tag,
            'notice request failed',
            error: e,
            stackTrace: st,
            fields: {
              'baseUrl': baseUrl,
              'attempt': attempt,
              'retryLimit': _maxRetryPerDomain,
            },
          );
        } catch (e, st) {
          lastError = e;
          lastStackTrace = st;
          AppLogger.I.warn(
            _tag,
            'notice request unexpected error',
            error: e,
            stackTrace: st,
            fields: {
              'baseUrl': baseUrl,
              'attempt': attempt,
              'retryLimit': _maxRetryPerDomain,
            },
          );
        }
      }
      if (i < candidates.length - 1) {
        AppLogger.I.warn(
          _tag,
          'notice domain unavailable fallback to official domain',
          fields: {'fromBaseUrl': baseUrl, 'toBaseUrl': _officialBaseUrl},
        );
      }
    }
    if (lastError != null) {
      Error.throwWithStackTrace(lastError, lastStackTrace ?? StackTrace.current);
    }
    throw Exception('调课通知请求失败');
  }
}
