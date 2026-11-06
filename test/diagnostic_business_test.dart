import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cqut_helper/api/auth/auth_api.dart';
import 'package:cqut_helper/api/calendar/calendar_api.dart';
import 'package:cqut_helper/api/core/api_client.dart';
import 'package:cqut_helper/api/course/course_api.dart';
import 'package:cqut_helper/api/notice/notice_api.dart';
import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/schedule_cache_database.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/diagnostics_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.respond);
  final Object Function(RequestOptions) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = respond(options);
    if (response is DioException) throw response;
    if (response is ResponseBody) return response;
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MalformedCourseApi extends CourseApi {
  @override
  Future<Map<String, dynamic>> fetchWeekEvents({
    required String userId,
    String? weekNum,
    String? yearTerm,
    String? password,
    String? encryptedPassword,
  }) async => {'eventList': 'unexpected-string'};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late FileDiagnosticStorage storage;
  late HttpClientAdapter originalAdapter;
  final logger = AppLogger.I;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp(
      'cqut-business-diagnostics-',
    );
    storage = FileDiagnosticStorage(
      Directory('${temporary.path}/records'),
      'foreground',
    );
    await logger.init(
      enableConsole: false,
      storage: storage,
      exportDirectory: Directory('${temporary.path}/exports'),
    );
    originalAdapter = ApiClient().dio.httpClientAdapter;
    await AuthApi().resetLoginContext();
  });

  tearDown(() async {
    ApiClient().dio.httpClientAdapter = originalAdapter;
    await logger.dispose();
    await temporary.delete(recursive: true);
  });

  Future<List<Map<String, Object?>>> records() async {
    await logger.flush();
    return storage.snapshot();
  }

  for (final recovers in [false, true]) {
    test(
      'notice payload retry keeps one root and validated recovery=$recovers',
      () async {
        var calls = 0;
        final api = NoticeApi(
          accessEnabled: () async => true,
          dioFactory: (baseUrl) =>
              Dio(BaseOptions(baseUrl: baseUrl))
                ..httpClientAdapter = _ResponseAdapter((_) {
                  calls++;
                  return {
                    'success': true,
                    'data': {
                      'year_term': '2026-2027-1',
                      'term_schedule_notices_complete': recovers && calls == 2,
                      'term_schedule_notices': <Object?>[],
                    },
                  };
                }),
        );
        final future = api.fetchTermScheduleNotices(
          username: 'private-account',
          encryptedPassword: 'private-password',
          yearTerm: '2026-2027-1',
        );
        if (recovers) {
          expect((await future).notices, isEmpty);
        } else {
          await expectLater(future, throwsA(isA<NoticeApiResponseException>()));
        }
        final rows = await records();
        final root = rows.singleWhere((row) => row['kind'] == 'incident');
        expect(root['attempts'], recovers ? 1 : 2);
        expect(root['errorCategory'], 'DATA_PARSE_FAILED');
        expect((root['fields'] as Map)['validation_failed'], isTrue);
        expect(
          rows.where((row) => row['kind'] == 'recovery'),
          hasLength(recovers ? 1 : 0),
        );
        final successes = rows
            .where(
              (row) => (row['fields'] as Map?)?['network_validated'] == true,
            )
            .toList();
        expect(successes, hasLength(recovers ? 1 : 0));
        if (recovers) {
          expect(successes.single['stage'], 'service_response');
          expect((successes.single['fields'] as Map)['service'], 'NoticeApi');
        }
      },
    );
  }

  test(
    'calendar 304 requires explicit cache validation for success evidence',
    () async {
      final dio = Dio()
        ..httpClientAdapter = _ResponseAdapter(
          (_) => ResponseBody.fromString('', 304),
        );
      final api = CalendarApi(
        dio: dio,
        baseUrl: 'https://custom.example.test:8443',
      );
      final response = await api.fetch(yearTerm: '2026-2027-1');
      expect(await records(), isEmpty);
      api.recordValidatedNotModified(response);
      final rows = await records();
      final success = rows.single;
      expect(success['kind'], 'operation_outcome');
      expect(success['operationId'], response.operationId);
      final fields = success['fields'] as Map;
      expect(fields['origin'], 'https://custom.example.test:8443');
      expect(fields['route'], '/api/calendar/term-overrides');
      expect(fields['network_validated'], isTrue);
      expect(fields['status_code'], 304);
    },
  );

  test('calendar rejects a different term without success evidence', () async {
    final api = CalendarApi(
      dio: Dio()
        ..httpClientAdapter = _ResponseAdapter(
          (_) => {
            'success': true,
            'data': {
              'schema_version': 1,
              'year_term': '2025-2026-2',
              'revision': 'test-revision',
              'generated_at': '2026-11-05T00:00:00Z',
              'term_calendar_complete': true,
              'days': <Object?>[],
            },
          },
        ),
    );
    await expectLater(
      api.fetch(yearTerm: '2026-2027-1'),
      throwsFormatException,
    );
    final rows = await records();
    expect(rows.where((row) => row['kind'] == 'incident'), hasLength(1));
    expect(
      rows.where(
        (row) => (row['fields'] as Map?)?['network_validated'] == true,
      ),
      isEmpty,
    );
  });

  test(
    'HTTP 200 login rejection records the business cause and stack',
    () async {
      ApiClient().dio.httpClientAdapter = _ResponseAdapter(
        (_) => {'code': 400, 'msg': '账号或密码错误'},
      );
      await expectLater(
        AuthApi().loginWithEncrypted(
          account: 'private-account',
          encryptedPassword: 'private-credential',
        ),
        throwsException,
      );

      final rows = await records();
      final root = rows.singleWhere((row) => row['kind'] == 'incident');
      expect(root['stage'], 'login');
      expect(root['reason'], contains('账号或密码错误'));
      expect(root['stackTrace'], isNotEmpty);
      expect(root['operationId'], isNotEmpty);
      expect(jsonEncode(rows), isNot(contains('private-credential')));
      expect(jsonEncode(rows), isNot(contains('private-account')));
    },
  );

  test('schedule decode failure keeps one root and its load outcome', () async {
    final api = ScheduleApi(courseApi: _MalformedCourseApi());
    await expectLater(
      api.loadFromNetwork(
        userId: 'private-account',
        encryptedPassword: 'private-credential',
      ),
      throwsA(isA<TypeError>()),
    );

    final rows = await records();
    final root = rows.singleWhere((row) => row['kind'] == 'incident');
    final outcome = rows.singleWhere((row) => row['kind'] == 'derived');
    expect(root['stage'], 'response_decode');
    expect(root['stackTrace'], contains('ScheduleData.fromJson'));
    expect(outcome['stage'], 'load_schedule');
    expect(outcome['rootEventId'], root['eventId']);
    expect(outcome['causeEventId'], root['eventId']);
    expect(outcome['operationId'], root['operationId']);
    expect(outcome['reason'], isNull);
    expect(outcome['errorCategory'], isNull);
    expect(outcome['stackTrace'], anyOf(isNull, isEmpty));
  });

  test(
    'malformed cache write records validation without storing raw data',
    () async {
      await expectLater(
        ScheduleCacheDatabase.instance.upsert(
          userId: 'private-account',
          yearTerm: '2026-2027-1',
          weekNum: '3',
          rawJson: jsonEncode({'eventList': 'private-course-payload'}),
        ),
        throwsFormatException,
      );

      final rows = await records();
      final root = rows.singleWhere((row) => row['kind'] == 'incident');
      expect(root['stage'], 'cache_write');
      expect(root['errorType'], 'FormatException');
      expect(root['stackTrace'], contains('canonicalizeAndValidate'));
      expect(jsonEncode(rows), isNot(contains('private-course-payload')));
    },
  );

  test(
    'mapped network timeout retains only the compact Dio summary',
    () async {
      ApiClient().dio.httpClientAdapter = _ResponseAdapter((options) {
        if (options.path.endsWith('listWeekEvents')) {
          return DioException(
            requestOptions: options,
            type: DioExceptionType.receiveTimeout,
            error: 'simulated receive timeout',
          );
        }
        return {'code': 200, 'msg': '登录成功！'};
      });
      await expectLater(
        CourseApi().fetchWeekEvents(
          userId: 'private-account',
          encryptedPassword: 'private-credential',
        ),
        throwsA(isA<CourseApiException>()),
      );

      final rows = await records();
      final root = rows.singleWhere((row) => row['kind'] == 'incident');
      expect(root['errorType'], 'DioException');
      expect(root['stackTrace'], isEmpty);
      expect(rows.where((row) => row['kind'] == 'derived'), isEmpty);
      expect(jsonEncode(rows), isNot(contains('private-credential')));
    },
  );

  NoticeApi closedNoticeApi() => NoticeApi(
    accessEnabled: () async => true,
    dioFactory: (baseUrl) =>
        NoticeApi.buildDioForTesting(baseUrl)
          ..httpClientAdapter = _ResponseAdapter((options) {
            expect(options.extra['diagnostic_expected_statuses'], [403]);
            return ResponseBody.fromString('closed for the night', 403);
          }),
  );

  test(
    'known notice service closure does not create an error record',
    () async {
      await expectLater(
        closedNoticeApi().fetchTermScheduleNotices(
          username: 'private-account',
          encryptedPassword: 'private-credential',
          yearTerm: '2026-2027-1',
        ),
        throwsA(isA<NoticeApiForbiddenException>()),
      );
      expect(await records(), isEmpty);
    },
  );

  test('availability check keeps a known closure out of diagnostics', () async {
    final result = await closedNoticeApi().testAvailability(
      baseUrl: 'https://notice.example.test',
      username: 'private-account',
      encryptedPassword: 'private-credential',
      yearTerm: '2026-2027-1',
    );
    expect(result.success, isFalse);
    expect(await records(), isEmpty);
  });

  test('unmarked HTTP 403 still records the network failure', () async {
    ApiClient().dio.httpClientAdapter = _ResponseAdapter(
      (_) => ResponseBody.fromString('forbidden', 403),
    );
    await expectLater(
      ApiClient().dio.get('https://school.example.test/private'),
      throwsA(isA<DioException>()),
    );
    final rows = await records();
    final root = rows.singleWhere((row) => row['kind'] == 'incident');
    final attempt = rows.singleWhere((row) => row['kind'] == 'attempt');
    expect((root['fields'] as Map)['status_code'], 403);
    expect((attempt['fields'] as Map)['status_code'], 403);
    expect(attempt['rootEventId'], root['eventId']);
    expect(attempt['operationId'], root['operationId']);
  });
}
