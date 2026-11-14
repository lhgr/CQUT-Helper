import 'package:cqut_helper/manager/schedule_update_intents.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => ScheduleUpdateIntents.openWeek.value = null);

  test(
    'only the matching destination is consumed and newest target is retained',
    () {
      ScheduleUpdateIntents.requestOpenWeek(
        userId: ' a ',
        yearTerm: ' term ',
        weekNum: ' 2 ',
      );
      final first = ScheduleUpdateIntents.openWeek.value!;
      expect(first.userId, 'a');
      expect(first.yearTerm, 'term');
      expect(first.weekNum, '2');
      ScheduleUpdateIntents.requestOpenWeek(
        userId: 'a',
        yearTerm: 'other',
        weekNum: '3',
      );
      final second = ScheduleUpdateIntents.openWeek.value!;
      expect(second.token, greaterThan(first.token));
      ScheduleUpdateIntents.consumeOpenWeek(first);
      expect(ScheduleUpdateIntents.openWeek.value, same(second));
      ScheduleUpdateIntents.consumeOpenWeek(second);
      expect(ScheduleUpdateIntents.openWeek.value, isNull);
    },
  );
}
