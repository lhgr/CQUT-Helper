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
      request.targetDate(now: DateTime.utc(2026, 12, 31, 4)),
      DateTime(2027, 1, 1),
    );
    expect(
      request.targetDate(now: DateTime.utc(2026, 11, 8, 4)),
      DateTime(2026, 11, 9),
    );
    expect(WidgetNavigation.consumeSyncAction(request), isFalse);
  });

  test('offset fallback follows Beijing midnight across the year', () {
    const request = WidgetNavigationRequest(token: 1, dayOffset: 1);
    expect(
      request.targetDate(now: DateTime.parse('2026-12-31T15:59:59Z')),
      DateTime(2027, 1, 1),
    );
    expect(
      request.targetDate(now: DateTime.parse('2026-12-31T16:00:00Z')),
      DateTime(2027, 1, 2),
    );
    // The same instant represented in a western time zone is already Jan 1
    // on the school calendar.
    expect(
      request.targetDate(now: DateTime.parse('2026-12-31T08:00:00-08:00')),
      DateTime(2027, 1, 2),
    );
  });

  test(
    'Android row date wins over a stale relative offset after midnight',
    () async {
      WidgetNavigation.debugIsSupportedOverride = true;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'date': '2026-12-31',
          'dayOffset': 1,
          'eventId': 'december-course',
        },
      );
      await WidgetNavigation.initialize();
      final request = WidgetNavigation.request.value!;
      expect(
        request.targetDate(now: DateTime.parse('2027-01-01T16:00:00Z')),
        DateTime(2026, 12, 31),
      );
      expect(request.eventId, 'december-course');
    },
  );
}
