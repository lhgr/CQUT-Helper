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

    final networkData = await _loadFromNetwork();
    if (cachedData != null && networkData != null && mounted) {
      final sameWeek = (cachedData.weekNum ?? '').trim().isNotEmpty &&
          (networkData.weekNum ?? '').trim().isNotEmpty &&
          cachedData.weekNum!.trim() == networkData.weekNum!.trim();
      final sameTerm = (cachedData.yearTerm ?? '').trim().isNotEmpty &&
          (networkData.yearTerm ?? '').trim().isNotEmpty &&
          cachedData.yearTerm!.trim() == networkData.yearTerm!.trim();
      if (sameWeek && sameTerm) {
        final beforeFp = scheduleFingerprintFromScheduleData(cachedData);
        final afterFp = scheduleFingerprintFromScheduleData(networkData);
        if (beforeFp != afterFp) {
          var lines = diffScheduleWeekLines(before: cachedData, after: networkData);
          if (lines.isEmpty) {
            lines = const <String>['课表内容有更新'];
          }
          _showUpdateNotification([
            ScheduleWeekChange(
              weekNum: networkData.weekNum!.trim(),
              lines: lines,
            ),
          ]);
        }
      }
    }

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
    await _maybeShowBackgroundPollingGuide();
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
  }

  Future<ScheduleData?> _loadFromNetwork({
    String? weekNum,
    String? yearTerm,
    bool updateWidgetPins = false,
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
