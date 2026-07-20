part of 'ClassSchedule.dart';

extension _ClassScheduleLoading on _ClassscheduleViewState {
  Future<void> _loadInitialData() async {
    await _settingsManager.load();
    if (!mounted) return;
    _setState(() {});

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

    await _loadFromNetwork(fromInitialBoot: true);
    _initialBootRequestPending = false;

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
      } else {
        await _runSilentFallbackSync(_currentScheduleData!);
        if (!mounted) return;
      }
      _scheduleSilentForegroundFullRefresh(_currentScheduleData!);
    }
    await _maybeShowBackgroundPollingGuide();
  }

  Future<void> _runSilentFallbackSync(ScheduleData currentData) async {
    final silentChanges = await _controller
        .silentCheckRecentWeeksForChangesDetailed(currentData);
    if (!mounted || silentChanges.isEmpty) return;
    _syncCurrentWeekFromCache();
  }

  void _scheduleSilentForegroundFullRefresh(ScheduleData currentData) {
    unawaited(
      _controller
          .refreshAllWeeksInForeground(currentData)
          .then((_) {
            if (!mounted) return;
            _syncCurrentWeekFromCache();
          })
          .catchError((_) {}),
    );
  }

  void _syncCurrentWeekFromCache() {
    if (!mounted || _weekList == null) return;
    if (_currentWeekIndex < 0 || _currentWeekIndex >= _weekList!.length) return;
    final week = _weekList![_currentWeekIndex];
    final wInt = int.tryParse(week) ?? 0;
    final refreshed = _weekCache[wInt];
    if (refreshed == null) return;
    _setState(() {
      _currentScheduleData = refreshed;
    });
  }

  Future<void> _maybeShowBackgroundPollingGuide() async {
    if (!mounted) return;
    if (_settingsManager.backgroundPollingEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    final account = (prefs.getString('account') ?? '').trim();
    final key = account.isEmpty
        ? 'schedule_polling_guide_shown'
        : 'schedule_polling_guide_shown_$account';
    final shown = prefs.getBool(key) ?? false;
    if (shown) return;
    await prefs.setBool(key, true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('如需自动更新课表，请在右上角设置中开启“定时轮询”功能'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '去设置',
          onPressed: _showScheduleSettingsSheetWrapper,
        ),
      ),
    );
  }

  void _processLoadedData(
    ScheduleData data, {
    bool isInitial = false,
    bool keepCurrentSelection = false,
  }) {
    if (data.weekNum == null || data.weekList == null) return;

    _controller.processLoadedData(data);

    _setState(() {
      final newIndex = _controller.weekList!.indexOf(data.weekNum!);
      final hasValidCurrentIndex =
          _weekList != null &&
          _currentWeekIndex >= 0 &&
          _currentWeekIndex < _weekList!.length;

      if (keepCurrentSelection && hasValidCurrentIndex) {
        final selectedWeek = _weekList![_currentWeekIndex];
        final selectedWeekInt = int.tryParse(selectedWeek) ?? -1;
        _currentScheduleData = _weekCache[selectedWeekInt] ?? data;
      } else {
        _currentScheduleData = data;
      }

      if (newIndex != -1) {
        final targetIndex = keepCurrentSelection && hasValidCurrentIndex
            ? _currentWeekIndex
            : newIndex;
        if (_pageController == null) {
          _currentWeekIndex = targetIndex;
          _pageController = PageController(initialPage: targetIndex);
        } else if (_currentWeekIndex != newIndex &&
            !isInitial &&
            !keepCurrentSelection) {
          _currentWeekIndex = newIndex;
          _pageController!.jumpToPage(newIndex);
        }
      }
    });
  }

  Future<ScheduleData?> _loadFromNetwork({
    String? weekNum,
    String? yearTerm,
    bool updateWidgetPins = false,
    bool fromInitialBoot = false,
  }) async {
    if (_controller.weekCache.containsKey(int.tryParse(weekNum ?? "") ?? -1)) {}

    _setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _controller.loadFromNetwork(
        weekNum: weekNum,
        yearTerm: yearTerm,
        updateWidgetPins: updateWidgetPins,
      );

      _processLoadedData(
        data,
        keepCurrentSelection:
            fromInitialBoot && _userChangedWeekDuringInitialBoot,
      );
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
      return data;
    } catch (e) {
      _setState(() {
        _error = e.toString();
      });
      return null;
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
    await _controller.ensureWeekLoaded(
      weekNum,
      yearTerm,
      updateLastViewed: true,
    );
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
  }
}
