import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('project no longer references Firebase', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final appBootstrap = File('lib/app/app_bootstrap.dart').readAsStringSync();
    final routes = File('lib/routes/Routes.dart').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(pubspec, isNot(contains('firebase_core')));
    expect(pubspec, isNot(contains('firebase_analytics')));
    expect(appBootstrap, isNot(contains('Firebase.initializeApp')));
    expect(routes, isNot(contains('FirebaseAnalyticsObserver')));
    expect(readme, isNot(contains('Firebase Analytics')));
    expect(File('firebase.json').existsSync(), isFalse);
    expect(File('lib/firebase_options.dart').existsSync(), isFalse);
  });
}
