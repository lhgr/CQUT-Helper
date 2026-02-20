import 'dart:async';
import 'dart:convert';
import 'package:cqut/manager/cache_cleanup_manager.dart';
import 'package:cqut/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut/pages/ClassSchedule/models/class_schedule_model.dart';
import 'package:cqut/pages/ClassSchedule/models/schedule_week_change.dart';
import 'package:cqut/pages/ClassSchedule/schedule_update_worker.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'schedule_update_intents.dart';
import 'widgets/schedule_header.dart';
import 'widgets/schedule_time_column.dart';
import 'widgets/schedule_course_grid.dart';
import 'widgets/week_picker_sheet.dart';
import 'widgets/term_picker_sheet.dart';
import 'widgets/schedule_changes_sheet.dart';
import 'widgets/schedule_settings_sheet.dart';

class ClassscheduleView extends StatefulWidget {
  const ClassscheduleView({super.key});

  @override
  State<ClassscheduleView> createState() => _ClassscheduleViewState();
}

class _ClassscheduleViewState extends State<ClassscheduleView>
    with WidgetsBindingObserver {
  static const String _prefsKeyShowWeekend = 'schedule_show_weekend';
  static const String _prefsKeyUpdateWeeksAhead = 'schedule_update_weeks_ahead';
  static const String _prefsKeyUpdateEnabled = 'schedule_update_enabled';
  static const String _prefsKeyUpdateIntervalMinutes =
      'schedule_update_interval_minutes';
  static const String _prefsKeyUpdateShowDiff = 'schedule_update_show_diff';
  static const String _prefsKeyUpdateSystemNotifyEnabled =
      'schedule_update_system_notification_enabled';

  final ScheduleController _controller = ScheduleController();
  ScheduleData? _currentScheduleData; // 当前显示的周数据

  // 获取控制器属性的 Getter
  Map<int, ScheduleData> get _weekCache => _controller.weekCache;
  List<String>? get _weekList => _controller.weekList;
  String? get _actualCurrentWeekStr => _controller.actualCurrentWeekStr;
  String? get _actualCurrentTermStr => _controller.actualCurrentTermStr;
  String? get _currentTerm => _controller.currentTerm;
  bool? get _nowInTeachingWeek => _controller.nowInTeachingWeek;
  String? get _nowStatusLabel => _controller.nowStatusLabel;

  bool _loading = true; // 默认为 true，防止初始空数据渲染
  String? _error;
  bool _showWeekend = true;
  int _updateWeeksAhead = 1;
  bool _updateEnabled = false;
  int _updateIntervalMinutes = 60;
  bool _updateShowDiff = true;
  bool _updateSystemNotifyEnabled = false;
  Timer? _updateTimer;
  bool _updateCheckInFlight = false;
  int _lastOpenChangesToken = 0;
  int _lastTimetableCacheEpoch = CacheCleanupManager.timetableCacheEpoch.value;

  // 用于周切换的 PageController
  PageController? _pageController;
  int _currentWeekIndex = 0; // 对应 weekList 的 0 基索引

  final double _headerHeight = 50.0;
  final double _timeColumnWidth = 30.0;
  final double _sessionHeight = 60.0;
  final List<Color> _lightColors = [
    Color(0xFFA8D8FF),
    Color(0xFFB9FBC0),
    Color(0xFFFFE29A),
    Color(0xFFFFC6FF),
    Color(0xFFFFADAD),
    Color(0xFF9BF6FF),
    Color(0xFFCAFFBF),
    Color(0xFFBDB2FF),
  ];

  final List<Color> _lightTextColors = [
    Color(0xFF0B3D91),
    Color(0xFF0F5132),
    Color(0xFF7A4E00),
    Color(0xFF5A189A),
    Color(0xFF7B2C2C),
    Color(0xFF006064),
    Color(0xFF155724),
    Color(0xFF2D1E8F),
  ];

  final List<Color> _darkColors = [
    Colors.blue.shade900,
    Colors.green.shade900,
    Colors.orange.shade900,
    Colors.purple.shade900,
    Colors.red.shade900,
    Colors.teal.shade900,
    Colors.pink.shade900,
    Colors.indigo.shade900,
  ];

  final List<Color> _darkTextColors = [
    Colors.blue.shade300,
    Colors.green.shade300,
    Colors.orange.shade300,
    Colors.purple.shade300,
    Colors.red.shade300,
    Colors.teal.shade300,
    Colors.pink.shade300,
    Colors.indigo.shade300,
  ];

  DateTime? _lastMessageTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ScheduleUpdateIntents.openChangesSheet.addListener(_onOpenChangesSheet);
    CacheCleanupManager.timetableCacheEpoch.addListener(
      _onTimetableCacheCleared,
    );
    _loadPreferences();
    _loadInitialData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ScheduleUpdateIntents.openChangesSheet.removeListener(_onOpenChangesSheet);
    CacheCleanupManager.timetableCacheEpoch.removeListener(
      _onTimetableCacheCleared,
    );
    _updateTimer?.cancel();
    _controller.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  void _onTimetableCacheCleared() {
    final epoch = CacheCleanupManager.timetableCacheEpoch.value;
    if (epoch == _lastTimetableCacheEpoch) return;
    _lastTimetableCacheEpoch = epoch;
    _controller.reset();
    if (!mounted) return;
    final pc = _pageController;
    setState(() {
      _currentScheduleData = null;
      _error = null;
      _loading = true;
      _currentWeekIndex = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (pc != null && pc.hasClients) {
        pc.jumpToPage(0);
      }
    });
    _loadFromNetwork();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _consumePendingChangesIfAny();
    }
  }

  Future<void> _loadInitialData() async {
    // 1. 优先尝试加载缓存以立即显示内容
    final cachedData = await _controller.loadFromCache();
    if (cachedData != null) {
      _processLoadedData(cachedData, isInitial: true);
    }

    // 2. 从网络加载以获取最新的“当前”周
    await _loadFromNetwork();
    await _consumePendingChangesIfAny();

    // 3. 优先预取前后一周，提升滑动体验
    if (_currentScheduleData != null) {
      _controller.schedulePrefetch(_currentScheduleData!, () {
        if (mounted) setState(() {});
      }, delay: Duration.zero);
    }

    if (_currentScheduleData != null) {
      final prefs = await SharedPreferences.getInstance();
      final weeksAhead =
          prefs.getInt(_prefsKeyUpdateWeeksAhead) ?? _updateWeeksAhead;
      final showDiff =
          prefs.getBool(_prefsKeyUpdateShowDiff) ?? _updateShowDiff;
      final changes = await _controller
          .silentCheckRecentWeeksForChangesDetailed(
            _currentScheduleData!,
            weeksAhead: weeksAhead,
          );
      if (!mounted) return;
      if (changes.isNotEmpty) {
        String labelForWeek(String week) {
          final currentWeek = _currentScheduleData?.weekNum;
          if (currentWeek != null && week == currentWeek) return '本周';
          if (_weekList != null &&
              currentWeek != null &&
              _weekList!.indexOf(week) == _weekList!.indexOf(currentWeek) + 1) {
            return '下周';
          }
          return '第$week周';
        }

        final first = changes.first;
        final firstLabel = labelForWeek(first.weekNum);
        final brief = showDiff && first.lines.isNotEmpty
            ? '：${first.brief}'
            : '';
        final msg = changes.length == 1
            ? '$firstLabel课表有更新$brief'
            : '$firstLabel等${changes.length}周课表有更新$brief';
        final firstChanged = first.weekNum;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            action: SnackBarAction(
              label: showDiff ? '详情' : '查看',
              onPressed: () {
                if (!mounted) return;
                if (!showDiff) {
                  if (_weekList != null && _weekList!.contains(firstChanged)) {
                    final idx = _weekList!.indexOf(firstChanged);
                    if (idx != -1) _pageController?.jumpToPage(idx);
                  }
                  return;
                }
                _showScheduleChangesSheet(changes);
              },
            ),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    if (_currentScheduleData != null) {
      _controller.prefetchAllWeeksInBackground(_currentScheduleData!, () {
        if (mounted) setState(() {});
      });
    }
  }

  void _processLoadedData(ScheduleData data, {bool isInitial = false}) {
    if (data.weekNum == null || data.weekList == null) return;

    _controller.processLoadedData(data);

    setState(() {
      _currentScheduleData = data;

      // 初始化或更新 PageController
      final newIndex = _controller.weekList!.indexOf(data.weekNum!);
      if (newIndex != -1) {
        if (_pageController == null) {
          _currentWeekIndex = newIndex;
          _pageController = PageController(initialPage: newIndex);
        } else if (_currentWeekIndex != newIndex && !isInitial) {
          // 如果加载的特定周与当前索引不同
          // (例如来自学期选择器)，跳转到该周
          _currentWeekIndex = newIndex;
          _pageController!.jumpToPage(newIndex);
        }
      }
    });
    _configureUpdateTimer();
  }

  Future<void> _loadFromNetwork({String? weekNum, String? yearTerm}) async {
    if (_controller.weekCache.containsKey(int.tryParse(weekNum ?? "") ?? -1)) {
      // 如果内存中有数据，直接更新视图 (除非正在刷新)
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _controller.loadFromNetwork(
        weekNum: weekNum,
        yearTerm: yearTerm,
      );

      _processLoadedData(data);
      _schedulePrefetch(data);
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _schedulePrefetch(ScheduleData currentData) {
    _controller.schedulePrefetch(currentData, () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _ensureWeekLoaded(String weekNum, String yearTerm) async {
    await _controller.ensureWeekLoaded(weekNum, yearTerm);
    final wInt = int.tryParse(weekNum) ?? 0;
    if (!mounted) return;
    if (_weekCache.containsKey(wInt)) {
      setState(() {
        _currentScheduleData = _weekCache[wInt];
      });
      _schedulePrefetch(_weekCache[wInt]!);
    } else {
      setState(() {});
    }
  }

  void _onPageChanged(int index) {
    if (_weekList != null && index >= 0 && index < _weekList!.length) {
      FirebaseAnalytics.instance.logEvent(
        name: 'view_schedule_week',
        parameters: {'week_number': _weekList![index]},
      );
    }

    setState(() {
      _currentWeekIndex = index;
    });

    if (_weekList == null || index < 0 || index >= _weekList!.length) return;

    final targetWeek = _weekList![index];
    final currentTerm = _currentScheduleData?.yearTerm ?? _currentTerm;

    // 如果有该周的缓存数据，立即更新标题
    final wInt = int.tryParse(targetWeek) ?? 0;
    if (_weekCache.containsKey(wInt)) {
      setState(() {
        _currentScheduleData = _weekCache[wInt];
      });
      _schedulePrefetch(_weekCache[wInt]!);
    } else {
      if (currentTerm != null) {
        _ensureWeekLoaded(targetWeek, currentTerm);
      }
    }
  }

  void _changeTerm(String term) {
    _weekCache.clear();
    _loadFromNetwork(weekNum: '1', yearTerm: term);
  }

  void _showWeekPickerSheet() {
    if (_weekList == null) return;
    showWeekPicker(
      context: context,
      weekList: _weekList!,
      currentScheduleData: _currentScheduleData,
      actualCurrentTermStr: _actualCurrentTermStr,
      actualCurrentWeekStr: _actualCurrentWeekStr,
      currentWeekIndex: _currentWeekIndex,
      onWeekSelected: (index) {
        _pageController?.jumpToPage(index);
      },
    );
  }

  void _showTermPickerSheet() {
    showTermPicker(
      context: context,
      currentScheduleData: _currentScheduleData,
      actualCurrentTermStr: _actualCurrentTermStr,
      onTermSelected: (term) {
        _changeTerm(term);
      },
    );
  }

  void _returnToCurrentWeek() {
    if (_actualCurrentWeekStr == null || _weekList == null) {
      _loadFromNetwork();
      return;
    }

    final index = _weekList!.indexOf(_actualCurrentWeekStr!);
    if (index != -1) {
      _pageController?.jumpToPage(index);
    } else {
      _loadFromNetwork();
    }
  }

  void _showBoundaryMessage(String message) {
    final now = DateTime.now();
    if (_lastMessageTime != null &&
        now.difference(_lastMessageTime!) < Duration(seconds: 2)) {
      return;
    }
    _lastMessageTime = now;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _labelForWeek(String week) {
    final currentWeek = _currentScheduleData?.weekNum;
    if (currentWeek != null && week == currentWeek) return '本周';
    if (_weekList != null &&
        currentWeek != null &&
        _weekList!.indexOf(week) == _weekList!.indexOf(currentWeek) + 1) {
      return '下周';
    }
    return '第$week周';
  }

  void _jumpToWeek(String week) {
    if (_weekList == null) return;
    final idx = _weekList!.indexOf(week);
    if (idx == -1) return;
    _pageController?.jumpToPage(idx);
  }

  void _showScheduleChangesSheet(List<ScheduleWeekChange> changes) {
    showScheduleChangesSheet(
      context: context,
      changes: changes,
      onJumpToWeek: _jumpToWeek,
      currentScheduleData: _currentScheduleData,
      weekList: _weekList,
    );
  }

  void _onOpenChangesSheet() {
    final token = ScheduleUpdateIntents.openChangesSheet.value;
    if (token == _lastOpenChangesToken) return;
    _lastOpenChangesToken = token;
    _consumePendingChangesIfAny(autoOpen: true);
  }

  Future<bool> _consumePendingChangesIfAny({bool autoOpen = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('account');
    if (userId == null || userId.trim().isEmpty) return false;

    final key = ScheduleUpdateWorker.pendingKeyForUser(userId);
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return false;
    await prefs.remove(key);

    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      final items = decoded['changes'];
      if (items is! List) return false;

      final changes = <ScheduleWeekChange>[];
      for (final it in items) {
        if (it is! Map) continue;
        final weekNum = (it['weekNum'] ?? '').toString();
        final linesRaw = it['lines'];
        final lines = linesRaw is List
            ? linesRaw.map((e) => e.toString()).toList()
            : const <String>[];
        if (weekNum.isEmpty) continue;
        changes.add(ScheduleWeekChange(weekNum: weekNum, lines: lines));
      }
      if (changes.isEmpty || !mounted) return false;

      final first = changes.first;

      if (autoOpen) {
        if (_updateShowDiff) {
          _showScheduleChangesSheet(changes);
        } else {
          _jumpToWeek(first.weekNum);
        }
        return true;
      }

      final msg = _updateShowDiff && first.lines.isNotEmpty
          ? '后台检测到${_labelForWeek(first.weekNum)}课表有更新：${first.brief}'
          : '后台检测到${_labelForWeek(first.weekNum)}课表有更新';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          action: SnackBarAction(
            label: _updateShowDiff ? '详情' : '查看',
            onPressed: () {
              if (!mounted) return;
              if (_updateShowDiff) {
                _showScheduleChangesSheet(changes);
              } else {
                _jumpToWeek(first.weekNum);
              }
            },
          ),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      return false;
    }
    return true;
  }

  void _configureUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = null;

    if (!_updateEnabled) return;
    if (_updateIntervalMinutes < 1) return;

    _updateTimer = Timer.periodic(
      Duration(minutes: _updateIntervalMinutes),
      (_) => _runUpdateCheckOnce(fromTimer: true),
    );
  }

  Future<void> _runUpdateCheckOnce({required bool fromTimer}) async {
    if (_updateCheckInFlight) return;
    if (_currentScheduleData == null) return;

    _updateCheckInFlight = true;
    try {
      final maxWeeksAhead = _maxWeeksAheadForCurrentTerm();
      final weeksAhead = _updateWeeksAhead.clamp(0, maxWeeksAhead);
      final changes = await _controller
          .silentCheckRecentWeeksForChangesDetailed(
            _currentScheduleData!,
            weeksAhead: weeksAhead,
          );
      if (!mounted) return;
      if (changes.isEmpty) return;

      final first = changes.first;
      final firstLabel = _labelForWeek(first.weekNum);
      final brief = _updateShowDiff && first.lines.isNotEmpty
          ? '：${first.brief}'
          : '';
      final msg = changes.length == 1
          ? '$firstLabel课表有更新$brief'
          : '$firstLabel等${changes.length}周课表有更新$brief';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          action: SnackBarAction(
            label: _updateShowDiff ? '详情' : '查看',
            onPressed: () {
              if (!mounted) return;
              if (_updateShowDiff) {
                _showScheduleChangesSheet(changes);
              } else {
                _jumpToWeek(first.weekNum);
              }
            },
          ),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _updateCheckInFlight = false;
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final showWeekend = prefs.getBool(_prefsKeyShowWeekend);
    final weeksAhead = prefs.getInt(_prefsKeyUpdateWeeksAhead);
    final updateEnabled = prefs.getBool(_prefsKeyUpdateEnabled);
    final intervalMinutes = prefs.getInt(_prefsKeyUpdateIntervalMinutes);
    final showDiff = prefs.getBool(_prefsKeyUpdateShowDiff);
    final systemNotifyEnabled = prefs.getBool(
      _prefsKeyUpdateSystemNotifyEnabled,
    );
    if (!mounted) return;
    setState(() {
      _showWeekend = showWeekend ?? true;
      _updateWeeksAhead = weeksAhead ?? 1;
      _updateEnabled = updateEnabled ?? false;
      _updateIntervalMinutes = intervalMinutes ?? 60;
      _updateShowDiff = showDiff ?? true;
      _updateSystemNotifyEnabled = systemNotifyEnabled ?? false;
    });
    _configureUpdateTimer();
  }

  int _maxWeeksAheadForCurrentTerm() {
    final totalWeeks = _weekList?.length ?? 0;
    if (totalWeeks <= 1) return 0;
    return totalWeeks - 1;
  }

  void _showScheduleSettingsSheetWrapper() {
    showScheduleSettingsSheet(
      context,
      initialWeeksAhead: _updateWeeksAhead,
      initialShowWeekend: _showWeekend,
      initialUpdateEnabled: _updateEnabled,
      initialUpdateIntervalMinutes: _updateIntervalMinutes,
      initialUpdateShowDiff: _updateShowDiff,
      initialSystemNotifyEnabled: _updateSystemNotifyEnabled,
      maxWeeksAhead: _maxWeeksAheadForCurrentTerm(),
      onSave: ({
        required weeksAhead,
        required showWeekend,
        required updateEnabled,
        required updateIntervalMinutes,
        required updateShowDiff,
        required systemNotifyEnabled,
      }) {
        setState(() {
          _updateWeeksAhead = weeksAhead;
          _showWeekend = showWeekend;
          _updateEnabled = updateEnabled;
          _updateIntervalMinutes = updateIntervalMinutes;
          _updateShowDiff = updateShowDiff;
          _updateSystemNotifyEnabled = systemNotifyEnabled;
        });
        _configureUpdateTimer();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if ((_currentScheduleData == null || _weekList == null) && _loading) {
      return Scaffold(
        appBar: AppBar(title: Text("课表"), centerTitle: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if ((_currentScheduleData == null || _weekList == null) && _error != null) {
      return Scaffold(
        appBar: AppBar(title: Text("课表"), centerTitle: true),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _loadFromNetwork(),
                icon: Icon(Icons.refresh),
                label: Text("重试"),
              ),
            ],
          ),
        ),
      );
    }

    // 防止 _weekList 为空时导致的 Null Check Error
    if (_weekList == null || _weekList!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text("课表"), centerTitle: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 检查是否应该显示 FAB
    bool showFab = false;
    if (_actualCurrentWeekStr != null && _weekList != null) {
      final displayedWeek = _weekList![_currentWeekIndex];
      if (displayedWeek != _actualCurrentWeekStr) {
        showFab = true;
      }
      if (!_weekList!.contains(_actualCurrentWeekStr)) {
        showFab = true;
      }
    }

    return Scaffold(
      floatingActionButton: showFab
          ? FloatingActionButton(
              onPressed: _returnToCurrentWeek,
              tooltip: '返回本周',
              child: Icon(Icons.today),
            )
          : null,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          IconButton(
            onPressed: _loading
                ? null
                : () => _loadFromNetwork(
                    weekNum: _weekList![_currentWeekIndex],
                    yearTerm: _currentScheduleData?.yearTerm,
                  ),
            icon: Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _showScheduleSettingsSheetWrapper,
            icon: Icon(Icons.tune),
            tooltip: '课表设置',
          ),
        ],
        title: Column(
          children: [
            InkWell(
              onTap: _showWeekPickerSheet,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 2.0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (_nowInTeachingWeek == false &&
                              _nowStatusLabel != null &&
                              _nowStatusLabel!.isNotEmpty)
                          ? "${_nowStatusLabel!} · 第${_weekList![_currentWeekIndex]}周"
                          : "第${_weekList![_currentWeekIndex]}周",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, size: 20),
                  ],
                ),
              ),
            ),
            if (_currentScheduleData != null)
              InkWell(
                onTap: _showTermPickerSheet,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 2.0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "${_currentScheduleData!.yearTerm}学期",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        centerTitle: true,
      ),
      body: NotificationListener<OverscrollNotification>(
        onNotification: (notification) {
          if (notification.overscroll < 0) {
            // 开始边界
            if (_currentWeekIndex == 0) {
              _showBoundaryMessage("已经是第一周了");
            }
          } else if (notification.overscroll > 0) {
            // 结束边界
            if (_weekList != null &&
                _currentWeekIndex == _weekList!.length - 1) {
              _showBoundaryMessage("已经是最后一周了");
            }
          }
          return false;
        },
        child: PageView.builder(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          itemCount: _weekList!.length,
          itemBuilder: (context, index) {
            final weekStr = _weekList![index];
            final weekNum = int.tryParse(weekStr) ?? 0;
            final data = _weekCache[weekNum];

            if (data == null) {
              return Center(child: CircularProgressIndicator());
            }

            return Column(
              children: [
                ScheduleHeader(
                  scheduleData: data,
                  height: _headerHeight,
                  timeColumnWidth: _timeColumnWidth,
                  showWeekend: _showWeekend,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ScheduleTimeColumn(
                          width: _timeColumnWidth,
                          sessionHeight: _sessionHeight,
                        ),
                        Expanded(
                          child: ScheduleCourseGrid(
                            events: data.eventList ?? [],
                            sessionHeight: _sessionHeight,
                            showWeekend: _showWeekend,
                            colors:
                                Theme.of(context).brightness == Brightness.dark
                                ? _darkColors
                                : _lightColors,
                            textColors:
                                Theme.of(context).brightness == Brightness.dark
                                ? _darkTextColors
                                : _lightTextColors,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
