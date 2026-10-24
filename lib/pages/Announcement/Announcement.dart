import 'package:cqut_helper/manager/announcement_manager.dart';
import 'package:cqut_helper/model/announcement_model.dart';
import 'package:cqut_helper/widgets/release_notes_markdown.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class AnnouncementListPage extends StatefulWidget {
  const AnnouncementListPage({super.key});

  @override
  State<AnnouncementListPage> createState() => _AnnouncementListPageState();
}

class _AnnouncementListPageState extends State<AnnouncementListPage> {
  late Future<AnnouncementListResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _load(forceRefresh: false);
  }

  Future<AnnouncementListResult> _load({required bool forceRefresh}) async {
    return AnnouncementManager().getAnnouncements(
      forceRefresh: forceRefresh,
      activeOnly: false,
    );
  }

  String _formatTime(String raw) {
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load(forceRefresh: true);
    });
    await _future;
    if (mounted) setState(() {});
  }

  Future<void> _launchExternalUrl(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开链接')));
      }
    }
  }

  void _openDetail(AnnouncementModel item) {
    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<AnnouncementDetailResult>(
          future: AnnouncementManager().getAnnouncementDetail(item.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return AlertDialog(
                title: Text(item.title),
                content: const SizedBox(
                  height: 112,
                  child: Center(child: CircularProgressIndicator()),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('关闭'),
                  ),
                ],
              );
            }

            final result = snapshot.data;
            final failure = result?.failure;
            final detail = result?.item;

            if (detail == null) {
              final text = failure == null
                  ? '获取公告详情失败，请稍后重试'
                  : announcementFailureDisplayText(failure);
              return AlertDialog(
                scrollable: true,
                title: Text(item.title),
                content: Text(text),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('关闭'),
                  ),
                ],
              );
            }

            return AlertDialog(
              scrollable: true,
              title: Row(children: [Expanded(child: Text(detail.title))]),
              content: ReleaseNotesMarkdown(
                data: detail.contentMarkdown,
                onTapLink: (href) => _launchExternalUrl(context, href),
              ),
              actions: [
                if (detail.linkUrl != null && detail.linkUrl!.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _launchExternalUrl(context, detail.linkUrl!);
                    },
                    child: Text('打开链接'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('关闭'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('公告')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<AnnouncementListResult>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Center(child: CircularProgressIndicator()),
                  SizedBox(height: 180),
                ],
              );
            }

            final data = snapshot.data;
            final items = data?.items ?? const <AnnouncementModel>[];
            final failure = data?.failure;
            final showFailureBanner = failure != null && items.isNotEmpty;

            if (items.isEmpty) {
              if (failure != null) {
                final text = announcementFailureDisplayText(failure);
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    const SizedBox(height: 112),
                    _AnnouncementState(
                      icon: Icons.cloud_off_outlined,
                      title: '公告暂时无法加载',
                      message: text,
                    ),
                  ],
                );
              }
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(height: 112),
                  _AnnouncementState(
                    icon: Icons.campaign_outlined,
                    title: '暂无公告',
                    message: '有新消息时会显示在这里。',
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length + (showFailureBanner ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (showFailureBanner && index == 0) {
                  final text = announcementFailureDisplayText(failure);
                  return Card(
                    elevation: 0,
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(text)),
                        ],
                      ),
                    ),
                  );
                }

                final item = items[showFailureBanner ? index - 1 : index];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      width: 1,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openDetail(item),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _formatTime(item.updatedAt),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AnnouncementState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _AnnouncementState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, color: colors.onSurfaceVariant, size: 28),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
