import 'package:flutter/material.dart';
import 'package:cqut/model/class_schedule_model.dart';

void showTermPicker({
  required BuildContext context,
  required ScheduleData? currentScheduleData,
  required String? actualCurrentTermStr,
  required Function(String) onTermSelected,
}) {
  if (currentScheduleData?.yearTermList == null) return;
  final scheduleData = currentScheduleData!;

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
                "选择学期",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: scheduleData.yearTermList!.length,
                itemBuilder: (context, index) {
                  final term = scheduleData.yearTermList![index];
                  final isCurrentTerm = term == actualCurrentTermStr;
                  return ListTile(
                    title: Text(
                      "$term${isCurrentTerm ? ' (当前学期)' : ''}",
                      textAlign: TextAlign.center,
                      style: isCurrentTerm
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            )
                          : null,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      onTermSelected(term);
                    },
                    selected: term == scheduleData.yearTerm,
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
