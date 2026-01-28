import 'package:dio/dio.dart';
import 'package:cqut/model/github_item.dart';

class GithubApi {
  static const String _baseUrl = 'https://api.github.com';
  static const String _owner = 'Royfor12';
  static const String _repo = 'CQUT-Course-Guide-Sharing-Scheme';

  final Dio _dio = Dio();

  final Map<String, List<GithubItem>> _cache = {};

  Future<List<GithubItem>> getContents(String path) async {
    // 移除 path 开头的斜杠
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;

    // 检查缓存
    if (_cache.containsKey(cleanPath)) {
      return _cache[cleanPath]!;
    }

    try {
      final String url;
      if (cleanPath.isEmpty) {
        url = '$_baseUrl/repos/$_owner/$_repo/contents';
      } else {
        url = '$_baseUrl/repos/$_owner/$_repo/contents/$cleanPath';
      }

      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        final items = data.map((json) => GithubItem.fromJson(json)).toList();

        // 存入缓存
        _cache[cleanPath] = items;
        return items;
      } else {
        throw Exception('Failed to load contents: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load contents: $e');
    }
  }
}
