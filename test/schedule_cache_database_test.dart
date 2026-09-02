import 'dart:convert';

import 'package:cqut_helper/manager/schedule_cache_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScheduleCacheDatabase validation', () {
    test('canonicalizes missing identity fields before checksumming', () {
      final canonical = ScheduleCacheDatabase.canonicalizeAndValidate(
        jsonEncode({'eventList': <Object?>[], 'weekDayList': <Object?>[]}),
        expectedYearTerm: '2026-2027-1',
        expectedWeekNum: '3',
      );
      final decoded = jsonDecode(canonical) as Map<String, dynamic>;

      expect(decoded['yearTerm'], '2026-2027-1');
      expect(decoded['weekNum'], '3');
      expect(ScheduleCacheDatabase.checksumFor(canonical), hasLength(64));
      final checksum = ScheduleCacheDatabase.checksumFor(canonical);
      expect(
        ScheduleCacheDatabase.checksumMatches(canonical, checksum),
        isTrue,
      );
      expect(
        ScheduleCacheDatabase.checksumMatches('$canonical ', checksum),
        isFalse,
      );
      expect(ScheduleCacheDatabase.databaseVersion, 2);
    });

    test('rejects malformed structures and mismatched week identity', () {
      expect(
        () => ScheduleCacheDatabase.canonicalizeAndValidate(
          jsonEncode({'eventList': 'invalid'}),
          expectedYearTerm: '2026-2027-1',
          expectedWeekNum: '3',
        ),
        throwsFormatException,
      );
      expect(
        () => ScheduleCacheDatabase.canonicalizeAndValidate(
          jsonEncode({
            'eventList': [
              {'eventName': '测试课程', 'sessionList': '1,2'},
            ],
          }),
          expectedYearTerm: '2026-2027-1',
          expectedWeekNum: '3',
        ),
        throwsFormatException,
      );
      expect(
        () => ScheduleCacheDatabase.canonicalizeAndValidate(
          jsonEncode({
            'yearTerm': '2026-2027-1',
            'weekNum': '4',
            'eventList': <Object?>[],
          }),
          expectedYearTerm: '2026-2027-1',
          expectedWeekNum: '3',
        ),
        throwsFormatException,
      );
    });

    test('legacy parser only accepts schedule keys matching their payload', () {
      final raw = jsonEncode({
        'yearTerm': '2026-2027-1',
        'weekNum': '3',
        'eventList': <Object?>[],
      });
      final record = ScheduleCacheDatabase.parseLegacyRecord(
        'schedule_remote_student_01_2026-2027-1_3',
        raw,
      );

      expect(record, isNotNull);
      expect(record!.userId, 'student_01');
      expect(record.isRemoteSource, isTrue);
      expect(
        ScheduleCacheDatabase.parseLegacyRecord(
          'schedule_remote_student_01_2026-2027-1_4',
          raw,
        ),
        isNull,
      );
      expect(
        ScheduleCacheDatabase.parseLegacyRecord(
          'schedule_fetch_at_student_01_2026-2027-1_3',
          raw,
        ),
        isNull,
      );

      final inferred = ScheduleCacheDatabase.parseLegacyRecord(
        'schedule_student_01_2026-2027-1_3',
        jsonEncode({'weekDayList': <Object?>[]}),
      );
      expect(inferred?.yearTerm, '2026-2027-1');
      expect(inferred?.weekNum, '3');
    });
  });
}
