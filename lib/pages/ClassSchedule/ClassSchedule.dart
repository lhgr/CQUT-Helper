import 'dart:async';
import 'package:cqut/manager/cache_cleanup_manager.dart';
import 'package:cqut/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut/manager/schedule_settings_manager.dart';
import 'package:cqut/manager/schedule_update_manager.dart';
import 'package:cqut/model/class_schedule_model.dart';
import 'package:cqut/model/schedule_week_change.dart';
import 'package:cqut/pages/ClassSchedule/widgets/schedule_app_bar.dart';
import 'package:cqut/pages/ClassSchedule/widgets/schedule_changes_sheet.dart';
import 'package:cqut/pages/ClassSchedule/widgets/schedule_page_view.dart';
import 'package:cqut/pages/ClassSchedule/widgets/schedule_settings_sheet.dart';
import 'package:cqut/pages/ClassSchedule/widgets/term_picker_sheet.dart';
import 'package:cqut/pages/ClassSchedule/widgets/week_picker_sheet.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:cqut/manager/schedule_update_intents.dart';

class ClassscheduleView extends StatefulWidget {
  const ClassscheduleView({super.key});

  @override
  State<ClassscheduleView> createState() => _ClassscheduleViewState();
}

class _ClassscheduleViewState extends State<ClassscheduleView>
    with WidgetsBindingObserver {
  final ScheduleController _controller = ScheduleController();
  final ScheduleSettingsManager _settingsManager = ScheduleSettingsManager();
  late final ScheduleUpdateManager _updateManager;

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

  int _lastOpenChangesToken = 0;
  int _lastTimetableCacheEpoch = CacheCleanupManager.timetableCacheEpoch.value;

  // 用于周切换的 PageController
  PageController? _pageController;
  int _currentWeekIndex = 0; // 对应 weekList 的 0 基索引

  DateTime? _lastMessageTime;

  @override
  void initState() {
    super.initState();
    _updateManager = ScheduleUpdateManager(
      controller: _controller,
      settings: _settingsManager,
    );
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
    _updateManager.dispose();
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

    // 检查是否有更新 (现在使用 updateManager)
    if (_currentScheduleData != null) {
      final changes = await _updateManager.checkForUpdates(
        _currentScheduleData!,
      );
      if (!mounted) return;
      if (changes.isNotEmpty) {
        _showUpdateNotification(changes);
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
        duration: const Duration(seconds: 1),
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
    final changes = await _updateManager.checkPendingChanges();
    if (changes.isEmpty || !mounted) return false;

    final first = changes.first;

    if (autoOpen) {
      if (_settingsManager.updateShowDiff) {
        _showScheduleChangesSheet(changes);
      } else {
        _jumpToWeek(first.weekNum);
      }
      return true;
    }

    _showUpdateNotification(changes);
    return true;
  }

  void _showUpdateNotification(List<ScheduleWeekChange> changes) {
    final first = changes.first;
    final showDiff = _settingsManager.updateShowDiff;
    final brief = showDiff && first.lines.isNotEmpty ? '：${first.brief}' : '';
    final msg = changes.length == 1
        ? '${_labelForWeek(first.weekNum)}课表有更新$brief'
        : '${_labelForWeek(first.weekNum)}等${changes.length}周课表有更新$brief';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        action: SnackBarAction(
          label: showDiff ? '详情' : '查看',
          onPressed: () {
            if (!mounted) return;
            if (showDiff) {
              _showScheduleChangesSheet(changes);
            } else {
              _jumpToWeek(first.weekNum);
            }
          },
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _configureUpdateTimer() {
    _updateManager.startTimer(() => _currentScheduleData, (changes) {
      if (mounted) {
        _showUpdateNotification(changes);
      }
    });
  }

  Future<void> _loadPreferences() async {
    await _settingsManager.load();
    if (!mounted) return;
    setState(() {}); // Refresh UI with loaded settings
    _configureUpdateTimer();
  }

  void _showScheduleSettingsSheetWrapper() {
    showScheduleSettingsSheet(
      context,
      initialWeeksAhead: _settingsManager.updateWeeksAhead,
      initialShowWeekend: _settingsManager.showWeekend,
      initialUpdateEnabled: _settingsManager.updateEnabled,
      initialUpdateIntervalMinutes: _settingsManager.updateIntervalMinutes,
      initialUpdateShowDiff: _settingsManager.updateShowDiff,
      initialSystemNotifyEnabled: _settingsManager.updateSystemNotifyEnabled,
      maxWeeksAhead: (_updateManager.controller.weekList?.length ?? 0) > 1
          ? (_updateManager.controller.weekList!.length - 1)
          : 0,
      onSave:
          ({
            required weeksAhead,
            required showWeekend,
            required updateEnabled,
            required updateIntervalMinutes,
            required updateShowDiff,
            required systemNotifyEnabled,
          }) async {
            await _settingsManager.save(
              showWeekend: showWeekend,
              updateWeeksAhead: weeksAhead,
              updateEnabled: updateEnabled,
              updateIntervalMinutes: updateIntervalMinutes,
              updateShowDiff: updateShowDiff,
              updateSystemNotifyEnabled: systemNotifyEnabled,
            );
            if (mounted) {
              setState(() {}); // Refresh UI
            }
            _configureUpdateTimer();
          },
    );
  }

  @override
  Widget build(BuildContext context) {
    if ((_currentScheduleData == null || _weekList == null) && _loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("课表"), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if ((_currentScheduleData == null || _weekList == null) && _error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("课表"), centerTitle: true),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _loadFromNetwork(),
                icon: const Icon(Icons.refresh),
                label: const Text("重试"),
              ),
            ],
          ),
        ),
      );
    }

    // 防止 _weekList 为空时导致的 Null Check Error
    if (_weekList == null || _weekList!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("课表"), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
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
              child: const Icon(Icons.today),
            )
          : null,
      appBar: ScheduleAppBar(
        loading: _loading,
        weekList: _weekList,
        currentWeekIndex: _currentWeekIndex,
        currentScheduleData: _currentScheduleData,
        nowInTeachingWeek: _nowInTeachingWeek,
        nowStatusLabel: _nowStatusLabel,
        onRefresh: () => _loadFromNetwork(
          weekNum: _weekList![_currentWeekIndex],
          yearTerm: _currentScheduleData?.yearTerm,
        ),
        onSettings: _showScheduleSettingsSheetWrapper,
        onWeekPicker: _showWeekPickerSheet,
        onTermPicker: _showTermPickerSheet,
      ),
      body: SchedulePageView(
        pageController: _pageController,
        onPageChanged: _onPageChanged,
        weekList: _weekList!,
        weekCache: _weekCache,
        showWeekend: _settingsManager.showWeekend,
        onBoundaryMessage: _showBoundaryMessage,
        currentWeekIndex: _currentWeekIndex,
      ),
    );
  }
}
