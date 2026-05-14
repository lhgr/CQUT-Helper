import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/schedule_diff_utils.dart';
import 'package:flutter_test/flutter_test.dart';

EventItem _event({
  required String id,
  required String name,
  String weekDay = '1',
  String sessionStart = '1',
  String sessionLast = '2',
  String teacher = '张三',
  String address = 'A101',
}) {
  return EventItem(
    eventID: id,
    eventName: name,
    weekDay: weekDay,
    sessionStart: sessionStart,
    sessionLast: sessionLast,
    memberName: teacher,
    address: address,
    eventType: 'course',
  );
}

ScheduleData _data(List<EventItem> events) {
  return ScheduleData(weekNum: '1', weekList: const ['1'], eventList: events);
}

void main() {
  group('diffScheduleWeekLines', () {
    test('能识别新增课程', () {
      final lines = diffScheduleWeekLines(
        before: _data(const []),
        after: _data([_event(id: 'e1', name: '高等数学')]),
      );

      expect(lines, ['新增：高等数学（张三） 周一 1-2节 A101']);
    });

    test('能识别删除课程', () {
      final lines = diffScheduleWeekLines(
        before: _data([_event(id: 'e1', name: '大学英语')]),
        after: _data(const []),
      );

      expect(lines, ['删除：大学英语（张三） 周一 1-2节 A101']);
    });

    test('能输出时间地点教师变化', () {
      final lines = diffScheduleWeekLines(
        before: _data([
          _event(id: 'e1', name: '数据结构', address: 'A101', teacher: '张三'),
        ]),
        after: _data([
          _event(
            id: 'e1',
            name: '数据结构',
            weekDay: '3',
            sessionStart: '3',
            sessionLast: '2',
            address: 'B202',
            teacher: '李四',
          ),
        ]),
      );

      expect(lines, [
        '数据结构：时间 周一 1-2节 → 周三 3-4节；地点 A101 → B202；教师 张三 → 李四',
      ]);
    });

    test('会根据 maxLines 截断输出', () {
      final after = _data([
        _event(id: 'e1', name: '高等数学'),
        _event(id: 'e2', name: '大学英语'),
        _event(id: 'e3', name: '线性代数'),
      ]);

      final lines = diffScheduleWeekLines(
        before: _data(const []),
        after: after,
        maxLines: 2,
      );

      expect(lines, hasLength(2));
    });
  });
}
