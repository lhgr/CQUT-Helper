import 'dart:convert';

import 'package:cqut_helper/manager/schedule_update_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseScheduleUpdatePendingPayload', () {
    test('payload 不是 map 时返回空结果', () {
      final result = parseScheduleUpdatePendingPayload(json.encode(['bad']));

      expect(result.yearTerm, isNull);
      expect(result.changes, isEmpty);
    });

    test('changes 不是 list 时保留 yearTerm 并返回空 changes', () {
      final result = parseScheduleUpdatePendingPayload(
        json.encode({'yearTerm': '2025-2026-2', 'changes': 'oops'}),
      );

      expect(result.yearTerm, '2025-2026-2');
      expect(result.changes, isEmpty);
    });

    test('合法 payload 只解析有效 change 项', () {
      final result = parseScheduleUpdatePendingPayload(
        json.encode({
          'yearTerm': '2025-2026-2',
          'changes': [
            {
              'weekNum': '3',
              'lines': ['新增：高等数学', 42],
            },
            {
              'weekNum': '',
              'lines': ['skip'],
            },
            'bad item',
          ],
        }),
      );

      expect(result.yearTerm, '2025-2026-2');
      expect(result.changes, hasLength(1));
      expect(result.changes.single.weekNum, '3');
      expect(result.changes.single.lines, ['新增：高等数学', '42']);
    });

    test('非法 JSON 返回空结果', () {
      final result = parseScheduleUpdatePendingPayload('{bad json');

      expect(result.yearTerm, isNull);
      expect(result.changes, isEmpty);
    });
  });
}
