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

  static const String _addCustomEventApi =
      'https://timetable-cfc.cqut.edu.cn/api/courseSchedule/addCustomEvent';

  static const String _editCustomEventApi =
      'https://timetable-cfc.cqut.edu.cn/api/courseSchedule/editCustomEvent';

  static const String _deleteCustomEventApi =
      'https://timetable-cfc.cqut.edu.cn/api/courseSchedule/deleteCustomEvent';

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

  Future<void> addCustomEvent({
    required String userId,
    required String encryptedPassword,
    required String yearTerm,
    required List<int> weekList,
    required int weekDay,
    required int sessionStart,
    required int sessionCount,
    required String eventName,
    required String address,
    required String memberName,
  }) {
    return _mutateCustomEvent(
      url: _addCustomEventApi,
      userId: userId,
      encryptedPassword: encryptedPassword,
      body: <String, dynamic>{
        'yearTerm': yearTerm,
        'weekList': weekList.map((week) => week.toString()).toList(),
        'weekDay': weekDay.toString(),
        'sessionStart': sessionStart.toString(),
        'sessionLast': sessionCount.toString(),
        'eventName': eventName,
        'address': address,
        'memberName': memberName,
      },
    );
  }

  Future<void> editCustomEvent({
    required String userId,
    required String encryptedPassword,
    required String eventId,
    required List<int> weekList,
    required int weekDay,
    required int sessionStart,
    required int sessionCount,
    required String eventName,
    required String address,
    required String memberName,
  }) {
    return _mutateCustomEvent(
      url: _editCustomEventApi,
      userId: userId,
      encryptedPassword: encryptedPassword,
      body: <String, dynamic>{
        'eventID': eventId,
        'weekList': weekList.map((week) => week.toString()).toList(),
        'weekDay': weekDay.toString(),
        'sessionStart': sessionStart.toString(),
        'sessionLast': sessionCount.toString(),
        'eventName': eventName,
        'address': address,
        'memberName': memberName,
      },
    );
  }

  Future<void> deleteCustomEvent({
    required String userId,
    required String encryptedPassword,
    required String eventId,
  }) {
    return _mutateCustomEvent(
      url: _deleteCustomEventApi,
      userId: userId,
      encryptedPassword: encryptedPassword,
      body: <String, dynamic>{'eventID': eventId},
    );
  }

  Future<void> _mutateCustomEvent({
    required String url,
    required String userId,
    required String encryptedPassword,
    required Map<String, dynamic> body,
  }) async {
    try {
      await _authApi.ensureTimetableLogin(
        account: userId,
        encryptedPassword: encryptedPassword,
      );
    } on DioException catch (error) {
      throw _mapDioException(error);
    }

    await _mutateCustomEventOnce(
      url: url,
      body: body,
      userId: userId,
      encryptedPassword: encryptedPassword,
      allowReloginRetry: true,
    );
  }

  Future<void> _mutateCustomEventOnce({
    required String url,
    required Map<String, dynamic> body,
    required String userId,
    required String encryptedPassword,
    required bool allowReloginRetry,
  }) async {
    try {
      final response = await _client.dio.post(url, data: body);
      final parsed = _parseCourseResponse(response.data);
      if (_isCustomEventMutationSuccess(parsed)) return;
      if (allowReloginRetry && _looksLikeMutationAuthError(parsed)) {
        await _forceRelogin(
          userId: userId,
          password: null,
          encryptedPassword: encryptedPassword,
        );
        return _mutateCustomEventOnce(
          url: url,
          body: body,
          userId: userId,
          encryptedPassword: encryptedPassword,
          allowReloginRetry: false,
        );
      }
      throw CourseApiException(
        CourseApiErrorKind.invalidResponse,
        _customEventMutationErrorMessage(parsed),
      );
    } on DioException catch (error) {
      if (allowReloginRetry &&
          _isAuthenticationStatus(error.response?.statusCode)) {
        await _forceRelogin(
          userId: userId,
          password: null,
          encryptedPassword: encryptedPassword,
        );
        return _mutateCustomEventOnce(
          url: url,
          body: body,
          userId: userId,
          encryptedPassword: encryptedPassword,
          allowReloginRetry: false,
        );
      }
      throw _mapDioException(error);
    }
  }

  bool _isCustomEventMutationSuccess(Map<String, dynamic> data) {
    final code = data['code'];
    return code == 0 || code?.toString() == '0';
  }

  bool _looksLikeMutationAuthError(Map<String, dynamic> data) {
    final message = <Object?>[data['message'], data['msg'], data['data']]
        .whereType<Object>()
        .map((value) => value.toString().toLowerCase())
        .join(' ');
    return message.contains('登录') ||
        message.contains('认证') ||
        message.contains('鉴权') ||
        message.contains('login') ||
        message.contains('unauthorized');
  }

  String _customEventMutationErrorMessage(Map<String, dynamic> data) {
    for (final key in const ['message', 'msg', 'data']) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '自定义课程操作失败，请稍后重试';
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
