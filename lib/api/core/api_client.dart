import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  late final Dio _dio;
  late final CookieJar _cookieJar;

  factory ApiClient() => _instance;

  ApiClient._internal() {
    _dio = Dio();
    _cookieJar = CookieJar();
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.options = BaseOptions(
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
        'Accept': 'application/json',
      },
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    );
  }

  Dio get dio => _dio;
  CookieJar get cookieJar => _cookieJar;

  Future<Response<dynamic>> getWithRedirects(String url) async {
    Uri current = Uri.parse(url);
    for (int i = 0; i < 10; i++) {
      final resp = await _dio.getUri(
        current,
        options: Options(followRedirects: false),
      );
      final status = resp.statusCode ?? 0;
      if (status == 301 ||
          status == 302 ||
          status == 303 ||
          status == 307 ||
          status == 308) {
        final location = resp.headers.value('location');
        if (location == null || location.isEmpty) {
          return resp;
        }
        final next = Uri.parse(location);
        current = next.hasScheme ? next : current.resolve(location);
        continue;
      }
      return resp;
    }
    throw Exception('Redirect loop detected');
  }
}
