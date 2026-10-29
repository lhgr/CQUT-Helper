import 'dart:async';

import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/manager/academic_calendar_manager.dart';
import 'package:cqut_helper/manager/schedule_refresh_state.dart';
import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/course_detail_dialog.dart';
import 'package:cqut_helper/pages/TodaySchedule/widgets/daily_quote_card.dart';
import 'package:cqut_helper/utils/schedule_date.dart';
import 'package:cqut_helper/utils/academic_calendar_resolver.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/widget_navigation.dart';
import 'package:cqut_helper/pages/Login/Login.dart';
import 'package:cqut_helper/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

class TodayScheduleView extends StatefulWidget {
  final bool isActive;

  const TodayScheduleView({super.key, this.isActive = true});

  @override
  State<TodayScheduleView> createState() => _TodayScheduleViewState();
}

class _TodayScheduleViewState extends State<TodayScheduleView> {
  final ScheduleController _controller = ScheduleController();

  ScheduleData? _scheduleData;
  bool _loading = true;
  String? _error;
  DateTime? _lastSuccessfulRefreshAt;
  String _dataSource = '缓存';
  AcademicCalendarSnapshot? _academicCalendar;
  String? _academicCalendarTerm;
  int _lastHandledWidgetNavigationToken = 0;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  int _quoteRefreshToken = 0;

  List<CampusTimeInfo>? get _timeInfoList => _controller.timeInfoList;

  @override
  void initState() {
    super.initState();
    WidgetNavigation.request.addListener(_onWidgetNavigation);
    ScheduleCustomizationManager.instance.addListener(_onCustomizationChanged);
    AcademicCalendarManager.instance.epoch.addListener(
      _onAcademicCalendarChanged,
    );
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
    AcademicCalendarManager.instance.epoch.removeListener(
      _onAcademicCalendarChanged,
    );
    _clockTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onAcademicCalendarChanged() {
    final term = (_scheduleData?.yearTerm ?? '').trim();
    if (term.isEmpty) return;
    unawaited(_loadAcademicCalendar(term));
  }

  Future<void> _loadAcademicCalendar(
    String term, {
    bool checkDue = false,
  }) async {
    if (!mounted) return;
    if (_academicCalendarTerm != term) {
      _academicCalendarTerm = term;
      if (_academicCalendar != null) {
        setState(() => _academicCalendar = null);
      }
    }
    final manager = AcademicCalendarManager.instance;
    final cached = await manager.loadCached(term);
    if (!mounted || (_scheduleData?.yearTerm ?? '').trim() != term) return;
    setState(() => _academicCalendar = cached);
    if (cached != null) unawaited(_ensureCalendarSourceWeek(cached));
    if (checkDue) unawaited(manager.refreshIfDue(term));
  }

  Future<void> _ensureCalendarSourceWeek(
    AcademicCalendarSnapshot calendar,
  ) async {
    final data = _scheduleData;
    final rule = calendar.dayAt(DateTime.now());
    final sourceDate = rule?.isTeachingDay == true ? rule!.scheduleDate : null;
    if (data == null || sourceDate == null) return;
    final range = ScheduleDate.tryExtractWeekRange(
      data.weekDayList,
      reference: DateTime.now(),
    );
    final currentWeek = int.tryParse((data.weekNum ?? '').trim());
    final term = (data.yearTerm ?? '').trim();
    if (range == null || currentWeek == null || term.isEmpty) return;
    final delta = sourceDate.difference(range.start).inDays;
    final week = currentWeek + (delta / 7).floor();
    if (_controller.weekCache.containsKey(week)) return;
    await _controller.ensureWeekLoaded(
      week.toString(),
      term,
      updateLastViewed: false,
    );
    if (mounted) setState(() {});
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
      );
    });
  }

  Future<void> _loadSchedule({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      if (forceRefresh) {
        _quoteRefreshToken++;
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
            final term = (cached!.yearTerm ?? '').trim();
            if (_academicCalendarTerm != term) {
              _academicCalendarTerm = term;
              _academicCalendar = null;
            }
            _scheduleData = cached;
            _loading = false;
            _dataSource = '缓存';
          });
          final term = (cached.yearTerm ?? '').trim();
          if (term.isNotEmpty) await _loadAcademicCalendar(term);
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
          final term = (networkData.yearTerm ?? '').trim();
          if (_academicCalendarTerm != term) {
            _academicCalendarTerm = term;
            _academicCalendar = null;
          }
          _scheduleData = networkData;
          _error = null;
          _dataSource = '在线';
        });
        await _loadRefreshSnapshot();
      }
      final term = (_scheduleData?.yearTerm ?? '').trim();
      if (term.isNotEmpty) {
        unawaited(_loadAcademicCalendar(term, checkDue: true));
      }
    } catch (e, stackTrace) {
      AppLogger.I.error(
        'TodaySchedule',
        'Failed to load today schedule',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      final term = (_scheduleData?.yearTerm ?? '').trim();
      if (term.isNotEmpty) {
        unawaited(AcademicCalendarManager.instance.refreshIfDue(term));
      }
      setState(() {
        _error = _mapError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
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
    final saved = _error != null || _dataSource == '缓存';
    if (at == null) return saved ? '使用已保存课表' : '课表已更新';
    final now = DateTime.now();
    final sameDay =
        now.year == at.year && now.month == at.month && now.day == at.day;
    final date = sameDay ? '' : '${at.month}月${at.day}日 ';
    final hour = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    final updated = '更新于 $date$hour:$minute';
    return saved ? '已保存课表 · $updated' : updated;
  }

  String _mapError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('login')) {
      return '需要登录后才能查看今日课表。';
    }
    if (text.contains('credential') ||
        text.contains('凭证') ||
        text.contains('鉴权')) {
      return '登录凭证已失效，请重新登录。';
    }
    return '无法加载今日课表，请检查网络后重试。';
  }

  bool get _requiresReauthentication {
    final text = (_error ?? '').toLowerCase();
    return text.contains('登录') ||
        text.contains('凭证') ||
        text.contains('鉴权') ||
        text.contains('credential');
  }

  Future<void> _reauthenticate() async {
    if (!await requestReauthentication(context) || !mounted) return;
    await _loadSchedule(forceRefresh: true);
  }

  List<EventItem> _todayEvents(ScheduleData data) {
    final resolved = _resolvedToday(data);
    if (resolved != null && _academicCalendar != null) {
      final events = resolved.events
          .map((item) {
            if (!item.isMapped) return item.event;
            final originalNote = (item.event.note ?? '').trim();
            return EventItem.fromJson({
              ...item.event.toJson(),
              'weekDay': item.actualDate.weekday.toString(),
              'note': [
                if (originalNote.isNotEmpty) originalNote,
                '调休：原${academicCalendarDateKey(item.sourceDate)}课程',
              ].join(' · '),
            });
          })
          .toList(growable: true);
      events.sort((a, b) {
        final bySession = _sessionStart(a).compareTo(_sessionStart(b));
        if (bySession != 0) return bySession;
        return _sessionEnd(a).compareTo(_sessionEnd(b));
      });
      return events;
    }
    final weekDay = DateTime.now().weekday.toString();
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

  AcademicCalendarResolvedDay? _resolvedToday(ScheduleData data) {
    final schedules = <ScheduleData>{..._controller.weekCache.values, data};
    return resolveAcademicCalendarDay(
      actualDate: DateTime.now(),
      schedules: schedules,
      calendar: _academicCalendar,
    );
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
    return sessions.isEmpty ? '' : '第$sessions节';
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
      1: '星期一',
      2: '星期二',
      3: '星期三',
      4: '星期四',
      5: '星期五',
      6: '星期六',
      7: '星期日',
    };
    return labels[weekDay] ?? '今天';
  }

  @override
  Widget build(BuildContext context) {
    final data = _scheduleData;

    if (_loading && data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('今日'), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('今日'), centerTitle: true),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
          children: [
            _EmptyState(
              icon: Icons.event_busy_outlined,
              title: _requiresReauthentication ? '需要重新登录' : '课表暂时不可用',
              message: _error ?? '暂无可用的课表数据。',
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_requiresReauthentication)
                  FilledButton.icon(
                    onPressed: _reauthenticate,
                    icon: const Icon(Icons.login),
                    label: const Text('重新登录'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _loadSchedule(forceRefresh: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final weekDayNum = now.weekday;
    final coveredToday = _isTodayCovered(data);
    final resolvedToday = _academicCalendar == null
        ? null
        : _resolvedToday(data);
    final calendarHoliday = resolvedToday?.isHoliday == true;
    final calendarMissingSource = resolvedToday?.sourceMissing == true;
    final events =
        (coveredToday || resolvedToday?.isTeachingDay == true) &&
            !calendarHoliday &&
            !calendarMissingSource
        ? _todayEvents(data)
        : const <EventItem>[];
    final moment = events.isEmpty ? null : _courseMoment(events);
    final hasCourseCount =
        calendarHoliday ||
        (!calendarMissingSource &&
            (coveredToday || resolvedToday?.isTeachingDay == true));

    return Scaffold(
      appBar: AppBar(title: const Text('今日'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: () => _loadSchedule(forceRefresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
          children: [
            _DateSummary(
              dateText:
                  '${now.month}月${now.day}日 · ${_weekDayLabel(weekDayNum)}',
              termText: data.yearTerm?.trim().isNotEmpty == true
                  ? data.yearTerm!.trim()
                  : '当前学期',
              weekText: data.weekNum?.trim().isNotEmpty == true
                  ? '第${data.weekNum!.trim()}周'
                  : '本周',
              freshnessText: _freshnessText,
            ),
            if (!calendarHoliday &&
                !calendarMissingSource &&
                resolvedToday?.isTeachingDay == true) ...[
              const SizedBox(height: 12),
              _InfoBanner(
                icon: Icons.event_available_outlined,
                message: [
                  if (resolvedToday!.label.isNotEmpty) resolvedToday.label,
                  '按原课表${academicCalendarDateKey(resolvedToday.scheduleDate!)}上课',
                ].join(' · '),
              ),
            ],
            if (moment != null) ...[
              const SizedBox(height: 24),
              _NowNextCard(moment: moment),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              _InfoBanner(
                icon: Icons.wifi_off_outlined,
                message: _requiresReauthentication
                    ? '请重新登录后刷新，正在显示已保存课表。'
                    : '刷新失败，正在显示已保存课表。',
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '今日课程',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (hasCourseCount)
                  Text(
                    '${events.length}项安排',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (calendarHoliday)
              _EmptyState(
                icon: Icons.event_busy_outlined,
                title: '今日放假',
                message: resolvedToday!.label.isEmpty
                    ? '今天没有课程安排。'
                    : '${resolvedToday.label}，今天没有课程安排。',
              )
            else if (calendarMissingSource)
              _EmptyState(
                icon: Icons.sync_problem_outlined,
                title: '调休课表尚未加载',
                message: [
                  if (resolvedToday!.label.isNotEmpty) resolvedToday.label,
                  if (resolvedToday.scheduleDate != null)
                    '按原课表${academicCalendarDateKey(resolvedToday.scheduleDate!)}上课',
                  '请下拉刷新后重试。',
                ].join(' · '),
              )
            else if (!coveredToday && resolvedToday?.isTeachingDay != true)
              const _EmptyState(
                icon: Icons.event_note_outlined,
                title: '当前不在教学周',
                message: '今天不在当前课表对应的教学周范围内。',
              )
            else if (events.isEmpty)
              const _EmptyState(
                icon: Icons.free_breakfast_outlined,
                title: '今天没课',
              )
            else
              ...events.indexed.expand(
                (entry) => [
                  if (entry.$1 > 0) const SizedBox(height: 12),
                  _buildEventCard(context, entry.$2),
                ],
              ),
            DailyQuoteCard(
              key: const ValueKey('today_daily_quote'),
              active: widget.isActive,
              refreshToken: _quoteRefreshToken,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, EventItem event) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final timeRange = _timeRangeLabel(event);
    final sessionLabel = _sessionLabel(event);
    final location = (event.address ?? '').trim();
    final teacher = (event.memberName ?? '').trim();
    final note = (event.note ?? '').trim();
    final name = (event.eventName ?? '').trim();

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          showCourseDetailDialog(
            context,
            courseName: event.eventName ?? '未命名课程',
            events: [event],
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? '未命名课程' : name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (sessionLabel.isNotEmpty || timeRange != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (sessionLabel.isNotEmpty)
                      Text(
                        sessionLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    if (timeRange != null)
                      Text(
                        timeRange,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
              if (location.isNotEmpty) ...[
                const SizedBox(height: 12),
                _CourseMetadata(
                  icon: Icons.location_on_outlined,
                  label: '地点',
                  text: location,
                ),
              ],
              if (teacher.isNotEmpty) ...[
                SizedBox(height: location.isNotEmpty ? 8 : 12),
                _CourseMetadata(
                  icon: Icons.person_outline,
                  label: '教师',
                  text: teacher,
                ),
              ],
              if (note.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseMetadata extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;

  const _CourseMetadata({
    required this.icon,
    required this.label,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: '$label：$text',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateSummary extends StatelessWidget {
  final String dateText;
  final String termText;
  final String weekText;
  final String freshnessText;

  const _DateSummary({
    required this.dateText,
    required this.termText,
    required this.weekText,
    required this.freshnessText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(dateText, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('$termText · $weekText', style: secondaryStyle),
        const SizedBox(height: 4),
        Text(freshnessText, style: secondaryStyle),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;

  const _InfoBanner({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.controlRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
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
  final String? message;

  const _EmptyState({required this.icon, required this.title, this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(color: color),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
            ],
          ],
        ),
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

  String get _countdownDuration {
    final hours = moment.minutes ~/ 60;
    final minutes = moment.minutes % 60;
    return hours > 0 ? '$hours小时$minutes分钟' : '$minutes分钟';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final finished = moment.kind == _CourseMomentKind.finished;
    final foreground = finished
        ? colors.onSurfaceVariant
        : colors.onPrimaryContainer;
    final name = (moment.event.eventName ?? '').trim();
    final location = (moment.event.address ?? '').trim();
    final countdownStyle = theme.textTheme.titleMedium?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w600,
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: finished ? colors.surfaceContainerLow : colors.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _title,
              style: theme.textTheme.labelLarge?.copyWith(color: foreground),
            ),
            if (finished) ...[
              const SizedBox(height: 8),
              Text(
                '辛苦了',
                style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                name.isEmpty ? '未命名课程' : name,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (location.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  location,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (moment.kind == _CourseMomentKind.ongoing)
                    Text('距离下课', style: countdownStyle),
                  Text(_countdownDuration, style: countdownStyle),
                  if (moment.kind == _CourseMomentKind.next)
                    Text('后开始', style: countdownStyle),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
