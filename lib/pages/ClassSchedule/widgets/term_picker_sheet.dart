import 'package:material_ui/material_ui.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';

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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '选择学期',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
                      textAlign: TextAlign.start,
                      style: isCurrentTerm
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
