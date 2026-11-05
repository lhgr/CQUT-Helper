import 'package:cqut_helper/model/update_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final release = <String, dynamic>{
    'tag_name': 'v1.2.3',
    'html_url': 'https://github.com/lhgr/CQUT-Helper/releases/tag/v1.2.3',
    'assets': [
      {
        'name': 'app.apk',
        'browser_download_url': 'https://example.com/app.apk',
      },
    ],
  };

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Android 更新选 APK', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      UpdateModel.fromJson(release).downloadUrl,
      'https://example.com/app.apk',
    );
  });

  test('iOS 更新打开发行页供个人侧载', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(UpdateModel.fromJson(release).downloadUrl, release['html_url']);
  });

  test('Android 无 APK 时打开发行页', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      UpdateModel.fromJson({...release, 'assets': []}).downloadUrl,
      release['html_url'],
    );
  });
}
