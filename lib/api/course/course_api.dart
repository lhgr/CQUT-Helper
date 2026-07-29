import 'dart:convert';
import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../auth/auth_api.dart';

enum CourseApiErrorKind {
  authentication,
  timeout,
  network,
  server,
  invalidResponse,
}

class CourseApiException implements Exception {
  final CourseApiErrorKind kind;
  final String message;
  final int? statusCode;

  const CourseApiException(this.kind, this.message, {this.statusCode});

  @override
  String toString() => message;
}

class CourseApi {
  final ApiClient _client = ApiClient();
  final AuthApi _authApi = AuthApi();

  static const String _timeTableApi =
      'https://timetable-cfc.cqut.edu.cn/api/courseSchedule/listWeekEvents';

  static const String _campusTimeInfoApi =
      'https://timetable-cfc.cqut.edu.cn/api/courseSchedule/getCampusTimeInfo';

  Future<List<dynamic>> fetchCampusTimeInfo(String campusName) async {
    final body = <String, dynamic>{'campusName': campusName};
    final resp = await _client.dio.post(_campusTimeInfoApi, data: body);
    if (resp.data is List) {
      return resp.data as List<dynamic>;
    }
    // Handle potential JSON string or map wrapping
    if (resp.data is String) {
      final decoded = json.decode(resp.data);
      if (decoded is List) return decoded;
    }
    throw Exception('Failed to fetch campus time info');
  }

  Future<Map<String, dynamic>> fetchWeekEvents({
    required String userId,
    String? weekNum,
    String? yearTerm,
    String? password,
    String? encryptedPassword,
  }) async {
    try {
      await _authApi.ensureTimetableLogin(
        account: userId,
        password: password,
        encryptedPassword: encryptedPassword,
      );
    } on DioException catch (error) {
      throw _mapDioException(error);
    }

    final body = <String, dynamic>{'userID': userId};
    if (weekNum != null) body['weekNum'] = weekNum;
    if (yearTerm != null) body['yearTerm'] = yearTerm;

    return await _fetchWeekEventsOnce(
      body: body,
      userId: userId,
      password: password,
      encryptedPassword: encryptedPassword,
      allowReloginRetry: true,
    );
  }

  Future<Map<String, dynamic>> _fetchWeekEventsOnce({
    required Map<String, dynamic> body,
    required String userId,
    required String? password,
    required String? encryptedPassword,
    required bool allowReloginRetry,
  }) async {
    try {
      final resp = await _client.dio.post(_timeTableApi, data: body);
      final parsed = _parseCourseResponse(resp.data);
      if (_looksLikeAuthError(parsed) && allowReloginRetry) {
        await _forceRelogin(
          userId: userId,
          password: password,
          encryptedPassword: encryptedPassword,
        );
        return await _fetchWeekEventsOnce(
          body: body,
          userId: userId,
          password: password,
          encryptedPassword: encryptedPassword,
          allowReloginRetry: false,
        );
      }
      if (_looksLikeAuthError(parsed)) {
        throw CourseApiException(
          CourseApiErrorKind.authentication,
          _authErrorMessage(parsed),
        );
      }
      return parsed;
    } on DioException catch (error) {
      if (allowReloginRetry &&
          _isAuthenticationStatus(error.response?.statusCode)) {
        await _forceRelogin(
          userId: userId,
          password: password,
          encryptedPassword: encryptedPassword,
        );
        return _fetchWeekEventsOnce(
          body: body,
          userId: userId,
          password: password,
          encryptedPassword: encryptedPassword,
          allowReloginRetry: false,
        );
      }
      throw _mapDioException(error);
    }
  }

  Future<void> _forceRelogin({
    required String userId,
    required String? password,
    required String? encryptedPassword,
  }) async {
    try {
      await _authApi.ensureTimetableLogin(
        account: userId,
        password: password,
        encryptedPassword: encryptedPassword,
        force: true,
      );
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Map<String, dynamic> _parseCourseResponse(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is String) {
      try {
        final decoded = json.decode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    throw const CourseApiException(
      CourseApiErrorKind.invalidResponse,
      '课表接口返回格式异常，请稍后重试',
    );
  }

  bool _looksLikeAuthError(Map<String, dynamic> data) {
    final hasScheduleFields =
        data.containsKey('yearTerm') || data.containsKey('weekDayList');
    if (hasScheduleFields) return false;
    if (data.containsKey('code') || data.containsKey('msg')) return true;
    return false;
  }

  String _authErrorMessage(Map<String, dynamic> data) {
    final msg = (data['msg'] ?? '').toString().trim();
    if (msg.isNotEmpty) return msg;
    return '课表鉴权失败，请重新登录';
  }

  bool _isAuthenticationStatus(int? statusCode) =>
      statusCode == 401 || statusCode == 403;

  CourseApiException _mapDioException(DioException error) {
    final statusCode = error.response?.statusCode;
    if (_isAuthenticationStatus(statusCode)) {
      return CourseApiException(
        CourseApiErrorKind.authentication,
        '登录凭证已失效，请重新登录',
        statusCode: statusCode,
      );
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const CourseApiException(
        CourseApiErrorKind.timeout,
        '课表服务响应超时，请稍后重试',
      );
    }
    if (error.type == DioExceptionType.connectionError) {
      return const CourseApiException(
        CourseApiErrorKind.network,
        '网络连接失败，请检查网络后重试',
      );
    }
    if (statusCode != null && statusCode >= 500) {
      return CourseApiException(
        CourseApiErrorKind.server,
        '课表服务暂时不可用，请稍后重试',
        statusCode: statusCode,
      );
    }
    return CourseApiException(
      CourseApiErrorKind.network,
      '课表获取失败，请稍后重试',
      statusCode: statusCode,
    );
  }
}
