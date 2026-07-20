import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/schedule_week_change.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_recent_change_detector.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_refresh_orchestrator.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_time_info_coordinator.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_week_loader.dart';

class ScheduleController {
  final ScheduleApi _service;
  late final ScheduleTimeInfoCoordinator _timeInfoCoordinator;
  late final ScheduleWeekLoader _weekLoader;
  late final ScheduleRefreshOrchestrator _refreshOrchestrator;
  late final ScheduleRecentChangeDetector _recentChangeDetector;

  ScheduleController({ScheduleApi? service}) : _service = service ?? ScheduleApi() {
    _timeInfoCoordinator = ScheduleTimeInfoCoordinator(
      service: _service,
      getTimeInfoList: () => timeInfoList,
      setTimeInfoList: (value) => timeInfoList = value,
    );
    _weekLoader = ScheduleWeekLoader(
      service: _service,
      getWeekCache: () => weekCache,
      setWeekCache: (value) => weekCache = value,
      getCurrentTerm: () => currentTerm,
      setCurrentTerm: (value) => currentTerm = value,
      setWeekList: (value) => weekList = value,
      setActualCurrentWeekStr: (value) => actualCurrentWeekStr = value,
      setActualCurrentTermStr: (value) => actualCurrentTermStr = value,
      setNowInTeachingWeek: (value) => nowInTeachingWeek = value,
      setNowStatusLabel: (value) => nowStatusLabel = value,
    );
    _refreshOrchestrator = ScheduleRefreshOrchestrator(
      isDisposed: () => _disposed,
      ensureWeekLoaded: ensureWeekLoaded,
      loadUserId: () async {
        await _weekLoader.loadCredentials();
        return _weekLoader.userId;
      },
    );
    _recentChangeDetector = ScheduleRecentChangeDetector(
      service: _service,
      weekLoader: _weekLoader,
      getWeekCache: () => weekCache,
      isDisposed: () => _disposed,
    );
  }

  Map<int, ScheduleData> weekCache = {};
  List<CampusTimeInfo>? timeInfoList;
  String? currentTerm;
  List<String>? weekList;
  String? actualCurrentWeekStr;
  String? actualCurrentTermStr;
  bool? nowInTeachingWeek;
  String? nowStatusLabel;

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _refreshOrchestrator.dispose();
  }

  void reset() {
    weekCache.clear();
    currentTerm = null;
    weekList = null;
    actualCurrentWeekStr = null;
    actualCurrentTermStr = null;
    nowInTeachingWeek = null;
    nowStatusLabel = null;
    _refreshOrchestrator.cancelPrefetch();
  }

  Future<bool> loadTimeInfoFromCacheIfAny() {
    return _timeInfoCoordinator.loadTimeInfoFromCacheIfAny();
  }

  Future<bool> refreshTimeInfoIfEnabled({bool force = false}) {
    return _timeInfoCoordinator.refreshTimeInfoIfEnabled(force: force);
  }

  Future<void> ensureTimeInfoLoaded() {
    return _timeInfoCoordinator.ensureTimeInfoLoaded(isDisposed: () => _disposed);
  }

  Future<ScheduleData?> loadFromCache({
    String? weekNum,
    String? yearTerm,
  }) {
    return _weekLoader.loadFromCache(weekNum: weekNum, yearTerm: yearTerm);
  }

  Future<ScheduleData> loadFromNetwork({
    String? weekNum,
    String? yearTerm,
    bool persistLastViewed = true,
    bool updateWidgetPins = false,
  }) {
    return _weekLoader.loadFromNetwork(
      weekNum: weekNum,
      yearTerm: yearTerm,
      persistLastViewed: persistLastViewed,
      updateWidgetPins: updateWidgetPins,
    );
  }

  bool processLoadedData(ScheduleData data) {
    return _weekLoader.processLoadedData(data);
  }

  void schedulePrefetch(
    ScheduleData currentData,
    Function() onUpdate, {
    Duration delay = const Duration(milliseconds: 300),
  }) {
    _refreshOrchestrator.schedulePrefetch(
      currentData,
      onUpdate,
      delay: delay,
    );
  }

  Future<List<ScheduleWeekChange>> silentCheckRecentWeeksForChangesDetailed(
    ScheduleData currentData, {
    int weeksAhead = 1,
    int maxDiffLinesPerWeek = 30,
  }) {
    return _recentChangeDetector.silentCheckRecentWeeksForChangesDetailed(
      currentData,
      weeksAhead: weeksAhead,
      maxDiffLinesPerWeek: maxDiffLinesPerWeek,
    );
  }

  Future<void> refreshAllWeeksInForeground(
    ScheduleData currentData, {
    Duration interval = const Duration(seconds: 2),
  }) {
    return _refreshOrchestrator.refreshAllWeeksInForeground(
      currentData,
      interval: interval,
    );
  }

  void prefetchAllWeeksInBackground(
    ScheduleData currentData,
    Function() onUpdate, {
    Duration interval = const Duration(milliseconds: 150),
    bool forceRefresh = false,
  }) {
    _refreshOrchestrator.prefetchAllWeeksInBackground(
      currentData,
      onUpdate,
      interval: interval,
      forceRefresh: forceRefresh,
    );
  }

  Future<void> ensureWeekLoaded(
    String weekNum,
    String yearTerm, {
    bool forceRefresh = false,
    bool updateLastViewed = false,
  }) {
    return _weekLoader.ensureWeekLoaded(
      weekNum,
      yearTerm,
      forceRefresh: forceRefresh,
      updateLastViewed: updateLastViewed,
    );
  }
}
