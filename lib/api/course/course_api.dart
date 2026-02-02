import 'dart:convert';
import '../core/api_client.dart';
import '../auth/auth_api.dart';

class CourseApi {
  final ApiClient _client = ApiClient();
  final AuthApi _authApi = AuthApi();

  static const String _timeTableApi =
      'https://timetable-cfc.cqut.edu.cn/api/courseSchedule/listWeekEvents';

  Future<Map<String, dynamic>> fetchWeekEvents({
    required String userId,
    String? weekNum,
    String? yearTerm,
    String? password,
    String? encryptedPassword,
  }) async {
    await _authApi.ensureTimetableLogin(
      account: userId,
      password: password,
      encryptedPassword: encryptedPassword,
    );

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
        await _authApi.ensureTimetableLogin(
          account: userId,
          password: password,
          encryptedPassword: encryptedPassword,
          force: true,
        );
        return await _fetchWeekEventsOnce(
          body: body,
          userId: userId,
          password: password,
          encryptedPassword: encryptedPassword,
          allowReloginRetry: false,
        );
      }
      return parsed;
    } catch (e) {
      if (!allowReloginRetry) rethrow;
      await _authApi.ensureTimetableLogin(
        account: userId,
        password: password,
        encryptedPassword: encryptedPassword,
        force: true,
      );
      return await _fetchWeekEventsOnce(
        body: body,
        userId: userId,
        password: password,
        encryptedPassword: encryptedPassword,
        allowReloginRetry: false,
      );
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
    throw Exception('Invalid course data format');
  }

  bool _looksLikeAuthError(Map<String, dynamic> data) {
    final hasScheduleFields =
        data.containsKey('yearTerm') || data.containsKey('weekDayList');
    if (hasScheduleFields) return false;
    if (data.containsKey('code') || data.containsKey('msg')) return true;
    return false;
  }
}
