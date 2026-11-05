import 'dart:convert';
import 'dart:io';

import 'package:cqut_helper/api/course/course_api.dart';
import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/schedule_cache_database.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class _FakeCourseApi extends CourseApi {
  final Map<String, Map<String, dynamic>> responses;
  final List<String> requestedWeeks = [];

  _FakeCourseApi(this.responses);

  @override
  Future<Map<String, dynamic>> fetchWeekEvents({
    required String userId,
    String? weekNum,
    String? yearTerm,
    String? password,
    String? encryptedPassword,
  }) async {
    requestedWeeks.add(weekNum!);
    return responses[weekNum] ?? <String, dynamic>{'eventList': []};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cached widget projection updates', () {
    const userId = 'projection-student';
    const term = '2026-2027-1';
    const displayKey = 'schedule_${userId}_${term}_5';
    const projectionKey = 'schedule_widget_calendar_projection_v1_$userId';
    const preferencesChannel = MethodChannel(
      'plugins.flutter.io/shared_preferences',
    );
    const databaseChannel = MethodChannel('com.tekartik.sqflite');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Map<String, dynamic> schedule;
    late Map<String, Object> storedPreferences;
    late List<Map<String, Object?>> coursePreferences;
    final writes = <String>[];
    var broadcasts = 0;

    setUp(() {
      SharedPreferences.resetStatic();
      databaseFactoryOrNull = databaseFactorySqflitePlugin;
      schedule = {
        'yearTerm': term,
        'weekNum': '5',
        'weekDayList': [
          {'weekDay': '2', 'weekDate': '2026-09-29'},
        ],
        'eventList': [
          {
            'eventName': '课程',
            'weekDay': '2',
            'sessionStart': '1',
            'sessionLast': '2',
          },
        ],
      };
      coursePreferences = [];
      storedPreferences = {
        'flutter.account': userId,
        'flutter.schedule_widget_week_$userId': '5',
        'flutter.schedule_widget_term_$userId': term,
      };
      writes.clear();
      broadcasts = 0;
      WidgetUpdater.debugIsAndroidOverride = true;
      WidgetUpdater.debugMethodInvoker = (_, arguments) async {
        broadcasts++;
      };
      messenger.setMockMethodCallHandler(preferencesChannel, (call) async {
        final arguments = call.arguments as Map?;
        if (call.method == 'getAll') return storedPreferences;
        final key = arguments?['key'] as String?;
        if (key != null) {
          writes.add(key);
          if (call.method == 'remove') {
            storedPreferences.remove(key);
          } else {
            storedPreferences[key] = arguments!['value'] as Object;
          }
        }
        return true;
      });
      messenger.setMockMethodCallHandler(databaseChannel, (call) async {
        final arguments = call.arguments as Map?;
        final sql = arguments?['sql'] as String? ?? '';
        if (call.method == 'getDatabasesPath') return Directory.systemTemp.path;
        if (call.method == 'openDatabase') {
          return {
            'id': (arguments?['path'] as String).contains('customizations')
                ? 2
                : 1,
          };
        }
        if (call.method == 'query') {
          if (sql.contains('user_version')) {
            return [
              {'user_version': 2},
            ];
          }
          if (sql.contains('cache_meta')) {
            return [
              {'value': '1'},
            ];
          }
          if (sql.contains('course_preferences')) return coursePreferences;
          if (sql.contains('schedule_weeks')) {
            final values = arguments?['arguments'] as List? ?? [];
            if (values.length == 3 && values.last != '5') {
              return [];
            }
            final raw = jsonEncode(schedule);
            return [
              {
                'user_id': userId,
                'year_term': term,
                'week_num': '5',
                'raw_json': raw,
                'checksum': ScheduleCacheDatabase.checksumFor(raw),
                'data_version': 1,
                'fetched_at': 1,
                'last_verified_at': DateTime.now().millisecondsSinceEpoch,
              },
            ];
          }
          return [];
        }
        if (call.method == 'execute' && sql.startsWith('BEGIN')) {
          return {'transactionId': 1};
        }
        if (call.method == 'insert') return 1;
        return null;
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(preferencesChannel, null);
      messenger.setMockMethodCallHandler(databaseChannel, null);
      WidgetUpdater.resetDebugOverrides();
      SharedPreferences.resetStatic();
    });

    Future<void> readCache(ScheduleApi api) async {
      expect(
        await api.loadFromCache(userId: userId, yearTerm: term, weekNum: '5'),
        isNotNull,
      );
    }

    test(
      'unchanged cache reads skip projection writes and broadcasts',
      () async {
        final api = ScheduleApi();
        await readCache(api);
        expect(broadcasts, 1);
        final prefs = await SharedPreferences.getInstance();
        final originalProjection = prefs.getString(projectionKey);
        writes.clear();

        await readCache(api);

        expect(writes, isEmpty);
        expect(broadcasts, 1);
        expect(prefs.getString(projectionKey), originalProjection);
      },
    );

    test('custom course colors and sessions remain part of content', () async {
      final api = ScheduleApi();
      await readCache(api);
      writes.clear();
      coursePreferences = [
        {
          'user_id': userId,
          'year_term': term,
          'course_key': 'course:课程|',
          'display_name': '自定义课程',
          'color_index': 3,
          'updated_at': 1,
        },
      ];
      (schedule['eventList'] as List).single['sessionStart'] = '3';

      await readCache(api);

      expect(
        writes,
        containsAll(['flutter.$displayKey', 'flutter.$projectionKey']),
      );
      expect(broadcasts, 2);
      final prefs = await SharedPreferences.getInstance();
      final projection = jsonDecode(prefs.getString(projectionKey)!) as Map;
      final event =
          ((projection['days'] as List).single['events'] as List).single;
      expect(event['eventName'], '自定义课程');
      expect(event['colorIndex'], 3);
      expect(event['sessionStart'], '3');
    });

    test('calendar changes refresh an otherwise identical week', () async {
      final api = ScheduleApi();
      await readCache(api);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'academic_calendar_snapshot_v1_$term',
        jsonEncode({
          'schema_version': 1,
          'year_term': term,
          'revision': 'holiday',
          'generated_at': '2026-09-19T10:00:00Z',
          'term_calendar_complete': true,
          'days': [
            {'date': '2026-09-29', 'kind': 'holiday', 'label': '假期'},
          ],
        }),
      );
      writes.clear();

      await readCache(api);

      expect(writes, ['flutter.$projectionKey']);
      expect(broadcasts, 2);
    });

    test(
      'successful identical network sync still publishes freshness',
      () async {
        final api = ScheduleApi(courseApi: _FakeCourseApi({'5': schedule}));
        await readCache(api);
        writes.clear();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'schedule_widget_refresh_state_$userId',
          'loading',
        );

        await api.loadFromNetwork(
          userId: userId,
          encryptedPassword: 'secret',
          yearTerm: term,
          weekNum: '5',
          persistLastViewed: false,
        );

        expect(writes, isNot(contains('flutter.$displayKey')));
        expect(writes, isNot(contains('flutter.$projectionKey')));
        expect(broadcasts, 2);
        expect(
          prefs.getString('schedule_widget_refresh_state_$userId'),
          'idle',
        );
        expect(
          prefs.getString('schedule_last_successful_refresh_at_$userId'),
          isNotNull,
        );
        expect(
          prefs.getInt(ScheduleApi.lastFetchAtKey(userId, term, '5')),
          greaterThan(1),
        );
      },
    );
  });

  group('ScheduleApi.isWidgetProjectionVisible', () {
    test('pinned week and both adjacent weeks can affect widget content', () {
      for (final week in const ['5', '6', '7']) {
        expect(
          ScheduleApi.isWidgetProjectionVisible(
            yearTerm: '2026-2027-1',
            weekNum: week,
            pinnedYearTerm: '2026-2027-1',
            pinnedWeekNum: '6',
          ),
          isTrue,
          reason: 'week $week belongs to the visible projection window',
        );
      }
    });

    test('a distant week or another term cannot affect widget content', () {
      expect(
        ScheduleApi.isWidgetProjectionVisible(
          yearTerm: '2026-2027-1',
          weekNum: '8',
          pinnedYearTerm: '2026-2027-1',
          pinnedWeekNum: '6',
        ),
        isFalse,
      );
      expect(
        ScheduleApi.isWidgetProjectionVisible(
          yearTerm: '2026-2027-2',
          weekNum: '6',
          pinnedYearTerm: '2026-2027-1',
          pinnedWeekNum: '6',
        ),
        isFalse,
      );
    });
  });

  test('fetchCustomEvents keeps only unique server custom events', () async {
    final courseApi = _FakeCourseApi({
      '1': {
        'eventList': [
          {
            'eventType': '3',
            'eventID': 'custom-1',
            'eventName': 'Custom course',
            'weekDay': '2',
            'sessionStart': '3',
          },
          {'eventType': '1', 'eventID': '', 'eventName': 'School course'},
        ],
      },
      '2': {
        'eventList': [
          {
            'eventType': '3',
            'eventID': 'custom-1',
            'eventName': 'Custom course',
            'weekDay': '2',
            'sessionStart': '3',
          },
          {
            'eventType': '3',
            'eventID': 'custom-2',
            'eventName': 'Another custom course',
            'weekDay': '1',
            'sessionStart': '1',
          },
        ],
      },
    });
    final progress = <int>[];

    final events = await ScheduleApi(courseApi: courseApi).fetchCustomEvents(
      userId: '20260001',
      encryptedPassword: 'secret',
      yearTerm: '2026-2027-1',
      weeks: const [2, 1, 2],
      onProgress: (completed, total) => progress.add(completed),
    );

    expect(courseApi.requestedWeeks, ['1', '2']);
    expect(events.map((event) => event.eventID), ['custom-2', 'custom-1']);
    expect(progress, [1, 2]);
  });
}
