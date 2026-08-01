import 'dart:async';

import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/manager/schedule_refresh_state.dart';
import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/course_detail_dialog.dart';
import 'package:cqut_helper/utils/schedule_date.dart';
import 'package:cqut_helper/utils/widget_navigation.dart';
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
  DateTime? _lastSuccessfulRefreshAt;
  String _dataSource = '缓存';
  int _lastHandledWidgetNavigationToken = 0;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  List<CampusTimeInfo>? get _timeInfoList => _controller.timeInfoList;

  @override
  void initState() {
    super.initState();
    WidgetNavigation.request.addListener(_onWidgetNavigation);
    ScheduleCustomizationManager.instance.addListener(_onCustomizationChanged);
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _loadInitialData();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onWidgetNavigation());
  }

  @override
  void dispose() {
    WidgetNavigation.request.removeListener(_onWidgetNavigation);
    ScheduleCustomizationManager.instance.removeListener(
      _onCustomizationChanged,
    );
    _clockTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onCustomizationChanged() async {
    final current = _scheduleData;
    if (current == null) return;
    final refreshed = await _controller.loadFromCache(
      weekNum: current.weekNum,
      yearTerm: current.yearTerm,
    );
    if (refreshed != null && mounted) {
      setState(() => _scheduleData = refreshed);
    }
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
    _onWidgetNavigation();
  }

  void _onWidgetNavigation() {
    final navigation = WidgetNavigation.request.value;
    final data = _scheduleData;
    if (!mounted ||
        data == null ||
        navigation == null ||
        !navigation.hasCourse ||
        navigation.token == _lastHandledWidgetNavigationToken) {
      return;
    }
    final eventId = navigation.eventId?.trim() ?? '';
    final eventName = navigation.eventName?.trim() ?? '';
    final targetWeekDay = DateTime.now()
        .add(Duration(days: navigation.dayOffset))
        .weekday
        .toString();
    final events = (data.eventList ?? const <EventItem>[])
        .where((event) {
          final sameCourse = eventId.isNotEmpty
              ? (event.eventID ?? '').trim() == eventId
              : (event.eventName ?? '').trim() == eventName;
          return sameCourse && (event.weekDay ?? '').trim() == targetWeekDay;
        })
        .toList(growable: false);
    if (events.isEmpty) return;

    _lastHandledWidgetNavigationToken = navigation.token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showCourseDetailDialog(
        context,
        courseName: (events.first.eventName ?? '').trim(),
        events: events,
        eventDate: DateTime.now(),
        timeInfoList: _timeInfoList,
      );
    });
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
            _dataSource = '缓存';
          });
          await _loadRefreshSnapshot();
        }
      }

      final cacheCoversToday =
          cached != null && ScheduleDate.dataCoversDate(cached, DateTime.now());
      final cacheIsFresh =
          cacheCoversToday && await _controller.isFresh(cached);
      final shouldFetchNetwork =
          forceRefresh || cached == null || !cacheCoversToday || !cacheIsFresh;

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
          _dataSource = '在线';
        });
        await _loadRefreshSnapshot();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _mapError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _loadRefreshSnapshot() async {
    final userId = _controller.userId;
    if (userId == null || userId.trim().isEmpty) return;
    final snapshot = await ScheduleRefreshState.load(userId);
    if (!mounted) return;
    setState(() {
      _lastSuccessfulRefreshAt = snapshot.lastSuccessfulRefreshAt;
    });
  }

  String get _freshnessText {
    final at = _lastSuccessfulRefreshAt;
    if (at == null) return '$_dataSource · 更新时间未知';
    final now = DateTime.now();
    final sameDay =
        now.year == at.year && now.month == at.month && now.day == at.day;
    final date = sameDay ? '今天' : '${at.month}/${at.day}';
    final hour = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    return '$_dataSource · $date $hour:$minute更新';
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
    return sessions.isEmpty ? '节次未知' : '第$sessions节';
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

  _CourseMoment? _courseMoment(List<EventItem> events) {
    final timeInfo = _timeInfoList;
    if (timeInfo == null || timeInfo.isEmpty || events.isEmpty) return null;
    final clocks = <int, ({int start, int end})>{};
    for (final info in timeInfo) {
      final session = info.sessionNum;
      final start = _minuteOfDay(info.startTime);
      final end = _minuteOfDay(info.endTime);
      if (session != null && start != null && end != null) {
        clocks[session] = (start: start, end: end);
      }
    }
    final nowMinute = _now.hour * 60 + _now.minute;
    _CourseMoment? next;
    for (final event in events) {
      final start = clocks[_sessionStart(event)]?.start;
      final end = clocks[_sessionEnd(event)]?.end;
      if (start == null || end == null) continue;
      if (nowMinute >= start && nowMinute < end) {
        return _CourseMoment(
          kind: _CourseMomentKind.ongoing,
          event: event,
          minutes: end - nowMinute,
        );
      }
      if (start > nowMinute) {
        final candidate = _CourseMoment(
          kind: _CourseMomentKind.next,
          event: event,
          minutes: start - nowMinute,
        );
        if (next == null || candidate.minutes < next.minutes) next = candidate;
      }
    }
    return next ??
        _CourseMoment(
          kind: _CourseMomentKind.finished,
          event: events.last,
          minutes: 0,
        );
  }

  int? _minuteOfDay(String? raw) {
    final match = RegExp(r'(\d{1,2})\s*[:：]\s*(\d{1,2})').firstMatch(raw ?? '');
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
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
        appBar: AppBar(title: const Text('今日课表'), centerTitle: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event_busy_outlined, size: 48),
                const SizedBox(height: 16),
                Text(_error ?? '暂无可用的课表数据。'),
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
    final moment = coveredToday ? _courseMoment(events) : null;

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
              freshnessText: _freshnessText,
            ),
            if (moment != null) ...[
              const SizedBox(height: 12),
              _NowNextCard(moment: moment),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              _InfoBanner(icon: Icons.wifi_off_outlined, message: _error!),
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
    final note = (event.note ?? '').trim();
    final startSession = _sessionStart(event);
    final endSession = _sessionEnd(event);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          showCourseDetailDialog(
            context,
            courseName: event.eventName ?? '未命名课程',
            events: [event],
            eventDate: DateTime.now(),
            timeInfoList: _timeInfoList,
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
                      endSession > startSession ? '-$endSession' : '单节',
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
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.tertiary,
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
  final String freshnessText;

  const _SummaryCard({
    required this.title,
    required this.dateText,
    required this.termText,
    required this.weekText,
    required this.freshnessText,
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
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
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
              _MetaChip(label: freshnessText),
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
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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

enum _CourseMomentKind { ongoing, next, finished }

class _CourseMoment {
  final _CourseMomentKind kind;
  final EventItem event;
  final int minutes;

  const _CourseMoment({
    required this.kind,
    required this.event,
    required this.minutes,
  });
}

class _NowNextCard extends StatelessWidget {
  final _CourseMoment moment;

  const _NowNextCard({required this.moment});

  String get _title => switch (moment.kind) {
    _CourseMomentKind.ongoing => '正在上课',
    _CourseMomentKind.next => '下一节课',
    _CourseMomentKind.finished => '今日课程已结束',
  };

  String get _countdown {
    if (moment.kind == _CourseMomentKind.finished) return '辛苦了';
    final hours = moment.minutes ~/ 60;
    final minutes = moment.minutes % 60;
    final duration = hours > 0 ? '$hours小时$minutes分钟' : '$minutes分钟';
    return moment.kind == _CourseMomentKind.ongoing
        ? '距离下课 $duration'
        : '$duration 后开始';
  }

  @override
  Widget build(BuildContext context) {
    final name = (moment.event.eventName ?? '').trim();
    final location = (moment.event.address ?? '').trim();
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              moment.kind == _CourseMomentKind.ongoing
                  ? Icons.play_circle_fill
                  : moment.kind == _CourseMomentKind.next
                  ? Icons.upcoming
                  : Icons.done_all,
              size: 34,
              color: Theme.of(context).colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (moment.kind != _CourseMomentKind.finished)
                    Text(
                      name.isEmpty ? '未命名课程' : name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(
                          context,
                        ).colorScheme.onTertiaryContainer,
                      ),
                    ),
                  if (location.isNotEmpty &&
                      moment.kind != _CourseMomentKind.finished)
                    Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _countdown,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
