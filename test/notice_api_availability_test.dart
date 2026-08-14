import 'package:cqut_helper/api/notice/notice_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('availability check calls notice service and parses notices', () async {
    final productionDio = NoticeApi.buildDioForTesting(
      'https://notice.example.com',
    );
    expect(productionDio.options.headers.containsKey('X-API-Key'), isFalse);

    RequestOptions? capturedRequest;
    final api = NoticeApi(
      dioFactory: (baseUrl) {
        final dio = Dio(BaseOptions(baseUrl: baseUrl));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              capturedRequest = options;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'success': true,
                    'data': {
                      'env': 'prod',
                      'year_term': '2026-2027-1',
                      'generated_at': '2026-08-14 12:00:00',
                      'term_schedule_notices_complete': true,
                      'term_schedule_notices': [
                        {
                          'notice_id': 'notice-1',
                          'status': '待阅',
                          'published_at': '2026-08-14 10:00:00',
                          'title': '调课提醒',
                          'content': '课程时间有调整',
                        },
                      ],
                    },
                  },
                ),
              );
            },
          ),
        );
        return dio;
      },
    );

    final result = await api.testAvailability(
      baseUrl: 'https://notice.example.com',
      username: 'student-id',
      encryptedPassword: 'encrypted-password',
      yearTerm: '2026-2027-1',
    );

    expect(result.success, isTrue);
    expect(result.noticeCount, 1);
    expect(result.message, contains('已获取当前学期调课信息（1 条）'));
    expect(capturedRequest?.method, 'POST');
    expect(capturedRequest?.path, '/api/jwxt/term-schedule-notices');
    expect(capturedRequest?.data, containsPair('username', 'student-id'));
    expect(capturedRequest?.data, containsPair('year_term', '2026-2027-1'));
  });

  test(
    'availability check fails locally when login credentials are missing',
    () async {
      var requestCount = 0;
      final api = NoticeApi(
        dioFactory: (baseUrl) {
          requestCount++;
          return Dio(BaseOptions(baseUrl: baseUrl));
        },
      );

      final result = await api.testAvailability(
        baseUrl: 'https://notice.example.com',
        username: '',
        encryptedPassword: '',
        yearTerm: '2026-2027-1',
      );

      expect(result.success, isFalse);
      expect(result.message, '登录凭据缺失，请重新登录后再检查');
      expect(requestCount, 0);
    },
  );

  test('availability check shows backend error message and status', () async {
    final api = NoticeApi(
      dioFactory: (baseUrl) {
        final dio = Dio(BaseOptions(baseUrl: baseUrl));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<Map<String, dynamic>>(
                    requestOptions: options,
                    statusCode: 502,
                    data: {
                      'success': false,
                      'error': {
                        'code': 'upstream_unavailable',
                        'message': '上游教务服务暂时不可用',
                      },
                    },
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );
        return dio;
      },
    );

    final result = await api.testAvailability(
      baseUrl: 'https://notice.example.com',
      username: 'student-id',
      encryptedPassword: 'encrypted-password',
      yearTerm: '2026-2027-1',
    );

    expect(result.success, isFalse);
    expect(result.message, '上游教务服务暂时不可用（HTTP 502）');
  });

  test('explicit complete empty notice list is a successful check', () async {
    final api = NoticeApi(
      dioFactory: (baseUrl) {
        final dio = Dio(BaseOptions(baseUrl: baseUrl));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'success': true,
                    'data': {
                      'env': 'prod',
                      'year_term': '2026-2027-1',
                      'generated_at': '2026-08-14 12:00:00',
                      'term_schedule_notices_complete': true,
                      'term_schedule_notices': <Object>[],
                    },
                  },
                ),
              );
            },
          ),
        );
        return dio;
      },
    );

    final result = await api.testAvailability(
      baseUrl: 'https://notice.example.com',
      username: 'student-id',
      encryptedPassword: 'encrypted-password',
      yearTerm: '2026-2027-1',
    );

    expect(result.success, isTrue);
    expect(result.noticeCount, 0);
    expect(result.message, contains('调课信息（0 条）'));
  });

  test('incomplete empty notice response is rejected', () async {
    final api = NoticeApi(
      dioFactory: (baseUrl) {
        final dio = Dio(BaseOptions(baseUrl: baseUrl));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'success': true,
                    'data': {
                      'env': 'prod',
                      'year_term': '2026-2027-1',
                      'generated_at': '2026-08-14 12:00:00',
                      'term_schedule_notices': <Object>[],
                    },
                  },
                ),
              );
            },
          ),
        );
        return dio;
      },
    );

    final result = await api.testAvailability(
      baseUrl: 'https://notice.example.com',
      username: 'student-id',
      encryptedPassword: 'encrypted-password',
      yearTerm: '2026-2027-1',
    );

    expect(result.success, isFalse);
    expect(result.message, '调课通知数据完整性未确认');
  });
}
