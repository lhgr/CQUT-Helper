import '../core/api_client.dart';

class UserApi {
  final ApiClient _client = ApiClient();

  static const String _userInfoApi =
      'https://timetable-cfc.cqut.edu.cn/api/courseSchedule/getUserInfo';

  Future<Map<String, dynamic>> getUserInfo() async {
    // Cookie 由 ApiClient 中的 cookieJar 管理，所以我们直接发起请求。
    // 根据需求，请求方法为 POST。
    final resp = await _client.dio.post(_userInfoApi);

    if (resp.data is Map<String, dynamic>) {
      return resp.data as Map<String, dynamic>;
    }
    throw Exception('加载个人信息失败');
  }
}
