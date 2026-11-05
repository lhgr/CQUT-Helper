import 'dart:async';
import 'dart:io';

import 'package:cqut_helper/api/calendar/calendar_api.dart';
import 'package:cqut_helper/manager/academic_calendar_manager.dart';
import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/diagnostics_storage.dart';

const _testTerm = '2026-2027-1';

void main() {
  test(
    'successful calendar sync persists an explicit network outcome',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final temporary = await Directory.systemTemp.createTemp(
        'cqut-calendar-diagnostics-',
      );
      final storage = FileDiagnosticStorage(
        Directory('${temporary.path}/records'),
        'foreground',
      );
      final logger = AppLogger.I;
      await logger.init(
        enableConsole: false,
        storage: storage,
        exportDirectory: Directory('${temporary.path}/exports'),
      );
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) => handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: _wireSnapshot(),
              ),
            ),
          ),
        );
      final manager = AcademicCalendarManager(api: CalendarApi(dio: dio));
      try {
        final result = await manager.refresh(
          _testTerm,
          trigger: 'test_manual_calendar',
        );
        expect(result.updated, isTrue);
        await logger.flush();
        final rows = await storage.snapshot();
        final outcome = rows.singleWhere(
          (row) =>
              row['kind'] == 'operation_outcome' &&
              row['stage'] == 'calendar_refresh',
        );
        expect(outcome['outcome'], 'succeeded');
        expect(outcome['causeEventId'], isNull);
        final fields = outcome['fields'] as Map;
        expect(fields['trigger'], 'test_manual_calendar');
        expect(fields['data_source'], 'network');
        expect(fields['network_outcome'], 'succeeded');
        expect(fields['network_attempted'], isTrue);
        expect(fields['cache_used'], isFalse);
        expect(fields['cache_available'], isFalse);
        expect(
          (fields['stage_durations_ms'] as Map).keys,
          containsAll([
            'load_cache',
            'fetch_calendar',
            'validate_calendar',
            'persist_calendar',
          ]),
        );
      } finally {
        manager.dispose();
        await logger.dispose();
        await temporary.delete(recursive: true);
      }
    },
  );
  test('API sends ETag and accepts 304', () async {
    RequestOptions? request;
    var count = 0;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          count++;
          if (count == 1) {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                headers: Headers.fromMap({
                  'etag': ['r1'],
                }),
                data: _wireSnapshot(),
              ),
            );
          } else {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 304,
                headers: Headers.fromMap({
                  'etag': ['r1'],
                }),
              ),
            );
          }
        },
      ),
    );
    final api = CalendarApi(dio: dio, baseUrl: 'https://calendar.test');
    final first = await api.fetch(yearTerm: _testTerm);
    final second = await api.fetch(yearTerm: _testTerm, etag: first.etag);
    expect(first.snapshot?.revision, 'r1');
    expect(second.notModified, isTrue);
    expect(request?.headers['If-None-Match'], 'r1');
  });

  test(
    'manager records a successful check when the server returns 304',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        'academic_calendar_snapshot_v1_$_testTerm': AcademicCalendarSnapshot(
          schemaVersion: 1,
          yearTerm: _testTerm,
          revision: 'r1',
          generatedAt: DateTime(2026, 9, 19),
          complete: true,
          days: const [],
        ).encode(),
        'academic_calendar_etag_v1_$_testTerm': 'r1',
      });
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 304,
                headers: Headers.fromMap({
                  'etag': ['r1'],
                }),
              ),
            );
          },
        ),
      );
      final manager = AcademicCalendarManager(
        api: CalendarApi(dio: dio, baseUrl: 'https://calendar.test'),
      );
      final result = await manager.refresh(_testTerm);
      expect(result.notModified, isTrue);
      expect(result.source, 'network');
      expect(result.networkOutcome, 'succeeded');
      expect(result.reason, 'http_304');
      expect(result.cacheUsed, isTrue);
      expect(manager.stateFor(_testTerm).lastSuccessfulAt, isNotNull);
      manager.dispose();
    },
  );

  test('304 without a local complete snapshot is a failed refresh', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'academic_calendar_etag_v1_$_testTerm': 'r1',
    });
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response<dynamic>(requestOptions: options, statusCode: 304),
        ),
      ),
    );
    final manager = AcademicCalendarManager(
      api: CalendarApi(dio: dio, baseUrl: 'https://calendar.test'),
    );
    final result = await manager.refresh(_testTerm);
    expect(result.error, isA<FormatException>());
    expect(result.networkOutcome, 'failed');
    expect(result.failedStage, 'validate_calendar');
    expect(manager.stateFor(_testTerm).hasError, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('academic_calendar_checked_at_v1_$_testTerm'), isNull);
    manager.dispose();
  });

  test(
    'fresh calendar cache is a skipped network check without HTTP 304',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final checkedAt = DateTime.now().millisecondsSinceEpoch;
      final successAt = checkedAt - const Duration(hours: 2).inMilliseconds;
      SharedPreferences.setMockInitialValues({
        'academic_calendar_snapshot_v1_$_testTerm': AcademicCalendarSnapshot(
          schemaVersion: 1,
          yearTerm: _testTerm,
          revision: 'r1',
          generatedAt: DateTime(2026, 9, 19),
          complete: true,
          days: const [],
        ).encode(),
        'academic_calendar_checked_at_v1_$_testTerm': checkedAt,
        'academic_calendar_success_at_v1_$_testTerm': successAt,
      });
      var requests = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests++;
              handler.reject(DioException(requestOptions: options));
            },
          ),
        );
      final manager = AcademicCalendarManager(api: CalendarApi(dio: dio));
      final result = await manager.refreshIfDue(
        _testTerm,
        trigger: 'test_cached_check',
      );
      expect(requests, 0);
      expect(result.source, 'cache');
      expect(result.reason, 'fresh_cache');
      expect(result.networkAttempted, isFalse);
      expect(result.networkOutcome, 'not_attempted');
      expect(result.notModified, isFalse);
      expect(result.snapshot?.revision, 'r1');
      expect(
        result.cacheAgeMs,
        greaterThanOrEqualTo(const Duration(hours: 2).inMilliseconds),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('academic_calendar_success_at_v1_$_testTerm'),
        successAt,
      );
      manager.dispose();
    },
  );

  test('incomplete cached snapshot cannot validate HTTP 304', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'academic_calendar_snapshot_v1_$_testTerm': AcademicCalendarSnapshot(
        schemaVersion: 1,
        yearTerm: _testTerm,
        revision: 'r1',
        generatedAt: DateTime(2026, 9, 19),
        complete: false,
        days: const [],
      ).encode(),
      'academic_calendar_etag_v1_$_testTerm': 'r1',
    });
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<dynamic>(requestOptions: options, statusCode: 304),
            );
          },
        ),
      );
    final manager = AcademicCalendarManager(api: CalendarApi(dio: dio));
    final result = await manager.refresh(_testTerm);
    expect(request?.headers['If-None-Match'], isNull);
    expect(result.error, isA<FormatException>());
    expect(result.cacheUsed, isFalse);
    expect(result.snapshot, isNull);
    manager.dispose();
  });

  test('missing term fails before requesting the calendar', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final manager = AcademicCalendarManager();
    final result = await manager.refreshIfDue(' ');
    expect(result.error, isA<FormatException>());
    expect(result.reason, 'missing_term');
    expect(result.failedStage, 'validate_term');
    expect(result.networkAttempted, isFalse);
    manager.dispose();
  });

  test('API rejects a non-success response body', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: {'success': false, 'data': _wireSnapshot()['data']},
          ),
        ),
      ),
    );
    final api = CalendarApi(dio: dio, baseUrl: 'https://calendar.test');
    await expectLater(api.fetch(yearTerm: _testTerm), throwsFormatException);
  });

  test(
    'manager keeps old snapshot on failure and deduplicates concurrent refresh',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      var requestCount = 0;
      final gate = Completer<void>();
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requestCount++;
            await gate.future;
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: _wireSnapshot(),
              ),
            );
          },
        ),
      );
      final manager = AcademicCalendarManager(
        api: CalendarApi(dio: dio, baseUrl: 'https://calendar.test'),
      );
      final first = manager.refresh(_testTerm);
      final second = manager.refresh(_testTerm);
      expect(identical(first, second), isTrue);
      gate.complete();
      final result = await first;
      expect(result.updated, isTrue);
      expect(requestCount, 1);
      expect((await manager.loadCached(_testTerm))?.revision, 'r1');
      manager.dispose();

      final failingDio = Dio();
      failingDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(requestOptions: options, message: 'offline'),
            );
          },
        ),
      );
      final failing = AcademicCalendarManager(
        api: CalendarApi(dio: failingDio, baseUrl: 'https://calendar.test'),
      );
      final failed = await failing.refresh(_testTerm);
      expect(failed.error, isNotNull);
      expect(failed.source, 'cache');
      expect(failed.networkOutcome, 'failed');
      expect(failed.cacheUsed, isTrue);
      expect((await failing.loadCached(_testTerm))?.revision, 'r1');
      failing.dispose();
    },
  );

  test(
    'regular reminder reschedule can read the active term calendar cache',
    () async {
      SharedPreferences.setMockInitialValues({
        'academic_calendar_snapshot_v1_$_testTerm': AcademicCalendarSnapshot(
          schemaVersion: 1,
          yearTerm: _testTerm,
          revision: 'r1',
          generatedAt: DateTime(2026, 9, 19),
          complete: true,
          days: [
            AcademicCalendarDay(
              date: DateTime(2026, 9, 26),
              kind: AcademicCalendarDayKind.teachingDay,
              scheduleDate: DateTime(2026, 9, 29),
              label: '调休补课',
            ),
          ],
        ).encode(),
      });
      final prefs = await SharedPreferences.getInstance();
      final cached = CourseReminderScheduler.loadCachedCalendarForTerm(
        prefs: prefs,
        yearTerm: _testTerm,
      );
      expect(cached?.dayAt(DateTime(2026, 9, 26))?.isTeachingDay, isTrue);
    },
  );
}

Map<String, dynamic> _wireSnapshot() => {
  'success': true,
  'data': {
    'schema_version': 1,
    'year_term': _testTerm,
    'revision': 'r1',
    'generated_at': '2026-09-19T10:00:00+08:00',
    'term_calendar_complete': true,
    'days': [
      {'date': '2026-09-25', 'kind': 'holiday', 'label': '中秋节'},
    ],
  },
};
