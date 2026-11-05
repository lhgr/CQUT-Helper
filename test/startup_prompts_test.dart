import 'dart:async';

import 'package:cqut_helper/api/update/update_api.dart';
import 'package:cqut_helper/manager/announcement_manager.dart';
import 'package:cqut_helper/manager/update_manager.dart';
import 'package:cqut_helper/model/announcement_model.dart';
import 'package:cqut_helper/model/update_model.dart';
import 'package:cqut_helper/pages/Main/Main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _announcement = AnnouncementModel(
  id: 'startup-test',
  title: '启动公告',
  contentMarkdown: '公告正文',
  createdAt: '',
  updatedAt: '',
);

UpdateFetchResult _update() => UpdateFetchResult(
  info: UpdateModel(
    tagName: 'v2.0.0',
    body: '版本日志',
    downloadUrl: 'https://example.com/app.apk',
    htmlUrl: 'https://example.com/release',
  ),
  fromCache: false,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'account': 'startup-test',
      'schedule_default_home_tab': 2,
      'user_info_startup-test': '{}',
    });
    PackageInfo.setMockInitialValues(
      appName: 'CQUT Helper',
      packageName: 'top.dawndrizzle.cqut',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<void> openMain(
    WidgetTester tester, {
    required Completer<AnnouncementModel?> announcement,
    required Completer<UpdateFetchResult> update,
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: MainPage(
          announcementManager: AnnouncementManager.forTesting(
            loadLatest: () => announcement.future,
          ),
          updateManager: UpdateManager.forTesting(
            fetchLatest: ({bool forceRefresh = false}) => update.future,
            currentVersion: () async => '1.0.0',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('更新先返回仍等待公告检查，并等待公告关闭后才展示', (tester) async {
    final announcement = Completer<AnnouncementModel?>();
    final update = Completer<UpdateFetchResult>();
    await openMain(tester, announcement: announcement, update: update);
    update.complete(_update());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    announcement.complete(_announcement);
    await tester.pumpAndSettle();
    expect(find.text('启动公告'), findsOneWidget);
    expect(find.text('发现新版本 v2.0.0'), findsNothing);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 v2.0.0'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('后台返回结果保留，恢复前台后展示', (tester) async {
    final announcement = Completer<AnnouncementModel?>();
    final update = Completer<UpdateFetchResult>();
    await openMain(tester, announcement: announcement, update: update);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    announcement.complete(null);
    update.complete(_update());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 v2.0.0'), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('其他路由在前时保留公告和更新，返回首页才继续', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final announcement = Completer<AnnouncementModel?>();
    final update = Completer<UpdateFetchResult>();
    await openMain(
      tester,
      announcement: announcement,
      update: update,
      navigatorKey: navigator,
    );
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('其他页面'))),
      ),
    );
    await tester.pumpAndSettle();
    announcement.complete(_announcement);
    update.complete(_update());
    await tester.pumpAndSettle();
    expect(find.text('其他页面'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('启动公告'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 v2.0.0'), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('首页销毁后丢弃晚到的公告和更新', (tester) async {
    final announcement = Completer<AnnouncementModel?>();
    final update = Completer<UpdateFetchResult>();
    await openMain(tester, announcement: announcement, update: update);
    await tester.pumpWidget(const MaterialApp(home: Text('已离开')));
    announcement.complete(_announcement);
    update.complete(_update());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('已离开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('公告检查异常结束该阶段，更新仍可正常展示', (tester) async {
    final announcement = Completer<AnnouncementModel?>();
    final update = Completer<UpdateFetchResult>();
    await openMain(tester, announcement: announcement, update: update);
    announcement.completeError(StateError('announcement unavailable'));
    update.complete(_update());
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 v2.0.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

