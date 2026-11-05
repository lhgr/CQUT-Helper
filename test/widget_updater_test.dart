import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:flutter/services.dart';
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
      expect(arguments['trigger'], 'schedule_refresh');
      if (attempts == 1) throw MissingPluginException();
    };

    final result = await WidgetUpdater.updateTodayWidget(
      trigger: 'schedule_refresh',
    );

    expect(attempts, 2);
    expect(result, WidgetUpdateResult.accepted);
  });

  test('does not invoke the Android bridge on other platforms', () async {
    WidgetUpdater.debugIsAndroidOverride = false;
    var invoked = false;
    WidgetUpdater.debugMethodInvoker = (method, arguments) async {
      invoked = true;
    };

    final result = await WidgetUpdater.updateTodayWidget(
      trigger: 'schedule_refresh',
    );

    expect(invoked, isFalse);
    expect(result, WidgetUpdateResult.notSupported);
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

      final result = await WidgetUpdater.updateTodayWidget(
        trigger: 'schedule_refresh',
      );
      expect(result, WidgetUpdateResult.failed);

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
}
