import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:flutter/material.dart';

void _noopScheduleAction() {}

class ScheduleAppBar extends StatelessWidget implements PreferredSizeWidget {
  static const double _appBarHeight = 76;

  final bool loading;
  final List<String>? weekList;
  final int currentWeekIndex;
  final ScheduleData? currentScheduleData;
  final bool? nowInTeachingWeek;
  final String? nowStatusLabel;
  final String? refreshStatusText;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;
  final VoidCallback onWeekPicker;
  final VoidCallback onTermPicker;
  final VoidCallback onSemesterCourses;
  final VoidCallback onAddCourse;
  final VoidCallback onManageCustomCourses;
  final VoidCallback onExportIcs;

  const ScheduleAppBar({
    super.key,
    required this.loading,
    required this.weekList,
    required this.currentWeekIndex,
    required this.currentScheduleData,
    this.nowInTeachingWeek,
    this.nowStatusLabel,
    this.refreshStatusText,
    required this.onRefresh,
    required this.onSettings,
    required this.onWeekPicker,
    required this.onTermPicker,
    required this.onSemesterCourses,
    this.onAddCourse = _noopScheduleAction,
    this.onManageCustomCourses = _noopScheduleAction,
    this.onExportIcs = _noopScheduleAction,
  });

  @override
  Size get preferredSize => const Size.fromHeight(_appBarHeight);

  @override
  Widget build(BuildContext context) {
    const double sideSlotWidth = 120;
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

    String compactRefreshStatus(String status) {
      return status
          .replaceFirst(RegExp(r'^今天\s+'), '')
          .replaceFirst(RegExp(r'更新$'), '');
    }

    Widget buildRefreshAction() {
      final status = refreshStatusText;
      final compactStatus = status == null
          ? null
          : compactRefreshStatus(status);
      final color = Theme.of(context).colorScheme.onSurfaceVariant;
      return Tooltip(
        message: status == null ? '刷新课表' : '最后更新：$status',
        child: Semantics(
          button: true,
          label: status == null ? '刷新课表' : '刷新课表，最后更新$status',
          child: InkWell(
            onTap: loading ? null : onRefresh,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 36,
              height: 54,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 30,
                    child: Center(
                      child: loading
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: color,
                              ),
                            )
                          : Icon(Icons.refresh, color: color),
                    ),
                  ),
                  if (compactStatus != null)
                    Text(
                      compactStatus,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontSize: 9.5,
                        height: 1,
                      ),
                    ),
                ],
              ),
            ),
          ),
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
      leadingWidth: sideSlotWidth,
      leading: SizedBox(
        width: sideSlotWidth,
        child: Padding(
          padding: const EdgeInsets.only(left: sideHorizontalPadding),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onSemesterCourses,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                '本学期课程',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      ),
      scrolledUnderElevation: 0,
      backgroundColor: Theme.of(context).colorScheme.surface,
      actions: [
        SizedBox(
          width: sideSlotWidth,
          child: Padding(
            padding: const EdgeInsets.only(right: sideHorizontalPadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                buildRefreshAction(),
                IconButton(
                  onPressed: onSettings,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.tune),
                  tooltip: '课表设置',
                ),
                SizedBox(
                  width: 32,
                  height: 36,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    tooltip: '更多课表操作',
                    onSelected: (value) {
                      switch (value) {
                        case 'add':
                          onAddCourse();
                          break;
                        case 'manage':
                          onManageCustomCourses();
                          break;
                        case 'export_ics':
                          onExportIcs();
                          break;
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'add',
                        child: ListTile(
                          leading: Icon(Icons.add),
                          title: Text('添加自定义课程'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'manage',
                        child: ListTile(
                          leading: Icon(Icons.edit_calendar_outlined),
                          title: Text('管理自定义课程'),
                        ),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'export_ics',
                        child: ListTile(
                          leading: Icon(Icons.ios_share_outlined),
                          title: Text('导出 ICS'),
                        ),
                      ),
                    ],
                  ),
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
