import 'package:dio/dio.dart';
import 'package:cqut/model/update_model.dart';

class UpdateApi {
  final Dio _dio = Dio();
  // 替换为您实际的 GitHub 仓库地址
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
      // 忽略错误或记录日志
      print('Check update failed: $e');
    }
    return null;
  }
}
