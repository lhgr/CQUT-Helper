import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleNoticeMetricsRecord {
  final String runType;
  final bool success;
  final bool degraded;
  final bool apiClosed;
  final int changeCount;
  final int affectedWeeks;
  final int durationMs;
  final int failureStreak;

  const ScheduleNoticeMetricsRecord({
    required this.runType,
    required this.success,
    required this.degraded,
    required this.apiClosed,
    required this.changeCount,
    required this.affectedWeeks,
    required this.durationMs,
    required this.failureStreak,
  });
}

class ScheduleNoticeMetrics {
  static const String _stateKey = 'schedule_notice_metrics_state_v1';
  static const String _textKey = 'schedule_notice_metrics_prom_text_v1';

  static Future<String> record(ScheduleNoticeMetricsRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final state = await _loadState(prefs);
    state['poll_total'] = (state['poll_total'] ?? 0) + 1;
    if (record.success) {
      state['success_total'] = (state['success_total'] ?? 0) + 1;
    } else {
      state['failure_total'] = (state['failure_total'] ?? 0) + 1;
    }
    if (record.apiClosed) {
      state['api_closed_total'] = (state['api_closed_total'] ?? 0) + 1;
    }
    if (record.degraded) {
      state['degraded_total'] = (state['degraded_total'] ?? 0) + 1;
    }
    state['changes_total'] = (state['changes_total'] ?? 0) + record.changeCount;
    state['affected_weeks_total'] =
        (state['affected_weeks_total'] ?? 0) + record.affectedWeeks;
    state['last_duration_ms'] = record.durationMs;
    state['last_failure_streak'] = record.failureStreak;
    state['last_poll_at_sec'] =
        DateTime.now().millisecondsSinceEpoch ~/ 1000;
    state['last_run_type'] = record.runType;

    await prefs.setString(_stateKey, json.encode(state));
    final text = _buildPromText(state);
    await prefs.setString(_textKey, text);
    return text;
  }

  static Future<String> loadPromText() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(_textKey);
    if (text != null && text.trim().isNotEmpty) return text;
    final state = await _loadState(prefs);
    return _buildPromText(state);
  }

  static Future<Map<String, dynamic>> _loadState(SharedPreferences prefs) async {
    final raw = prefs.getString(_stateKey);
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return <String, dynamic>{};
  }

  static String _buildPromText(Map<String, dynamic> state) {
    num v(String key) {
      final raw = state[key];
      if (raw is num) return raw;
      return num.tryParse((raw ?? '0').toString()) ?? 0;
    }

    final runType = (state['last_run_type'] ?? 'unknown').toString();
    return [
      '# HELP schedule_notice_poll_total Total notice polling count',
      '# TYPE schedule_notice_poll_total counter',
      'schedule_notice_poll_total ${v('poll_total')}',
      '# HELP schedule_notice_poll_success_total Successful notice polling count',
      '# TYPE schedule_notice_poll_success_total counter',
      'schedule_notice_poll_success_total ${v('success_total')}',
      '# HELP schedule_notice_poll_failure_total Failed notice polling count',
      '# TYPE schedule_notice_poll_failure_total counter',
      'schedule_notice_poll_failure_total ${v('failure_total')}',
      '# HELP schedule_notice_poll_api_closed_total Nightly API closed events',
      '# TYPE schedule_notice_poll_api_closed_total counter',
      'schedule_notice_poll_api_closed_total ${v('api_closed_total')}',
      '# HELP schedule_notice_changes_total Total changed notices',
      '# TYPE schedule_notice_changes_total counter',
      'schedule_notice_changes_total ${v('changes_total')}',
      '# HELP schedule_notice_affected_weeks_total Total affected weeks',
      '# TYPE schedule_notice_affected_weeks_total counter',
      'schedule_notice_affected_weeks_total ${v('affected_weeks_total')}',
      '# HELP schedule_notice_degraded_total Total degraded mode enter count',
      '# TYPE schedule_notice_degraded_total counter',
      'schedule_notice_degraded_total ${v('degraded_total')}',
      '# HELP schedule_notice_last_duration_ms Last polling duration milliseconds',
      '# TYPE schedule_notice_last_duration_ms gauge',
      'schedule_notice_last_duration_ms ${v('last_duration_ms')}',
      '# HELP schedule_notice_failure_streak Current failure streak',
      '# TYPE schedule_notice_failure_streak gauge',
      'schedule_notice_failure_streak ${v('last_failure_streak')}',
      '# HELP schedule_notice_last_poll_at_seconds Last polling unix timestamp',
      '# TYPE schedule_notice_last_poll_at_seconds gauge',
      'schedule_notice_last_poll_at_seconds ${v('last_poll_at_sec')}',
      '# HELP schedule_notice_last_run_info Last run type info',
      '# TYPE schedule_notice_last_run_info gauge',
      'schedule_notice_last_run_info{run_type="$runType"} 1',
    ].join('\n');
  }
}
