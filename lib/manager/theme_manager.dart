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

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_themeModeKey);
    if (savedMode != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (e) => e.toString() == savedMode,
        orElse: () => ThemeMode.system,
      );
    }

    _isSystemColor = prefs.getBool(_isSystemColorKey) ?? true;
    final savedColor = prefs.getInt(_customColorKey);
    if (savedColor != null) {
      _customColor = Color(savedColor);
    }
    notifyListeners();
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
    if (kDebugMode) {
      debugPrint('ThemeManager: notifying listeners. New mode: $_themeMode');
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.toString());
    await WidgetUpdater.updateTodayWidget();
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
