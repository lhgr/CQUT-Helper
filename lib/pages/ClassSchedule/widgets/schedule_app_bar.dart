import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:material_ui/material_ui.dart';

void _noopScheduleAction() {}

class ScheduleAppBar extends StatelessWidget implements PreferredSizeWidget {
  late final ({bool stacked, double height, double weekWidth, double termWidth})
  _layout;
  late final TextStyle _titleStyle;
  late final TextStyle _termStyle;
  late final TextHeightBehavior? _textHeightBehavior;

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

  ScheduleAppBar({
    super.key,
    required BuildContext context,
    required double availableWidth,
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
  }) {
    final theme = Theme.of(context);
    final defaults = DefaultTextStyle.of(context);
    _textHeightBehavior = defaults.textHeightBehavior;
    TextStyle resolvedStyle(TextStyle? style) {
      final resolved = defaults.style.merge(style);
      return resolved.copyWith(
        inherit: false,
        fontWeight: MediaQuery.boldTextOf(context)
            ? FontWeight.bold
            : resolved.fontWeight,
      );
    }

    _titleStyle = resolvedStyle(
      theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
    _termStyle = resolvedStyle(theme.textTheme.bodySmall);
    final width = (availableWidth - 112).clamp(1.0, double.infinity);
    double measure(
      String text,
      TextStyle? style, {
      double maxWidth = double.infinity,
      bool height = false,
    }) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        textHeightBehavior: _textHeightBehavior,
      )..layout(maxWidth: maxWidth);
      final result = height ? painter.height : painter.width;
      painter.dispose();
      return result;
    }

    final titleStyle = _titleStyle;
    final termStyle = _termStyle;
    final weekWidth = (measure(_weekLabel, titleStyle) + 16).clamp(
      48.0,
      double.infinity,
    );
    final termWidth = currentScheduleData == null
        ? 0.0
        : (measure(_termLabel, termStyle) + 16).clamp(48.0, double.infinity);
    final stacked = weekWidth + termWidth > width;
    double buttonHeight(String label, TextStyle? style) =>
        (measure(
                  label,
                  style,
                  maxWidth: (width - 16).clamp(1.0, double.infinity),
                  height: true,
                ) +
                12)
            .clamp(48.0, double.infinity);
    final height = stacked
        ? buttonHeight(_weekLabel, titleStyle) +
              (currentScheduleData == null
                  ? 0
                  : buttonHeight(_termLabel, termStyle))
        : [
            buttonHeight(_weekLabel, titleStyle),
            if (currentScheduleData != null)
              buttonHeight(_termLabel, termStyle),
          ].reduce((a, b) => a > b ? a : b);
    _layout = (
      stacked: stacked,
      height: height + 8,
      weekWidth: weekWidth,
      termWidth: termWidth,
    );
  }

  String get _termLabel => '${currentScheduleData!.yearTerm}学期';
  String get _weekLabel =>
      nowInTeachingWeek == false &&
          nowStatusLabel?.isNotEmpty == true &&
          weekList != null &&
          currentWeekIndex < weekList!.length
      ? '$nowStatusLabel · 第${weekList![currentWeekIndex]}周'
      : weekList != null && currentWeekIndex < weekList!.length
      ? '第${weekList![currentWeekIndex]}周'
      : '课表';

  @override
  Size get preferredSize => Size.fromHeight(_layout.height);

  @override
  Widget build(BuildContext context) {
    const double sideSlotWidth = 48;

    Widget buildPickerButton({
      required String label,
      required VoidCallback onTap,
      required TextStyle? textStyle,
    }) {
      return Tooltip(
        message: label,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
          child: Text(
            label,
            style: textStyle,
            textAlign: TextAlign.center,
            textHeightBehavior: _textHeightBehavior,
          ),
        ),
      );
    }

    Widget buildRefreshAction() {
      final status = refreshStatusText;
      final color = Theme.of(context).colorScheme.onSurfaceVariant;
      return Semantics(
        button: true,
        label: status == null ? '刷新课表' : '刷新课表，最后更新$status',
        child: IconButton(
          onPressed: loading ? null : onRefresh,
          tooltip: status == null ? '刷新课表' : '最后更新：$status',
          style: IconButton.styleFrom(
            sizeVariant: ButtonSizeVariant.small,
            iconButtonWidth: IconButtonWidthVariant.narrow,
            minimumSize: const Size(48, 48),
          ),
          icon: loading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : const Icon(Icons.refresh),
        ),
      );
    }

    final titleTextStyle = _titleStyle;
    final termTextStyle = _termStyle.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final weekButton = buildPickerButton(
      label: _weekLabel,
      onTap: onWeekPicker,
      textStyle: titleTextStyle,
    );
    final termButton = currentScheduleData == null
        ? null
        : buildPickerButton(
            label: _termLabel,
            onTap: onTermPicker,
            textStyle: termTextStyle,
          );

    return AppBar(
      toolbarHeight: _layout.height,
      titleSpacing: 8,
      leadingWidth: sideSlotWidth,
      automaticallyImplyLeading: false,
      scrolledUnderElevation: 0,
      backgroundColor: transparentBackground
          ? Theme.of(context).colorScheme.surface.withAlpha(240)
          : Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      leading: Center(child: buildRefreshAction()),
      actions: [
        SizedBox(
          width: sideSlotWidth,
          child: Center(
            child: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
        ),
      ],
      title: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: _layout.stacked
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [weekButton, ?termButton],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: _layout.weekWidth, child: weekButton),
                  if (termButton != null)
                    SizedBox(width: _layout.termWidth, child: termButton),
                ],
              ),
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

      void runAction(VoidCallback action) {
        Navigator.of(sheetContext).pop();
        action();
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('课表操作', style: theme.textTheme.titleMedium),
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
                    title: '导出ICS',
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
    return ListTile(
      minTileHeight: 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
