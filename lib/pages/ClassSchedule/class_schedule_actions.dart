part of 'ClassSchedule.dart';

extension _ClassScheduleActions on _ClassscheduleViewState {
  void _onPageChanged(int index) {
    if (_initialBootRequestPending) {
      _userChangedWeekDuringInitialBoot = true;
    }

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

  String _normalizeCourseName(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) {
      return '未命名课程';
    }
    return value;
  }

  String _buildCourseTimeText(EventItem event) {
    final dayLabel = _weekDayLabel(event.weekDay);
    final start = int.tryParse(event.sessionStart ?? '');
    final last = int.tryParse(event.sessionLast ?? '');
    final sessionText = (start != null && last != null)
        ? '${event.sessionStart}-${start + last - 1}节'
        : '节次未知';
    final weekCover = (event.weekCover ?? '').trim();
    final timeParts = <String>[if (dayLabel.isNotEmpty) dayLabel, sessionText];
    if (weekCover.isEmpty) {
      return timeParts.join(' ');
    }
    return '$weekCover · ${timeParts.join(' ')}';
  }

  String _weekDayLabel(String? raw) {
    const labels = <int, String>{
      1: '周一',
      2: '周二',
      3: '周三',
      4: '周四',
      5: '周五',
      6: '周六',
      7: '周日',
    };
    final day = int.tryParse((raw ?? '').trim());
    if (day == null) {
      return '';
    }
    return labels[day] ?? '';
  }

  int _buildCourseTimeSortValue(EventItem event) {
    final day = int.tryParse((event.weekDay ?? '').trim()) ?? 9;
    final sessionStart = int.tryParse((event.sessionStart ?? '').trim()) ?? 99;
    return day * 100 + sessionStart;
  }

  String _buildAggregatedCourseTimeText(List<EventItem> events) {
    final sorted = List<EventItem>.from(events)
      ..sort(
        (a, b) => _buildCourseTimeSortValue(
          a,
        ).compareTo(_buildCourseTimeSortValue(b)),
      );
    final seen = <String>{};
    final result = <String>[];
    for (final event in sorted) {
      final text = _buildCourseTimeText(event);
      if (seen.add(text)) {
        result.add(text);
      }
    }
    return result.join('；');
  }

  void _openCourseNotebookByEvent(EventItem event) {
    final name = _normalizeCourseName(event.eventName);
    final subtitleParts = <String>[
      if ((event.memberName ?? '').trim().isNotEmpty)
        '教师：${event.memberName!.trim()}',
      if ((event.address ?? '').trim().isNotEmpty)
        '教室：${event.address!.trim()}',
      _buildCourseTimeText(event),
    ];
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourseNotebookPage(
          courseName: name,
          yearTerm: _currentScheduleData?.yearTerm,
          subtitle: subtitleParts.join(' · '),
        ),
      ),
    );
  }

  void _openCourseOverview() {
    final currentData = _currentScheduleData;
    if (currentData == null) {
      return;
    }
    _controller.prefetchAllWeeksInBackground(currentData, () {
      if (mounted) {
        _setState(() {});
      }
    });
    final grouped = <String, List<EventItem>>{};
    final weeks = _weekCache.values.toList()
      ..sort((a, b) {
        final wa = int.tryParse(a.weekNum ?? '') ?? 0;
        final wb = int.tryParse(b.weekNum ?? '') ?? 0;
        return wa.compareTo(wb);
      });
    for (final weekData in weeks) {
      final events = weekData.eventList ?? const <EventItem>[];
      for (final event in events) {
        final name = _normalizeCourseName(event.eventName);
        grouped.putIfAbsent(name, () => <EventItem>[]).add(event);
      }
    }
    final map = <String, CourseOverviewItem>{};
    grouped.forEach((name, events) {
      final first = events.first;
      map[name] = CourseOverviewItem(
        courseName: name,
        teacher: first.memberName,
        address: first.address,
        timeText: _buildAggregatedCourseTimeText(events),
      );
    });
    final courses = map.values.toList()
      ..sort((a, b) => a.courseName.compareTo(b.courseName));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourseOverviewPage(
          yearTerm: _currentScheduleData?.yearTerm,
          courses: courses,
          onTapCourse: (item) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CourseNotebookPage(
                  courseName: item.courseName,
                  yearTerm: _currentScheduleData?.yearTerm,
                  subtitle: [
                    item.timeText,
                    if ((item.address ?? '').trim().isNotEmpty)
                      '教室：${item.address!.trim()}',
                    if ((item.teacher ?? '').trim().isNotEmpty)
                      '教师：${item.teacher!.trim()}',
                  ].join(' · '),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showScheduleSettingsSheetWrapper() {
    showScheduleSettingsSheet(
      context,
      initialShowWeekend: _settingsManager.showWeekend,
      initialTimeInfoEnabled: _settingsManager.timeInfoEnabled,
      initialUpdateShowDiff: _settingsManager.updateShowDiff,
      initialBackgroundPollingEnabled:
          _settingsManager.backgroundPollingEnabled,
      initialNoticeApiBaseUrl: _settingsManager.noticeApiBaseUrl,
      onSave:
          ({
            required showWeekend,
            required timeInfoEnabled,
            required updateShowDiff,
            required backgroundPollingEnabled,
            required noticeApiBaseUrl,
          }) async {
            await _settingsManager.save(
              showWeekend: showWeekend,
              timeInfoEnabled: timeInfoEnabled,
              updateShowDiff: updateShowDiff,
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

  Future<void> _openTermNoticeRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = (prefs.getString('account') ?? '').trim();
    final encryptedPassword = (prefs.getString('encrypted_password') ?? '')
        .trim();
    final yearTerm = (_currentScheduleData?.yearTerm ?? '').trim();
    final nowHour = DateTime.now().hour;
    final deepNight = nowHour >= 0 && nowHour < 7;
    final cache = _loadNoticeCache(
      prefs: prefs,
      userId: userId,
      yearTerm: yearTerm,
    );

    Future<ScheduleNoticePollData> Function()? onRefresh;
    if (userId.isNotEmpty && encryptedPassword.isNotEmpty && !deepNight) {
      onRefresh = () async {
        final result = await ScheduleApi().fetchTermScheduleNotices(
          userId: userId,
          encryptedPassword: encryptedPassword,
        );
        await _saveNoticeCache(
          prefs: prefs,
          userId: userId,
          yearTerm: yearTerm,
          data: result,
        );
        return result;
      };
    } else if (deepNight) {
      final day = DateTime.now().toIso8601String().split('T').first;
      final noticeTipKey =
          'schedule_notice_deep_night_tip_shown_${userId.isEmpty ? 'anon' : userId}_$day';
      final shown = prefs.getBool(noticeTipKey) ?? false;
      if (!shown) {
        await prefs.setBool(noticeTipKey, true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('由于学校接口限制，在0:00-7:00时会关闭请求服务'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (cache.notices.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未读取到账号凭证，请重新登录后再试'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    showScheduleNoticeRecordsSheet(
      context,
      yearTerm: yearTerm,
      initialNotices: cache.notices,
      initialGeneratedAt: cache.generatedAt,
      onRefresh: onRefresh,
    );
  }

  ({String generatedAt, List<ScheduleNotice> notices}) _loadNoticeCache({
    required SharedPreferences prefs,
    required String userId,
    required String yearTerm,
  }) {
    if (userId.isEmpty) {
      return (generatedAt: '', notices: const <ScheduleNotice>[]);
    }
    final raw = prefs.getString(_noticeCacheKey(userId, yearTerm));
    if (raw == null || raw.trim().isEmpty) {
      return (generatedAt: '', notices: const <ScheduleNotice>[]);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return (generatedAt: '', notices: const <ScheduleNotice>[]);
      }
      final generatedAt = (decoded['generatedAt'] ?? '').toString();
      final listRaw = decoded['notices'];
      if (listRaw is! List) {
        return (generatedAt: generatedAt, notices: const <ScheduleNotice>[]);
      }
      final notices = <ScheduleNotice>[];
      for (final item in listRaw) {
        if (item is! Map) continue;
        notices.add(
          ScheduleNotice(
            noticeId: (item['noticeId'] ?? '').toString(),
            status: (item['status'] ?? '').toString(),
            publishedAt: (item['publishedAt'] ?? '').toString(),
            title: (item['title'] ?? '').toString(),
            content: (item['content'] ?? '').toString(),
            courseName: _asNullableText(item['courseName']),
            teacher: _asNullableText(item['teacher']),
            originalTime: _asNullableText(item['originalTime']),
            originalClassroom: _asNullableText(item['originalClassroom']),
            adjustedTime: _asNullableText(item['adjustedTime']),
            adjustedClassroom: _asNullableText(item['adjustedClassroom']),
          ),
        );
      }
      notices.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      return (generatedAt: generatedAt, notices: notices);
    } catch (_) {
      return (generatedAt: '', notices: const <ScheduleNotice>[]);
    }
  }

  Future<void> _saveNoticeCache({
    required SharedPreferences prefs,
    required String userId,
    required String yearTerm,
    required ScheduleNoticePollData data,
  }) async {
    if (userId.isEmpty) return;
    final payload = <String, dynamic>{
      'generatedAt': data.generatedAt,
      'notices': data.notices
          .map(
            (e) => <String, dynamic>{
              'noticeId': e.noticeId,
              'status': e.status,
              'publishedAt': e.publishedAt,
              'title': e.title,
              'content': e.content,
              'courseName': e.courseName,
              'teacher': e.teacher,
              'originalTime': e.originalTime,
              'originalClassroom': e.originalClassroom,
              'adjustedTime': e.adjustedTime,
              'adjustedClassroom': e.adjustedClassroom,
            },
          )
          .toList(),
    };
    await prefs.setString(
      _noticeCacheKey(userId, yearTerm),
      jsonEncode(payload),
    );
  }

  String _noticeCacheKey(String userId, String yearTerm) {
    final termKey = yearTerm.trim().isEmpty ? 'current' : yearTerm.trim();
    return 'schedule_notice_records_cache_${userId}_$termKey';
  }

  String? _asNullableText(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }
}
