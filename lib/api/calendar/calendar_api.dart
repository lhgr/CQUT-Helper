import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:dio/dio.dart';

class AcademicCalendarApiResponse {
  const AcademicCalendarApiResponse({
    this.snapshot,
    required this.notModified,
    this.etag,
  });

  final AcademicCalendarSnapshot? snapshot;
  final bool notModified;
  final String? etag;
}

/// Read-only client for the published school calendar snapshot.
class CalendarApi {
  CalendarApi({Dio? dio, String? baseUrl})
    : _dio = dio ?? Dio(),
      _baseUrl = (baseUrl ?? 'https://notice.dawndrizzle.top').replaceFirst(
        RegExp(r'/$'),
        '',
      ) {
    _dio.options = _dio.options.copyWith(
      connectTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    );
  }

  final Dio _dio;
  final String _baseUrl;

  Future<AcademicCalendarApiResponse> fetch({
    required String yearTerm,
    String? etag,
  }) async {
    final response = await _dio.get<dynamic>(
      '$_baseUrl/api/calendar/term-overrides',
      queryParameters: {'year_term': yearTerm.trim()},
      options: Options(
        headers: {
          if (etag != null && etag.trim().isNotEmpty)
            'If-None-Match': etag.trim(),
        },
      ),
    );
    final responseEtag = response.headers.value('etag')?.trim();
    if (response.statusCode == 304) {
      return AcademicCalendarApiResponse(
        notModified: true,
        etag: responseEtag ?? etag,
      );
    }
    if (response.statusCode != 200) {
      throw DioException.badResponse(
        statusCode: response.statusCode ?? 0,
        requestOptions: response.requestOptions,
        response: response,
      );
    }
    final body = response.data;
    if (body is! Map) throw const FormatException('校历接口返回格式无效');
    if (body['success'] != true) {
      throw const FormatException('校历接口未返回成功结果');
    }
    final snapshot = AcademicCalendarSnapshot.fromJson(
      body.cast<String, dynamic>(),
    );
    return AcademicCalendarApiResponse(
      snapshot: snapshot,
      notModified: false,
      etag: responseEtag ?? snapshot.revision,
    );
  }
}
