import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('提醒健康状态可完整序列化', () {
    final status = CourseReminderStatus(
      enabled: true,
      ready: true,
      reason: '提醒计划正常',
      scheduledCount: 72,
      cachedWeekCount: 18,
      expectedWeekCount: 20,
      nextReminderAt: DateTime(2026, 8, 21, 8, 0),
      coveredUntil: DateTime(2026, 10, 20),
      updatedAt: DateTime(2026, 8, 20, 12, 0),
    );

    final restored = CourseReminderStatus.fromJson(status.toJson());
    expect(restored.enabled, isTrue);
    expect(restored.ready, isTrue);
    expect(restored.scheduledCount, 72);
    expect(restored.cachedWeekCount, 18);
    expect(restored.expectedWeekCount, 20);
    expect(restored.nextReminderAt, DateTime(2026, 8, 21, 8, 0));
    expect(restored.coveredUntil, DateTime(2026, 10, 20));
  });
}
