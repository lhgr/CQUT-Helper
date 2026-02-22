import 'package:shared_preferences/shared_preferences.dart';

class ScheduleSettingsManager {
  static const String _prefsKeyShowWeekend = 'schedule_show_weekend';
  static const String _prefsKeyUpdateWeeksAhead = 'schedule_update_weeks_ahead';
  static const String _prefsKeyUpdateEnabled = 'schedule_update_enabled';
  static const String _prefsKeyUpdateIntervalMinutes =
      'schedule_update_interval_minutes';
  static const String _prefsKeyUpdateShowDiff = 'schedule_update_show_diff';
  static const String _prefsKeyUpdateSystemNotifyEnabled =
      'schedule_update_system_notification_enabled';

  bool showWeekend = true;
  int updateWeeksAhead = 1;
  bool updateEnabled = false;
  int updateIntervalMinutes = 60;
  bool updateShowDiff = true;
  bool updateSystemNotifyEnabled = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    showWeekend = prefs.getBool(_prefsKeyShowWeekend) ?? true;
    updateWeeksAhead = prefs.getInt(_prefsKeyUpdateWeeksAhead) ?? 1;
    updateEnabled = prefs.getBool(_prefsKeyUpdateEnabled) ?? false;
    updateIntervalMinutes = prefs.getInt(_prefsKeyUpdateIntervalMinutes) ?? 60;
    updateShowDiff = prefs.getBool(_prefsKeyUpdateShowDiff) ?? true;
    updateSystemNotifyEnabled =
        prefs.getBool(_prefsKeyUpdateSystemNotifyEnabled) ?? false;
  }

  Future<void> save({
    required bool showWeekend,
    required int updateWeeksAhead,
    required bool updateEnabled,
    required int updateIntervalMinutes,
    required bool updateShowDiff,
    required bool updateSystemNotifyEnabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    this.showWeekend = showWeekend;
    this.updateWeeksAhead = updateWeeksAhead;
    this.updateEnabled = updateEnabled;
    this.updateIntervalMinutes = updateIntervalMinutes;
    this.updateShowDiff = updateShowDiff;
    this.updateSystemNotifyEnabled = updateSystemNotifyEnabled;

    await prefs.setBool(_prefsKeyShowWeekend, showWeekend);
    await prefs.setInt(_prefsKeyUpdateWeeksAhead, updateWeeksAhead);
    await prefs.setBool(_prefsKeyUpdateEnabled, updateEnabled);
    await prefs.setInt(_prefsKeyUpdateIntervalMinutes, updateIntervalMinutes);
    await prefs.setBool(_prefsKeyUpdateShowDiff, updateShowDiff);
    await prefs.setBool(
        _prefsKeyUpdateSystemNotifyEnabled, updateSystemNotifyEnabled);
  }
}
