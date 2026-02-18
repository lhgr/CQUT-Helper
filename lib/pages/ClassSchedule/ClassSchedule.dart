import 'dart:async';
import 'dart:convert';
import 'package:cqut/pages/ClassSchedule/schedule_controller.dart';
import 'package:cqut/pages/ClassSchedule/schedule_diff.dart';
import 'package:cqut/pages/ClassSchedule/schedule_update_worker.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../model/schedule_model.dart';
import '../../utils/local_notifications.dart';
import 'schedule_update_intents.dart';
import 'widgets/schedule_header.dart';
import 'widgets/schedule_time_column.dart';
import 'widgets/schedule_course_grid.dart';

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

  // 获取控制器属性的 Getter，以最小化代码更改
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
    _loadPreferences();
    _loadInitialData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ScheduleUpdateIntents.openChangesSheet.removeListener(_onOpenChangesSheet);
    _updateTimer?.cancel();
    _controller.dispose();
    _pageController?.dispose();
    super.dispose();
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

  // 显示选择器...
  void _showWeekPicker() {
    if (_weekList == null) return;
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SizedBox(
          height: 300,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "选择周次",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _weekList!.length,
                  itemBuilder: (context, index) {
                    final week = _weekList![index];
                    final isCurrentWeek =
                        _actualCurrentTermStr != null &&
                        _currentScheduleData?.yearTerm ==
                            _actualCurrentTermStr &&
                        week == _actualCurrentWeekStr;

                    return ListTile(
                      title: Text(
                        "第 $week 周${isCurrentWeek ? ' (当前周)' : ''}",
                        textAlign: TextAlign.center,
                        style: isCurrentWeek
                            ? TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              )
                            : null,
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _pageController?.jumpToPage(index);
                      },
                      selected: index == _currentWeekIndex,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTermPicker() {
    if (_currentScheduleData?.yearTermList == null) return;
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SizedBox(
          height: 300,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "选择学期",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _currentScheduleData!.yearTermList!.length,
                  itemBuilder: (context, index) {
                    final term = _currentScheduleData!.yearTermList![index];
                    final isCurrentTerm = term == _actualCurrentTermStr;
                    return ListTile(
                      title: Text(
                        "$term${isCurrentTerm ? ' (当前学期)' : ''}",
                        textAlign: TextAlign.center,
                        style: isCurrentTerm
                            ? TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              )
                            : null,
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _changeTerm(term);
                      },
                      selected: term == _currentScheduleData?.yearTerm,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _returnToCurrentWeek() {
    if (_actualCurrentWeekStr == null || _weekList == null) {
      // 回退：重新加载网络以查找当前
      _loadFromNetwork();
      return;
    }

    // 检查我们是否在正确的学期。如果不是，切换学期
    // 假设 actualCurrentWeek 仅对当前学期有效
    // 但我们不存储 "actualCurrentTerm"。我们可以假设初始加载的学期是当前的
    // 让我们遍历 weekList 来查找该周
    final index = _weekList!.indexOf(_actualCurrentWeekStr!);
    if (index != -1) {
      _pageController?.jumpToPage(index);
    } else {
      // 也许我们在不同的学期，重新加载初始数据
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
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: changes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final c = changes[index];
                final title = '${_labelForWeek(c.weekNum)}变更';
                final lines = c.lines.isEmpty
                    ? const ['课表有更新（无法解析具体变更）']
                    : c.lines;

                return Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _jumpToWeek(c.weekNum);
                            },
                            child: Text('跳转'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...lines.map(
                        (t) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('· $t'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
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

  Future<void> _setShowWeekend(bool value) async {
    setState(() {
      _showWeekend = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyShowWeekend, value);
    unawaited(
      FirebaseAnalytics.instance.logEvent(
        name: 'schedule_toggle_show_weekend',
        parameters: {'value': value},
      ),
    );
  }

  int _maxWeeksAheadForCurrentTerm() {
    final totalWeeks = _weekList?.length ?? 0;
    if (totalWeeks <= 1) return 0;
    return totalWeeks - 1;
  }

  String _formatIntervalLabel(int minutes) {
    if (minutes <= 0) return '未设置';
    if (minutes % 60 == 0) {
      final h = minutes ~/ 60;
      return h == 1 ? '每 1 小时' : '每 $h 小时';
    }
    return '每 $minutes 分钟';
  }

  double? _estimateDailyRequests({
    required int weeksAhead,
    required int intervalMinutes,
  }) {
    if (intervalMinutes <= 0) return null;
    final perDayRuns = 1440 / intervalMinutes;
    return (1 + weeksAhead) * perDayRuns;
  }

  Future<bool> _confirmHighFrequencyIfNeeded({
    required BuildContext context,
    required int weeksAhead,
    required int intervalMinutes,
  }) async {
    final est = _estimateDailyRequests(
      weeksAhead: weeksAhead,
      intervalMinutes: intervalMinutes,
    );
    final risky = intervalMinutes < 15 || (est != null && est >= 200);
    if (!risky) return true;

    final detail = <String>[
      if (intervalMinutes < 15) '后台定时检查系统通常要求间隔不少于 15 分钟',
      if (est != null) '按当前设置，预计每天约 ${est.toStringAsFixed(0)} 次课表接口请求',
      '请求过于频繁可能导致耗电增加、流量增加，且可能触发学校系统的风控限制',
    ].join('\n');

    final proceed =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text('请求频率风险提示'),
              content: Text(detail),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('启用'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!proceed) return false;
    if (!context.mounted) return false;

    final disclaimer = <String>[
      detail,
      '',
      '请注意：',
      '1. 频繁请求可能导致耗电/流量增加，且可能触发学校系统风控（如账号被限制、请求被拒绝等）。',
      '2. 由此产生的任何直接或间接损失（包括但不限于账号限制、数据异常等）由用户自行承担。',
    ].join('\n');

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text('风险提醒'),
              content: Text(disclaimer),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('返回修改'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('我已知悉'),
                ),
              ],
            );
          },
        ) ??
        false;
    return confirmed;
  }

  Future<int?> _askIntervalMinutes(BuildContext context, int initial) async {
    final controller = TextEditingController(text: initial.toString());
    final value = await showDialog<int?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('设置检查间隔（分钟）'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: '例如 60'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final v = int.tryParse(controller.text.trim());
                Navigator.pop(context, v);
              },
              child: Text('确定'),
            ),
          ],
        );
      },
    );
    if (value == null) return null;
    if (value < 1) return 1;
    return value;
  }

  void _showScheduleSettingsSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final maxWeeksAhead = _maxWeeksAheadForCurrentTerm();
        int weeksAhead = _updateWeeksAhead.clamp(0, maxWeeksAhead);
        bool showWeekend = _showWeekend;
        bool updateEnabled = _updateEnabled;
        int intervalMinutes = _updateIntervalMinutes;
        bool showDiff = _updateShowDiff;
        bool systemNotifyEnabled = _updateSystemNotifyEnabled;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final est = _estimateDailyRequests(
              weeksAhead: weeksAhead,
              intervalMinutes: intervalMinutes,
            );

            String weeksLabel() {
              if (weeksAhead == 0) return '仅本周';
              return '本周 + 未来 $weeksAhead 周';
            }

            final showRisk =
                updateEnabled &&
                (intervalMinutes < 15 || (est != null && est >= 200));

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SwitchListTile(
                          title: Text('显示周末'),
                          subtitle: Text('关闭后仅显示周一到周五'),
                          value: showWeekend,
                          onChanged: (value) {
                            setModalState(() {
                              showWeekend = value;
                            });
                          },
                        ),
                        ListTile(
                          title: Text('课表更新检查范围'),
                          subtitle: Text(
                            maxWeeksAhead == 0
                                ? '本学期周数不足'
                                : '${weeksLabel()}（上限：未来 $maxWeeksAhead 周）',
                          ),
                        ),
                        if (maxWeeksAhead > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Slider(
                              min: 0,
                              max: maxWeeksAhead.toDouble(),
                              value: weeksAhead.toDouble(),
                              divisions: maxWeeksAhead,
                              label: weeksLabel(),
                              onChanged: (v) {
                                setModalState(() {
                                  weeksAhead = v.round();
                                });
                              },
                            ),
                          ),
                        SwitchListTile(
                          title: Text('启用定时检查（后台）'),
                          subtitle: Text('定期静默检查课表是否变化'),
                          value: updateEnabled,
                          onChanged: (value) {
                            setModalState(() {
                              updateEnabled = value;
                            });
                          },
                        ),
                        ListTile(
                          title: Text('检查间隔'),
                          subtitle: Text(
                            updateEnabled
                                ? _formatIntervalLabel(intervalMinutes)
                                : '未启用',
                          ),
                          enabled: updateEnabled,
                          onTap: !updateEnabled
                              ? null
                              : () async {
                                  final v = await _askIntervalMinutes(
                                    context,
                                    intervalMinutes,
                                  );
                                  if (v == null) return;
                                  setModalState(() {
                                    intervalMinutes = v;
                                  });
                                },
                        ),
                        SwitchListTile(
                          title: Text('变更提示显示详情'),
                          subtitle: Text('提示具体变化课程以及变化详情'),
                          value: showDiff,
                          onChanged: (value) {
                            setModalState(() {
                              showDiff = value;
                            });
                          },
                        ),
                        SwitchListTile(
                          title: Text('系统通知提醒'),
                          subtitle: Text('在后台也发送系统通知提醒'),
                          value: systemNotifyEnabled,
                          onChanged: !updateEnabled
                              ? null
                              : (value) {
                                  setModalState(() {
                                    systemNotifyEnabled = value;
                                  });
                                },
                        ),
                        if (showRisk)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Text(
                              est == null
                                  ? '当前设置可能导致请求频繁'
                                  : '当前设置预计每天约 ${est.toStringAsFixed(0)} 次请求，可能触发风控或增加耗电',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text('取消'),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () async {
                                    if (updateEnabled) {
                                      final ok =
                                          await _confirmHighFrequencyIfNeeded(
                                            context: context,
                                            weeksAhead: weeksAhead,
                                            intervalMinutes: intervalMinutes,
                                          );
                                      if (!ok) return;
                                    }

                                    if (updateEnabled && systemNotifyEnabled) {
                                      final ok =
                                          await LocalNotifications.ensurePermission();
                                      if (!ok) {
                                        systemNotifyEnabled = false;
                                        if (context.mounted) {
                                          await showDialog<void>(
                                            context: context,
                                            builder: (context) {
                                              return AlertDialog(
                                                title: Text('通知权限未授予'),
                                                content: Text(
                                                  '未授予通知权限，将无法发送系统通知提醒。你仍可使用应用内提示。',
                                                ),
                                                actions: [
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                    child: Text('知道了'),
                                                  ),
                                                ],
                                              );
                                            },
                                          );
                                        }
                                      }
                                    }

                                    await _setShowWeekend(showWeekend);

                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setInt(
                                      _prefsKeyUpdateWeeksAhead,
                                      weeksAhead,
                                    );
                                    await prefs.setBool(
                                      _prefsKeyUpdateEnabled,
                                      updateEnabled,
                                    );
                                    await prefs.setInt(
                                      _prefsKeyUpdateIntervalMinutes,
                                      intervalMinutes,
                                    );
                                    await prefs.setBool(
                                      _prefsKeyUpdateShowDiff,
                                      showDiff,
                                    );
                                    await prefs.setBool(
                                      _prefsKeyUpdateSystemNotifyEnabled,
                                      systemNotifyEnabled,
                                    );

                                    if (!mounted) return;
                                    setState(() {
                                      _updateWeeksAhead = weeksAhead;
                                      _updateEnabled = updateEnabled;
                                      _updateIntervalMinutes = intervalMinutes;
                                      _updateShowDiff = showDiff;
                                      _updateSystemNotifyEnabled =
                                          systemNotifyEnabled;
                                    });
                                    _configureUpdateTimer();
                                    await ScheduleUpdateWorker.syncFromPreferences();

                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                  },
                                  child: Text('保存'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
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
    // 如果当前显示的周 != 实际当前周，则显示
    bool showFab = false;
    if (_actualCurrentWeekStr != null && _weekList != null) {
      final displayedWeek = _weekList![_currentWeekIndex];
      if (displayedWeek != _actualCurrentWeekStr) {
        showFab = true;
      }
      // 也要检查学期? 除了初始加载外，我们没有明确存储 currentTerm
      // 但如果 _weekList 包含 _actualCurrentWeekStr，我们可能在正确的学期 (或者周数重叠，但通常是唯一的，或者我们假设如此)
      // 实际上，如果我们切换学期，_weekList 会改变。如果 _weekList 不包含 _actualCurrentWeekStr，我们肯定在错误的学期 (或错误的周列表)
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
            onPressed: _showScheduleSettingsSheet,
            icon: Icon(Icons.tune),
            tooltip: '课表设置',
          ),
        ],
        title: Column(
          children: [
            InkWell(
              onTap: _showWeekPicker,
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
                onTap: _showTermPicker,
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
