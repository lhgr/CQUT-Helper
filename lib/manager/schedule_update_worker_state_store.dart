import 'dart:convert';

import 'package:cqut_helper/model/schedule_week_change.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _backgroundPollingEnabledKey =
    'schedule_background_polling_enabled';
const String _backgroundPollingEnabledAtKey =
    'schedule_background_poll_enabled_at';
const String _backgroundPollingLastSuccessAtKey =
    'schedule_background_poll_last_success_at';
const String _backgroundPollLastStateKey = 'schedule_background_poll_last_state';
const String _backgroundPollSyncStateKey = 'schedule_background_poll_sync_state';
const String _pendingKeyPrefix = 'schedule_pending_changes_';

class ScheduleUpdateWorkerStoredState {
  final bool enabled;
  final DateTime? enabledAt;
  final DateTime? lastSuccessAt;
  final Map<String, dynamic>? lastState;
  final Map<String, dynamic>? syncState;

  const ScheduleUpdateWorkerStoredState({
    required this.enabled,
    required this.enabledAt,
    required this.lastSuccessAt,
    required this.lastState,
    required this.syncState,
  });
}

String scheduleUpdateWorkerPendingKeyForUser(String userId) =>
    '$_pendingKeyPrefix$userId';

Future<void> markScheduleUpdateWorkerEnabledAtIfNeeded({
  required bool enabled,
}) async {
  final prefs = await SharedPreferences.getInstance();
  if (!enabled) {
    await prefs.remove(_backgroundPollingEnabledAtKey);
    await prefs.remove(_backgroundPollingLastSuccessAtKey);
    await prefs.remove(_backgroundPollLastStateKey);
    await prefs.remove(_backgroundPollSyncStateKey);
    return;
  }
  if (prefs.getString(_backgroundPollingEnabledAtKey)?.trim().isNotEmpty ==
      true) {
    return;
  }
  await prefs.setString(
    _backgroundPollingEnabledAtKey,
    DateTime.now().toIso8601String(),
  );
}

Future<ScheduleUpdateWorkerStoredState>
loadScheduleUpdateWorkerStoredState() async {
  final prefs = await SharedPreferences.getInstance();
  return ScheduleUpdateWorkerStoredState(
    enabled: prefs.getBool(_backgroundPollingEnabledKey) ?? false,
    enabledAt: _parseTime(prefs, _backgroundPollingEnabledAtKey),
    lastSuccessAt: _parseTime(prefs, _backgroundPollingLastSuccessAtKey),
    lastState: _parseState(prefs, _backgroundPollLastStateKey),
    syncState: _parseState(prefs, _backgroundPollSyncStateKey),
  );
}

Future<void> recordScheduleUpdateWorkerSuccessfulRun() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _backgroundPollingLastSuccessAtKey,
      DateTime.now().toIso8601String(),
    );
  } catch (_) {}
}

Future<void> recordScheduleUpdateWorkerState({
  required String status,
  required String trigger,
  required String task,
  Map<String, Object?> fields = const {},
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _backgroundPollLastStateKey,
      json.encode({
        'at': DateTime.now().toIso8601String(),
        'status': status,
        'trigger': trigger,
        'task': task,
        'fields': fields,
      }),
    );
  } catch (_) {}
}

Future<void> recordScheduleUpdateWorkerSyncState({
  required String status,
  Map<String, Object?> fields = const {},
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _backgroundPollSyncStateKey,
      json.encode({
        'at': DateTime.now().toIso8601String(),
        'status': status,
        'fields': fields,
      }),
    );
  } catch (_) {}
}

Future<void> writeScheduleUpdateWorkerPendingChanges({
  required SharedPreferences prefs,
  required String userId,
  required String yearTerm,
  required List<ScheduleWeekChange> changes,
}) async {
  final payload = json.encode({
    'yearTerm': yearTerm,
    'changes': changes
        .map((e) => {'weekNum': e.weekNum, 'lines': e.lines})
        .toList(),
  });
  await prefs.setString(scheduleUpdateWorkerPendingKeyForUser(userId), payload);
}

DateTime? _parseTime(SharedPreferences prefs, String key) {
  final raw = (prefs.getString(key) ?? '').trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

Map<String, dynamic>? _parseState(SharedPreferences prefs, String key) {
  final raw = (prefs.getString(key) ?? '').trim();
  if (raw.isEmpty) return null;
  try {
    final decoded = json.decode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
