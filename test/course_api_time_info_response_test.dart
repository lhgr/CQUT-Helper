import 'dart:convert';

import 'package:cqut_helper/api/course/course_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CourseApi.parseCampusTimeInfoResponse', () {
    const item = {
      'campusName': '两江校区',
      'sessionNum': 1,
      'startTime': '08:00',
      'endTime': '08:45',
    };

    test('接受历史顶层数组', () {
      expect(CourseApi.parseCampusTimeInfoResponse([item]), [item]);
    });

    test('接受 data 包装和嵌套 list 包装', () {
      expect(
        CourseApi.parseCampusTimeInfoResponse({
          'data': [item],
        }),
        [item],
      );
      expect(
        CourseApi.parseCampusTimeInfoResponse({
          'result': {
            'list': [item],
          },
        }),
        [item],
      );
    });

    test('接受 JSON 字符串并拒绝错误响应', () {
      expect(
        CourseApi.parseCampusTimeInfoResponse(
          json.encode({
            'rows': [item],
          }),
        ),
        [item],
      );
      expect(
        CourseApi.parseCampusTimeInfoResponse({'code': 500, 'msg': 'failed'}),
        isNull,
      );
    });

    test('异常响应诊断只记录结构而不记录正文', () {
      final diagnostics = CourseApi.campusTimeInfoResponseDiagnostics(
        raw: {'code': 500, 'msg': '包含敏感内容'},
        statusCode: 200,
        contentType: 'application/json',
      );

      expect(diagnostics['response_status'], 200);
      expect(diagnostics['response_shape'], 'map');
      expect(diagnostics['response_keys'], 'code,msg');
      expect(diagnostics['response_code'], 500);
      expect(diagnostics.toString(), isNot(contains('包含敏感内容')));
    });
  });
}
