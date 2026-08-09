import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

enum ScheduleDisplayDensity {
  compact(48),
  comfortable(60),
  spacious(76);

  final double sessionHeight;
  const ScheduleDisplayDensity(this.sessionHeight);
}

class ScheduleSettingsManager {
  static final ValueNotifier<int> experienceEpoch = ValueNotifier<int>(0);
  static final ValueNotifier<int> settingsEpoch = ValueNotifier<int>(0);
  static const String _prefsKeyShowWeekend = 'schedule_show_weekend';
  static const String _prefsKeyTimeInfoEnabled = 'schedule_time_info_enabled';
  static const String backgroundPollingEnabledKey =
      'schedule_background_polling_enabled';
  static const String noticePrivacyConsentVersionKey =
      'schedule_notice_privacy_consent_version';
  static const int currentNoticePrivacyConsentVersion = 1;
  static const String _prefsKeyNoticeApiBaseUrl =
      'schedule_notice_api_base_url';
  static const String remindersEnabledKey = 'schedule_course_reminders_enabled';
  static const String defaultReminderMinutesKey =
      'schedule_default_reminder_minutes';
  static const String displayDensityKey = 'schedule_display_density';
  static const String defaultHomeTabKey = 'schedule_default_home_tab';
  static const String _gridCellWidthKey = 'schedule_grid_cell_width';
  static const String _gridCellHeightKey = 'schedule_grid_cell_height';
  static const String _showGridLinesKey = 'schedule_show_grid_lines';
  static const String _backgroundImagePathKey =
      'schedule_background_image_path';
  static const String _backgroundOpacityKey = 'schedule_background_opacity';
  static const String _backgroundBlurKey = 'schedule_background_blur';
  static const String _hideLocationKey = 'schedule_card_hide_location';
  static const String _hideTeacherKey = 'schedule_card_hide_teacher';
  static const String _removeCampusPrefixKey =
      'schedule_card_remove_campus_prefix';
  static const String _horizontalCenterKey = 'schedule_card_horizontal_center';
  static const String _verticalCenterKey = 'schedule_card_vertical_center';
  static const String _cardRadiusKey = 'schedule_card_radius';
  static const String _cardTextScaleKey = 'schedule_card_text_scale';
  static const String officialNoticeApiBaseUrl =
      'https://notice.dawndrizzle.top';

  bool showWeekend = false;
  bool timeInfoEnabled = true;
  bool backgroundPollingEnabled = false;
  String noticeApiBaseUrl = officialNoticeApiBaseUrl;
  bool remindersEnabled = false;
  int defaultReminderMinutes = 10;
  ScheduleDisplayDensity displayDensity = ScheduleDisplayDensity.comfortable;
  ScheduleLayoutSettings layoutSettings = const ScheduleLayoutSettings();
  int defaultHomeTab = 1;

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
    remindersEnabled = prefs.getBool(remindersEnabledKey) ?? false;
    defaultReminderMinutes = (prefs.getInt(defaultReminderMinutesKey) ?? 10)
        .clamp(0, 120);
    final densityName = prefs.getString(displayDensityKey);
    displayDensity = ScheduleDisplayDensity.values.firstWhere(
      (value) => value.name == densityName,
      orElse: () => ScheduleDisplayDensity.comfortable,
    );
    layoutSettings = ScheduleLayoutSettings(
      gridCellWidth: (prefs.getDouble(_gridCellWidthKey) ?? 52)
          .clamp(
            ScheduleLayoutSettings.minGridCellWidth,
            ScheduleLayoutSettings.maxGridCellWidth,
          )
          .toDouble(),
      gridCellHeight:
          (prefs.getDouble(_gridCellHeightKey) ?? displayDensity.sessionHeight)
              .clamp(
                ScheduleLayoutSettings.minGridCellHeight,
                ScheduleLayoutSettings.maxGridCellHeight,
              )
              .toDouble(),
      showGridLines: prefs.getBool(_showGridLinesKey) ?? true,
      backgroundImagePath: prefs.getString(_backgroundImagePathKey),
      backgroundOpacity: (prefs.getDouble(_backgroundOpacityKey) ?? 0.32)
          .clamp(0.0, 1.0)
          .toDouble(),
      backgroundBlur: (prefs.getDouble(_backgroundBlurKey) ?? 0)
          .clamp(0.0, 20.0)
          .toDouble(),
      hideLocation: prefs.getBool(_hideLocationKey) ?? false,
      hideTeacher: prefs.getBool(_hideTeacherKey) ?? false,
      removeCampusPrefix: prefs.getBool(_removeCampusPrefixKey) ?? false,
      horizontalCenter: prefs.getBool(_horizontalCenterKey) ?? false,
      verticalCenter: prefs.getBool(_verticalCenterKey) ?? false,
      cardRadius: (prefs.getDouble(_cardRadiusKey) ?? 12)
          .clamp(0.0, 28.0)
          .toDouble(),
      textScale: (prefs.getDouble(_cardTextScaleKey) ?? 1)
          .clamp(0.7, 1.5)
          .toDouble(),
    );
    defaultHomeTab = (prefs.getInt(defaultHomeTabKey) ?? 1).clamp(0, 2);
  }

  Future<void> saveExperienceSettings({
    required bool remindersEnabled,
    required int defaultReminderMinutes,
    required ScheduleDisplayDensity displayDensity,
    required int defaultHomeTab,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    this.remindersEnabled = remindersEnabled;
    this.defaultReminderMinutes = defaultReminderMinutes.clamp(0, 120);
    this.displayDensity = displayDensity;
    this.defaultHomeTab = defaultHomeTab.clamp(0, 2);
    await prefs.setBool(remindersEnabledKey, this.remindersEnabled);
    await prefs.setInt(defaultReminderMinutesKey, this.defaultReminderMinutes);
    await prefs.setString(displayDensityKey, displayDensity.name);
    await prefs.setInt(defaultHomeTabKey, this.defaultHomeTab);
    experienceEpoch.value++;
    settingsEpoch.value++;
  }

  Future<void> saveLayoutSettings(ScheduleLayoutSettings value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value.normalized();
    layoutSettings = normalized;
    await prefs.setDouble(_gridCellWidthKey, normalized.gridCellWidth);
    await prefs.setDouble(_gridCellHeightKey, normalized.gridCellHeight);
    await prefs.setBool(_showGridLinesKey, normalized.showGridLines);
    final backgroundPath = normalized.backgroundImagePath?.trim();
    if (backgroundPath == null || backgroundPath.isEmpty) {
      await prefs.remove(_backgroundImagePathKey);
    } else {
      await prefs.setString(_backgroundImagePathKey, backgroundPath);
    }
    await prefs.setDouble(_backgroundOpacityKey, normalized.backgroundOpacity);
    await prefs.setDouble(_backgroundBlurKey, normalized.backgroundBlur);
    await prefs.setBool(_hideLocationKey, normalized.hideLocation);
    await prefs.setBool(_hideTeacherKey, normalized.hideTeacher);
    await prefs.setBool(_removeCampusPrefixKey, normalized.removeCampusPrefix);
    await prefs.setBool(_horizontalCenterKey, normalized.horizontalCenter);
    await prefs.setBool(_verticalCenterKey, normalized.verticalCenter);
    await prefs.setDouble(_cardRadiusKey, normalized.cardRadius);
    await prefs.setDouble(_cardTextScaleKey, normalized.textScale);
    settingsEpoch.value++;
  }

  Future<void> save({
    required bool showWeekend,
    required bool timeInfoEnabled,
    required bool backgroundPollingEnabled,
    required String noticeApiBaseUrl,
    bool notify = true,
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
    if (notify) settingsEpoch.value++;
  }
}

@immutable
class ScheduleLayoutSettings {
  static const double minGridCellWidth = 40;
  static const double maxGridCellWidth = 96;
  static const double minGridCellHeight = 40;
  static const double maxGridCellHeight = 96;

  final double gridCellWidth;
  final double gridCellHeight;
  final bool showGridLines;
  final String? backgroundImagePath;
  final double backgroundOpacity;
  final double backgroundBlur;
  final bool hideLocation;
  final bool hideTeacher;
  final bool removeCampusPrefix;
  final bool horizontalCenter;
  final bool verticalCenter;
  final double cardRadius;
  final double textScale;

  const ScheduleLayoutSettings({
    this.gridCellWidth = 52,
    this.gridCellHeight = 60,
    this.showGridLines = true,
    this.backgroundImagePath,
    this.backgroundOpacity = 0.32,
    this.backgroundBlur = 0,
    this.hideLocation = false,
    this.hideTeacher = false,
    this.removeCampusPrefix = false,
    this.horizontalCenter = false,
    this.verticalCenter = false,
    this.cardRadius = 12,
    this.textScale = 1,
  });

  ScheduleLayoutSettings copyWith({
    double? gridCellWidth,
    double? gridCellHeight,
    bool? showGridLines,
    String? backgroundImagePath,
    bool clearBackgroundImage = false,
    double? backgroundOpacity,
    double? backgroundBlur,
    bool? hideLocation,
    bool? hideTeacher,
    bool? removeCampusPrefix,
    bool? horizontalCenter,
    bool? verticalCenter,
    double? cardRadius,
    double? textScale,
  }) {
    return ScheduleLayoutSettings(
      gridCellWidth: gridCellWidth ?? this.gridCellWidth,
      gridCellHeight: gridCellHeight ?? this.gridCellHeight,
      showGridLines: showGridLines ?? this.showGridLines,
      backgroundImagePath: clearBackgroundImage
          ? null
          : backgroundImagePath ?? this.backgroundImagePath,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      hideLocation: hideLocation ?? this.hideLocation,
      hideTeacher: hideTeacher ?? this.hideTeacher,
      removeCampusPrefix: removeCampusPrefix ?? this.removeCampusPrefix,
      horizontalCenter: horizontalCenter ?? this.horizontalCenter,
      verticalCenter: verticalCenter ?? this.verticalCenter,
      cardRadius: cardRadius ?? this.cardRadius,
      textScale: textScale ?? this.textScale,
    );
  }

  ScheduleLayoutSettings normalized() => copyWith(
    gridCellWidth: gridCellWidth
        .clamp(minGridCellWidth, maxGridCellWidth)
        .toDouble(),
    gridCellHeight: gridCellHeight
        .clamp(minGridCellHeight, maxGridCellHeight)
        .toDouble(),
    backgroundOpacity: backgroundOpacity.clamp(0.0, 1.0).toDouble(),
    backgroundBlur: backgroundBlur.clamp(0.0, 20.0).toDouble(),
    cardRadius: cardRadius.clamp(0.0, 28.0).toDouble(),
    textScale: textScale.clamp(0.7, 1.5).toDouble(),
    backgroundImagePath: backgroundImagePath?.trim(),
  );
}
