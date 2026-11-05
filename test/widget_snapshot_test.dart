import 'dart:convert';

import 'package:cqut_helper/manager/schedule_refresh_state.dart';
import 'package:cqut_helper/utils/widget_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const projection = {
    'schema_version': 1,
    'year_term': '2026-2027-1',
    'days': [
      {
        'date': '2026-11-05',
        'events': [
          {'eventName': '已重命名课程', 'colorIndex': 7},
        ],
      },
    ],
  };
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'account': 'student',
      'schedule_widget_term_student': '2026-2027-1',
      'schedule_widget_week_student': '10',
      'schedule_widget_calendar_projection_v1_student': jsonEncode(projection),
      'schedule_last_successful_refresh_at_student': '2026-11-05T08:00:00',
      'schedule_time_info_cache_v1': jsonEncode({
        'items': [
          {
            'sessionNum': 1,
            'startTime': '08:00',
            'endTime': '08:45',
            'campusName': '花溪',
          },
        ],
      }),
      'schedule_course_color_map_v1_student|2026-2027-1': '{"已重命名课程":7}',
      'theme_mode': 'dark',
    });
  });

  test(
    'reuses customized projection, clocks, color assignments and freshness',
    () async {
      final value = jsonDecode(await WidgetSnapshot.encode()) as Map;
      expect(value['schemaVersion'], 1);
      expect(value['generatedAt'], isA<int>());
      expect(value['activeUserId'], 'student');
      expect(value['yearTerm'], '2026-2027-1');
      expect(value['pinnedWeek'], 10);
      expect(value['calendarProjection'], projection);
      expect(value['sessionClocks'], [
        {'sessionNum': 1, 'startTime': '08:00', 'endTime': '08:45'},
      ]);
      expect(value['courseColorMap'], {'已重命名课程': 7});
      expect(value['themeMode'], 'dark');
      expect(value['refresh']['state'], 'normal');
      expect(
        value['refresh']['lastSuccessfulAt'],
        DateTime(2026, 11, 5, 8).millisecondsSinceEpoch,
      );
    },
  );

  test(
    'account changes and logout never expose the previous account',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account', 'other');
      var value = jsonDecode(await WidgetSnapshot.encode()) as Map;
      expect(value['activeUserId'], 'other');
      expect(value['calendarProjection'], isNull);
      expect(value['courseColorMap'], isEmpty);
      expect(value['refresh']['state'], 'needs_sync');
      await prefs.remove('account');
      value = jsonDecode(await WidgetSnapshot.encode()) as Map;
      expect(value['activeUserId'], '');
      expect(value['yearTerm'], '');
      expect(value['calendarProjection'], isNull);
      expect(value['refresh']['lastSuccessfulAt'], isNull);
    },
  );

  test(
    'represents loading and credential failure while retaining saved classes',
    () async {
      await ScheduleRefreshState.markLoading('student');
      var value = jsonDecode(await WidgetSnapshot.encode()) as Map;
      expect(value['refresh']['state'], 'loading');
      expect(value['calendarProjection'], projection);
      await ScheduleRefreshState.markFailure(
        'student',
        failure: ScheduleWidgetRefreshFailure.credentialInvalid,
      );
      value = jsonDecode(await WidgetSnapshot.encode()) as Map;
      expect(value['refresh']['state'], 'credential_invalid');
      expect(value['calendarProjection'], projection);
    },
  );

  test(
    'ignores malformed or mismatched projection and normalizes theme',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'schedule_widget_calendar_projection_v1_student',
        '{broken',
      );
      var value = jsonDecode(
        await WidgetSnapshot.encode(themeMode: 'ThemeMode.light'),
      ) as Map;
      expect(value['calendarProjection'], isNull);
      expect(value['themeMode'], 'light');
      await prefs.setString(
        'schedule_widget_calendar_projection_v1_student',
        '{"schema_version":1,"year_term":"old"}',
      );
      value = jsonDecode(await WidgetSnapshot.encode()) as Map;
      expect(value['calendarProjection'], isNull);
      expect(value['refresh']['state'], 'needs_sync');
    },
  );
}
