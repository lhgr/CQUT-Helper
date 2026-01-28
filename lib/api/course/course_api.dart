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
    if (encryptedPassword != null) {
      await _authApi.loginWithEncrypted(
        account: userId,
        encryptedPassword: encryptedPassword,
      );
    } else if (password != null) {
      await _authApi.login(account: userId, password: password);
    } else {
      throw Exception('Password or encryptedPassword must be provided');
    }

    final body = <String, dynamic>{'userID': userId};
    if (weekNum != null) body['weekNum'] = weekNum;
    if (yearTerm != null) body['yearTerm'] = yearTerm;

    final resp = await _client.dio.post(_timeTableApi, data: body);
    if (resp.data is Map<String, dynamic>) {
      return resp.data as Map<String, dynamic>;
    }
    if (resp.data is String) {
      return json.decode(resp.data as String) as Map<String, dynamic>;
    }
    throw Exception('Invalid course data format');
  }
}
