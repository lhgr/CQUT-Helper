import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:intl/intl.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  late final Dio _dio;
  late final CookieJar _cookieJar;

  factory ApiClient() => _instance;

  ApiClient._internal() {
    _dio = Dio();
    _cookieJar = CookieJar();
    
    // 先添加我们的自定义拦截器，再添加 CookieManager
    _dio.interceptors.add(CookieDateFixInterceptor());
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

/// 修复 Cookie 中非标准日期格式的问题
class CookieDateFixInterceptor extends Interceptor {
  static final List<DateFormat> _dateFormats = [
    // RFC 1123: Fri, 27 Feb 2026 22:42:43 +0800
    DateFormat('EEE, dd MMM yyyy HH:mm:ss Z', 'en_US'),
    // RFC 850: Friday, 27-Feb-26 22:42:43 GMT
    DateFormat('EEEE, dd-MMM-yy HH:mm:ss z', 'en_US'),
    // asctime: Fri Feb 27 22:42:43 2026
    DateFormat('EEE MMM dd HH:mm:ss yyyy', 'en_US'),
    // RFC 1123 without timezone: Fri, 27 Feb 2026 22:42:43 GMT
    DateFormat('EEE, dd MMM yyyy HH:mm:ss z', 'en_US'),
  ];

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    try {
      final setCookieHeaders = response.headers['set-cookie'];
      if (setCookieHeaders != null && setCookieHeaders.isNotEmpty) {
        final fixedCookies = <String>[];
        
        for (final cookie in setCookieHeaders) {
          fixedCookies.add(_fixCookieDate(cookie));
        }
        
        // 更新响应头
        response.headers.set('set-cookie', fixedCookies);
      }
    } catch (e) {
      print('CookieDateFixInterceptor error: $e');
      // 不抛出异常，继续处理
    }
    
    handler.next(response);
  }

  String _fixCookieDate(String cookie) {
    // 查找 expires= 部分
    final expiresRegex = RegExp(r'expires=([^;]+)', caseSensitive: false);
    final match = expiresRegex.firstMatch(cookie);
    
    if (match == null) {
      return cookie; // 没有 expires 属性，直接返回
    }
    
    final originalDateStr = match.group(1)!;
    String fixedDateStr = originalDateStr;
    
    try {
      // 尝试解析日期
      DateTime? parsedDate;
      
      // 首先尝试直接解析
      try {
        parsedDate = DateTime.parse(originalDateStr.replaceAll(' GMT', ''));
      } catch (_) {}
      
      // 如果直接解析失败，尝试使用各种格式
      if (parsedDate == null) {
        for (final format in _dateFormats) {
          try {
            parsedDate = format.parse(originalDateStr);
            break;
          } catch (_) {}
        }
      }
      
      // 如果解析成功，格式化为标准 GMT 时间
      if (parsedDate != null) {
        // 转换为 UTC/GMT
        final gmtDate = parsedDate.toUtc();
        fixedDateStr = DateFormat('EEE, dd MMM yyyy HH:mm:ss').format(gmtDate) + ' GMT';
      } else {
        // 如果所有解析都失败，使用更激进的方法
        fixedDateStr = _forceFixDate(originalDateStr);
      }
    } catch (e) {
      print('Failed to parse cookie date "$originalDateStr": $e');
      // 如果解析失败，使用保守的修复方法
      fixedDateStr = _forceFixDate(originalDateStr);
    }
    
    // 替换原始 expires 值
    return cookie.replaceFirst(
      'expires=$originalDateStr',
      'expires=$fixedDateStr',
      match.start,
    );
  }

  String _forceFixDate(String dateStr) {
    // 移除时区偏移，直接添加 GMT
    return dateStr.replaceAll(RegExp(r'\s*[+-]\d{4}'), '').trim() + ' GMT';
  }
}
