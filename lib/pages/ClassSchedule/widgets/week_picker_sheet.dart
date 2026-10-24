import 'package:material_ui/material_ui.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';

void showWeekPicker({
  required BuildContext context,
  required List<String> weekList,
  required ScheduleData? currentScheduleData,
  required String? actualCurrentTermStr,
  required String? actualCurrentWeekStr,
  required int currentWeekIndex,
  required Function(int) onWeekSelected,
}) {
  const double _weekItemExtent = 56;
  final initialOffset = (currentWeekIndex * _weekItemExtent).toDouble();
  showModalBottomSheet(
    context: context,
    builder: (BuildContext context) {
      return SizedBox(
        height: 300,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '选择周次',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: ScrollController(
                  initialScrollOffset: initialOffset,
                ),
                itemExtent: _weekItemExtent,
                itemCount: weekList.length,
                itemBuilder: (context, index) {
                  final week = weekList[index];
                  final isCurrentWeek =
                      actualCurrentTermStr != null &&
                      currentScheduleData?.yearTerm == actualCurrentTermStr &&
                      week == actualCurrentWeekStr;

                  return ListTile(
                    title: Text(
                      "第 $week 周${isCurrentWeek ? ' (当前周)' : ''}",
                      textAlign: TextAlign.start,
                      style: isCurrentWeek
                          ? Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600)
                          : null,
                    ),
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .secondaryContainer,
                    selectedColor: Theme.of(context)
                        .colorScheme
                        .onSecondaryContainer,
                    onTap: () {
                      Navigator.pop(context);
                      onWeekSelected(index);
                    },
                    selected: index == currentWeekIndex,
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
