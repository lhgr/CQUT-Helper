import 'dart:convert';

import 'package:cqut_helper/manager/schedule_message_center_manager.dart';
import 'package:cqut_helper/model/schedule_week_change.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Uses the platform fake already provided by shared_preferences; no new dependency.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FailingPreferenceStore extends InMemorySharedPreferencesStore {
  _FailingPreferenceStore() : super.withData({});
  bool failWrite = false;
  bool failRemove = false;
  bool throwWrite = false;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (failWrite) {
      failWrite = false;
      if (throwWrite) throw StateError('disk unavailable');
      return false;
    }
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (failRemove) {
      failRemove = false;
      return false;
    }
    return super.remove(key);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final throws in [false, true]) {
    test(
      'failed read write restores cached unread and queue can retry (throws=$throws)',
      () async {
        final store = _FailingPreferenceStore();
        SharedPreferencesStorePlatform.instance = store;
        SharedPreferences.resetStatic();
        await ScheduleMessageCenterManager.appendChanges(
          userId: 'a',
          yearTerm: 'term',
          changes: const [
            ScheduleWeekChange(weekNum: '1', lines: ['one']),
          ],
        );
        final first = (await ScheduleMessageCenterManager.load('a')).single;
        final epoch = ScheduleMessageCenterManager.epoch.value;
        store.failWrite = true;
        store.throwWrite = throws;
        await expectLater(
          ScheduleMessageCenterManager.markRead('a', first.id),
          throwsStateError,
        );
        expect(
          (await ScheduleMessageCenterManager.load('a')).single.read,
          isFalse,
        );
        expect(ScheduleMessageCenterManager.epoch.value, epoch);
        await ScheduleMessageCenterManager.markRead('a', first.id);
        SharedPreferences.resetStatic();
        expect(
          (await ScheduleMessageCenterManager.load('a')).single.read,
          isTrue,
        );
        expect(ScheduleMessageCenterManager.epoch.value, epoch + 1);
        store.failRemove = true;
        await expectLater(
          ScheduleMessageCenterManager.clear('a'),
          throwsStateError,
        );
        expect(await ScheduleMessageCenterManager.load('a'), hasLength(1));
        await ScheduleMessageCenterManager.clear('a');
        SharedPreferences.resetStatic();
        expect(await ScheduleMessageCenterManager.load('a'), isEmpty);
      },
    );
  }

  test('single read reloads external appended history before saving', () async {
    final store = _FailingPreferenceStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    await ScheduleMessageCenterManager.appendChanges(
      userId: 'a',
      yearTerm: 'term',
      changes: const [
        ScheduleWeekChange(weekNum: '1', lines: ['one']),
      ],
    );
    final first = (await ScheduleMessageCenterManager.load('a')).single;
    final external = ScheduleMessageRecord(
      id: 'external',
      userId: 'a',
      yearTerm: 'term',
      changes: const [
        ScheduleWeekChange(weekNum: '2', lines: ['two']),
      ],
      createdAt: DateTime.now(),
      read: false,
    );
    await store.setValue(
      'String',
      'flutter.schedule_message_history_v1_a',
      jsonEncode([external.toJson(), first.toJson()]),
    );
    await ScheduleMessageCenterManager.markRead('a', first.id);
    SharedPreferences.resetStatic();
    final saved = await ScheduleMessageCenterManager.load('a');
    expect(saved, hasLength(2));
    expect(saved.singleWhere((record) => record.id == first.id).read, isTrue);
    expect(
      saved.singleWhere((record) => record.id == 'external').read,
      isFalse,
    );
  });

  test('调课变更会持久化、去重并可全部标为已读', () async {
    const changes = [
      ScheduleWeekChange(weekNum: '3', lines: ['高等数学由周一调到周三']),
    ];

    await ScheduleMessageCenterManager.appendChanges(
      userId: '20260001',
      yearTerm: '2026-2027-1',
      changes: changes,
    );
    await ScheduleMessageCenterManager.appendChanges(
      userId: '20260001',
      yearTerm: '2026-2027-1',
      changes: changes,
    );

    var records = await ScheduleMessageCenterManager.load('20260001');
    expect(records, hasLength(1));
    expect(records.single.read, isFalse);
    expect(records.single.changes.single.weekNum, '3');

    await ScheduleMessageCenterManager.markAllRead('20260001');
    records = await ScheduleMessageCenterManager.load('20260001');
    expect(records.single.read, isTrue);
  });

  test(
    'single read is persisted and leaves other records and accounts unread',
    () async {
      for (final week in ['1', '2']) {
        await ScheduleMessageCenterManager.appendChanges(
          userId: 'a',
          yearTerm: 'term',
          changes: [
            ScheduleWeekChange(weekNum: week, lines: [week]),
          ],
        );
      }
      await ScheduleMessageCenterManager.appendChanges(
        userId: 'b',
        yearTerm: 'term',
        changes: const [
          ScheduleWeekChange(weekNum: '1', lines: ['other']),
        ],
      );
      final records = await ScheduleMessageCenterManager.load('a');
      final epoch = ScheduleMessageCenterManager.epoch.value;
      await ScheduleMessageCenterManager.markRead('a', records.first.id);
      final saved = await ScheduleMessageCenterManager.load('a');
      expect(saved.first.read, isTrue);
      expect(saved.last.read, isFalse);
      expect(
        (await ScheduleMessageCenterManager.load('b')).single.read,
        isFalse,
      );
      expect(ScheduleMessageCenterManager.epoch.value, epoch + 1);
      await ScheduleMessageCenterManager.markRead('a', records.first.id);
      await ScheduleMessageCenterManager.markRead('a', 'missing');
      expect(ScheduleMessageCenterManager.epoch.value, epoch + 1);
    },
  );

  test(
    'queued mutations retain appended messages and order clear before append',
    () async {
      await ScheduleMessageCenterManager.appendChanges(
        userId: 'a',
        yearTerm: 'term',
        changes: const [
          ScheduleWeekChange(weekNum: '1', lines: ['first']),
        ],
      );
      final first = (await ScheduleMessageCenterManager.load('a')).single;
      await Future.wait([
        ScheduleMessageCenterManager.markRead('a', first.id),
        ScheduleMessageCenterManager.appendChanges(
          userId: 'a',
          yearTerm: 'term',
          changes: const [
            ScheduleWeekChange(weekNum: '2', lines: ['second']),
          ],
        ),
      ]);
      final saved = await ScheduleMessageCenterManager.load('a');
      expect(saved, hasLength(2));
      expect(saved.singleWhere((record) => record.id == first.id).read, isTrue);
      expect(
        saved.singleWhere((record) => record.id != first.id).read,
        isFalse,
      );
      await Future.wait([
        ScheduleMessageCenterManager.clear('a'),
        ScheduleMessageCenterManager.appendChanges(
          userId: 'a',
          yearTerm: 'term',
          changes: const [
            ScheduleWeekChange(weekNum: '3', lines: ['after clear']),
          ],
        ),
      ]);
      expect(
        (await ScheduleMessageCenterManager.load('a'))
            .single
            .changes
            .single
            .weekNum,
        '3',
      );
    },
  );
}
