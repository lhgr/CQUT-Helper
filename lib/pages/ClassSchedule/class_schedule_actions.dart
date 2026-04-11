part of 'ClassSchedule.dart';

extension _ClassScheduleActions on _ClassscheduleViewState {
  void _onPageChanged(int index) {
    if (_weekList != null && index >= 0 && index < _weekList!.length) {
      FirebaseAnalytics.instance.logEvent(
        name: 'view_schedule_week',
        parameters: {'week_number': _weekList![index]},
      );
    }

    _setState(() {
      _currentWeekIndex = index;
    });

    if (_weekList == null || index < 0 || index >= _weekList!.length) return;

    final targetWeek = _weekList![index];
    final currentTerm = _currentScheduleData?.yearTerm ?? _currentTerm;

    final wInt = int.tryParse(targetWeek) ?? 0;
    if (_weekCache.containsKey(wInt)) {
      _setState(() {
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
      final pc = _pageController;
      if (pc != null && pc.hasClients) {
        pc.animateToPage(
          index,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      } else {
        pc?.jumpToPage(index);
      }
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

  void _showScheduleSettingsSheetWrapper() {
    final maxWeeksAhead = maxWeeksAheadForSchedule(
      weekList:
          _currentScheduleData?.weekList ?? _updateManager.controller.weekList,
      currentWeek: _currentScheduleData?.weekNum ??
          _updateManager.controller.actualCurrentWeekStr,
    );
    showScheduleSettingsSheet(
      context,
      initialWeeksAhead: _settingsManager.updateWeeksAhead,
      initialShowWeekend: _settingsManager.showWeekend,
      initialTimeInfoEnabled: _settingsManager.timeInfoEnabled,
      initialUpdateEnabled: _settingsManager.updateEnabled,
      initialUpdateIntervalMinutes: _settingsManager.updateIntervalMinutes,
      initialUpdateShowDiff: _settingsManager.updateShowDiff,
      initialSystemNotifyEnabled: _settingsManager.updateSystemNotifyEnabled,
      maxWeeksAhead: maxWeeksAhead,
      onSave:
          ({
            required weeksAhead,
            required showWeekend,
            required timeInfoEnabled,
            required updateEnabled,
            required updateIntervalMinutes,
            required updateShowDiff,
            required systemNotifyEnabled,
          }) async {
            await _settingsManager.save(
              showWeekend: showWeekend,
              timeInfoEnabled: timeInfoEnabled,
              updateWeeksAhead: weeksAhead,
              updateEnabled: updateEnabled,
              updateIntervalMinutes: updateIntervalMinutes,
              updateShowDiff: updateShowDiff,
              updateSystemNotifyEnabled: systemNotifyEnabled,
            );
            if (mounted) {
              _setState(() {});
            }
            if (timeInfoEnabled) {
              final loaded = await _controller.loadTimeInfoFromCacheIfAny();
              if (loaded && mounted) _setState(() {});
              unawaited(
                _controller.refreshTimeInfoIfEnabled(force: true).then((changed) {
                  if (changed && mounted) _setState(() {});
                }),
              );
            }
            _configureUpdateTimer();
          },
    );
  }
}
