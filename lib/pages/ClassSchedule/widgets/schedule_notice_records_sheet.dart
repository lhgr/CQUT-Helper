import 'package:cqut_helper/model/schedule_notice.dart';
import 'package:flutter/material.dart';

void showScheduleNoticeRecordsSheet(
  BuildContext context, {
  required String yearTerm,
  required List<ScheduleNotice> initialNotices,
  String initialGeneratedAt = '',
  String tipMessage = '',
  Future<ScheduleNoticePollData> Function()? onRefresh,
}) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return _ScheduleNoticeRecordsSheetBody(
        yearTerm: yearTerm,
        initialNotices: initialNotices,
        initialGeneratedAt: initialGeneratedAt,
        tipMessage: tipMessage,
        onRefresh: onRefresh,
      );
    },
  );
}

class _ScheduleNoticeRecordsSheetBody extends StatefulWidget {
  final String yearTerm;
  final List<ScheduleNotice> initialNotices;
  final String initialGeneratedAt;
  final String tipMessage;
  final Future<ScheduleNoticePollData> Function()? onRefresh;

  const _ScheduleNoticeRecordsSheetBody({
    required this.yearTerm,
    required this.initialNotices,
    required this.initialGeneratedAt,
    required this.tipMessage,
    required this.onRefresh,
  });

  @override
  State<_ScheduleNoticeRecordsSheetBody> createState() =>
      _ScheduleNoticeRecordsSheetBodyState();
}

class _ScheduleNoticeRecordsSheetBodyState
    extends State<_ScheduleNoticeRecordsSheetBody> {
  late List<ScheduleNotice> _notices;
  late String _generatedAt;
  bool _refreshing = false;
  String _refreshErrorMessage = '';

  @override
  void initState() {
    super.initState();
    _notices = List.of(widget.initialNotices);
    _generatedAt = widget.initialGeneratedAt;
    _refresh();
  }

  Future<void> _refresh() async {
    if (widget.onRefresh == null) return;
    setState(() {
      _refreshing = true;
    });
    try {
      final result = await widget.onRefresh!.call();
      if (!mounted) return;
      final notices = List.of(result.notices);
      notices.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      setState(() {
        _notices = notices;
        _generatedAt = result.generatedAt;
        _refreshErrorMessage = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _refreshErrorMessage = '获取最新调课记录失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.yearTerm.trim().isEmpty
        ? '当前学期'
        : '${widget.yearTerm} 学期';
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('$title 调课记录'),
              subtitle: Text(
                _refreshing
                    ? '正在获取最新数据...'
                    : _generatedAt.trim().isEmpty
                    ? '共 ${_notices.length} 条'
                    : '共 ${_notices.length} 条 · 同步于 $_generatedAt',
              ),
              trailing: IconButton(
                onPressed: _refreshing ? null : _refresh,
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
              ),
            ),
            const Divider(height: 1),
            if (widget.tipMessage.trim().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Text(
                  widget.tipMessage,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (_refreshErrorMessage.trim().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: Theme.of(context).colorScheme.errorContainer,
                child: Text(
                  _refreshErrorMessage,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            if (_notices.isEmpty)
              const Expanded(child: Center(child: Text('暂无调课记录')))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _notices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final n = _notices[index];
                    final timeText = n.adjustedTime ?? n.originalTime ?? '-';
                    final roomText =
                        n.adjustedClassroom ?? n.originalClassroom ?? '-';
                    final subtitleParts = <String>[
                      if (n.publishedAt.isNotEmpty) n.publishedAt,
                      if ((n.courseName ?? '').isNotEmpty) n.courseName!,
                      if ((n.teacher ?? '').isNotEmpty) n.teacher!,
                      if (timeText.isNotEmpty) timeText,
                      if (roomText.isNotEmpty) roomText,
                    ];
                    return ListTile(
                      title: Text(n.title.isEmpty ? '调课通知' : n.title),
                      subtitle: Text(subtitleParts.join('\n')),
                      isThreeLine: true,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
