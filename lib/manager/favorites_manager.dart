import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class FavoriteItem {
  final String title;
  final String path;
  final String type; // 'dir' or 'file'
  final String subtitle;

  FavoriteItem({
    required this.title,
    required this.path,
    required this.type,
    this.subtitle = '',
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'path': path,
    'type': type,
    'subtitle': subtitle,
  };

  factory FavoriteItem.fromJson(Map<String, dynamic> json) => FavoriteItem(
    title: json['title'],
    path: json['path'],
    type: json['type'],
    subtitle: json['subtitle'] ?? '',
  );
}

class FavoritesManager extends ChangeNotifier {
  static final FavoritesManager _instance = FavoritesManager._internal();
  factory FavoritesManager() => _instance;
  FavoritesManager._internal();

  String? _userId;
  
  String get _key {
    if (_userId == null || _userId!.isEmpty) {
      return 'repo_favorites_guest'; 
    }
    return 'repo_favorites_$_userId';
  }

  List<FavoriteItem> _favorites = [];

  List<FavoriteItem> get favorites => _favorites;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('account');
    
    final String? jsonString = prefs.getString(_key);
    if (jsonString != null) {
      final List<dynamic> jsonList = json.decode(jsonString);
      _favorites = jsonList.map((e) => FavoriteItem.fromJson(e)).toList();
    } else {
      _favorites = [];
    }
    notifyListeners();
  }

  Future<void> addFavorite(FavoriteItem item) async {
    if (isFavorite(item.path)) return;
    _favorites.add(item);
    await _save();
    notifyListeners();
  }

  Future<void> removeFavorite(String path) async {
    _favorites.removeWhere((item) => item.path == path);
    await _save();
    notifyListeners();
  }

  bool isFavorite(String path) {
    return _favorites.any((item) => item.path == path);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = json.encode(
      _favorites.map((e) => e.toJson()).toList(),
    );
    await prefs.setString(_key, jsonString);
  }
}
