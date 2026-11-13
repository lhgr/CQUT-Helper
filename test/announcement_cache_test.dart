import 'dart:async';

import 'package:cqut_helper/manager/announcement_manager.dart';
import 'package:cqut_helper/model/announcement_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const item = AnnouncementModel(
    id: '1',
    title: 'saved',
    contentMarkdown: '',
    createdAt: '',
    updatedAt: '',
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('expired successful announcement survives offline refresh and repeated failures', () async {
    var now = DateTime.utc(2026);
    var offline = false;
    var calls = 0;
    final manager = AnnouncementManager.forTesting(
      appVersion: () async => '1.2.3',
      now: () => now,
      loadList: (_, _) async {
        calls++;
        if (offline) {
          throw DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionError,
          );
        }
        return [item];
      },
    );
    expect((await manager.getAnnouncements()).fromCache, isFalse);
    now = now.add(const Duration(hours: 7));
    offline = true;
    for (var i = 0; i < 2; i++) {
      final result = await manager.getAnnouncements();
      expect(result.fromCache, isTrue);
      expect(result.items.single.id, '1');
      expect(result.failure, isNotNull);
    }
    expect(calls, 3);
  });
  test('equivalent concurrent refreshes share network and different filters retain separate caches', () async {
    var calls = 0;
    final gate = Completer<void>();
    final manager = AnnouncementManager.forTesting(
      appVersion: () async => '1.2.3',
      loadList: (_, active) async {
        calls++;
        await gate.future;
        return active ? [item] : [];
      },
    );
    final a = manager.getAnnouncements(forceRefresh: true);
    final b = manager.getAnnouncements(forceRefresh: true);
    final c = manager.getAnnouncements(activeOnly: false);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
    gate.complete();
    expect((await a).items.single.id, '1');
    expect((await b).items.single.id, '1');
    expect((await c).items, isEmpty);
    expect((await manager.getAnnouncements()).items.single.id, '1');
    expect((await manager.getAnnouncements(activeOnly: false)).items, isEmpty);
    expect(calls, 2);
  });
}
