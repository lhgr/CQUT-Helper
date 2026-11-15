import 'package:cqut_helper/api/exam/exam_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exam response budget covers the shared backend query deadline', () {
    final dio = Dio();
    ExamApi(dio: dio);
    expect(dio.options.receiveTimeout, const Duration(seconds: 120));
  });
  test(
    'exams use shared service with credentials and no term argument',
    () async {
      final dio = Dio();
      RequestOptions? request;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': {
                    'generated_at': '2026-11-18T08:00:00+08:00',
                    'exams_complete': true,
                    'exams': [],
                  },
                },
              ),
            );
          },
        ),
      );
      final result = await ExamApi(dio: dio).fetch(
        baseUrl: 'https://query.example',
        username: 'student',
        encryptedPassword: 'encrypted-test',
      );
      expect(request!.path, 'https://query.example/api/jwxt/exams');
      expect(request!.data, {
        'username': 'student',
        'encrypted_password': 'encrypted-test',
      });
      expect(result.exams, isEmpty);
    },
  );

  test(
    'incomplete response is rejected rather than clearing cached exams',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': {
                  'generated_at': '2026-11-18T08:00:00+08:00',
                  'exams_complete': false,
                  'exams': [],
                },
              },
            ),
          ),
        ),
      );
      await expectLater(
        ExamApi(dio: dio).fetch(
          baseUrl: 'https://query.example',
          username: 'student',
          encryptedPassword: 'encrypted-test',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'authentication failure is distinguished from network unavailability',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException.badResponse(
              statusCode: 401,
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 401,
                data: {
                  'error': {'code': 'authentication_failed'},
                },
              ),
            ),
          ),
        ),
      );
      await expectLater(
        ExamApi(dio: dio).fetch(
          baseUrl: 'https://query.example',
          username: 'student',
          encryptedPassword: 'encrypted-test',
        ),
        throwsA(isA<ExamAuthenticationException>()),
      );
    },
  );
}
