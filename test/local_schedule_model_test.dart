import 'package:cqut_helper/model/local_schedule_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LocalScheduleEvent event({DateTime? date, List<int> weeks = const [1, 3]}) {
    return LocalScheduleEvent(
      id: 'local-1',
      userId: '20260001',
      yearTerm: '2026-2027-1',
      title: 'Study group',
      teacher: '',
      location: 'Library',
      note: 'Bring notes',
      weeks: weeks,
      weekDay: DateTime.wednesday,
      startSession: 3,
      sessionCount: 2,
      specificDate: date,
      reminderMinutes: 15,
      colorIndex: 4,
      source: LocalScheduleSource.manual,
      createdAt: DateTime(2026, 8, 1, 10),
      updatedAt: DateTime(2026, 8, 1, 11),
    );
  }

  test('repeating event applies only to selected weeks', () {
    final value = event();
    expect(value.appliesToWeek(1, const []), isTrue);
    expect(value.appliesToWeek(2, const []), isFalse);
  });

  test('dated event follows its date rather than the week list', () {
    final value = event(date: DateTime(2026, 9, 16), weeks: const []);
    expect(
      value.appliesToWeek(1, [DateTime(2026, 9, 14), DateTime(2026, 9, 16)]),
      isTrue,
    );
    expect(value.appliesToWeek(2, [DateTime(2026, 9, 23)]), isFalse);
  });

  test('database mapping round-trips all user fields', () {
    final original = event(date: DateTime(2026, 9, 16));
    final decoded = LocalScheduleEvent.fromDatabaseMap(
      original.toDatabaseMap(),
    );

    expect(decoded.id, original.id);
    expect(decoded.userId, original.userId);
    expect(decoded.title, original.title);
    expect(decoded.note, original.note);
    expect(decoded.specificDate, DateTime(2026, 9, 16));
    expect(decoded.reminderMinutes, 15);
    expect(decoded.colorIndex, 4);
    expect(decoded.source, LocalScheduleSource.manual);
  });
}
