import 'dart:async';

import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/course_detail_dialog.dart';
import 'package:cqut_helper/utils/schedule_date.dart';
import 'package:flutter/material.dart';

class TodayScheduleView extends StatefulWidget {
  const TodayScheduleView({super.key});

  @override
  State<TodayScheduleView> createState() => _TodayScheduleViewState();
}

class _TodayScheduleViewState extends State<TodayScheduleView> {
  final ScheduleController _controller = ScheduleController();

  ScheduleData? _scheduleData;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  List<CampusTimeInfo>? get _timeInfoList => _controller.timeInfoList;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    unawaited(
      _controller.loadTimeInfoFromCacheIfAny().then((loaded) {
        if (loaded && mounted) {
          setState(() {});
        }
      }),
    );
    unawaited(
      _controller.refreshTimeInfoIfEnabled().then((changed) {
        if (changed && mounted) {
          setState(() {});
        }
      }),
    );
    await _loadSchedule();
  }

  Future<void> _loadSchedule({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      if (forceRefresh) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _error = null;
    });

    ScheduleData? cached;
    try {
      if (!forceRefresh) {
        cached = await _controller.loadFromCache();
        if (cached != null && mounted) {
          setState(() {
            _scheduleData = cached;
            _loading = false;
          });
        }
      }

      final shouldFetchNetwork =
          forceRefresh ||
          cached == null ||
          !ScheduleDate.dataCoversDate(cached, DateTime.now());

      if (shouldFetchNetwork) {
        final networkData = await _controller.loadFromNetwork(
          persistLastViewed: false,
          updateWidgetPins: false,
        );
        _controller.processLoadedData(networkData);
        if (!mounted) return;
        setState(() {
          _scheduleData = networkData;
          _error = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _mapError(e);
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  String _mapError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('login')) {
      return '需要登录后才能查看今日课表。';
    }
    if (text.contains('credential')) {
      return '登录凭证已失效，请重新登录。';
    }
    return '加载今日课表失败：$error';
  }

  WeekDayItem? _todayWeekDayItem(ScheduleData data) {
    final weekDayList = data.weekDayList ?? const <WeekDayItem>[];
    for (final item in weekDayList) {
      if (item.today == true) return item;
    }
    final todayWeekDay = DateTime.now().weekday.toString();
    for (final item in weekDayList) {
      if ((item.weekDay ?? '').trim() == todayWeekDay) return item;
    }
    return null;
  }

  int _todayWeekDayNum(ScheduleData data) {
    final item = _todayWeekDayItem(data);
    final parsed = int.tryParse((item?.weekDay ?? '').trim());
    if (parsed != null && parsed >= 1 && parsed <= 7) return parsed;
    return DateTime.now().weekday;
  }

  List<EventItem> _todayEvents(ScheduleData data) {
    final weekDay = _todayWeekDayNum(data).toString();
    final events = (data.eventList ?? const <EventItem>[])
        .where((event) => (event.weekDay ?? '').trim() == weekDay)
        .toList(growable: false);
    events.sort((a, b) {
      final bySession = _sessionStart(a).compareTo(_sessionStart(b));
      if (bySession != 0) return bySession;
      final byEnd = _sessionEnd(a).compareTo(_sessionEnd(b));
      if (byEnd != 0) return byEnd;
      return (a.eventName ?? '').compareTo(b.eventName ?? '');
    });
    return events;
  }

  int _sessionStart(EventItem event) {
    final parsed = int.tryParse((event.sessionStart ?? '').trim());
    if (parsed != null && parsed > 0) return parsed;
    var minSession = 99;
    for (final raw in event.sessionList ?? const <String>[]) {
      final value = int.tryParse(raw.trim());
      if (value != null && value > 0 && value < minSession) {
        minSession = value;
      }
    }
    return minSession == 99 ? 99 : minSession;
  }

  int _sessionLast(EventItem event) {
    final parsed = int.tryParse((event.sessionLast ?? '').trim());
    if (parsed != null && parsed > 0) return parsed;
    final sessions = event.sessionList ?? const <String>[];
    return sessions.isEmpty ? 1 : sessions.length;
  }

  int _sessionEnd(EventItem event) {
    final start = _sessionStart(event);
    if (start <= 0 || start >= 99) return start;
    return start + _sessionLast(event) - 1;
  }

  String _sessionLabel(EventItem event) {
    final start = _sessionStart(event);
    final end = _sessionEnd(event);
    if (start > 0 && start < 99 && end >= start) {
      return '第$start-$end节';
    }
    final sessions = (event.sessionList ?? const <String>[])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join('、');
    return sessions.isEmpty
        ? '节次未知'
        : '第$sessions节';
  }

  String? _timeRangeLabel(EventItem event) {
    final timeInfoList = _timeInfoList;
    if (timeInfoList == null || timeInfoList.isEmpty) return null;

    final startNum = _sessionStart(event);
    final endNum = _sessionEnd(event);
    if (startNum <= 0 || endNum < startNum) return null;

    CampusTimeInfo? startInfo;
    CampusTimeInfo? endInfo;
    for (final info in timeInfoList) {
      if (info.sessionNum == startNum) startInfo = info;
      if (info.sessionNum == endNum) endInfo = info;
    }
    final start = (startInfo?.startTime ?? '').trim();
    final end = (endInfo?.endTime ?? '').trim();
    if (start.isEmpty || end.isEmpty) return null;
    return '$start - $end';
  }

  bool _isTodayCovered(ScheduleData data) {
    return ScheduleDate.dataCoversDate(data, DateTime.now());
  }

  String _weekDayLabel(int weekDay) {
    const labels = <int, String>{
      1: '周一',
      2: '周二',
      3: '周三',
      4: '周四',
      5: '周五',
      6: '周六',
      7: '周日',
    };
    return labels[weekDay] ?? '今天';
  }

  @override
  Widget build(BuildContext context) {
    final data = _scheduleData;

    if (_loading && data == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (data == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('今日课表'),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event_busy_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  _error ??
                      '暂无可用的课表数据。',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _loadSchedule(forceRefresh: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final now = DateTime.now();
    final weekDayNum = _todayWeekDayNum(data);
    final weekDayItem = _todayWeekDayItem(data);
    final coveredToday = _isTodayCovered(data);
    final events = coveredToday ? _todayEvents(data) : const <EventItem>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('今日课表'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _refreshing
                ? null
                : () => _loadSchedule(forceRefresh: true),
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadSchedule(forceRefresh: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _SummaryCard(
              title: _weekDayLabel(weekDayNum),
              dateText: weekDayItem?.weekDate ?? '${now.month}-${now.day}',
              termText: data.yearTerm?.trim().isNotEmpty == true
                  ? data.yearTerm!.trim()
                  : '当前学期',
              weekText: data.weekNum?.trim().isNotEmpty == true
                  ? '第${data.weekNum!.trim()}周'
                  : '本周',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _InfoBanner(
                icon: Icons.wifi_off_outlined,
                message: _error!,
              ),
            ],
            const SizedBox(height: 16),
            if (!coveredToday)
              const _EmptyState(
                icon: Icons.event_note_outlined,
                title: '当前不在教学周',
                message: '今天不在当前课表对应的教学周范围内。',
              )
            else if (events.isEmpty)
              const _EmptyState(
                icon: Icons.free_breakfast_outlined,
                title: '今天没课',
                message: '今天没有排课。',
              )
            else
              ...events.map((event) => _buildEventCard(context, event)),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, EventItem event) {
    final timeRange = _timeRangeLabel(event);
    final sessionLabel = _sessionLabel(event);
    final location = (event.address ?? '').trim();
    final teacher = (event.memberName ?? '').trim();
    final startSession = _sessionStart(event);
    final endSession = _sessionEnd(event);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          showCourseDetailDialog(
            context,
            courseName: event.eventName ?? '未命名课程',
            events: [event],
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '$startSession',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      endSession > startSession
                          ? '-$endSession'
                          : '单节',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (event.eventName ?? '').trim().isEmpty
                          ? '未命名课程'
                          : event.eventName!.trim(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      timeRange == null
                          ? sessionLabel
                          : '$sessionLabel  |  $timeRange',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '地点：$location',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    if (teacher.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '教师：$teacher',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String dateText;
  final String termText;
  final String weekText;

  const _SummaryCard({
    required this.title,
    required this.dateText,
    required this.termText,
    required this.weekText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(dateText, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(label: weekText),
              _MetaChip(label: termText),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;

  const _MetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(180),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;

  const _InfoBanner({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            icon,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
