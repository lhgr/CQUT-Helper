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
import 'package:cqut/utils/schedule_update_range_utils.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:cqut/manager/schedule_update_intents.dart';

part 'class_schedule_actions.dart';
part 'class_schedule_loading.dart';
part 'class_schedule_updates.dart';

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
    ScheduleUpdateIntents.scheduleUpdated.addListener(_onScheduleUpdated);
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
    ScheduleUpdateIntents.scheduleUpdated.removeListener(_onScheduleUpdated);
    CacheCleanupManager.timetableCacheEpoch.removeListener(
      _onTimetableCacheCleared,
    );
    _updateManager.dispose();
    _controller.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  void _setState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
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

  void _onScheduleUpdated() {
    if (!mounted) return;
    if (_weekList != null &&
        _currentWeekIndex >= 0 &&
        _currentWeekIndex < _weekList!.length) {
      final week = _weekList![_currentWeekIndex];
      final wInt = int.tryParse(week) ?? 0;
      final data = _controller.weekCache[wInt];
      if (data != null) {
        setState(() {
          _currentScheduleData = data;
        });
        return;
      }
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _consumePendingChangesIfAny();
    }
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
        timeInfoList:
            _settingsManager.timeInfoEnabled ? _controller.timeInfoList : null,
      ),
    );
  }
}
