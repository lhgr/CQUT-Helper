import 'dart:convert';

import 'package:cqut/api/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MineNotLoggedInException implements Exception {
  const MineNotLoggedInException();

  @override
  String toString() => '未登录';
}

class MineUserInfoLoadResult {
  final String userId;
  final Map<String, dynamic> userInfo;

  const MineUserInfoLoadResult({required this.userId, required this.userInfo});
}

class MineUserInfoLoader {
  final ApiService apiService;

  const MineUserInfoLoader(this.apiService);

  Future<MineUserInfoLoadResult> load({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('account');

    if (userId == null || userId.isEmpty) {
      throw const MineNotLoggedInException();
    }

    final cacheKey = 'user_info_$userId';

    if (!forceRefresh) {
      final cachedJson = prefs.getString(cacheKey);
      if (cachedJson != null) {
        final decoded = json.decode(cachedJson);
        if (decoded is Map<String, dynamic>) {
          return MineUserInfoLoadResult(userId: userId, userInfo: decoded);
        }
      }
    }

    final info = await apiService.user.getUserInfo();
    await prefs.setString(cacheKey, json.encode(info));

    return MineUserInfoLoadResult(userId: userId, userInfo: info);
  }
}
