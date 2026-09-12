import 'package:cqut_helper/model/daily_quote_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DailyQuoteItem', () {
    test('uses an inclusive start and exclusive end time', () {
      final item = DailyQuoteItem(
        id: 'holiday',
        text: '节日快乐',
        startsAt: DateTime.parse('2026-10-01T00:00:00+08:00'),
        endsAt: DateTime.parse('2026-10-08T00:00:00+08:00'),
      );

      expect(
        item.isActiveAt(DateTime.parse('2026-10-01T00:00:00+08:00')),
        isTrue,
      );
      expect(
        item.isActiveAt(DateTime.parse('2026-10-07T23:59:59+08:00')),
        isTrue,
      );
      expect(
        item.isActiveAt(DateTime.parse('2026-10-08T00:00:00+08:00')),
        isFalse,
      );
    });
  });

  group('buildDailyQuoteQueue', () {
    DailyQuoteConfig config(List<DailyQuoteItem> items) => DailyQuoteConfig(
      enabled: true,
      revision: 1,
      rotationMode: 'daily',
      items: items,
    );

    test('puts active priority items before daily-rotated normal items', () {
      final items = [
        const DailyQuoteItem(id: 'normal-a', text: 'A', order: 10),
        const DailyQuoteItem(
          id: 'priority-low',
          text: 'P50',
          priority: 50,
          order: 1,
        ),
        const DailyQuoteItem(id: 'normal-b', text: 'B', order: 20),
        const DailyQuoteItem(
          id: 'priority-high',
          text: 'P100',
          priority: 100,
          order: 99,
        ),
      ];

      final firstDay = buildDailyQuoteQueue(
        config(items),
        now: DateTime.utc(1970, 1, 1, 12),
      );
      final secondDay = buildDailyQuoteQueue(
        config(items),
        now: DateTime.utc(1970, 1, 2, 12),
      );

      expect(firstDay.map((item) => item.id), [
        'priority-high',
        'priority-low',
        'normal-a',
        'normal-b',
      ]);
      expect(secondDay.map((item) => item.id), [
        'priority-high',
        'priority-low',
        'normal-b',
        'normal-a',
      ]);
    });

    test('filters disabled and out-of-window items', () {
      final queue = buildDailyQuoteQueue(
        config([
          const DailyQuoteItem(id: 'active', text: 'Active'),
          const DailyQuoteItem(
            id: 'disabled',
            text: 'Disabled',
            enabled: false,
          ),
          DailyQuoteItem(
            id: 'future',
            text: 'Future',
            startsAt: DateTime.utc(2026, 1, 2),
          ),
          DailyQuoteItem(
            id: 'expired',
            text: 'Expired',
            endsAt: DateTime.utc(2025, 12, 31),
          ),
        ]),
        now: DateTime.utc(2026, 1, 1),
      );

      expect(queue.map((item) => item.id), ['active']);
    });

    test('global switch hides all items', () {
      const disabledConfig = DailyQuoteConfig(
        enabled: false,
        revision: 1,
        rotationMode: 'daily',
        items: [DailyQuoteItem(id: 'one', text: 'One')],
      );

      expect(
        buildDailyQuoteQueue(disabledConfig, now: DateTime.utc(2026)),
        isEmpty,
      );
    });
  });
}
