import 'package:material_ui/material_ui.dart';

enum UsageGuideChapter { schedule, reminders, widgets }

class UsageGuidePage extends StatefulWidget {
  const UsageGuidePage({super.key, this.initialChapter});

  final UsageGuideChapter? initialChapter;

  @override
  State<UsageGuidePage> createState() => _UsageGuidePageState();
}

class _UsageGuidePageState extends State<UsageGuidePage> {
  final _scheduleKey = GlobalKey();
  final _remindersKey = GlobalKey();
  final _widgetsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.initialChapter != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          _keyFor(widget.initialChapter!).currentContext!,
          alignment: 0.08,
          duration: const Duration(milliseconds: 250),
        );
      });
    }
  }

  GlobalKey _keyFor(UsageGuideChapter chapter) => switch (chapter) {
    UsageGuideChapter.schedule => _scheduleKey,
    UsageGuideChapter.reminders => _remindersKey,
    UsageGuideChapter.widgets => _widgetsKey,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('使用指南')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GuideChapter(
              key: _scheduleKey,
              icon: Icons.calendar_month_outlined,
              title: '查看课表',
              paragraphs: const ['点周次切换要查看的周，点课程可查看课程详情。', '课表缓存后可离线查看。'],
            ),
            const SizedBox(height: 12),
            _GuideChapter(
              key: _remindersKey,
              icon: Icons.notifications_none_rounded,
              title: '课前提醒',
              paragraphs: const ['前往“设置 → 通知与提醒 → 课前提醒”进行设置。'],
            ),
            const SizedBox(height: 12),
            _GuideChapter(
              key: _widgetsKey,
              icon: Icons.widgets_outlined,
              title: '桌面小组件',
              paragraphs: const [
                '长按手机桌面空白处 → 打开小组件列表 → 找到 CQUT Helper → 选择样式并添加。',
                '不同桌面的入口名称可能不同。',
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideChapter extends StatelessWidget {
  const _GuideChapter({
    super.key,
    required this.icon,
    required this.title,
    required this.paragraphs,
  });

  final IconData icon;
  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final paragraph in paragraphs) ...[
              Text(paragraph, style: Theme.of(context).textTheme.bodyMedium),
              if (paragraph != paragraphs.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
