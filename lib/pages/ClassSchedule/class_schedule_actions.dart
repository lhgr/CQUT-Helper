part of 'ClassSchedule.dart';

extension _ClassScheduleActions on _ClassscheduleViewState {
  void _onPageChanged(int index) {
    if (_initialBootRequestPending) {
      _userChangedWeekDuringInitialBoot = true;
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
    } else if (currentTerm != null) {
      _ensureWeekLoaded(targetWeek, currentTerm);
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

  Future<void> _openSemesterCourseListPage() async {
    final yearTerm = (_currentScheduleData?.yearTerm ?? '').trim();
    if (yearTerm.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前学期信息不可用'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final weeks = _weekList ?? const <String>[];
    final progress = ValueNotifier<int>(0);
    BuildContext? progressDialogContext;
    if (weeks.isNotEmpty) {
      final dialogReady = Completer<BuildContext>();
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            if (!dialogReady.isCompleted) {
              dialogReady.complete(dialogContext);
            }
            progressDialogContext = dialogContext;
            return PopScope(
              canPop: false,
              child: AlertDialog(
                title: const Text('正在准备本学期课程'),
                content: ValueListenableBuilder<int>(
                  valueListenable: progress,
                  builder: (context, completed, _) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: weeks.isEmpty
                              ? null
                              : completed / weeks.length,
                        ),
                        const SizedBox(height: 12),
                        Text('已读取 $completed/${weeks.length} 周'),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      );
      await dialogReady.future;
    }

    final failedWeeks = <String>[];
    try {
      for (var index = 0; index < weeks.length; index++) {
        if (!mounted) return;
        final week = weeks[index];
        final success = await _controller.ensureWeekLoaded(
          week,
          yearTerm,
          updateLastViewed: false,
        );
        if (!success) failedWeeks.add(week);
        progress.value = index + 1;
      }
    } finally {
      final dialogContext = progressDialogContext;
      if (dialogContext != null && dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      progress.dispose();
    }
    if (!mounted) return;

    final events = <EventItem>[];
    for (final data in _weekCache.values) {
      if ((data.yearTerm ?? '').trim() != yearTerm) continue;
      final list = data.eventList;
      if (list == null || list.isEmpty) continue;
      events.addAll(list);
    }
    if (events.isEmpty) {
      final fallback = _currentScheduleData?.eventList;
      if (fallback != null && fallback.isNotEmpty) {
        events.addAll(fallback);
      }
    }
    if (failedWeeks.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('部分课表读取失败：第${failedWeeks.join('、')}周，已展示其余课程'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SemesterCourseListPage(
          yearTerm: yearTerm,
          events: events,
          userId: _controller.userId ?? '',
        ),
      ),
    );
  }

  List<int> get _availableWeekNumbers => (_weekList ?? const <String>[])
      .map(int.tryParse)
      .whereType<int>()
      .where((week) => week > 0)
      .toList(growable: false);

  Future<void> _refreshAfterCustomCourseMutation() async {
    final userId = (_controller.userId ?? '').trim();
    final term = (_currentScheduleData?.yearTerm ?? '').trim();
    final currentWeek = (_currentScheduleData?.weekNum ?? '').trim();
    if (userId.isEmpty || term.isEmpty || currentWeek.isEmpty) return;
    await _controller.invalidateCachedWeeks(
      userId: userId,
      yearTerm: term,
      weeks: _availableWeekNumbers,
    );
    if (!mounted) return;
    await _loadFromNetwork(weekNum: currentWeek, yearTerm: term);
  }

  Future<void> _openCustomCourseEditor() async {
    await _controller.loadCredentials();
    if (!mounted) return;
    final userId = (_controller.userId ?? '').trim();
    final encryptedPassword = (_controller.encryptedPassword ?? '').trim();
    final term = (_currentScheduleData?.yearTerm ?? '').trim();
    if (userId.isEmpty ||
        encryptedPassword.isEmpty ||
        term.isEmpty ||
        _availableWeekNumbers.isEmpty) {
      _showBoundaryMessage('请先登录并加载当前学期课表');
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomCourseEditorPage(
          userId: userId,
          encryptedPassword: encryptedPassword,
          yearTerm: term,
          availableWeeks: _availableWeekNumbers,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _refreshAfterCustomCourseMutation();
    }
  }

  Future<void> _openCustomCourseList() async {
    await _controller.loadCredentials();
    if (!mounted) return;
    final userId = (_controller.userId ?? '').trim();
    final encryptedPassword = (_controller.encryptedPassword ?? '').trim();
    final term = (_currentScheduleData?.yearTerm ?? '').trim();
    if (userId.isEmpty ||
        encryptedPassword.isEmpty ||
        term.isEmpty ||
        _availableWeekNumbers.isEmpty) {
      _showBoundaryMessage('请先登录并加载当前学期课表');
      return;
    }
    var changed = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CustomCourseListPage(
          userId: userId,
          encryptedPassword: encryptedPassword,
          yearTerm: term,
          availableWeeks: _availableWeekNumbers,
          onChanged: () => changed = true,
        ),
      ),
    );
    if (changed && mounted) {
      await _refreshAfterCustomCourseMutation();
    }
  }

  Future<void> _exportIcs() async {
    final term = (_currentScheduleData?.yearTerm ?? '').trim();
    final weeks = _weekList ?? const <String>[];
    if (term.isEmpty || weeks.isEmpty) {
      _showBoundaryMessage('当前学期信息不可用');
      return;
    }
    BuildContext? loadingContext;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          loadingContext = dialogContext;
          return const PopScope(
            canPop: false,
            child: AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 18),
                  Expanded(child: Text('正在整理本学期课表…')),
                ],
              ),
            ),
          );
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    try {
      for (final week in weeks) {
        if (!mounted) return;
        await _controller.ensureWeekLoaded(week, term, updateLastViewed: false);
        final merged = await _controller.loadFromCache(
          weekNum: week,
          yearTerm: term,
        );
        if (merged != null) _controller.processLoadedData(merged);
      }
      await _controller.ensureTimeInfoLoaded();
      final schedules = _weekCache.values
          .where((data) => (data.yearTerm ?? '').trim() == term)
          .toList(growable: false);
      final content = ScheduleIcsService.generate(
        schedules: schedules,
        timeInfo: _controller.timeInfoList ?? const <CampusTimeInfo>[],
      );
      final safeTerm = term.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_');
      final path = await ScheduleIcsService.exportToDownloads(
        content: content,
        fileName: 'CQUT-$safeTerm.ics',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ICS 已导出到 $path')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ICS 导出失败：$error')));
    } finally {
      final dialogContext = loadingContext;
      if (dialogContext != null && dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
    }
  }

  void _returnToCurrentWeek() {
    if (_actualCurrentWeekStr == null) {
      _loadFromNetwork();
      return;
    }

    final actualTerm = _actualCurrentTermStr;
    final currentTerm = _currentScheduleData?.yearTerm ?? _currentTerm;
    if (actualTerm != null && currentTerm != actualTerm) {
      _weekCache.clear();
      _loadFromNetwork(weekNum: _actualCurrentWeekStr, yearTerm: actualTerm);
      return;
    }

    if (_weekList == null) {
      _loadFromNetwork(weekNum: _actualCurrentWeekStr, yearTerm: actualTerm);
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
        now.difference(_lastMessageTime!) < const Duration(seconds: 2)) {
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

  void _showScheduleSettingsSheetWrapper() {
    showScheduleSettingsSheet(
      context,
      initialShowWeekend: _settingsManager.showWeekend,
      initialTimeInfoEnabled: _settingsManager.timeInfoEnabled,
      initialBackgroundPollingEnabled:
          _settingsManager.backgroundPollingEnabled,
      initialNoticeApiBaseUrl: _settingsManager.noticeApiBaseUrl,
      onSave:
          ({
            required showWeekend,
            required timeInfoEnabled,
            required backgroundPollingEnabled,
            required noticeApiBaseUrl,
          }) async {
            await _settingsManager.save(
              showWeekend: showWeekend,
              timeInfoEnabled: timeInfoEnabled,
              backgroundPollingEnabled: backgroundPollingEnabled,
              noticeApiBaseUrl: noticeApiBaseUrl,
            );
            await ScheduleUpdateWorker.syncFromPreferences();
            if (mounted) {
              _setState(() {});
            }
            if (timeInfoEnabled) {
              final loaded = await _controller.loadTimeInfoFromCacheIfAny();
              if (loaded && mounted) _setState(() {});
              unawaited(
                _controller.refreshTimeInfoIfEnabled(force: true).then((
                  changed,
                ) {
                  if (changed && mounted) _setState(() {});
                }),
              );
            }
          },
    );
  }
}
