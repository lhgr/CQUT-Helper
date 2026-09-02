import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'schedule_settings_manager.dart';
import '../utils/app_logger.dart';
import '../utils/widget_updater.dart';

enum ThemeColorSource { system, scheduleBackground, custom }

class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  static const String _themeModeKey = 'theme_mode';
  static const String _isSystemColorKey = 'is_system_color';
  static const String _customColorKey = 'custom_color';
  static const String _colorSourceKey = 'theme_color_source';
  static const String _scheduleBackgroundColorKey =
      'schedule_background_theme_color';
  static const String _wingColorUnlockedKey = 'wing_color_unlocked';
  static const String _predictiveBackDisabledKey =
      'predictive_back_gesture_disabled';

  static const Color wingColor = Color(0xFFFF98A1);

  ThemeMode _themeMode = ThemeMode.system;
  bool _isSystemColor = true;
  Color _customColor = Colors.blue;
  ThemeColorSource _colorSource = ThemeColorSource.system;
  Color? _scheduleBackgroundColor;
  bool _hasScheduleBackground = false;
  bool _wingColorUnlocked = false;
  bool _predictiveBackDisabled = false;

  ThemeMode get themeMode => _themeMode;
  bool get isSystemColor => _colorSource == ThemeColorSource.system;
  Color get customColor => _customColor;
  ThemeColorSource get colorSource => _colorSource;
  Color? get scheduleBackgroundColor => _scheduleBackgroundColor;
  bool get wingColorUnlocked => _wingColorUnlocked;
  bool get predictiveBackDisabled => _predictiveBackDisabled;
  bool get canUseScheduleBackgroundColor =>
      _hasScheduleBackground && _scheduleBackgroundColor != null;
  Color get activeSeedColor =>
      _colorSource == ThemeColorSource.scheduleBackground &&
          _scheduleBackgroundColor != null
      ? _scheduleBackgroundColor!
      : _customColor;

  String _persistedModeValue(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  ThemeMode _parsePersistedMode(String? raw) {
    switch (raw) {
      case 'light':
      case 'ThemeMode.light':
        return ThemeMode.light;
      case 'dark':
      case 'ThemeMode.dark':
        return ThemeMode.dark;
      case 'system':
      case 'ThemeMode.system':
        return ThemeMode.system;
      default:
        return ThemeMode.system;
    }
  }

  String _widgetModeValue(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_themeModeKey);
    _themeMode = _parsePersistedMode(savedMode);

    _isSystemColor = prefs.getBool(_isSystemColorKey) ?? true;
    final savedColor = prefs.getInt(_customColorKey);
    _customColor = savedColor == null ? Colors.blue : Color(savedColor);
    _wingColorUnlocked = prefs.getBool(_wingColorUnlockedKey) ?? false;
    _predictiveBackDisabled =
        prefs.getBool(_predictiveBackDisabledKey) ?? false;
    final savedBackgroundColor = prefs.getInt(_scheduleBackgroundColorKey);
    _scheduleBackgroundColor = savedBackgroundColor == null
        ? null
        : Color(savedBackgroundColor);
    _hasScheduleBackground =
        (prefs.getString(ScheduleSettingsManager.backgroundImagePathKey) ?? '')
            .trim()
            .isNotEmpty;
    final sourceName = prefs.getString(_colorSourceKey);
    _colorSource = ThemeColorSource.values.firstWhere(
      (source) => source.name == sourceName,
      orElse: () =>
          _isSystemColor ? ThemeColorSource.system : ThemeColorSource.custom,
    );
    if (_colorSource == ThemeColorSource.scheduleBackground &&
        !canUseScheduleBackgroundColor) {
      _colorSource = ThemeColorSource.system;
      _scheduleBackgroundColor = null;
      await _persistColorSelection(prefs);
    }
    _isSystemColor = isSystemColor;
    notifyListeners();
    await WidgetUpdater.updateTodayWidget(
      themeMode: _widgetModeValue(_themeMode),
      trigger: 'init',
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (kDebugMode) {
      AppLogger.I.event(
        LogLevel.debug,
        'ThemeManager',
        event: 'ui_theme_change_start',
        messageZh: '开始切换主题模式',
        message: 'set theme mode requested',
        module: 'ui',
        action: 'change_theme',
        status: 'start',
        fields: {'target_mode': mode.name},
      );
    }
    if (_themeMode == mode) {
      if (kDebugMode) {
        AppLogger.I.event(
          LogLevel.debug,
          'ThemeManager',
          event: 'ui_theme_change_skip',
          messageZh: '主题模式未变化，跳过更新',
          message: 'theme mode unchanged',
          module: 'ui',
          action: 'change_theme',
          status: 'skip',
          reason: 'same_mode',
          fields: {'mode': mode.name},
        );
      }
      return;
    }
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    final modeText = _persistedModeValue(mode);
    await prefs.setString(_themeModeKey, modeText);
    if (kDebugMode) {
      AppLogger.I.event(
        LogLevel.debug,
        'ThemeManager',
        event: 'ui_theme_change_ok',
        messageZh: '主题模式切换完成',
        message: 'theme mode updated',
        module: 'ui',
        action: 'change_theme',
        status: 'ok',
        fields: {'new_mode': _themeMode.name},
      );
    }
    notifyListeners();
    await WidgetUpdater.updateTodayWidget(
      themeMode: _widgetModeValue(mode),
      trigger: 'app_theme_changed',
    );
  }

  Future<void> setSystemColor(bool isSystem) async {
    await setColorSource(
      isSystem ? ThemeColorSource.system : ThemeColorSource.custom,
    );
  }

  Future<bool> setColorSource(ThemeColorSource source) async {
    if (source == ThemeColorSource.scheduleBackground &&
        !canUseScheduleBackgroundColor) {
      return false;
    }
    if (_colorSource == source) return true;
    _colorSource = source;
    _isSystemColor = isSystemColor;
    final prefs = await SharedPreferences.getInstance();
    await _persistColorSelection(prefs);
    notifyListeners();
    return true;
  }

  Future<void> setCustomColor(Color color) async {
    final changed =
        _customColor != color || _colorSource != ThemeColorSource.custom;
    _customColor = color;
    _colorSource = ThemeColorSource.custom;
    _isSystemColor = false;
    final prefs = await SharedPreferences.getInstance();
    await _persistColorSelection(prefs);
    if (changed) notifyListeners();
  }

  Future<bool> unlockWingColor() async {
    if (_wingColorUnlocked) return false;
    _wingColorUnlocked = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wingColorUnlockedKey, true);
    notifyListeners();
    return true;
  }

  Future<void> setPredictiveBackDisabled(bool disabled) async {
    if (_predictiveBackDisabled == disabled) return;
    _predictiveBackDisabled = disabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_predictiveBackDisabledKey, disabled);
    notifyListeners();
  }

  Future<void> applyScheduleBackgroundColor(Color color) async {
    _scheduleBackgroundColor = color;
    _hasScheduleBackground = true;
    _colorSource = ThemeColorSource.scheduleBackground;
    _isSystemColor = false;
    final prefs = await SharedPreferences.getInstance();
    await _persistColorSelection(prefs);
    notifyListeners();
  }

  Future<void> clearScheduleBackgroundColor() async {
    _colorSource = ThemeColorSource.system;
    _scheduleBackgroundColor = null;
    _hasScheduleBackground = false;
    _isSystemColor = isSystemColor;
    final prefs = await SharedPreferences.getInstance();
    await _persistColorSelection(prefs);
    notifyListeners();
  }

  Future<void> invalidateScheduleBackgroundColor() async {
    if (_colorSource == ThemeColorSource.scheduleBackground) {
      _colorSource = ThemeColorSource.system;
    }
    _scheduleBackgroundColor = null;
    _hasScheduleBackground = true;
    _isSystemColor = isSystemColor;
    final prefs = await SharedPreferences.getInstance();
    await _persistColorSelection(prefs);
    notifyListeners();
  }

  Future<void> _persistColorSelection(SharedPreferences prefs) async {
    await prefs.setString(_colorSourceKey, _colorSource.name);
    await prefs.setBool(_isSystemColorKey, isSystemColor);
    await prefs.setInt(_customColorKey, _customColor.toARGB32());
    final backgroundColor = _scheduleBackgroundColor;
    if (backgroundColor == null) {
      await prefs.remove(_scheduleBackgroundColorKey);
    } else {
      await prefs.setInt(
        _scheduleBackgroundColorKey,
        backgroundColor.toARGB32(),
      );
    }
  }
}
