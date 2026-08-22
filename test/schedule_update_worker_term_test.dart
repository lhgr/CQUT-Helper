import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingScheduleApi extends ScheduleApi {
  final List<
    ({
      String? week,
      String? term,
      bool persistLastViewed,
      bool updateWidgetPins,
      bool notifyWidget,
      String? refreshId,
    })
  >
  requests = [];

  @override
  Future<ScheduleData> loadFromNetwork({
    required String userId,
    required String encryptedPassword,
    String? weekNum,
    String? yearTerm,
    bool persistLastViewed = true,
    bool updateWidgetPins = false,
    bool notifyWidget = true,
    String? refreshId,
  }) async {
    requests.add((
      week: weekNum,
      term: yearTerm,
      persistLastViewed: persistLastViewed,
      updateWidgetPins: updateWidgetPins,
      notifyWidget: notifyWidget,
      refreshId: refreshId,
    ));
    return ScheduleData(
      yearTerm: '2026-2027-1',
      weekNum: '2',
      weekList: const ['1', '2', '3'],
    );
  }
}

void main() {
  group('ScheduleUpdateWorker.resolvePollingTarget', () {
    test('优先使用当前学期锚点(widget)而非当前查看学期', () async {
      SharedPreferences.setMockInitialValues({
        'schedule_widget_term_u1': '2025-2026-2',
        'schedule_widget_week_u1': '8',
        'schedule_last_term_u1': '2024-2025-2',
        'schedule_last_week_u1': '6',
      });
      final prefs = await SharedPreferences.getInstance();
      final target = ScheduleUpdateWorker.resolvePollingTarget(
        prefs: prefs,
        userId: 'u1',
      );

      expect(target.yearTerm, '2025-2026-2');
      expect(target.weekNum, '8');
    });

    test('当前学期锚点缺失时回退到当前查看学期，非法周次回退到1', () async {
      SharedPreferences.setMockInitialValues({
        'schedule_last_term_u1': '2023-2024-1',
        'schedule_last_week_u1': 'abc',
      });
      final prefs = await SharedPreferences.getInstance();
      final target = ScheduleUpdateWorker.resolvePollingTarget(
        prefs: prefs,
        userId: 'u1',
      );

      expect(target.yearTerm, '2023-2024-1');
      expect(target.weekNum, '1');
    });
  });

  group('ScheduleUpdateWorker 后台任务参数', () {
    test('只保存账号和调度元数据，不复制教务系统凭证', () {
      final inputData = ScheduleUpdateWorker.buildTaskInputData(
        userId: 'u1',
        trigger: 'daily_9am',
        logicalDateBjt: '2026-07-29',
        scheduledAtBjt: '2026-07-29T09:00:00+08:00',
      );

      expect(inputData['userId'], 'u1');
      expect(inputData['trigger'], 'daily_9am');
      expect(inputData.containsKey('encryptedPassword'), isFalse);
      expect(inputData.values, isNot(contains('secure-p1')));
    });
  });

  group('ScheduleUpdateWorker 当前周重锚定', () {
    test('widget 手动刷新不携带旧周参数并更新 pin', () async {
      final api = _RecordingScheduleApi();

      await ScheduleUpdateWorker.loadCurrentWeekAndUpdateWidgetPin(
        scheduleApi: api,
        userId: 'u1',
        encryptedPassword: 'p1',
        notifyWidget: false,
        refreshId: 'refresh-1',
      );

      final currentRequest = api.requests.first;
      expect(currentRequest.week, isNull);
      expect(currentRequest.term, isNull);
      expect(currentRequest.persistLastViewed, isFalse);
      expect(currentRequest.updateWidgetPins, isTrue);
      expect(currentRequest.notifyWidget, isFalse);
      expect(currentRequest.refreshId, 'refresh-1');
      expect(
        api.requests
            .skip(1)
            .map((request) => (week: request.week, term: request.term))
            .toSet(),
        {(week: '1', term: '2026-2027-1'), (week: '3', term: '2026-2027-1')},
      );
      for (final request in api.requests.skip(1)) {
        expect(request.persistLastViewed, isFalse);
        expect(request.updateWidgetPins, isFalse);
        expect(request.notifyWidget, isFalse);
        expect(request.refreshId, 'refresh-1');
      }
    });

    test('stale today marker does not prevent background reanchor', () {
      final stale = ScheduleData(
        weekDayList: [
          WeekDayItem(weekDate: '2026-08-03', today: true),
          WeekDayItem(weekDate: '2026-08-09'),
        ],
      );
      final current = ScheduleData(
        weekDayList: [
          WeekDayItem(weekDate: '2026-08-10'),
          WeekDayItem(weekDate: '2026-08-16'),
        ],
      );
      final targetDate = DateTime(2026, 8, 10);

      expect(
        ScheduleUpdateWorker.shouldReanchorPollingTarget(
          stale,
          now: targetDate,
        ),
        isTrue,
      );
      expect(
        ScheduleUpdateWorker.shouldReanchorPollingTarget(
          current,
          now: targetDate,
        ),
        isFalse,
      );
      expect(
        ScheduleUpdateWorker.shouldReanchorPollingTarget(null, now: targetDate),
        isTrue,
      );
    });

    test('coverage date follows actual BJT execution day', () {
      final executionDate = ScheduleUpdateWorker.pollingCoverageDateBjt(
        nowUtc: DateTime.utc(2026, 8, 22, 16, 30),
      );

      expect(
        (executionDate.year, executionDate.month, executionDate.day),
        (2026, 8, 23),
      );
    });

    test('daily 9am scheduling never skips a BJT day after 16 oclock', () {
      expect(
        ScheduleUpdateWorker.nextDaily9amUtcAt(
          DateTime.utc(2026, 8, 22, 7, 59), // BJT 15:59
        ),
        DateTime.utc(2026, 8, 23, 1),
      );
      expect(
        ScheduleUpdateWorker.nextDaily9amUtcAt(
          DateTime.utc(2026, 8, 22, 8), // BJT 16:00
        ),
        DateTime.utc(2026, 8, 23, 1),
      );
    });

    test('deep night is evaluated in BJT instead of device local time', () {
      expect(
        ScheduleUpdateWorker.isDeepNightAt(DateTime.utc(2026, 8, 22, 22, 59)),
        isTrue, // BJT 06:59
      );
      expect(
        ScheduleUpdateWorker.isDeepNightAt(DateTime.utc(2026, 8, 22, 23)),
        isFalse, // BJT 07:00
      );
    });
  });
}
