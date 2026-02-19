import 'package:dio/dio.dart';
import 'package:cqut/model/update_model.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:cqut/utils/github_proxy.dart';

class UpdateApi {
  final Dio _dio = Dio();
  static const String _owner = 'lhgr';
  static const String _repo = 'CQUT-Helper';

  Future<UpdateModel?> checkUpdate() async {
    try {
      final response = await GithubProxy.getWithFallback(
        _dio,
        Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest'),
      );

      if (response.statusCode == 200) {
        return UpdateModel.fromJson(response.data);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Check update failed: $e');
      }
    }
    return null;
  }
}
