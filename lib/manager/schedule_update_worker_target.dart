import 'package:shared_preferences/shared_preferences.dart';

const String _lastViewedWeekKeyPrefix = 'schedule_last_week_';
const String _lastViewedTermKeyPrefix = 'schedule_last_term_';
const String _widgetWeekKeyPrefix = 'schedule_widget_week_';
const String _widgetTermKeyPrefix = 'schedule_widget_term_';

String _lastViewedWeekKey(String userId) => '$_lastViewedWeekKeyPrefix$userId';

String _lastViewedTermKey(String userId) => '$_lastViewedTermKeyPrefix$userId';

String _widgetWeekKey(String userId) => '$_widgetWeekKeyPrefix$userId';

String _widgetTermKey(String userId) => '$_widgetTermKeyPrefix$userId';

bool _isValidTerm(String value) =>
    RegExp(r'^\d{4}-\d{4}-[12]$').hasMatch(value.trim());

String _normalizeWeek(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return '1';
  if (!RegExp(r'^\d+$').hasMatch(raw)) return '1';
  return raw;
}

({String? yearTerm, String weekNum}) resolveScheduleUpdateWorkerPollingTarget({
  required SharedPreferences prefs,
  required String userId,
}) {
  final lastTerm = (prefs.getString(_lastViewedTermKey(userId)) ?? '').trim();
  final widgetTerm = (prefs.getString(_widgetTermKey(userId)) ?? '').trim();
  final selectedTerm = _isValidTerm(widgetTerm)
      ? widgetTerm
      : (_isValidTerm(lastTerm) ? lastTerm : null);
  final lastWeek = (prefs.getString(_lastViewedWeekKey(userId)) ?? '').trim();
  final widgetWeek = (prefs.getString(_widgetWeekKey(userId)) ?? '').trim();
  final selectedWeek = _normalizeWeek(
    widgetWeek.isNotEmpty ? widgetWeek : lastWeek,
  );
  return (yearTerm: selectedTerm, weekNum: selectedWeek);
}
