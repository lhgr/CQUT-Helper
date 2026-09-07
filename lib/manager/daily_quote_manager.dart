import 'dart:convert';

import 'package:cqut_helper/api/api_service.dart';
import 'package:cqut_helper/model/daily_quote_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DailyQuotePresentation {
  final DailyQuoteConfig config;
  final List<DailyQuoteItem> queue;
  final int index;

  const DailyQuotePresentation({
    required this.config,
    required this.queue,
    required this.index,
  });

  DailyQuoteItem get current => queue[index];
}

class DailyQuoteManager {
  final Future<DailyQuoteConfig> Function() _fetchConfig;
  final Future<SharedPreferences> Function() _prefsProvider;

  DailyQuoteManager({
    Future<DailyQuoteConfig> Function()? fetchConfig,
    Future<SharedPreferences> Function()? prefsProvider,
  }) : _fetchConfig =
           fetchConfig ?? (() => ApiService().dailyQuote.getConfig()),
       _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  static final DailyQuoteManager instance = DailyQuoteManager();

  static const _cacheKey = 'daily_quote_config_v1';
  static const _cacheTimestampKey = 'daily_quote_cache_ts_v1';
  static const _selectedDayKey = 'daily_quote_selected_day_v1';
  static const _selectedIdKey = 'daily_quote_selected_id_v1';
  static const _nextRefreshAtKey = 'daily_quote_next_refresh_at_v1';
  static const _cacheTtl = Duration(minutes: 30);

  Future<DailyQuotePresentation?> loadCached({DateTime? now}) async {
    final prefs = await _prefsProvider();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final config = DailyQuoteConfig.fromJson(decoded.cast<String, dynamic>());
      return await _buildPresentation(config, prefs, now ?? DateTime.now());
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> cachedNextRefreshAt() async {
    final prefs = await _prefsProvider();
    return DateTime.tryParse(prefs.getString(_nextRefreshAtKey) ?? '');
  }

  Future<DailyQuotePresentation?> refresh({
    DateTime? now,
    bool force = false,
  }) async {
    final instant = now ?? DateTime.now();
    final prefs = await _prefsProvider();
    final cachedAt = prefs.getInt(_cacheTimestampKey);
    final nextRefreshAt = DateTime.tryParse(
      prefs.getString(_nextRefreshAtKey) ?? '',
    );
    final reachedScheduledBoundary =
        nextRefreshAt != null &&
        !instant.toUtc().isBefore(nextRefreshAt.toUtc());
    if (!force && cachedAt != null) {
      final age = instant.difference(
        DateTime.fromMillisecondsSinceEpoch(cachedAt),
      );
      if (!age.isNegative && age < _cacheTtl && !reachedScheduledBoundary) {
        return loadCached(now: instant);
      }
    }

    final previous = await loadCached(now: instant);
    final DailyQuoteConfig config;
    try {
      config = await _fetchConfig();
    } catch (_) {
      return previous;
    }
    await prefs.setString(_cacheKey, jsonEncode(config.toJson()));
    await prefs.setInt(_cacheTimestampKey, instant.millisecondsSinceEpoch);
    final nextBoundary = config.nextRefreshAt;
    if (nextBoundary == null) {
      await prefs.remove(_nextRefreshAtKey);
    } else {
      await prefs.setString(_nextRefreshAtKey, nextBoundary.toIso8601String());
    }
    return await _buildPresentation(config, prefs, instant, previous: previous);
  }

  Future<DailyQuotePresentation> selectNext(
    DailyQuotePresentation presentation, {
    DateTime? now,
  }) async {
    final nextIndex = (presentation.index + 1) % presentation.queue.length;
    final next = DailyQuotePresentation(
      config: presentation.config,
      queue: presentation.queue,
      index: nextIndex,
    );
    await _persistSelection(next.current.id, now ?? DateTime.now());
    return next;
  }

  Future<DailyQuotePresentation?> _buildPresentation(
    DailyQuoteConfig config,
    SharedPreferences prefs,
    DateTime now, {
    DailyQuotePresentation? previous,
  }) async {
    final queue = buildDailyQuoteQueue(config, now: now);
    if (queue.isEmpty) return null;

    final day = _dayKey(now);
    final selectedId = prefs.getString(_selectedDayKey) == day
        ? prefs.getString(_selectedIdKey)
        : null;
    var index = selectedId == null
        ? 0
        : queue.indexWhere((item) => item.id == selectedId);
    if (index < 0) index = 0;

    if (previous != null &&
        previous.config.revision != config.revision &&
        queue.first.priority > queue[index].priority) {
      index = 0;
    }
    await _persistSelection(queue[index].id, now);
    return DailyQuotePresentation(config: config, queue: queue, index: index);
  }

  Future<void> _persistSelection(String id, DateTime now) async {
    final prefs = await _prefsProvider();
    await prefs.setString(_selectedDayKey, _dayKey(now));
    await prefs.setString(_selectedIdKey, id);
  }

  String _dayKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
