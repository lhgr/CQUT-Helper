import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleRepository {
  ScheduleRepository(this.api);

  static final ScheduleRepository shared = ScheduleRepository(ScheduleApi());

  final ScheduleApi api;
  final Map<String, Future<ScheduleData>> _networkRequests = {};

  Future<ScheduleData> loadFromNetwork({
    required String userId,
    required String encryptedPassword,
    String? weekNum,
    String? yearTerm,
    bool persistLastViewed = true,
    bool updateWidgetPins = false,
  }) async {
    final key = [
      userId.trim(),
      yearTerm?.trim() ?? '',
      weekNum?.trim() ?? '',
      persistLastViewed,
      updateWidgetPins,
    ].join('|');
    final existing = _networkRequests[key];
    if (existing != null) return existing;

    final request = api.loadFromNetwork(
      userId: userId,
      encryptedPassword: encryptedPassword,
      weekNum: weekNum,
      yearTerm: yearTerm,
      persistLastViewed: persistLastViewed,
      updateWidgetPins: updateWidgetPins,
    );
    _networkRequests[key] = request;
    try {
      return await request;
    } finally {
      if (identical(_networkRequests[key], request)) {
        _networkRequests.remove(key);
      }
    }
  }

  Future<bool> isFresh(
    ScheduleData data, {
    Duration maxAge = const Duration(minutes: 15),
  }) async {
    final term = (data.yearTerm ?? '').trim();
    final week = (data.weekNum ?? '').trim();
    if (term.isEmpty || week.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final userId = (prefs.getString('account') ?? '').trim();
    if (userId.isEmpty) return false;
    final fetchedAt = prefs.getInt(
      ScheduleApi.lastFetchAtKey(userId, term, week),
    );
    if (fetchedAt == null || fetchedAt <= 0) return false;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(fetchedAt),
    );
    return !age.isNegative && age <= maxAge;
  }

  int get inFlightCount => _networkRequests.length;
}
