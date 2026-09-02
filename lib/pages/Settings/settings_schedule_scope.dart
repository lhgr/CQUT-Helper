import 'package:shared_preferences/shared_preferences.dart';

class SettingsScheduleScope {
  final String userId;
  final String yearTerm;

  const SettingsScheduleScope({required this.userId, required this.yearTerm});

  bool get canManageCourses => userId.isNotEmpty && yearTerm.isNotEmpty;

  static Future<SettingsScheduleScope> resolve({
    String? userId,
    String? yearTerm,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedUserId = (userId ?? prefs.getString('account') ?? '').trim();
    final providedTerm = (yearTerm ?? '').trim();
    final resolvedTerm = providedTerm.isNotEmpty
        ? providedTerm
        : resolvedUserId.isEmpty
        ? ''
        : (prefs.getString('schedule_last_term_$resolvedUserId') ?? '').trim();
    return SettingsScheduleScope(
      userId: resolvedUserId,
      yearTerm: resolvedTerm,
    );
  }
}
