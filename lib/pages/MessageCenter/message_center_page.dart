import 'package:cqut_helper/manager/schedule_message_center_manager.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/pages/Announcement/Announcement.dart';
import 'package:cqut_helper/pages/Settings/app_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MessageCenterPage extends StatefulWidget {
  const MessageCenterPage({super.key});

  @override
  State<MessageCenterPage> createState() => _MessageCenterPageState();
}

class _MessageCenterPageState extends State<MessageCenterPage> {
  String _userId = '';
  List<ScheduleMessageRecord> _records = const [];
  bool _noticeEnhancementEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ScheduleMessageCenterManager.epoch.addListener(_reload);
    _load(markRead: true);
  }

  @override
  void dispose() {
    ScheduleMessageCenterManager.epoch.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _load();

  Future<void> _load({bool markRead = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = (prefs.getString('account') ?? '').trim();
    final noticeEnhancementEnabled =
        ScheduleSettingsManager.isNoticeEnhancementEnabledIn(prefs);
    var records = await ScheduleMessageCenterManager.load(userId);
    if (markRead && records.any((record) => !record.read)) {
      await ScheduleMessageCenterManager.markAllRead(userId);
      records = await ScheduleMessageCenterManager.load(userId);
    }
    if (!mounted) return;
    setState(() {
      _userId = userId;
      _records = records;
      _noticeEnhancementEnabled = noticeEnhancementEnabled;
      _loading = false;
    });
  }

  Future<void> _openNotificationSettings() async {
    await openAppSettings(
      context,
      section: AppSettingsSection.notifications,
      userId: _userId,
    );
    if (mounted) await _load();
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空调课记录？'),
        content: const Text('只会删除本机消息历史，不会修改学校课表。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) await ScheduleMessageCenterManager.clear(_userId);
  }

  String _time(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.month}/${value.day} ${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息中心'),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              onPressed: _clear,
              tooltip: '清空调课记录',
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: const Icon(Icons.campaign_outlined),
                      title: const Text('应用公告'),
                      subtitle: const Text('版本说明、服务状态和重要通知'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AnnouncementListPage(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!_noticeEnhancementEnabled) ...[
                    Card(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('调课通知增强未开启'),
                        subtitle: const Text(
                          '不会访问官方或第三方调课通知接口；下方仅展示普通课表同步在本机检测到的差异和既有记录，不代表已查询调课通知。',
                        ),
                        trailing: TextButton(
                          onPressed: _openNotificationSettings,
                          child: const Text('去开启'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    _noticeEnhancementEnabled ? '课表变更记录' : '课表变更记录（仅本地）',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_records.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            _noticeEnhancementEnabled
                                ? '暂无调课或课表变更记录'
                                : '暂无本地课表变更记录',
                          ),
                        ),
                      ),
                    )
                  else
                    ..._records.map(
                      (record) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ExpansionTile(
                          leading: Icon(
                            Icons.swap_horiz_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(
                            record.changes.length == 1
                                ? '第${record.changes.first.weekNum}周课表有变更'
                                : '${record.changes.length}周课表有变更',
                          ),
                          subtitle: Text(
                            '${record.yearTerm.isEmpty ? '当前学期' : record.yearTerm} · ${_time(record.createdAt)}',
                          ),
                          children: [
                            for (final change in record.changes)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  14,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '第${change.weekNum}周',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelLarge,
                                    ),
                                    const SizedBox(height: 4),
                                    for (final line
                                        in change.lines.isEmpty
                                            ? const ['课表有更新，未能解析具体内容']
                                            : change.lines)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text('· $line'),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
