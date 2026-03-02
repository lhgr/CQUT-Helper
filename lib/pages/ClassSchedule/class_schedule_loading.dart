part of 'ClassSchedule.dart';

extension _ClassScheduleLoading on _ClassscheduleViewState {
  Future<void> _loadInitialData() async {
    unawaited(
      _controller.loadTimeInfoFromCacheIfAny().then((loaded) {
        if (loaded) _setState(() {});
      }),
    );
    unawaited(
      _controller.refreshTimeInfoIfEnabled().then((changed) {
        if (changed) _setState(() {});
      }),
    );

    final cachedData = await _controller.loadFromCache();
    if (cachedData != null) {
      _processLoadedData(cachedData, isInitial: true);
    }

    await _loadFromNetwork();
    await _consumePendingChangesIfAny();

    if (_currentScheduleData != null) {
      _controller.schedulePrefetch(_currentScheduleData!, () {
        _setState(() {});
      }, delay: Duration.zero);
    }

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
        _setState(() {});
      });
    }
  }

  void _processLoadedData(ScheduleData data, {bool isInitial = false}) {
    if (data.weekNum == null || data.weekList == null) return;

    _controller.processLoadedData(data);

    _setState(() {
      _currentScheduleData = data;

      final newIndex = _controller.weekList!.indexOf(data.weekNum!);
      if (newIndex != -1) {
        if (_pageController == null) {
          _currentWeekIndex = newIndex;
          _pageController = PageController(initialPage: newIndex);
        } else if (_currentWeekIndex != newIndex && !isInitial) {
          _currentWeekIndex = newIndex;
          _pageController!.jumpToPage(newIndex);
        }
      }
    });
    _configureUpdateTimer();
  }

  Future<void> _loadFromNetwork({String? weekNum, String? yearTerm}) async {
    if (_controller.weekCache.containsKey(int.tryParse(weekNum ?? "") ?? -1)) {}

    _setState(() {
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

      if (_controller.timeInfoList == null) {
        unawaited(
          _controller.loadTimeInfoFromCacheIfAny().then((loaded) {
            if (loaded) _setState(() {});
          }),
        );
        unawaited(
          _controller.refreshTimeInfoIfEnabled().then((changed) {
            if (changed) _setState(() {});
          }),
        );
      }
    } catch (e) {
      _setState(() {
        _error = e.toString();
      });
    } finally {
      _setState(() {
        _loading = false;
      });
    }
  }

  void _schedulePrefetch(ScheduleData currentData) {
    _controller.schedulePrefetch(currentData, () {
      _setState(() {});
    });
  }

  Future<void> _ensureWeekLoaded(String weekNum, String yearTerm) async {
    await _controller.ensureWeekLoaded(weekNum, yearTerm);
    final wInt = int.tryParse(weekNum) ?? 0;
    if (!mounted) return;
    if (_weekCache.containsKey(wInt)) {
      _setState(() {
        _currentScheduleData = _weekCache[wInt];
      });
      _schedulePrefetch(_weekCache[wInt]!);
    } else {
      _setState(() {});
    }
  }

  Future<void> _loadPreferences() async {
    await _settingsManager.load();
    if (!mounted) return;
    _setState(() {});
    _configureUpdateTimer();
  }
}
