import '../core/api_client.dart';

class UserApi {
  final ApiClient _client = ApiClient();

  static const String _userInfoApi =
      'https://timetable-cfc.cqut.edu.cn/api/courseSchedule/getUserInfo';

  Future<Map<String, dynamic>> getUserInfo() async {
    // The cookies are managed by the cookieJar in ApiClient, so we just make the request.
    // The request method is POST as per requirement.
    final resp = await _client.dio.post(_userInfoApi);

    if (resp.data is Map<String, dynamic>) {
      return resp.data as Map<String, dynamic>;
    }
    throw Exception('加载个人信息失败');
  }
}
