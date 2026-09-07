import 'package:cqut_helper/routes/Routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('未知平台路由安全回退到首页', () {
    final route = buildUnknownRoute(
      const RouteSettings(name: '/today/12/0/course'),
    );

    expect(route, isA<MaterialPageRoute<void>>());
    expect(route.settings.name, '/');
  });
}
