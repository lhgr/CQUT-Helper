import 'package:shared_preferences/shared_preferences.dart';

class ScheduleSettingsManager {
  static const String _prefsKeyShowWeekend = 'schedule_show_weekend';
  static const String _prefsKeyTimeInfoEnabled = 'schedule_time_info_enabled';
  static const String backgroundPollingEnabledKey =
      'schedule_background_polling_enabled';
  static const String noticePrivacyConsentVersionKey =
      'schedule_notice_privacy_consent_version';
  static const int currentNoticePrivacyConsentVersion = 1;
  static const String _prefsKeyNoticeApiBaseUrl =
      'schedule_notice_api_base_url';
  static const String officialNoticeApiBaseUrl =
      'https://notice.dawndrizzle.top';

  bool showWeekend = false;
  bool timeInfoEnabled = true;
  bool backgroundPollingEnabled = false;
  String noticeApiBaseUrl = officialNoticeApiBaseUrl;

  static String normalizeNoticeApiBaseUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return officialNoticeApiBaseUrl;
    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        !parsed.hasScheme ||
        parsed.scheme != 'https' ||
        (parsed.host.isEmpty && !parsed.hasAuthority) ||
        (parsed.path.isNotEmpty && parsed.path != '/')) {
      return officialNoticeApiBaseUrl;
    }
    final normalized = parsed.replace(path: '', query: null, fragment: null);
    final text = normalized.toString();
    return text.endsWith('/') ? text.substring(0, text.length - 1) : text;
  }

  static bool isValidNoticeApiBaseUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return false;
    final parsed = Uri.tryParse(value);
    if (parsed == null) return false;
    if (parsed.scheme != 'https') return false;
    if (parsed.host.isEmpty && !parsed.hasAuthority) return false;
    if (parsed.path.isNotEmpty && parsed.path != '/') return false;
    if (parsed.query.isNotEmpty || parsed.fragment.isNotEmpty) return false;
    return true;
  }

  static Future<String> loadNoticeApiBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyNoticeApiBaseUrl) ?? '';
    if (!isValidNoticeApiBaseUrl(raw)) {
      return officialNoticeApiBaseUrl;
    }
    return normalizeNoticeApiBaseUrl(raw);
  }

  static bool isNoticeEnhancementEnabledIn(SharedPreferences prefs) {
    final enabled = prefs.getBool(backgroundPollingEnabledKey) ?? false;
    final consentVersion = prefs.getInt(noticePrivacyConsentVersionKey) ?? 0;
    return enabled && consentVersion >= currentNoticePrivacyConsentVersion;
  }

  static Future<bool> isNoticeEnhancementEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return isNoticeEnhancementEnabledIn(prefs);
  }

  static Future<void> markNoticePrivacyConsentAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      noticePrivacyConsentVersionKey,
      currentNoticePrivacyConsentVersion,
    );
  }

  static Future<void> disableNoticeEnhancementForLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(backgroundPollingEnabledKey, false);
    await prefs.remove(noticePrivacyConsentVersionKey);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    showWeekend = prefs.getBool(_prefsKeyShowWeekend) ?? false;
    timeInfoEnabled = prefs.getBool(_prefsKeyTimeInfoEnabled) ?? true;
    final wasPreviouslyEnabled =
        prefs.getBool(backgroundPollingEnabledKey) ?? false;
    backgroundPollingEnabled = isNoticeEnhancementEnabledIn(prefs);
    if (wasPreviouslyEnabled && !backgroundPollingEnabled) {
      await prefs.setBool(backgroundPollingEnabledKey, false);
    }
    final savedBaseUrl = prefs.getString(_prefsKeyNoticeApiBaseUrl) ?? '';
    noticeApiBaseUrl = isValidNoticeApiBaseUrl(savedBaseUrl)
        ? normalizeNoticeApiBaseUrl(savedBaseUrl)
        : officialNoticeApiBaseUrl;
  }

  Future<void> save({
    required bool showWeekend,
    required bool timeInfoEnabled,
    required bool backgroundPollingEnabled,
    required String noticeApiBaseUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    this.showWeekend = showWeekend;
    this.timeInfoEnabled = timeInfoEnabled;
    this.backgroundPollingEnabled = backgroundPollingEnabled;
    this.noticeApiBaseUrl = normalizeNoticeApiBaseUrl(noticeApiBaseUrl);

    await prefs.setBool(_prefsKeyShowWeekend, showWeekend);
    await prefs.setBool(_prefsKeyTimeInfoEnabled, timeInfoEnabled);
    await prefs.remove('schedule_update_show_diff');
    await prefs.setBool(backgroundPollingEnabledKey, backgroundPollingEnabled);
    await prefs.setString(_prefsKeyNoticeApiBaseUrl, this.noticeApiBaseUrl);
  }
}
