import 'package:dio/dio.dart';
import 'package:cqut/model/update_model.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

class UpdateApi {
  final Dio _dio = Dio();
  static const String _owner = 'lhgr';
  static const String _repo = 'CQUT-Helper';

  Future<UpdateModel?> checkUpdate() async {
    try {
      final response = await _dio.get(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
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
