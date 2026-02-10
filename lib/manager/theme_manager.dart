import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  static const String _themeModeKey = 'theme_mode';
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_themeModeKey);
    if (savedMode != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (e) => e.toString() == savedMode,
        orElse: () => ThemeMode.system,
      );
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
  }
}
