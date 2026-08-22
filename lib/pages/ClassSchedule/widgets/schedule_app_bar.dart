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
  final VoidCallback onAddCourse;
  final VoidCallback onExportIcs;
  final bool transparentBackground;

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
    this.onAddCourse = _noopScheduleAction,
    this.onExportIcs = _noopScheduleAction,
    this.transparentBackground = false,
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

    Widget buildRefreshAction() {
      final status = refreshStatusText;
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
      leading: const SizedBox.shrink(),
      scrolledUnderElevation: 0,
      backgroundColor: transparentBackground
          ? Colors.transparent
          : Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      actions: [
        SizedBox(
          width: sideSlotWidth,
          child: Padding(
            padding: const EdgeInsets.only(right: sideHorizontalPadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                buildRefreshAction(),
                SizedBox(
                  width: 40,
                  height: 44,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: '更多课表操作',
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () => _showScheduleActionsSheet(
                      context,
                      onAddCourse: onAddCourse,
                      onExportIcs: onExportIcs,
                      onSettings: onSettings,
                    ),
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

void _showScheduleActionsSheet(
  BuildContext context, {
  required VoidCallback onAddCourse,
  required VoidCallback onExportIcs,
  required VoidCallback onSettings,
}) {
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colorScheme = theme.colorScheme;

      void runAction(VoidCallback action) {
        Navigator.of(sheetContext).pop();
        action();
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.calendar_month_outlined,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('课表操作', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          '添加、导出或调整当前课表',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              color: colorScheme.surfaceContainerHigh,
              child: Column(
                children: [
                  _ScheduleActionTile(
                    icon: Icons.add_rounded,
                    title: '添加自定义课程',
                    onTap: () => runAction(onAddCourse),
                  ),
                  const Divider(indent: 72),
                  _ScheduleActionTile(
                    icon: Icons.ios_share_outlined,
                    title: '导出 ICS',
                    onTap: () => runAction(onExportIcs),
                  ),
                  const Divider(indent: 72),
                  _ScheduleActionTile(
                    icon: Icons.tune_rounded,
                    title: '课表设置',
                    onTap: () => runAction(onSettings),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ScheduleActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ScheduleActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 72,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: colorScheme.onSecondaryContainer, size: 22),
      ),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
