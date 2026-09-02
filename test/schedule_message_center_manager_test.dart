import 'package:cqut_helper/manager/schedule_message_center_manager.dart';
import 'package:cqut_helper/model/schedule_week_change.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('调课变更会持久化、去重并可全部标为已读', () async {
    const changes = [
      ScheduleWeekChange(weekNum: '3', lines: ['高等数学由周一调到周三']),
    ];

    await ScheduleMessageCenterManager.appendChanges(
      userId: '20260001',
      yearTerm: '2026-2027-1',
      changes: changes,
    );
    await ScheduleMessageCenterManager.appendChanges(
      userId: '20260001',
      yearTerm: '2026-2027-1',
      changes: changes,
    );

    var records = await ScheduleMessageCenterManager.load('20260001');
    expect(records, hasLength(1));
    expect(records.single.read, isFalse);
    expect(records.single.changes.single.weekNum, '3');

    await ScheduleMessageCenterManager.markAllRead('20260001');
    records = await ScheduleMessageCenterManager.load('20260001');
    expect(records.single.read, isTrue);
  });
}
