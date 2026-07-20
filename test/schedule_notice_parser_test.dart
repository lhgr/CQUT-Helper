import 'package:cqut_helper/model/schedule_notice.dart';
import 'package:cqut_helper/utils/schedule_notice_parser.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduleNotice _notice({
  String title = '关于2023级计算机1班调课的通知',
  String content = '2023级计算机1班 高等数学调课',
  String? courseName = '高等数学',
  String? originalTime = '第3周 星期一 第1-2节',
  String? adjustedTime = '第4周 星期三 第3-4节',
}) {
  return ScheduleNotice(
    noticeId: 'notice-1',
    status: 'published',
    publishedAt: '2026-05-09 10:00:00',
    title: title,
    content: content,
    courseName: courseName,
    teacher: '张三',
    originalTime: originalTime,
    originalClassroom: 'A101',
    adjustedTime: adjustedTime,
    adjustedClassroom: 'B202',
  );
}

void main() {
  group('ScheduleNoticeParser.parseImpact', () {
    test('能解析周次区间、班级、节次和可读文案', () {
      final notice = _notice(
        content: '2023级计算机1班 高等数学从第3周调到第4-5周',
      );

      final impact = ScheduleNoticeParser.parseImpact(notice);

      expect(impact.noticeId, 'notice-1');
      expect(impact.noticeVersion, notice.versionHash());
      expect(impact.weeks, {'3', '4', '5'});
      expect(impact.keys, {
        '3-2023级计算机1班-第3-4节',
        '4-2023级计算机1班-第3-4节',
        '5-2023级计算机1班-第3-4节',
      });
      expect(impact.line, '第3周星期一第1-2节的**高等数学**课程调课到第4周星期三第3-4节');
    });

    test('信息不完整时回退到默认值', () {
      final notice = _notice(
        title: '临时调课通知',
        content: '请相关班级同学注意',
        courseName: null,
        originalTime: null,
        adjustedTime: null,
      );

      final impact = ScheduleNoticeParser.parseImpact(notice);

      expect(impact.weeks, {'0'});
      expect(impact.keys, {'0-请相关班-未知节次'});
      expect(impact.line, '调课通知信息不完整：**未知课程**课程（请在调课记录中查看详情）');
    });
  });
}
