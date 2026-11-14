import 'package:cqut_helper/manager/schedule_message_center_manager.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_intents.dart';
import 'package:cqut_helper/pages/Announcement/Announcement.dart';
import 'package:cqut_helper/pages/Settings/app_settings_page.dart';
import 'package:material_ui/material_ui.dart';
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
  String? _error;
  int _loadVersion = 0;
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    ScheduleMessageCenterManager.epoch.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    ScheduleMessageCenterManager.epoch.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _load();

  Future<void> _load() async {
    final version = ++_loadVersion;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = (prefs.getString('account') ?? '').trim();
      final noticeEnhancementEnabled =
          ScheduleSettingsManager.isNoticeEnhancementEnabledIn(prefs);
      final records = await ScheduleMessageCenterManager.load(userId);
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _userId = userId;
        _records = records;
        _noticeEnhancementEnabled = noticeEnhancementEnabled;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loading = false;
        _error = '消息记录加载失败，请重试。';
      });
    }
  }

  Future<void> _saveRead(String key, Future<void> Function() operation) async {
    if (_saving.contains(key)) return;
    setState(() => _saving.add(key));
    try {
      await operation();
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已读状态保存失败'),
            action: SnackBarAction(
              label: '重试',
              onPressed: () => _saveRead(key, operation),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  void _openWeek(ScheduleMessageRecord record, String week) {
    Navigator.of(context).pop();
    ScheduleUpdateIntents.requestOpenWeek(
      userId: record.userId,
      yearTerm: record.yearTerm,
      weekNum: week,
    );
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
    if (confirmed == true) {
      try {
        await ScheduleMessageCenterManager.clear(_userId);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('清空失败，请重试。')));
        }
      }
    }
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
          if (_records.any((record) => !record.read))
            IconButton(
              tooltip: '全部已读',
              onPressed: _saving.contains('all')
                  ? null
                  : () {
                      final account = _userId;
                      _saveRead(
                        'all',
                        () => ScheduleMessageCenterManager.markAllRead(account),
                      );
                    },
              icon: const Icon(Icons.done_all),
            ),
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
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (_error != null)
                    ListTile(
                      title: Text(_error!),
                      trailing: TextButton(
                        onPressed: _load,
                        child: const Text('重试'),
                      ),
                    ),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: const Icon(Icons.campaign_outlined),
                      title: const Text('应用公告'),
                      subtitle: const Text('版本与服务通知'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AnnouncementListPage(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_noticeEnhancementEnabled) ...[
                    Card(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '调课通知增强未开启',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '未查询调课通知，仅显示本机记录与同步变更。',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _openNotificationSettings,
                                child: const Text('通知设置'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    '课表变更记录',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_noticeEnhancementEnabled) ...[
                    const SizedBox(height: 4),
                    Text(
                      '记录保存在本机',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_records.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(child: Text('暂无课表变更记录')),
                      ),
                    )
                  else
                    ..._records.map(
                      (record) => Card(
                        key: ValueKey('message-${record.id}'),
                        margin: const EdgeInsets.only(bottom: 8),
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          key: PageStorageKey('message-${record.id}'),
                          onExpansionChanged: (expanded) {
                            if (expanded && !record.read) {
                              _saveRead(
                                record.id,
                                () => ScheduleMessageCenterManager.markRead(
                                  record.userId,
                                  record.id,
                                ),
                              );
                            }
                          },
                          leading: record.read
                              ? null
                              : Semantics(
                                  label: '未读',
                                  child: Icon(
                                    Icons.circle,
                                    size: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                ),
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          childrenPadding: const EdgeInsets.only(bottom: 4),
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
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
                                    if (record.yearTerm.trim().isNotEmpty &&
                                        (int.tryParse(change.weekNum) ?? 0) > 0)
                                      TextButton(
                                        onPressed: () =>
                                            _openWeek(record, change.weekNum),
                                        child: const Text('查看该周课表'),
                                      )
                                    else
                                      const Text('该记录缺少学期或周次，无法定位课表'),
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
