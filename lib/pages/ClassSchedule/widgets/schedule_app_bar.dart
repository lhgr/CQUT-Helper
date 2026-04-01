import 'package:cqut/model/class_schedule_model.dart';
import 'package:flutter/material.dart';

class ScheduleAppBar extends StatelessWidget implements PreferredSizeWidget {
  static const double _appBarHeight = 76;
  final bool loading;
  final List<String>? weekList;
  final int currentWeekIndex;
  final ScheduleData? currentScheduleData;
  final bool? nowInTeachingWeek;
  final String? nowStatusLabel;
  final VoidCallback onCourseOverview;
  final VoidCallback onNoticeRecords;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;
  final VoidCallback onWeekPicker;
  final VoidCallback onTermPicker;

  const ScheduleAppBar({
    super.key,
    required this.loading,
    required this.weekList,
    required this.currentWeekIndex,
    required this.currentScheduleData,
    this.nowInTeachingWeek,
    this.nowStatusLabel,
    required this.onCourseOverview,
    required this.onNoticeRecords,
    required this.onRefresh,
    required this.onSettings,
    required this.onWeekPicker,
    required this.onTermPicker,
  });

  @override
  Size get preferredSize => const Size.fromHeight(_appBarHeight);

  @override
  Widget build(BuildContext context) {
    const double sideSlotWidth = 132;
    const double sideHorizontalPadding = 12;
    const double pickerButtonGap = 2;
    Widget buildPickerButton({
      required String label,
      required VoidCallback onTap,
      required TextStyle? textStyle,
    }) {
      return TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 24),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          style: textStyle,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final titleTextStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold);
    final termTextStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.outline,
    );
    final weekLabel =
        (nowInTeachingWeek == false &&
            nowStatusLabel != null &&
            nowStatusLabel!.isNotEmpty &&
            weekList != null &&
            currentWeekIndex < weekList!.length)
        ? "$nowStatusLabel · 第${weekList![currentWeekIndex]}周"
        : (weekList != null && currentWeekIndex < weekList!.length)
        ? "第${weekList![currentWeekIndex]}周"
        : "课表";
    return AppBar(
      toolbarHeight: _appBarHeight,
      titleSpacing: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Theme.of(context).colorScheme.surface,
      leadingWidth: sideSlotWidth,
      leading: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: onCourseOverview,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.only(
              left: sideHorizontalPadding,
              right: 8,
            ),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('本学期课程'),
        ),
      ),
      actions: [
        SizedBox(
          width: sideSlotWidth,
          child: Padding(
            padding: const EdgeInsets.only(right: sideHorizontalPadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: onNoticeRecords,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.notifications_outlined),
                  tooltip: '调课记录',
                ),
                IconButton(
                  onPressed: loading ? null : onRefresh,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  onPressed: onSettings,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.tune),
                  tooltip: '课表设置',
                ),
              ],
            ),
          ),
        ),
      ],
      title: LayoutBuilder(
        builder: (context, constraints) {
          final centerButtons = <Widget>[
            buildPickerButton(
              label: weekLabel,
              onTap: onWeekPicker,
              textStyle: titleTextStyle,
            ),
          ];
          if (currentScheduleData != null) {
            centerButtons.add(const SizedBox(height: pickerButtonGap));
            centerButtons.add(
              buildPickerButton(
                label: "${currentScheduleData!.yearTerm}学期",
                onTap: onTermPicker,
                textStyle: termTextStyle,
              ),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: centerButtons,
              ),
            ),
          );
        },
      ),
      centerTitle: true,
    );
  }
}
