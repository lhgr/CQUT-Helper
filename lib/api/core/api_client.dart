import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  late final Dio _dio;
  late final CookieJar _cookieJar;

  factory ApiClient() => _instance;

  ApiClient._internal() {
    _dio = Dio();
    _cookieJar = CookieJar();
    
    // 关键：先添加 CookieFixInterceptor，再添加 CookieManager
    // 这样 CookieFixInterceptor 会先修复 Cookie，然后 CookieManager 再处理修复后的 Cookie
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
  
  Future<Response<dynamic>> get(String url, {Map<String, dynamic>? queryParameters}) async {
    return await _dio.get(url, queryParameters: queryParameters);
  }
  
  Future<Response<dynamic>> post(String url, {dynamic data}) async {
    return await _dio.post(url, data: data);
  }
}

/// 基础修复，只处理 +0800 时区问题
class BasicCookieFixInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    try {
      final setCookieHeaders = response.headers['set-cookie'];
      if (setCookieHeaders != null && setCookieHeaders.isNotEmpty) {
        final fixedCookies = <String>[];
        
        for (final cookie in setCookieHeaders) {
          var fixedCookie = cookie;
          
          // 修复特定格式：Fri, 27 Feb 2026 22:42:43 +0800
          // 使用更精确的正则，只匹配 expires= 后面的日期
          fixedCookie = _fixExpiresDate(fixedCookie);
          
          fixedCookies.add(fixedCookie);
        }
        
        // 更新响应头
        response.headers.set('set-cookie', fixedCookies);
        
        // 调试输出
        if (setCookieHeaders.length != fixedCookies.length) {
          if (kDebugMode) {
            debugPrint('CookieFix: Fixed ${setCookieHeaders.length} cookies');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CookieFixInterceptor error: $e');
      }
      // 不要抛出异常，继续处理
    }
    
    handler.next(response);
  }
  
  String _fixExpiresDate(String cookie) {
    // 使用正则表达式查找 expires= 后面的日期部分
    final expiresRegex = RegExp(r'expires=([^;]+)', caseSensitive: false);
    
    return cookie.replaceAllMapped(expiresRegex, (match) {
      final dateStr = match.group(1)!;
      var fixedDate = dateStr;
      
      // 检查是否是 +0800 格式
      if (dateStr.contains(' +0800')) {
        fixedDate = dateStr.replaceAll(' +0800', ' GMT');
        if (kDebugMode) {
          debugPrint('CookieFix: Fixed +0800 timezone: $dateStr -> $fixedDate');
        }
      }
      // 检查其他时区偏移
      else if (dateStr.contains(RegExp(r' [+-]\d{4}$'))) {
        fixedDate = dateStr.replaceAll(RegExp(r' [+-]\d{4}$'), ' GMT');
        if (kDebugMode) {
          debugPrint('CookieFix: Fixed timezone offset: $dateStr -> $fixedDate');
        }
      }
      
      return 'expires=$fixedDate';
    });
  }
}
