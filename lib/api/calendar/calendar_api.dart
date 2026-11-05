import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/diagnostic_operation.dart';
import 'package:dio/dio.dart';

class AcademicCalendarApiResponse {
  const AcademicCalendarApiResponse({
    this.snapshot,
    required this.notModified,
    this.etag,
    this.requestUri,
    this.diagnosticFields = const {},
  });

  final AcademicCalendarSnapshot? snapshot;
  final bool notModified;
  final String? etag;
  final Uri? requestUri;
  final Map<String, Object?> diagnosticFields;
  String? get operationId => diagnosticFields['trace_id'] as String?;
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
    AppLogger.I.attachToDio(_dio, tag: 'CalendarApi');
  }

  final Dio _dio;
  final String _baseUrl;

  Future<AcademicCalendarApiResponse> fetch({
    required String yearTerm,
    String? etag,
  }) => runDiagnosticOperation(
    'CalendarApi',
    'fetch_calendar',
    () => _fetch(yearTerm: yearTerm, etag: etag),
  );

  Future<AcademicCalendarApiResponse> _fetch({
    required String yearTerm,
    String? etag,
  }) async {
    final diagnostics = AppLogger.I.dioInterceptor(tag: 'CalendarApi');
    final response = await _dio.get<dynamic>(
      '$_baseUrl/api/calendar/term-overrides',
      queryParameters: {'year_term': yearTerm.trim()},
      options: Options(
        extra: {
          'diagnostic_service': 'CalendarApi',
          'diagnostic_validate_response': true,
        },
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
        requestUri: response.requestOptions.uri,
        diagnosticFields: diagnostics.responseContext(response),
      );
    }
    if (response.statusCode != 200) {
      throw DioException.badResponse(
        statusCode: response.statusCode ?? 0,
        requestOptions: response.requestOptions,
        response: response,
      );
    }
    try {
      final body = response.data;
      if (body is! Map) throw const FormatException('校历接口返回格式无效');
      if (body['success'] != true) {
        throw const FormatException('校历接口未返回成功结果');
      }
      final snapshot = AcademicCalendarSnapshot.fromJson(
        body.cast<String, dynamic>(),
      );
      if (!snapshot.complete || snapshot.yearTerm != yearTerm.trim()) {
        throw const FormatException('校历快照不完整或学期不匹配');
      }
      diagnostics.logValidatedResponse(response);
      return AcademicCalendarApiResponse(
        snapshot: snapshot,
        notModified: false,
        etag: responseEtag ?? snapshot.revision,
        requestUri: response.requestOptions.uri,
        diagnosticFields: diagnostics.responseContext(response),
      );
    } catch (error, stackTrace) {
      diagnostics.logValidationFailure(response, error, stackTrace);
      rethrow;
    }
  }

  /// Called after the manager confirms that its cached 304 snapshot is valid.
  void recordValidatedNotModified(AcademicCalendarApiResponse response) {
    final uri = response.requestUri;
    if (!response.notModified || uri == null) return;
    AppLogger.I.logServiceSuccess(
      'CalendarApi',
      service: 'CalendarApi',
      method: 'GET',
      uri: uri,
      statusCode: 304,
      fields: response.diagnosticFields,
    );
  }
}
