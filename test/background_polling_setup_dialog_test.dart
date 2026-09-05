import 'dart:async';

import 'package:cqut_helper/widgets/background_polling_setup_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showSetup(
    WidgetTester tester, {
    bool batteryAlreadyIgnored = false,
    required Future<bool> Function() requestBattery,
    required Future<bool> Function() openBattery,
    required Future<bool> Function() openAutoStart,
    ValueChanged<bool?>? onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => BackgroundPollingSetupDialog(
                    batteryAlreadyIgnored: batteryAlreadyIgnored,
                    requestBattery: requestBattery,
                    openBattery: openBattery,
                    openAutoStart: openAutoStart,
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('开始'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();
  }

  testWidgets('省电跳转返回成功时不会连发自启动跳转，回到应用后点击才继续', (tester) async {
    final batteryLaunch = Completer<bool>();
    final calls = <String>[];
    bool? result;
    await showSetup(
      tester,
      requestBattery: () {
        calls.add('battery');
        return batteryLaunch.future;
      },
      openBattery: () async {
        calls.add('fallback');
        return true;
      },
      openAutoStart: () async {
        calls.add('autostart');
        return true;
      },
      onResult: (value) => result = value,
    );

    await tester.tap(find.text('打开省电设置'));
    await tester.pump();
    // Repeated taps while the platform call is pending must not relaunch it.
    await tester.tap(find.text('打开省电设置'));
    expect(calls, ['battery']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    batteryLaunch.complete(true);
    await tester.pump();
    expect(calls, ['battery']);
    expect(result, isNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('2. 设置自启动'), findsOneWidget);
    expect(calls, ['battery']);
    await tester.tap(find.text('打开自启动设置'));
    await tester.pumpAndSettle();
    expect(calls, ['battery', 'autostart']);
    expect(result, isNull);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('省电请求失败时尝试备用入口，全部失败时提示并允许重试', (tester) async {
    var attempts = 0;
    var fallbackCalls = 0;
    await showSetup(
      tester,
      requestBattery: () async => ++attempts > 1,
      openBattery: () async {
        fallbackCalls++;
        return false;
      },
      openAutoStart: () async => true,
    );
    await tester.tap(find.text('打开省电设置'));
    await tester.pumpAndSettle();
    expect(fallbackCalls, 1);
    expect(find.textContaining('无法打开系统设置'), findsOneWidget);
    expect(find.text('1. 设置省电策略'), findsOneWidget);
    await tester.tap(find.text('打开省电设置'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(fallbackCalls, 1);
    expect(find.text('2. 设置自启动'), findsOneWidget);
    expect(find.textContaining('无法打开系统设置'), findsNothing);
  });

  testWidgets('省电备用入口打开后仍需点击才能跳转自启动', (tester) async {
    var autoStartCalls = 0;
    await showSetup(
      tester,
      requestBattery: () async => false,
      openBattery: () async => true,
      openAutoStart: () async {
        autoStartCalls++;
        return true;
      },
    );
    await tester.tap(find.text('打开省电设置'));
    await tester.pumpAndSettle();
    expect(find.text('2. 设置自启动'), findsOneWidget);
    expect(autoStartCalls, 0);
  });

  testWidgets('已经忽略电池优化时直接引导自启动，失败不显示完成', (tester) async {
    var batteryCalls = 0;
    bool? result;
    await showSetup(
      tester,
      batteryAlreadyIgnored: true,
      requestBattery: () async {
        batteryCalls++;
        return true;
      },
      openBattery: () async => true,
      openAutoStart: () async => false,
      onResult: (value) => result = value,
    );
    expect(find.text('2. 设置自启动'), findsOneWidget);
    await tester.tap(find.text('打开自启动设置'));
    await tester.pumpAndSettle();
    expect(batteryCalls, 0);
    expect(find.textContaining('无法打开系统设置'), findsOneWidget);
    expect(find.text('完成'), findsNothing);
    expect(result, isNull);
    await tester.tap(find.text('稍后设置'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('跳过省电设置后仍提供自启动引导', (tester) async {
    final calls = <String>[];
    await showSetup(
      tester,
      requestBattery: () async {
        calls.add('battery');
        return true;
      },
      openBattery: () async => true,
      openAutoStart: () async {
        calls.add('autostart');
        return true;
      },
    );
    await tester.tap(find.text('稍后设置'));
    await tester.pumpAndSettle();
    expect(find.text('2. 设置自启动'), findsOneWidget);
    expect(calls, isEmpty);
    await tester.tap(find.text('打开自启动设置'));
    await tester.pumpAndSettle();
    expect(calls, ['autostart']);
  });
}
