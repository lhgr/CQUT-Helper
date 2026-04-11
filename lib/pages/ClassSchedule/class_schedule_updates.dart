part of 'ClassSchedule.dart';

extension _ClassScheduleUpdates on _ClassscheduleViewState {
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
    final pending = await _updateManager.checkPendingChanges();
    final changes = pending.changes;
    if (changes.isEmpty || !mounted) return false;

    final first = changes.first;

    Future<void> refreshWeeks() async {
      final payloadTerm = pending.yearTerm;
      final currentTerm = _currentScheduleData?.yearTerm ?? _currentTerm;
      final termToUse = payloadTerm == null ||
              payloadTerm.isEmpty ||
              currentTerm == null ||
              currentTerm == payloadTerm
          ? (payloadTerm ?? currentTerm)
          : currentTerm;
      if (termToUse == null || termToUse.trim().isEmpty) return;

      final uniqWeeks = changes.map((c) => c.weekNum).toSet().toList();
      for (final w in uniqWeeks) {
        if (!mounted) return;
        await _controller.ensureWeekLoaded(w, termToUse, forceRefresh: true);
      }
      if (!mounted) return;
      _setState(() {});
    }

    if (autoOpen) {
      await refreshWeeks();
      if (_settingsManager.updateShowDiff) {
        _showScheduleChangesSheet(changes);
      } else {
        _jumpToWeek(first.weekNum);
      }
      return true;
    }

    unawaited(refreshWeeks());
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
}
