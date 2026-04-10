import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CourseColorAssignmentManager {
  CourseColorAssignmentManager._();

  static final CourseColorAssignmentManager instance =
      CourseColorAssignmentManager._();

  static const String _prefsKeyPrefix = 'schedule_course_color_map_v1';
  static const String _anonymousScope = 'anonymous';

  final Map<String, Map<String, int>> _cacheByScope = {};
  final Set<String> _loadedScopes = {};
  String? _accountCache;

  Future<Map<String, int>> assignForCourses({
    required String term,
    required Iterable<String> courseKeys,
    required int paletteSize,
  }) async {
    if (paletteSize <= 0) {
      return <String, int>{};
    }
    final scope = await _buildScope(term);
    final scopedMap = await _ensureScopeLoaded(scope);
    var changed = false;
    final usedColors = scopedMap.values.toSet();

    for (final key in courseKeys) {
      final normalizedKey = key.trim();
      if (normalizedKey.isEmpty || scopedMap.containsKey(normalizedKey)) {
        continue;
      }
      final colorIndex = _pickColorIndex(
        usedColors,
        paletteSize,
        scopedMap.length,
      );
      scopedMap[normalizedKey] = colorIndex;
      usedColors.add(colorIndex);
      changed = true;
    }

    if (changed) {
      await _saveScope(scope, scopedMap);
    }
    return Map<String, int>.from(scopedMap);
  }

  Map<String, int> getCachedAssignments(String term) {
    final normalizedTerm = term.trim();
    final account = (_accountCache ?? _anonymousScope).trim();
    final scope = '$account|$normalizedTerm';
    final cached = _cacheByScope[scope];
    if (cached == null) {
      return <String, int>{};
    }
    return Map<String, int>.from(cached);
  }

  Future<String> _buildScope(String term) async {
    if (_accountCache == null) {
      final prefs = await SharedPreferences.getInstance();
      final account = (prefs.getString('account') ?? '').trim();
      _accountCache = account.isEmpty ? _anonymousScope : account;
    }
    return '${_accountCache!}|${term.trim()}';
  }

  Future<Map<String, int>> _ensureScopeLoaded(String scope) async {
    if (_loadedScopes.contains(scope)) {
      return _cacheByScope[scope] ?? <String, int>{};
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey(scope));
    final map = <String, int>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key is String && value is num) {
              map[key] = value.toInt();
            }
          });
        }
      } catch (_) {}
    }
    _cacheByScope[scope] = map;
    _loadedScopes.add(scope);
    return map;
  }

  Future<void> _saveScope(String scope, Map<String, int> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey(scope), jsonEncode(map));
  }

  String _prefsKey(String scope) => '${_prefsKeyPrefix}_$scope';

  int _pickColorIndex(Set<int> usedColors, int paletteSize, int assignedCount) {
    for (var i = 0; i < paletteSize; i++) {
      if (!usedColors.contains(i)) {
        return i;
      }
    }
    return assignedCount % paletteSize;
  }
}
