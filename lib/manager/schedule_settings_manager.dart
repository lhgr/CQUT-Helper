import 'package:shared_preferences/shared_preferences.dart';

class ScheduleSettingsManager {
  static const String _prefsKeyShowWeekend = 'schedule_show_weekend';
  static const String _prefsKeyTimeInfoEnabled = 'schedule_time_info_enabled';
  static const String _prefsKeyUpdateShowDiff = 'schedule_update_show_diff';
  static const String _prefsKeyBackgroundPollingEnabled =
      'schedule_background_polling_enabled';

  bool showWeekend = true;
  bool timeInfoEnabled = true;
  bool updateShowDiff = true;
  bool backgroundPollingEnabled = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    showWeekend = prefs.getBool(_prefsKeyShowWeekend) ?? true;
    timeInfoEnabled = prefs.getBool(_prefsKeyTimeInfoEnabled) ?? true;
    updateShowDiff = prefs.getBool(_prefsKeyUpdateShowDiff) ?? true;
    backgroundPollingEnabled =
        prefs.getBool(_prefsKeyBackgroundPollingEnabled) ?? false;
  }

  Future<void> save({
    required bool showWeekend,
    required bool timeInfoEnabled,
    required bool updateShowDiff,
    required bool backgroundPollingEnabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    this.showWeekend = showWeekend;
    this.timeInfoEnabled = timeInfoEnabled;
    this.updateShowDiff = updateShowDiff;
    this.backgroundPollingEnabled = backgroundPollingEnabled;

    await prefs.setBool(_prefsKeyShowWeekend, showWeekend);
    await prefs.setBool(_prefsKeyTimeInfoEnabled, timeInfoEnabled);
    await prefs.setBool(_prefsKeyUpdateShowDiff, updateShowDiff);
    await prefs.setBool(
      _prefsKeyBackgroundPollingEnabled,
      backgroundPollingEnabled,
    );
  }
}
