import 'package:cqut_helper/manager/daily_quote_manager.dart';
import 'package:cqut_helper/model/daily_quote_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists a manual selection for the same day', () async {
    SharedPreferences.setMockInitialValues({});
    var fetchCount = 0;
    final manager = DailyQuoteManager(
      fetchConfig: () async {
        fetchCount++;
        return const DailyQuoteConfig(
          enabled: true,
          revision: 1,
          rotationMode: 'daily',
          items: [
            DailyQuoteItem(id: 'a', text: 'A', order: 1),
            DailyQuoteItem(id: 'b', text: 'B', order: 2),
          ],
        );
      },
    );
    final now = DateTime(1970, 1, 1, 12);

    final initial = await manager.refresh(force: true, now: now);
    expect(initial?.current.id, 'a');
    final next = await manager.selectNext(initial!, now: now);
    expect(next.current.id, 'b');

    final cached = await manager.loadCached(now: now);
    expect(cached?.current.id, 'b');
    expect(fetchCount, 1);
  });

  test('a newly published higher priority item moves to the front', () async {
    SharedPreferences.setMockInitialValues({});
    var config = const DailyQuoteConfig(
      enabled: true,
      revision: 1,
      rotationMode: 'daily',
      items: [
        DailyQuoteItem(id: 'a', text: 'A', order: 1),
        DailyQuoteItem(id: 'b', text: 'B', order: 2),
      ],
    );
    final manager = DailyQuoteManager(fetchConfig: () async => config);
    final now = DateTime(1970, 1, 1, 12);

    final initial = await manager.refresh(force: true, now: now);
    final normal = await manager.selectNext(initial!, now: now);
    expect(normal.current.priority, 0);

    config = const DailyQuoteConfig(
      enabled: true,
      revision: 2,
      rotationMode: 'daily',
      items: [
        DailyQuoteItem(id: 'holiday', text: '节日快乐', priority: 100),
        DailyQuoteItem(id: 'a', text: 'A', order: 1),
        DailyQuoteItem(id: 'b', text: 'B', order: 2),
      ],
    );

    final refreshed = await manager.refresh(force: true, now: now);
    expect(refreshed?.current.id, 'holiday');
  });

  test('scheduled boundary bypasses the normal cache TTL', () async {
    final now = DateTime(2026, 10, 1, 0, 0);
    SharedPreferences.setMockInitialValues({});
    var fetchCount = 0;
    final manager = DailyQuoteManager(
      fetchConfig: () async {
        fetchCount++;
        return DailyQuoteConfig(
          enabled: true,
          revision: fetchCount,
          rotationMode: 'daily',
          nextRefreshAt: now.add(const Duration(minutes: 5)),
          items: const [DailyQuoteItem(id: 'a', text: 'A')],
        );
      },
    );

    await manager.refresh(force: true, now: now);
    await manager.refresh(now: now.add(const Duration(minutes: 4)));
    expect(fetchCount, 1);

    await manager.refresh(now: now.add(const Duration(minutes: 5)));
    expect(fetchCount, 2);
  });

  test('falls back to the still-active cache when refresh fails', () async {
    SharedPreferences.setMockInitialValues({});
    var shouldFail = false;
    final manager = DailyQuoteManager(
      fetchConfig: () async {
        if (shouldFail) throw Exception('offline');
        return const DailyQuoteConfig(
          enabled: true,
          revision: 1,
          rotationMode: 'daily',
          items: [DailyQuoteItem(id: 'cached', text: 'Cached')],
        );
      },
    );
    final now = DateTime(2026, 1, 1, 12);

    await manager.refresh(force: true, now: now);
    shouldFail = true;
    final fallback = await manager.refresh(force: true, now: now);

    expect(fallback?.current.id, 'cached');
  });
}
