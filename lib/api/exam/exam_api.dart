import 'package:cqut_helper/model/exam_model.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:dio/dio.dart';

class ExamAuthenticationException implements Exception {
  const ExamAuthenticationException();
  @override
  String toString() => '登录凭据已失效，请重新登录';
}

class ExamApi {
  ExamApi({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 120),
      responseType: ResponseType.json,
    );
    AppLogger.I.attachToDio(_dio, tag: 'ExamApi');
  }
  final Dio _dio;

  Future<ExamSnapshot> fetch({
    required String baseUrl,
    required String username,
    required String encryptedPassword,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '$baseUrl/api/jwxt/exams',
        data: {'username': username, 'encrypted_password': encryptedPassword},
      );
      final body = response.data;
      if (body is! Map || body['success'] != true || body['data'] is! Map) {
        throw const FormatException('考试服务返回格式无效');
      }
      return ExamSnapshot.fromJson(
        (body['data'] as Map).cast<String, dynamic>(),
        fetchedAt: DateTime.now(),
      );
    } on DioException catch (error) {
      final body = error.response?.data;
      final detail = body is Map ? body['error'] : null;
      final code = detail is Map
          ? (detail['code'] ?? '').toString().toLowerCase()
          : '';
      if (error.response?.statusCode == 401 ||
          code.contains('credential') ||
          code.contains('login_failed') ||
          code == 'authentication_failed') {
        throw const ExamAuthenticationException();
      }
      rethrow;
    }
  }
}
