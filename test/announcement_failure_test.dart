import 'package:cqut_helper/manager/announcement_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DioException dioError({required DioExceptionType type, int? statusCode}) {
    final request = RequestOptions(path: '/announcements');
    return DioException(
      requestOptions: request,
      type: type,
      response: statusCode == null
          ? null
          : Response<void>(requestOptions: request, statusCode: statusCode),
    );
  }

  test('连接失败归类为公告服务连接问题而不是用户侧问题', () {
    final failure = announcementFailureFromDio(
      dioError(type: DioExceptionType.connectionError),
    );

    expect(failure.type, AnnouncementFailureType.network);
    expect(announcementFailureDisplayText(failure), contains('公告服务连接失败'));
    expect(announcementFailureDisplayText(failure), isNot(contains('用户侧问题')));
  });

  test('服务端与请求响应按状态码区分', () {
    expect(
      announcementFailureFromDio(
        dioError(type: DioExceptionType.badResponse, statusCode: 503),
      ).type,
      AnnouncementFailureType.backend,
    );
    expect(
      announcementFailureFromDio(
        dioError(type: DioExceptionType.badResponse, statusCode: 404),
      ).type,
      AnnouncementFailureType.request,
    );
  });
}
