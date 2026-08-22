import 'package:cqut_helper/model/schedule_notice.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class NoticeApiForbiddenException implements Exception {
  final String message;

  NoticeApiForbiddenException(this.message);

  @override
  String toString() => message;
}

class NoticeApiResponseException implements Exception {
  final String message;

  NoticeApiResponseException(this.message);

  @override
  String toString() => message;
}

class NoticeApiAvailabilityResult {
  final bool success;
  final int elapsedMs;
  final String message;
  final int? noticeCount;

  const NoticeApiAvailabilityResult({
    required this.success,
    required this.elapsedMs,
    required this.message,
    this.noticeCount,
  });
}

class NoticeApi {
  static const String _path = '/api/jwxt/term-schedule-notices';
  static const String _tag = 'NoticeApi';
  static const int _maxRetryPerDomain = 2;

  final Dio Function(String baseUrl) _dioFactory;
  final Future<bool> Function() _accessEnabled;

  NoticeApi({
    @visibleForTesting Dio Function(String baseUrl)? dioFactory,
    @visibleForTesting Future<bool> Function()? accessEnabled,
  }) : _dioFactory = dioFactory ?? _buildDio,
       _accessEnabled =
           accessEnabled ?? ScheduleSettingsManager.isNoticeEnhancementEnabled;

  @visibleForTesting
  static List<String> serviceCandidates(String selectedBaseUrl) {
    return <String>[
      ScheduleSettingsManager.normalizeNoticeApiBaseUrl(selectedBaseUrl),
    ];
  }

  static Dio _buildDio(String baseUrl) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    AppLogger.I.attachToDio(dio, tag: _tag);
    return dio;
  }

  @visibleForTesting
  static Dio buildDioForTesting(String baseUrl) => _buildDio(baseUrl);

  static String? _backendErrorMessage(Object? data) {
    if (data is! Map) return null;
    final error = data['error'];
    if (error is! Map) return null;
    final message = (error['message'] ?? '').toString().trim();
    return message.isEmpty ? null : message;
  }

  static String _dioErrorMessage(DioException error) {
    final statusCode = error.response?.statusCode;
    final backendMessage = _backendErrorMessage(error.response?.data);
    if (backendMessage != null) {
      return statusCode == null
          ? backendMessage
          : '$backendMessage（HTTP $statusCode）';
    }
    return statusCode == null ? '服务不可用，请检查网络或服务地址' : '服务调用失败（HTTP $statusCode）';
  }

  Future<NoticeApiAvailabilityResult> testAvailability({
    required String baseUrl,
    required String username,
    required String encryptedPassword,
    required String yearTerm,
    String env = 'prod',
    bool headless = true,
  }) async {
    final stopwatch = Stopwatch()..start();
    if (!await _accessEnabled()) {
      stopwatch.stop();
      return NoticeApiAvailabilityResult(
        success: false,
        elapsedMs: stopwatch.elapsedMilliseconds,
        message: '调课通知增强未开启，未访问调课服务',
      );
    }
    final normalizedBaseUrl = ScheduleSettingsManager.normalizeNoticeApiBaseUrl(
      baseUrl,
    );
    if (username.trim().isEmpty || encryptedPassword.trim().isEmpty) {
      stopwatch.stop();
      return NoticeApiAvailabilityResult(
        success: false,
        elapsedMs: stopwatch.elapsedMilliseconds,
        message: '登录凭据缺失，请重新登录后再检查',
      );
    }
    if (!RegExp(r'^\d{4}-\d{4}-[12]$').hasMatch(yearTerm.trim())) {
      stopwatch.stop();
      return NoticeApiAvailabilityResult(
        success: false,
        elapsedMs: stopwatch.elapsedMilliseconds,
        message: '当前学期信息缺失，请先打开课表后再检查',
      );
    }
    try {
      final pollData = await _fetchFromBaseUrl(
        baseUrl: normalizedBaseUrl,
        username: username,
        encryptedPassword: encryptedPassword,
        yearTerm: yearTerm,
        env: env,
        headless: headless,
      );
      stopwatch.stop();
      return NoticeApiAvailabilityResult(
        success: true,
        elapsedMs: stopwatch.elapsedMilliseconds,
        message: '服务可用，已获取当前学期调课信息（${pollData.notices.length} 条）',
        noticeCount: pollData.notices.length,
      );
    } on DioException catch (e, st) {
      stopwatch.stop();
      AppLogger.I.warn(
        _tag,
        'availability test failed',
        error: e,
        stackTrace: st,
        fields: {'baseUrl': normalizedBaseUrl},
      );
      return NoticeApiAvailabilityResult(
        success: false,
        elapsedMs: stopwatch.elapsedMilliseconds,
        message: _dioErrorMessage(e),
      );
    } catch (e, st) {
      stopwatch.stop();
      AppLogger.I.warn(
        _tag,
        'availability test unexpected error',
        error: e,
        stackTrace: st,
        fields: {'baseUrl': normalizedBaseUrl},
      );
      return NoticeApiAvailabilityResult(
        success: false,
        elapsedMs: stopwatch.elapsedMilliseconds,
        message: e is StateError
            ? e.message.toString()
            : e is NoticeApiResponseException
            ? e.message
            : '服务调用失败，未能获取调课信息',
      );
    }
  }

  Future<ScheduleNoticePollData> _fetchFromBaseUrl({
    required String baseUrl,
    required String username,
    required String encryptedPassword,
    required String yearTerm,
    required String env,
    required bool headless,
  }) async {
    if (!await _accessEnabled()) {
      throw NoticeApiForbiddenException('调课通知增强未开启，禁止访问调课服务');
    }
    final normalizedYearTerm = yearTerm.trim();
    if (!RegExp(r'^\d{4}-\d{4}-[12]$').hasMatch(normalizedYearTerm)) {
      throw ArgumentError.value(yearTerm, 'yearTerm', '学期格式应为YYYY-YYYY-1/2');
    }
    final response = await _dioFactory(baseUrl).post(
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
      throw NoticeApiResponseException('调课通知响应格式错误');
    }
    if (data['success'] != true) {
      throw NoticeApiResponseException(
        _backendErrorMessage(data) ?? '调课通知响应失败',
      );
    }
    final payload = data['data'];
    if (payload is! Map<String, dynamic>) {
      throw NoticeApiResponseException('调课通知数据缺失');
    }
    final envName = (payload['env'] ?? env).toString().trim();
    final responseYearTerm = (payload['year_term'] ?? '').toString().trim();
    if (responseYearTerm.isNotEmpty && responseYearTerm != normalizedYearTerm) {
      throw StateError(
        '调课通知学期不一致: request=$normalizedYearTerm, response=$responseYearTerm',
      );
    }
    final generatedAt = (payload['generated_at'] ?? '').toString().trim();
    if (payload['term_schedule_notices_complete'] != true) {
      throw NoticeApiResponseException('调课通知数据完整性未确认');
    }
    final rawNotices = payload['term_schedule_notices'];
    if (rawNotices is! List) {
      throw NoticeApiResponseException('调课通知列表缺失或格式错误');
    }
    final notices = <ScheduleNotice>[];
    for (final item in rawNotices) {
      if (item is Map<String, dynamic>) {
        notices.add(ScheduleNotice.fromJson(item));
      } else if (item is Map) {
        notices.add(ScheduleNotice.fromJson(item.cast<String, dynamic>()));
      } else {
        throw NoticeApiResponseException('调课通知条目格式错误');
      }
    }
    return ScheduleNoticePollData(
      env: envName,
      yearTerm: responseYearTerm.isEmpty
          ? normalizedYearTerm
          : responseYearTerm,
      generatedAt: generatedAt,
      notices: notices,
    );
  }

  Future<ScheduleNoticePollData> fetchTermScheduleNotices({
    required String username,
    required String encryptedPassword,
    required String yearTerm,
    String env = 'prod',
    bool headless = true,
  }) async {
    if (!await _accessEnabled()) {
      throw NoticeApiForbiddenException('调课通知增强未开启，禁止访问调课服务');
    }
    final normalizedYearTerm = yearTerm.trim();
    if (!RegExp(r'^\d{4}-\d{4}-[12]$').hasMatch(normalizedYearTerm)) {
      throw ArgumentError.value(yearTerm, 'yearTerm', '学期格式应为YYYY-YYYY-1/2');
    }
    final customBaseUrl = await ScheduleSettingsManager.loadNoticeApiBaseUrl();
    // Never send credentials to a different service than the one selected by
    // the user. In particular, a self-hosted endpoint must not silently fall
    // back to the official service when it is unavailable.
    final candidates = serviceCandidates(customBaseUrl);
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var i = 0; i < candidates.length; i++) {
      final baseUrl = candidates[i];
      for (var attempt = 1; attempt <= _maxRetryPerDomain; attempt++) {
        try {
          return await _fetchFromBaseUrl(
            baseUrl: baseUrl,
            username: username,
            encryptedPassword: encryptedPassword,
            yearTerm: normalizedYearTerm,
            env: env,
            headless: headless,
          );
        } on DioException catch (e, st) {
          final code = e.response?.statusCode;
          if (code == 403) {
            throw NoticeApiForbiddenException('调课通知接口夜间关闭(403)');
          }
          if (code == 429) {
            throw Exception('调课服务请求过于频繁，请稍后再试');
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
    }
    if (lastError != null) {
      Error.throwWithStackTrace(
        lastError,
        lastStackTrace ?? StackTrace.current,
      );
    }
    throw Exception('调课通知请求失败');
  }
}
