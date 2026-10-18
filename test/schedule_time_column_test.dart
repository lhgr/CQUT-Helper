import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_time_column.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final height in [ScheduleLayoutSettings.minGridCellHeight, 60.0]) {
    testWidgets('large text keeps complete times within a $height high row', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: Align(
                alignment: Alignment.topLeft,
                child: ScheduleTimeColumn(
                  sessionHeight: height,
                  sessionCount: 1,
                  timeInfoList: [
                    CampusTimeInfo(
                      campusName: '花溪校区',
                      sessionNum: 1,
                      startTime: '13:00',
                      endTime: '13:45',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final columnRect = tester.getRect(find.byType(ScheduleTimeColumn));
      for (final value in ['13:00', '1', '13:45']) {
        final label = find.text(value);
        final paragraph = tester.renderObject<RenderParagraph>(label);
        expect(
          paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: value.length),
          ),
          hasLength(1),
          reason: '$value must stay on one line',
        );
        final rect = tester.getRect(label);
        expect(rect.left, greaterThanOrEqualTo(columnRect.left));
        expect(rect.right, lessThanOrEqualTo(columnRect.right));
        expect(rect.top, greaterThanOrEqualTo(columnRect.top));
        expect(rect.bottom, lessThanOrEqualTo(columnRect.top + height));
      }
    });
  }
}
