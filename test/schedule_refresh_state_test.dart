import 'dart:convert';

import 'package:cqut_helper/manager/schedule_refresh_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ScheduleRefreshState', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('成功刷新会更新时间并清理失败状态', () async {
      await ScheduleRefreshState.markFailure(
        'u1',
        failure: ScheduleWidgetRefreshFailure.generic,
      );
      final at = DateTime(2026, 7, 29, 9, 12);

      await ScheduleRefreshState.markSuccess('u1', at: at);
      final snapshot = await ScheduleRefreshState.load('u1');

      expect(snapshot.lastSuccessfulRefreshAt, at);
      expect(snapshot.widgetState, ScheduleWidgetRefreshState.idle);
      expect(snapshot.failure, isNull);
    });

    test('刷新中会清理旧失败原因', () async {
      await ScheduleRefreshState.markFailure(
        'u1',
        failure: ScheduleWidgetRefreshFailure.credentialInvalid,
      );

      await ScheduleRefreshState.markLoading('u1');
      final snapshot = await ScheduleRefreshState.load('u1');

      expect(snapshot.widgetState, ScheduleWidgetRefreshState.loading);
      expect(snapshot.failure, isNull);
    });

    test('能区分凭证错误与普通错误', () {
      expect(
        ScheduleRefreshState.looksLikeCredentialFailure(Exception('登录凭证已失效')),
        isTrue,
      );
      expect(
        ScheduleRefreshState.looksLikeCredentialFailure(Exception('网络连接失败')),
        isFalse,
      );
    });

    test(
      'migrates the legacy weekly fetch timestamp for a valid cache',
      () async {
        final now = DateTime.now();
        final legacyFetchAt = DateTime(2026, 7, 29, 8, 30);
        SharedPreferences.setMockInitialValues({
          'schedule_widget_term_u1': '2025-2026-2',
          'schedule_widget_week_u1': '20',
          'schedule_u1_2025-2026-2_20': jsonEncode({
            'weekDayList': [
              {
                'weekDate': '${now.month}.${now.day}',
                'weekDay': now.weekday.toString(),
              },
            ],
            'eventList': const [],
          }),
          'schedule_fetch_at_u1_2025-2026-2_20':
              legacyFetchAt.millisecondsSinceEpoch,
        });

        final snapshot = await ScheduleRefreshState.load('u1');
        final prefs = await SharedPreferences.getInstance();

        expect(snapshot.lastSuccessfulRefreshAt, legacyFetchAt);
        expect(
          DateTime.tryParse(
            prefs.getString('schedule_last_successful_refresh_at_u1') ?? '',
          ),
          legacyFetchAt,
        );
      },
    );

    test('marks an existing current cache as synced during upgrade', () async {
      final before = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'schedule_last_term_u1': '2025-2026-2',
        'schedule_last_week_u1': '20',
        'schedule_u1_2025-2026-2_20': jsonEncode({
          'weekDayList': [
            {'today': true, 'weekDate': ''},
          ],
          'eventList': const [],
        }),
      });

      final snapshot = await ScheduleRefreshState.load('u1');

      expect(snapshot.lastSuccessfulRefreshAt, isNotNull);
      expect(
        snapshot.lastSuccessfulRefreshAt!.isBefore(
          before.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });

    test(
      'migrates a real legacy fetch timestamp outside the teaching week',
      () async {
        final now = DateTime.now();
        final oldDate = now.subtract(const Duration(days: 14));
        final legacyFetchAt = DateTime(2026, 7, 1);
        SharedPreferences.setMockInitialValues({
          'schedule_widget_term_u1': '2025-2026-2',
          'schedule_widget_week_u1': '18',
          'schedule_u1_2025-2026-2_18': jsonEncode({
            'weekDayList': [
              {
                'weekDate': '${oldDate.month}.${oldDate.day}',
                'weekDay': oldDate.weekday.toString(),
              },
            ],
            'eventList': const [],
          }),
          'schedule_fetch_at_u1_2025-2026-2_18': DateTime(
            2026,
            7,
            1,
          ).millisecondsSinceEpoch,
        });

        final snapshot = await ScheduleRefreshState.load('u1');

        expect(snapshot.lastSuccessfulRefreshAt, legacyFetchAt);
      },
    );

    test(
      'does not invent a refresh timestamp for an uncovered cache',
      () async {
        final now = DateTime.now();
        final oldDate = now.subtract(const Duration(days: 14));
        SharedPreferences.setMockInitialValues({
          'schedule_widget_term_u1': '2025-2026-2',
          'schedule_widget_week_u1': '18',
          'schedule_u1_2025-2026-2_18': jsonEncode({
            'weekDayList': [
              {
                'weekDate': '${oldDate.month}.${oldDate.day}',
                'weekDay': oldDate.weekday.toString(),
              },
            ],
            'eventList': const [],
          }),
        });

        final snapshot = await ScheduleRefreshState.load('u1');

        expect(snapshot.lastSuccessfulRefreshAt, isNull);
      },
    );
  });
}
