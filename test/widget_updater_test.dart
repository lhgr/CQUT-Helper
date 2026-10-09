import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:cqut_helper/utils/app_logger.dart';
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

  test(
    'final bridge failure keeps one operation and never reports success',
    () async {
      final logger = AppLogger.I;
      await logger.init(enableFile: false, enableConsole: false);
      addTearDown(logger.dispose);
      final previousSequence = logger.recent.isEmpty
          ? 0
          : logger.recent.last.sequence;
      WidgetUpdater.debugIsAndroidOverride = true;
      WidgetUpdater.debugDelay = (_) async {};
      final operationIds = <String>{};
      WidgetUpdater.debugMethodInvoker = (_, arguments) async {
        operationIds.add(arguments['operationId'] as String);
        throw MissingPluginException('bridge unavailable');
      };

      await WidgetUpdater.updateTodayWidget(trigger: 'schedule_refresh');

      final failures = logger.recent
          .where(
            (event) =>
                event.tag == 'WidgetUpdater' &&
                event.sequence > previousSequence &&
                event.level.priority >= LogLevel.warn.priority,
          )
          .toList();
      expect(operationIds, hasLength(1));
      expect(
        failures.map((event) => event.fields?['trace_id']).toSet(),
        operationIds,
      );
      expect(failures.last.fields?['outcome'], 'failed');
      expect(
        logger.recent.any(
          (event) =>
              event.sequence > previousSequence &&
              event.message == 'widget update completed',
        ),
        isFalse,
      );
    },
  );

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
