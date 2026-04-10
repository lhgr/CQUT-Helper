import 'package:flutter/material.dart';

class ScheduleInlineNoticePanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (notices.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.28;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.9),
        border: Border.all(color: cs.error, width: 1.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.campaign, color: cs.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '调课通知',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onErrorContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: onDismissAll,
                child: const Text('知道了'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: notices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                return Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.error.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 13,
                              height: 1.35,
                            ),
                            children: _buildNoticeSpans(notices[index]),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onDismissOne(index),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
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
        spans.add(TextSpan(text: bold, style: const TextStyle(fontWeight: FontWeight.w700)));
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
