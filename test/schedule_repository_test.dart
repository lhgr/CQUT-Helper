import 'dart:async';

import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/schedule_repository.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BlockingScheduleApi extends ScheduleApi {
  int calls = 0;
  final Completer<ScheduleData> completer = Completer<ScheduleData>();

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
  }) {
    calls++;
    return completer.future;
  }
}

void main() {
  group('ScheduleRepository', () {
    test('相同用户学期周次的并发请求只执行一次', () async {
      final api = _BlockingScheduleApi();
      final repository = ScheduleRepository(api);

      final first = repository.loadFromNetwork(
        userId: 'u1',
        encryptedPassword: 'p1',
        weekNum: '2',
        yearTerm: '2025-2026-2',
      );
      final second = repository.loadFromNetwork(
        userId: 'u1',
        encryptedPassword: 'p1',
        weekNum: '2',
        yearTerm: '2025-2026-2',
      );

      expect(api.calls, 1);
      expect(repository.inFlightCount, 1);

      api.completer.complete(
        ScheduleData(
          weekNum: '2',
          yearTerm: '2025-2026-2',
          weekList: const ['1', '2', '3'],
        ),
      );
      final results = await Future.wait([first, second]);

      expect(results[0], same(results[1]));
      expect(repository.inFlightCount, 0);
    });

    test('按每周抓取时间判断缓存是否新鲜', () async {
      final now = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        ScheduleApi.lastFetchAtKey('u1', '2025-2026-2', '2'): now,
      });
      final repository = ScheduleRepository(ScheduleApi());
      final data = ScheduleData(weekNum: '2', yearTerm: '2025-2026-2');

      expect(await repository.isFresh(data), isTrue);
      expect(await repository.isFresh(data, maxAge: Duration.zero), isFalse);
    });
  });
}
