import 'package:cqut_helper/theme/app_theme.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

class ScheduleInlineNoticePanel extends StatefulWidget {
  final List<String> notices;
  final ValueChanged<int> onDismissOne;
  final VoidCallback onDismissAll;

  const ScheduleInlineNoticePanel({
    super.key,
    required this.notices,
    required this.onDismissOne,
    required this.onDismissAll,
  });

  @override
  State<ScheduleInlineNoticePanel> createState() =>
      _ScheduleInlineNoticePanelState();
}

class _ScheduleInlineNoticePanelState extends State<ScheduleInlineNoticePanel> {
  ValueNotifier<List<String>>? _sheetNotices;

  @override
  void didUpdateWidget(covariant ScheduleInlineNoticePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSheet();
  }

  void _syncSheet() {
    final notifier = _sheetNotices;
    if (notifier == null) return;
    // The sheet lives in a separate route: update it after the parent build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sheetNotices != notifier) return;
      final notices = mounted ? List<String>.of(widget.notices) : <String>[];
      if (!listEquals(notifier.value, notices)) notifier.value = notices;
    });
  }

  @override
  void dispose() {
    _syncSheet();
    super.dispose();
  }

  Future<void> _openDetails() async {
    if (_sheetNotices != null) return;
    final notifier = ValueNotifier(List<String>.of(widget.notices));
    _sheetNotices = notifier;
    try {
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (sheetContext) => ValueListenableBuilder<List<String>>(
          valueListenable: notifier,
          builder: (context, notices, _) {
            if (notices.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (sheetContext.mounted &&
                    ModalRoute.of(sheetContext)?.isCurrent == true) {
                  Navigator.of(sheetContext).pop();
                }
              });
              return const SizedBox.shrink();
            }
            final theme = Theme.of(context);
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .8,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '调课通知',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ],
                    ),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: notices.length,
                        separatorBuilder: (_, _) => const Divider(height: 16),
                        itemBuilder: (context, index) => Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text.rich(
                                  TextSpan(
                                    children: _buildNoticeSpans(notices[index]),
                                  ),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '关闭此通知',
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () {
                                if (!mounted) return;
                                // Never apply a stale row index to a replaced parent list.
                                if (!listEquals(notices, notifier.value) ||
                                    !listEquals(notices, widget.notices)) {
                                  _syncSheet();
                                  return;
                                }
                                if (notices.length == 1) {
                                  Navigator.of(sheetContext).pop();
                                }
                                notifier.value = List<String>.of(notices)
                                  ..removeAt(index);
                                widget.onDismissOne(index);
                                _syncSheet();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          if (notifier.value.isEmpty) return;
                          notifier.value = const [];
                          Navigator.of(sheetContext).pop();
                          if (mounted) widget.onDismissAll();
                        },
                        child: const Text('知道了'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } finally {
      _sheetNotices = null;
      notifier.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.notices.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.controlRadius),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: true,
          hint: '查看调课通知',
          child: InkWell(
            key: const ValueKey('schedule-inline-notice-summary'),
            onTap: _openDetails,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.campaign_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.notices.length}条调课通知',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<InlineSpan> _buildNoticeSpans(String text) {
    final spans = <InlineSpan>[];
    final reg = RegExp(r'\*\*(.*?)\*\*');
    int start = 0;
    for (final m in reg.allMatches(text)) {
      if (m.start > start) {
        spans.add(TextSpan(text: text.substring(start, m.start)));
      }
      final bold = (m.group(1) ?? '').trim();
      if (bold.isNotEmpty) {
        spans.add(
          TextSpan(
            text: bold,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      }
      start = m.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text));
    }
    return spans;
  }
}
