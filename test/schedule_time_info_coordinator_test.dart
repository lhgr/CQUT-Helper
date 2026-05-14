import 'dart:convert';

import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_time_info_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTimeInfoScheduleApi extends ScheduleApi {
  _FakeTimeInfoScheduleApi({
    required this.response,
    this.resolvedCampusName = '两江校区',
  });

  final List<CampusTimeInfo> response;
  final String resolvedCampusName;
  int fetchCount = 0;

  @override
  Future<String?> getCampusName() async => resolvedCampusName;

  @override
  Future<List<CampusTimeInfo>> fetchCampusTimeInfo(String campusName) async {
    fetchCount++;
    return response;
  }
}

void main() {
  group('ScheduleTimeInfoCoordinator', () {
    test('能从缓存加载 time info', () async {
      SharedPreferences.setMockInitialValues({
        'schedule_time_info_cache_v1': json.encode({
          'campusName': '两江校区',
          'updatedAt': 1,
          'items': [
            {
              'campusName': '两江校区',
              'sessionNum': 1,
              'startTime': '08:00',
              'endTime': '08:45',
            },
          ],
        }),
      });
      List<CampusTimeInfo>? state;
      final coordinator = ScheduleTimeInfoCoordinator(
        service: _FakeTimeInfoScheduleApi(response: const []),
        getTimeInfoList: () => state,
        setTimeInfoList: (value) => state = value,
      );

      final loaded = await coordinator.loadTimeInfoFromCacheIfAny();

      expect(loaded, isTrue);
      expect(state, isNotNull);
      expect(state!.single.sessionNum, 1);
    });

    test('短时间内重复刷新会命中 cooldown', () async {
      SharedPreferences.setMockInitialValues({});
      List<CampusTimeInfo>? state;
      final api = _FakeTimeInfoScheduleApi(
        resolvedCampusName: '花溪校区',
        response: [
          CampusTimeInfo(
            campusName: '两江校区',
            sessionNum: 1,
            startTime: '08:00',
            endTime: '08:45',
          ),
        ],
      );
      final coordinator = ScheduleTimeInfoCoordinator(
        service: api,
        getTimeInfoList: () => state,
        setTimeInfoList: (value) => state = value,
      );

      final first = await coordinator.refreshTimeInfoIfEnabled();
      final second = await coordinator.refreshTimeInfoIfEnabled();

      expect(first, isTrue);
      expect(second, isFalse);
      expect(api.fetchCount, 1);
    });

    test('刷新结果未变化时返回 false 并保留缓存可读', () async {
      final items = [
        {
          'campusName': '两江校区',
          'sessionNum': 1,
          'startTime': '08:00',
          'endTime': '08:45',
        },
      ];
      SharedPreferences.setMockInitialValues({
        'schedule_time_info_cache_v1': json.encode({
          'campusName': '两江校区',
          'fingerprint': json.encode(items),
          'updatedAt': 1,
          'items': items,
        }),
        'schedule_time_info_last_campus': '两江校区',
      });
      List<CampusTimeInfo>? state;
      final api = _FakeTimeInfoScheduleApi(
        response: [
          CampusTimeInfo(
            campusName: '两江校区',
            sessionNum: 1,
            startTime: '08:00',
            endTime: '08:45',
          ),
        ],
      );
      final coordinator = ScheduleTimeInfoCoordinator(
        service: api,
        getTimeInfoList: () => state,
        setTimeInfoList: (value) => state = value,
      );

      final changed = await coordinator.refreshTimeInfoIfEnabled(force: true);
      final loaded = await coordinator.loadTimeInfoFromCacheIfAny();

      expect(changed, isFalse);
      expect(loaded, isTrue);
      expect(state, isNotNull);
      expect(state!.single.startTime, '08:00');
    });
  });
}
