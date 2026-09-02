import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(WidgetUpdater.resetDebugOverrides);

  test('retries a transient platform bridge failure', () async {
    WidgetUpdater.debugIsAndroidOverride = true;
    WidgetUpdater.debugDelay = (_) async {};
    var attempts = 0;
    WidgetUpdater.debugMethodInvoker = (method, arguments) async {
      attempts++;
      expect(method, 'updateTodayWidget');
      expect(arguments['trigger'], 'app_resumed');
      if (attempts == 1) throw MissingPluginException();
    };

    await WidgetUpdater.updateTodayWidget(trigger: 'app_resumed');

    expect(attempts, 2);
  });

  test('does not invoke the Android bridge on other platforms', () async {
    WidgetUpdater.debugIsAndroidOverride = false;
    var invoked = false;
    WidgetUpdater.debugMethodInvoker = (method, arguments) async {
      invoked = true;
    };

    await WidgetUpdater.updateTodayWidget(trigger: 'schedule_refresh');

    expect(invoked, isFalse);
  });

  test('warm resume gate ignores launch and repairs after backgrounding', () {
    final gate = WidgetResumeRefreshGate();

    expect(gate.shouldRefresh(AppLifecycleState.resumed), isFalse);
    expect(gate.shouldRefresh(AppLifecycleState.inactive), isFalse);
    expect(gate.shouldRefresh(AppLifecycleState.hidden), isFalse);
    expect(gate.shouldRefresh(AppLifecycleState.paused), isFalse);
    expect(gate.shouldRefresh(AppLifecycleState.resumed), isTrue);
    expect(gate.shouldRefresh(AppLifecycleState.resumed), isFalse);
  });
}
