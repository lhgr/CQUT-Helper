import 'package:cqut_helper/utils/widget_navigation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cqut/navigation');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    WidgetNavigation.debugIsSupportedOverride = null;
    WidgetNavigation.request.value = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'initial iOS navigation preserves actual date, course and one-shot sync',
    () async {
      WidgetNavigation.debugIsSupportedOverride = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getInitialWidgetNavigation');
        return {
          'date': '2026-11-09',
          'dayOffset': 1,
          'eventId': 'course-id',
          'eventName': '课程',
          'action': 'sync',
        };
      });
      await WidgetNavigation.initialize();
      final request = WidgetNavigation.request.value!;
      expect(
        request.targetDate(now: DateTime(2026, 11, 5)),
        DateTime(2026, 11, 9),
      );
      expect(request.eventId, 'course-id');
      expect(request.eventName, '课程');
      expect(request.hasCourse, isTrue);
      expect(WidgetNavigation.consumeSyncAction(request), isTrue);
      expect(WidgetNavigation.consumeSyncAction(request), isFalse);
    },
  );

  test('legacy day offsets cross week and year boundaries and invalid dates fall back', () async {
    WidgetNavigation.debugIsSupportedOverride = true;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'date': '2026-02-30', 'dayOffset': 1},
    );
    await WidgetNavigation.initialize();
    final request = WidgetNavigation.request.value!;
    expect(request.date, isNull);
    expect(request.action, 'open');
    expect(
      request.targetDate(now: DateTime(2026, 12, 31)),
      DateTime(2027, 1, 1),
    );
    expect(
      request.targetDate(now: DateTime(2026, 11, 8)),
      DateTime(2026, 11, 9),
    );
    expect(WidgetNavigation.consumeSyncAction(request), isFalse);
  });
}
