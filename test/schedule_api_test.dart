import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cqut_helper/api/course/course_api.dart';
import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/schedule_cache_database.dart';
import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/manager/widget_calendar_projection_store.dart';
import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/model/course_preference_model.dart';
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
    late Map<String, Map<String, dynamic>> cachedSchedules;
    late Map<String, Object> storedPreferences;
    late List<Map<String, Object?>> coursePreferences;
    final writes = <String>[];
    var broadcasts = 0;
    final snapshots = <Map<String, dynamic>>[];

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
      cachedSchedules = {'5': schedule};
      coursePreferences = [];
      storedPreferences = {
        'flutter.account': userId,
        'flutter.schedule_widget_week_$userId': '5',
        'flutter.schedule_widget_term_$userId': term,
      };
      writes.clear();
      broadcasts = 0;
      snapshots.clear();
      WidgetUpdater.debugIsAndroidOverride = true;
      WidgetUpdater.debugMethodInvoker = (_, arguments) async {
        broadcasts++;
        final raw = arguments['snapshotJson'];
        if (raw is String) {
          snapshots.add(jsonDecode(raw) as Map<String, dynamic>);
        }
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
            return [
              for (final entry in cachedSchedules.entries)
                if (values.length != 3 || values.last == entry.key)
                  (() {
                    final raw = jsonEncode(entry.value);
                    return <String, Object?>{
                      'user_id': userId,
                      'year_term': term,
                      'week_num': entry.key,
                      'raw_json': raw,
                      'checksum': ScheduleCacheDatabase.checksumFor(raw),
                      'data_version': 1,
                      'fetched_at': 1,
                      'last_verified_at': DateTime.now().millisecondsSinceEpoch,
                    };
                  })(),
            ];
          }
          return [];
        }
        if (call.method == 'execute' && sql.startsWith('BEGIN')) {
          return {'transactionId': 1};
        }
        if (call.method == 'insert') {
          final columns = RegExp(r'\(([^)]+)\)')
              .firstMatch(sql)!
              .group(1)!
              .split(',')
              .map((column) => column.trim().replaceAll('"', ''))
              .toList();
          final values = arguments!['arguments'] as List;
          final literals = RegExp(
            r'VALUES\s*\(([^)]+)\)',
            caseSensitive: false,
          ).firstMatch(sql)!.group(1)!.split(',');
          var argumentIndex = 0;
          final row = <String, Object?>{
            for (var i = 0; i < columns.length; i++)
              columns[i]: literals[i].trim() == '?'
                  ? values[argumentIndex++]
                  : null,
          };
          if (sql.contains('course_preferences')) coursePreferences = [row];
          if (sql.contains('schedule_weeks')) {
            cachedSchedules[row['week_num']! as String] =
                jsonDecode(row['raw_json']! as String) as Map<String, dynamic>;
          }
          return 1;
        }
        if (call.method == 'update' &&
            sql.contains('DELETE FROM course_preferences')) {
          coursePreferences.clear();
          return 1;
        }
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

    void captureIOSPayloads() {
      WidgetUpdater.debugIsAndroidOverride = false;
      WidgetUpdater.debugIsIOSOverride = true;
    }

    Map<String, dynamic> projectedDay(Map snapshot, String date) =>
        (snapshot['calendarProjection']['days'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((day) => day['date'] == date);

    Future<AcademicCalendarSnapshot> saveRemoteMakeupCalendar() async {
      final calendar = AcademicCalendarSnapshot.fromJson({
        'schema_version': 1,
        'year_term': term,
        'revision': 'remote-makeup',
        'generated_at': '2026-09-19T10:00:00Z',
        'term_calendar_complete': true,
        'days': [
          {
            'date': '2026-09-29',
            'kind': 'teaching_day',
            'schedule_date': '2026-10-20',
            'label': '调休补课',
          },
        ],
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'academic_calendar_snapshot_v1_$term',
        calendar.encode(),
      );
      return calendar;
    }

    Map<String, dynamic> remoteWeek(String courseName) => {
      'yearTerm': term,
      'weekNum': '8',
      'weekDayList': [
        {'weekDay': '2', 'weekDate': '2026-10-20'},
      ],
      'eventList': [
        {
          'eventName': courseName,
          'weekDay': '2',
          'sessionStart': '1',
          'sessionLast': '2',
        },
      ],
    };

    test('preference mutations publish the customized projection without a page listener', () async {
      captureIOSPayloads();
      final api = ScheduleApi();
      await readCache(api);
      final preference = CoursePreference(
        userId: userId,
        yearTerm: term,
        courseKey: 'course:课程|',
        displayName: '更名课程',
        teacher: null,
        location: '新教室',
        note: '',
        hidden: false,
        reminderMinutes: null,
        colorIndex: 4,
        updatedAt: DateTime(2026, 9, 29),
      );
      await ScheduleCustomizationManager.instance.saveCoursePreference(
        preference,
      );
      var events = projectedDay(snapshots.last, '2026-09-29')['events'] as List;
      expect(events.single['eventName'], '更名课程');
      expect(events.single['colorIndex'], 4);
      expect(events.single['address'], '新教室');

      await ScheduleCustomizationManager.instance.saveCoursePreference(
        preference.copyWith(hidden: true),
      );
      expect(projectedDay(snapshots.last, '2026-09-29')['events'], isEmpty);

      await ScheduleCustomizationManager.instance.deleteCoursePreference(
        preference,
      );
      events = projectedDay(snapshots.last, '2026-09-29')['events'] as List;
      expect(events.single['eventName'], '课程');
    });

    test('ordinary cache and network refresh retain a cached distant makeup source', () async {
      captureIOSPayloads();
      cachedSchedules['8'] = remoteWeek('远周课程');
      final calendar = await saveRemoteMakeupCalendar();
      final api = ScheduleApi(courseApi: _FakeCourseApi({'5': schedule}));
      await api.rebuildWidgetCalendarProjection(calendar: calendar);
      await readCache(api);
      expect(
        projectedDay(
          snapshots.last,
          '2026-09-29',
        )['events'].single['eventName'],
        '远周课程',
      );

      await api.loadFromNetwork(
        userId: userId,
        encryptedPassword: 'secret',
        yearTerm: term,
        weekNum: '5',
        persistLastViewed: false,
      );
      expect(
        projectedDay(
          snapshots.last,
          '2026-09-29',
        )['events'].single['eventName'],
        '远周课程',
      );
    });

    test('loading a distant source week fills and publishes an existing missing source', () async {
      captureIOSPayloads();
      await saveRemoteMakeupCalendar();
      final api = ScheduleApi(
        courseApi: _FakeCourseApi({'8': remoteWeek('刚加载课程')}),
      );
      await readCache(api);
      expect(
        projectedDay(snapshots.last, '2026-09-29')['kind'],
        'missing_source',
      );
      await api.loadFromNetwork(
        userId: userId,
        encryptedPassword: 'secret',
        yearTerm: term,
        weekNum: '8',
        persistLastViewed: false,
      );
      final day = projectedDay(snapshots.last, '2026-09-29');
      expect(day['kind'], 'teaching_day');
      expect(day['events'].single['eventName'], '刚加载课程');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('schedule_${userId}_${term}_8'), isNull);
    });

    test(
      'queued projection rebuilds finish with the latest raw course data',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final started = Completer<void>();
        final release = Completer<void>();
        final first = WidgetCalendarProjectionStore.rebuild(
          prefs: prefs,
          userId: userId,
          yearTerm: term,
          centerWeek: '5',
          customizeSchedules: (schedules) async {
            started.complete();
            await release.future;
            return schedules.toList();
          },
        );
        await started.future;
        (schedule['eventList'] as List).single['eventName'] = '新课表课程';
        final second = WidgetCalendarProjectionStore.rebuild(
          prefs: prefs,
          userId: userId,
          yearTerm: term,
          centerWeek: '5',
          customizeSchedules: (schedules) async => schedules.toList(),
        );
        release.complete();
        await Future.wait([first, second]);
        await WidgetUpdater.updateTodayWidget();
        final projection = jsonDecode(prefs.getString(projectionKey)!) as Map;
        expect(
          projection['days'].single['events'].single['eventName'],
          '新课表课程',
        );
      },
    );

    test(
      'projection rebuilding abandons an account or pin changed while reading',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final changed = await WidgetCalendarProjectionStore.rebuild(
          prefs: prefs,
          userId: userId,
          yearTerm: term,
          centerWeek: '5',
          customizeSchedules: (schedules) async {
            await prefs.setString('schedule_widget_week_$userId', '9');
            return schedules.toList();
          },
        );
        expect(changed, isFalse);
        expect(prefs.getString(projectionKey), isNull);
      },
    );

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

    test(
      'a saved week outside widget coverage still refreshes reminders',
      () async {
        final remote = {...schedule, 'weekNum': '8'};
        final api = ScheduleApi(courseApi: _FakeCourseApi({'8': remote}));
        await api.loadFromNetwork(
          userId: userId,
          encryptedPassword: 'secret',
          yearTerm: term,
          weekNum: '8',
          persistLastViewed: false,
        );
        expect(broadcasts, 0);
        expect((await CourseReminderScheduler.loadStatus()).reason, '课前提醒已关闭');
      },
    );

    test(
      'explicit side effect completion does not hold the persisted result',
      () async {
        final gate = Completer<void>();
        WidgetUpdater.debugMethodInvoker = (_, _) => gate.future;
        final api = ScheduleApi(courseApi: _FakeCourseApi({'5': schedule}));
        final loaded = await api.loadFromNetwork(
          userId: userId,
          encryptedPassword: 'secret',
          yearTerm: term,
          weekNum: '5',
          persistLastViewed: false,
          refreshReminders: false,
          waitForSideEffects: false,
        );
        expect(loaded.weekNum, '5');
        var completed = false;
        final pending = api.completePendingSideEffects().then(
          (_) => completed = true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(completed, isFalse);
        gate.complete();
        await pending;
        expect(completed, isTrue);
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
