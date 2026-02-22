import 'package:flutter/material.dart';
import 'package:cqut/model/class_schedule_model.dart';

void showWeekPicker({
  required BuildContext context,
  required List<String> weekList,
  required ScheduleData? currentScheduleData,
  required String? actualCurrentTermStr,
  required String? actualCurrentWeekStr,
  required int currentWeekIndex,
  required Function(int) onWeekSelected,
}) {
  showModalBottomSheet(
    context: context,
    builder: (BuildContext context) {
      return SizedBox(
        height: 300,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "选择周次",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
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
                      textAlign: TextAlign.center,
                      style: isCurrentWeek
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            )
                          : null,
                    ),
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
