import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/widget_updater.dart';

class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  static const String _themeModeKey = 'theme_mode';
  static const String _isSystemColorKey = 'is_system_color';
  static const String _customColorKey = 'custom_color';

  ThemeMode _themeMode = ThemeMode.system;
  bool _isSystemColor = true;
  Color _customColor = Colors.blue;

  ThemeMode get themeMode => _themeMode;
  bool get isSystemColor => _isSystemColor;
  Color get customColor => _customColor;

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
    if (savedColor != null) {
      _customColor = Color(savedColor);
    }
    notifyListeners();
    await WidgetUpdater.updateTodayWidget(
      themeMode: _widgetModeValue(_themeMode),
      trigger: 'init',
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (kDebugMode) {
      debugPrint('ThemeManager: setThemeMode called with $mode');
    }
    if (_themeMode == mode) {
      if (kDebugMode) {
        debugPrint('ThemeManager: mode is already $mode, ignoring');
      }
      return;
    }
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    final modeText = _persistedModeValue(mode);
    await prefs.setString(_themeModeKey, modeText);
    if (kDebugMode) {
      debugPrint('ThemeManager: notifying listeners. New mode: $_themeMode');
    }
    notifyListeners();
    await WidgetUpdater.updateTodayWidget(
      themeMode: _widgetModeValue(mode),
      trigger: 'app_theme_changed',
    );
  }

  Future<void> setSystemColor(bool isSystem) async {
    if (_isSystemColor == isSystem) return;
    _isSystemColor = isSystem;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isSystemColorKey, isSystem);
  }

  Future<void> setCustomColor(Color color) async {
    if (_customColor == color) return;
    _customColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_customColorKey, color.toARGB32());
  }
}
