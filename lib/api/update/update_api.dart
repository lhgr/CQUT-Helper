import 'package:dio/dio.dart';
import 'package:cqut_helper/model/update_model.dart';
import 'package:cqut_helper/utils/github_proxy.dart';
import 'package:cqut_helper/utils/app_logger.dart';

class UpdateApi {
  static const String _tag = 'UpdateApi';
  late final Dio _dio;
  static const String _owner = 'lhgr';
  static const String _repo = 'CQUT-Helper';

  UpdateApi() {
    _dio = Dio();
    AppLogger.I.attachToDio(_dio, tag: _tag);
  }

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
      AppLogger.I.warn(_tag, 'Check update failed', error: e);
    }
    return null;
  }
}
