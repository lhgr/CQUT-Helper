import 'package:cqut_helper/api/course/course_api.dart';
import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCourseApi extends CourseApi {
  final Map<String, Map<String, dynamic>> responses;
  final List<String> requestedWeeks = [];

  _FakeCourseApi(this.responses);

  @override
  Future<Map<String, dynamic>> fetchWeekEvents({
    required String userId,
    String? weekNum,
    String? yearTerm,
    String? password,
    String? encryptedPassword,
  }) async {
    requestedWeeks.add(weekNum!);
    return responses[weekNum] ?? <String, dynamic>{'eventList': []};
  }
}

void main() {
  test('fetchCustomEvents keeps only unique server custom events', () async {
    final courseApi = _FakeCourseApi({
      '1': {
        'eventList': [
          {
            'eventType': '3',
            'eventID': 'custom-1',
            'eventName': 'Custom course',
            'weekDay': '2',
            'sessionStart': '3',
          },
          {'eventType': '1', 'eventID': '', 'eventName': 'School course'},
        ],
      },
      '2': {
        'eventList': [
          {
            'eventType': '3',
            'eventID': 'custom-1',
            'eventName': 'Custom course',
            'weekDay': '2',
            'sessionStart': '3',
          },
          {
            'eventType': '3',
            'eventID': 'custom-2',
            'eventName': 'Another custom course',
            'weekDay': '1',
            'sessionStart': '1',
          },
        ],
      },
    });
    final progress = <int>[];

    final events = await ScheduleApi(courseApi: courseApi).fetchCustomEvents(
      userId: '20260001',
      encryptedPassword: 'secret',
      yearTerm: '2026-2027-1',
      weeks: const [2, 1, 2],
      onProgress: (completed, total) => progress.add(completed),
    );

    expect(courseApi.requestedWeeks, ['1', '2']);
    expect(events.map((event) => event.eventID), ['custom-2', 'custom-1']);
    expect(progress, [1, 2]);
  });
}
