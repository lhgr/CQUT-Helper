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
    
    // 使用最简化的修复拦截器
    _dio.interceptors.add(BasicCookieFixInterceptor());
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

  // getWithRedirects 方法保持不变
}

/// 基础修复，只处理 +0800 时区问题
class BasicCookieFixInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final setCookieHeaders = response.headers['set-cookie'];
    if (setCookieHeaders != null && setCookieHeaders.isNotEmpty) {
      final fixedCookies = <String>[];
      
      for (final cookie in setCookieHeaders) {
        var fixedCookie = cookie;
        
        // 修复 +0800 时区格式
        if (cookie.contains(' +0800')) {
          fixedCookie = cookie.replaceAll(' +0800', ' GMT');
        }
        // 修复 -0800 等其他时区
        else if (cookie.contains(RegExp(r' [+-]\d{4}(?=;|$)'))) {
          fixedCookie = cookie.replaceAll(RegExp(r' [+-]\d{4}(?=;|$)'), ' GMT');
        }
        
        fixedCookies.add(fixedCookie);
      }
      
      response.headers.set('set-cookie', fixedCookies);
    }
    
    handler.next(response);
  }
}
