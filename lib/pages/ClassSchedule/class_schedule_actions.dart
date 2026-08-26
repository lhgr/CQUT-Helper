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

  String _courseCustomizationKey(EventItem event) {
    final cachedKey = (event.customizationKey ?? '').trim();
    return cachedKey.isNotEmpty
        ? cachedKey
        : ScheduleCustomizationManager.courseKeyForEvent(event);
  }

  Future<void> _editCourse(EventItem event) async {
    if (event.isSchoolCustomCourse) {
      await _editCustomCourse(event);
      return;
    }
    await _editCoursePreference(event);
  }

  Future<void> _editCoursePreference(EventItem event) async {
    final userId = (_controller.userId ?? '').trim();
    final term = (_currentScheduleData?.yearTerm ?? '').trim();
    if (userId.isEmpty || term.isEmpty) {
      _showBoundaryMessage('请先登录并加载当前学期课表');
      return;
    }
    final courseKey = _courseCustomizationKey(event);
    final initial = await ScheduleCustomizationManager.instance.preferenceFor(
      userId: userId,
      yearTerm: term,
      courseKey: courseKey,
    );
    if (!mounted) return;
    final preference = await showCoursePreferenceEditor(
      context,
      userId: userId,
      yearTerm: term,
      courseKey: courseKey,
      currentName: (event.eventName ?? '').trim(),
      currentTeacher: (event.memberName ?? '').trim(),
      currentLocation: (event.address ?? '').trim(),
      initial: initial,
    );
    if (preference == null) return;
    await ScheduleCustomizationManager.instance.saveCoursePreference(
      preference,
    );
    if (preference.hidden && initial?.hidden != true) {
      await _maybeShowHiddenCourseGuide(userId);
    }
  }

  Future<void> _maybeShowHiddenCourseGuide(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'schedule_hidden_course_guide_shown_${userId.trim()}';
    if (prefs.getBool(key) ?? false) return;
    await prefs.setBool(key, true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('课程已隐藏，可在“课表设置 → 已隐藏课程”中取消隐藏'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '去设置',
          onPressed: _showScheduleSettingsPage,
        ),
      ),
    );
  }

  Future<void> _editCustomCourse(EventItem event) async {
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
          initial: event,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _refreshAfterCustomCourseMutation();
    }
  }

  Future<void> _deleteCustomCourse(EventItem event) async {
    if (!event.isSchoolCustomCourse) return;
    final title = (event.eventName ?? '').trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除自定义课程'),
        content: Text('确定从学校课表中删除“$title”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _controller.loadCredentials();
    if (!mounted) return;
    final userId = (_controller.userId ?? '').trim();
    final encryptedPassword = (_controller.encryptedPassword ?? '').trim();
    if (userId.isEmpty || encryptedPassword.isEmpty) {
      _showBoundaryMessage('请先登录并加载当前学期课表');
      return;
    }
    try {
      await _controller.deleteCustomEvent(
        userId: userId,
        encryptedPassword: encryptedPassword,
        eventId: event.eventID!.trim(),
      );
      if (mounted) await _refreshAfterCustomCourseMutation();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
      final schedulesByWeek = <String, ScheduleData>{};
      final failedWeeks = <String>[];
      for (final week in weeks) {
        if (!mounted) return;
        final loaded = await _controller.ensureWeekLoaded(
          week,
          term,
          updateLastViewed: false,
        );
        final data = _weekCache[int.tryParse(week)];
        if (!loaded || data == null || (data.yearTerm ?? '').trim() != term) {
          failedWeeks.add(week);
          continue;
        }
        schedulesByWeek[week] = data;
      }
      final current = _currentScheduleData;
      final currentWeek = (current?.weekNum ?? '').trim();
      if (current != null &&
          currentWeek.isNotEmpty &&
          (current.yearTerm ?? '').trim() == term) {
        schedulesByWeek.putIfAbsent(currentWeek, () => current);
      }
      await _controller.ensureTimeInfoLoaded();
      await _settingsManager.load();
      final result = ScheduleIcsService.generateResult(
        schedules: schedulesByWeek.values,
        timeInfo: _controller.timeInfoList ?? const <CampusTimeInfo>[],
        defaultReminderMinutes: _settingsManager.defaultReminderMinutes,
      );
      if (result.eventCount == 0) {
        final message = result.sourceEventCount == 0
            ? failedWeeks.isEmpty
                  ? '当前学期没有可导出的课程'
                  : '课表读取失败，未生成 ICS 文件'
            : '课程日期信息不完整，未生成 ICS 文件';
        if (mounted) _showBoundaryMessage(message);
        return;
      }
      final safeTerm = term.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_');
      final path = await ScheduleIcsService.exportToDownloads(
        content: result.content,
        fileName: 'CQUT-$safeTerm.ics',
      );
      if (!mounted) return;
      final suffix = failedWeeks.isEmpty
          ? ''
          : '（第${failedWeeks.join('、')}周读取失败）';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ICS 已导出到 $path$suffix')));
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

  void _showScheduleSettingsPage() {
    openAppSettings(
      context,
      section: AppSettingsSection.schedule,
      userId: _controller.userId ?? '',
      yearTerm: _currentScheduleData?.yearTerm ?? '',
    );
  }

  void _showNotificationSettingsPage() {
    openAppSettings(
      context,
      section: AppSettingsSection.notifications,
      userId: _controller.userId ?? '',
      yearTerm: _currentScheduleData?.yearTerm ?? '',
    );
  }
}
