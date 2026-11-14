import 'package:cqut_helper/manager/course_reminder_scheduler.dart';

enum DiagnosticCondition { normal, off, pending, problem }

/// Presentation of the scheduler's actual plan, combined with live permissions.
/// This does not calculate coverage or create a reminder plan.
class ReminderReadiness {
  final bool? enabled;
  final CourseReminderStatus? plan;
  final bool? notifications;
  final bool? exactAlarm;
  final bool readFailed;
  final bool isIOS;

  const ReminderReadiness({
    required this.enabled,
    required this.plan,
    required this.notifications,
    required this.exactAlarm,
    this.readFailed = false,
    required this.isIOS,
  });

  bool get unreadable =>
      enabled != false &&
      (readFailed ||
          enabled == null ||
          plan == null ||
          notifications == null ||
          exactAlarm == null);

  DiagnosticCondition get condition {
    if (enabled == false) return DiagnosticCondition.off;
    if (unreadable) return DiagnosticCondition.pending;
    if (notifications == false || exactAlarm == false) {
      return DiagnosticCondition.problem;
    }
    if (plan!.updatedAt == null || !plan!.enabled) {
      return DiagnosticCondition.pending;
    }
    return plan!.ready
        ? DiagnosticCondition.normal
        : DiagnosticCondition.problem;
  }

  String get detail {
    if (enabled == false) {
      return isIOS ? '开启后根据课表安排近期提醒，打开应用时续排' : '开启后会根据课表生成未来 60 天提醒';
    }
    if (unreadable) return '暂时无法获取，请重试';
    if (notifications == false || exactAlarm == false) {
      return isIOS ? '通知权限未授予，请检查系统设置' : '通知或精确闹钟权限未授予，请检查系统设置';
    }
    if (plan!.updatedAt == null || !plan!.enabled) return '尚未建立提醒计划';
    return plan!.reason;
  }
}
