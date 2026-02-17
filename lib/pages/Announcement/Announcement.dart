import 'package:cqut/manager/announcement_manager.dart';
import 'package:cqut/model/announcement_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
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

  String _formatMarkdown(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final buffer = StringBuffer();
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isNotEmpty && !line.endsWith('  ')) {
        buffer.write(line);
        buffer.write('  ');
      } else {
        buffer.write(line);
      }
      if (i != lines.length - 1) buffer.write('\n');
    }
    return buffer.toString();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开链接')));
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
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                ),
                actions: [
                  FilledButton(
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
                  : (failure.type == AnnouncementFailureType.backend
                        ? '后端服务异常：${failure.message}'
                        : '用户侧问题：${failure.message}');
              return AlertDialog(
                title: Text(item.title),
                content: Text(text),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('关闭'),
                  ),
                ],
              );
            }

            return AlertDialog(
              title: Row(
                children: [
                  Expanded(child: Text(detail.title)),
                ],
              ),
              content: SingleChildScrollView(
                child: MarkdownBody(
                  data: _formatMarkdown(detail.contentMarkdown),
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
                  onTapLink: (text, href, title) {
                    if (href == null || href.isEmpty) return;
                    _launchExternalUrl(context, href);
                  },
                ),
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
                FilledButton(
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
                children: [
                  SizedBox(height: 320),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }

            final data = snapshot.data;
            final items = data?.items ?? const <AnnouncementModel>[];
            final failure = data?.failure;
            final showFailureBanner = failure != null && items.isNotEmpty;

            if (items.isEmpty) {
              if (failure != null) {
                final text = failure.type == AnnouncementFailureType.backend
                    ? '后端服务异常：${failure.message}'
                    : '用户侧问题：${failure.message}';
                return ListView(
                  children: [
                    SizedBox(height: 240),
                    Center(child: Text(text)),
                  ],
                );
              }
              return ListView(
                children: [
                  SizedBox(height: 240),
                  Center(child: Text('暂无公告')),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length + (showFailureBanner ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (showFailureBanner && index == 0) {
                  final text = failure.type == AnnouncementFailureType.backend
                      ? '后端服务异常：${failure.message}'
                      : '用户侧问题：${failure.message}';
                  return Card(
                    elevation: 0,
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(text),
                    ),
                  );
                }

                final item = items[showFailureBanner ? index - 1 : index];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      width: 1,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openDetail(item),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.campaign_outlined,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _formatTime(item.updatedAt),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
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
