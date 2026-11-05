import 'dart:async';

import 'package:cqut_helper/api/update/update_api.dart';
import 'package:cqut_helper/manager/update_manager.dart';
import 'package:cqut_helper/model/update_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

UpdateFetchResult _result({Object? failure, String body = ''}) =>
    UpdateFetchResult(
      info: UpdateModel(
        tagName: 'v2.0.0',
        body: body,
        downloadUrl: 'https://example.com/app.apk',
        htmlUrl: 'https://example.com/release',
      ),
      fromCache: failure != null,
      validatedAt: DateTime(2026, 11, 5, 10, 30),
      failure: failure,
    );

void main() {
  late BuildContext pageContext;

  Future<void> openPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: Text('检查入口'));
          },
        ),
      ),
    );
  }

  UpdateManager managerFor(UpdateFetchResult result, {List<bool>? requests}) =>
      UpdateManager.forTesting(
        fetchLatest: ({bool forceRefresh = false}) async {
          requests?.add(forceRefresh);
          return result;
        },
        currentVersion: () async => '1.0.0',
      );

  testWidgets('手动检查强制刷新并等待关闭，自动跳过手动已展示版本，手动可再次查看', (tester) async {
    await openPage(tester);
    final requests = <bool>[];
    final result = _result();
    final manager = managerFor(result, requests: requests);
    var finished = false;
    final checking = manager.checkUpdate(pageContext, showNoUpdateToast: true)
      ..then((_) => finished = true);
    await tester.pumpAndSettle();
    expect(requests, [true]);
    expect(finished, isFalse);
    expect(find.text('暂无更新说明'), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    await checking;
    expect(finished, isTrue);
    expect(await manager.showFetchedUpdate(pageContext, result), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    final again = manager.checkUpdate(pageContext, showNoUpdateToast: true);
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 v2.0.0'), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    await again;
    expect(requests, [true, true]);
  });

  testWidgets('刷新失败自动静默，手动缓存明确说明获取时间与刷新失败', (tester) async {
    await openPage(tester);
    final result = _result(failure: StateError('offline'));
    final manager = managerFor(result);
    await manager.showFetchedUpdate(pageContext, result);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final showing = manager.checkUpdate(pageContext, showNoUpdateToast: true);
    await tester.pumpAndSettle();
    expect(find.text('上次获取的版本日志 v2.0.0'), findsOneWidget);
    expect(find.textContaining('本次刷新失败'), findsOneWidget);
    expect(find.text('上次获取时间 2026-11-05 10:30'), findsOneWidget);
    expect(find.textContaining('最新版本'), findsNothing);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    await showing;
  });

  testWidgets('手动失败没有缓存时显示失败提示', (tester) async {
    await openPage(tester);
    final manager = managerFor(
      const UpdateFetchResult(info: null, fromCache: false, failure: 'offline'),
    );
    await manager.checkUpdate(pageContext, showNoUpdateToast: true);
    await tester.pump();
    expect(find.text('检查更新失败，请稍后重试'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('读取当前版本期间路由被覆盖则延后且不消耗去重记录', (tester) async {
    await openPage(tester);
    final version = Completer<String>();
    final result = _result();
    final manager = UpdateManager.forTesting(
      fetchLatest: ({bool forceRefresh = false}) async => result,
      currentVersion: () => version.future,
    );
    final showing = manager.showFetchedUpdate(pageContext, result);
    unawaited(
      Navigator.of(pageContext).push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('其他页面'))),
      ),
    );
    await tester.pumpAndSettle();
    version.complete('1.0.0');
    await tester.pumpAndSettle();
    expect(await showing, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    Navigator.of(pageContext).pop();
    await tester.pumpAndSettle();
    final retry = manager.showFetchedUpdate(pageContext, result);
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 v2.0.0'), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(await retry, isTrue);
  });

  testWidgets('关闭按钮同帧重复触发只关闭更新弹窗', (tester) async {
    await openPage(tester);
    final result = _result();
    final showing = managerFor(result).showFetchedUpdate(pageContext, result);
    await tester.pumpAndSettle();
    final dismiss = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '稍后'),
    );
    dismiss.onPressed!();
    dismiss.onPressed!();
    await tester.pumpAndSettle();
    await showing;
    expect(find.text('检查入口'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长日志小屏大字号保留固定操作按钮', (tester) async {
    tester.view.physicalSize = const Size(360, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: Text('检查入口'));
          },
        ),
      ),
    );
    final result = _result(body: List.filled(60, '更新内容说明。').join('\n\n'));
    final showing = managerFor(result).showFetchedUpdate(pageContext, result);
    await tester.pumpAndSettle();
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
      isTrue,
    );
    expect(tester.getRect(find.text('稍后')).bottom, lessThan(520));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    await showing;
  });
}
