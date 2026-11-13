import 'dart:async';
import 'dart:io';

import 'package:cqut_helper/api/notice/notice_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> success() => {
  'success': true,
  'data': {
    'year_term': '2026-2027-1',
    'term_schedule_notices_complete': true,
    'term_schedule_notices': [],
  },
};
Future<Object?> query(NoticeApi api) async {
  try {
    return await api.fetchTermScheduleNotices(
      username: 'u',
      encryptedPassword: 'p',
      yearTerm: '2026-2027-1',
    );
  } catch (e) {
    return e;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final type in [
    DioExceptionType.receiveTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.connectionError,
    DioExceptionType.unknown,
    DioExceptionType.badResponse,
  ]) {
    test('$type after request is not retried', () async {
      var requests = 0;
      final api = NoticeApi(
        accessEnabled: () async => true,
        dioFactory: (url) {
          final dio = NoticeApi.buildDioForTesting(url);
          dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                requests++;
                h.reject(
                  DioException(
                    requestOptions: o,
                    type: type,
                    error: const SocketException(
                      'connection reset during response',
                    ),
                    response: type == DioExceptionType.badResponse
                        ? Response(requestOptions: o, statusCode: 503)
                        : null,
                  ),
                );
              },
            ),
          );
          return dio;
        },
      );
      expect(await query(api), isA<DioException>());
      expect(requests, 1);
    });
  }
  for (final payload in [
    <String, dynamic>{
      'success': false,
      'error': {'message': 'busy'},
    },
    <String, dynamic>{'success': true, 'data': {}},
    'invalid',
  ]) {
    test('business and malformed payload $payload are not retried', () async {
      var requests = 0;
      final api = NoticeApi(
        accessEnabled: () async => true,
        dioFactory: (url) {
          final dio = NoticeApi.buildDioForTesting(url);
          dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                requests++;
                h.resolve(
                  Response(requestOptions: o, statusCode: 200, data: payload),
                );
              },
            ),
          );
          return dio;
        },
      );
      expect(await query(api), isA<NoticeApiResponseException>());
      expect(requests, 1);
    });
  }
  test('connection establishment timeout retries at most once on same selected service', () async {
    final urls = <String>[];
    final api = NoticeApi(
      accessEnabled: () async => true,
      dioFactory: (url) {
        urls.add(url);
        final dio = NoticeApi.buildDioForTesting(url);
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) => h.reject(
              DioException.connectionTimeout(
                requestOptions: o,
                timeout: const Duration(seconds: 10),
              ),
            ),
          ),
        );
        return dio;
      },
    );
    expect(await query(api), isA<DioException>());
    expect(urls.length, 2);
    expect(urls.toSet().length, 1);
  });
  testWidgets(
    '40 second upstream response fits receive budget without duplicate queries',
    (tester) async {
      var requests = 0;
      var completed = false;
      final api = NoticeApi(
        accessEnabled: () async => true,
        dioFactory: (url) {
          final dio = NoticeApi.buildDioForTesting(url);
          dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                requests++;
                expectSync(o.receiveTimeout, const Duration(seconds: 100));
                Timer(
                  const Duration(seconds: 40),
                  () => h.resolve(
                    Response(
                      requestOptions: o,
                      statusCode: 200,
                      data: success(),
                    ),
                  ),
                );
              },
            ),
          );
          return dio;
        },
      );
      final result = query(api).then((v) {
        completed = true;
        return v;
      });
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 31));
      expect(completed, isFalse);
      expect(requests, 1);
      await tester.pump(const Duration(seconds: 9));
      expect(await result, isNot(isA<Exception>()));
      expect(requests, 1);
    },
  );
}
