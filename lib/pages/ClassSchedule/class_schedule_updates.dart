part of 'ClassSchedule.dart';

extension _ClassScheduleUpdates on _ClassscheduleViewState {
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
    } else {
      unawaited(refreshWeeks());
    }
    _showUpdateNotification(changes);
    return true;
  }

  void _showUpdateNotification(List<ScheduleWeekChange> changes) {
    if (!mounted || changes.isEmpty) return;
    final hasScheduleNotice = changes.any(
      (c) => c.lines.any((line) => line.contains('调课到')),
    );
    if (hasScheduleNotice) {
      final messages = _buildInlineNoticeMessages(changes);
      if (messages.isNotEmpty) {
        _setState(() {
          _inlineNoticeMessages = messages;
        });
      }
    }
    final first = changes.first;
    final msg = hasScheduleNotice
        ? (changes.length == 1
              ? '${_labelForWeek(first.weekNum)}检测到调课'
              : '${_labelForWeek(first.weekNum)}等${changes.length}周检测到调课')
        : (changes.length == 1
              ? '${_labelForWeek(first.weekNum)}课表有更新'
              : '${_labelForWeek(first.weekNum)}等${changes.length}周课表有更新');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<String> _buildInlineNoticeMessages(List<ScheduleWeekChange> changes) {
    final messages = <String>[];
    for (final change in changes) {
      if (change.lines.isEmpty) {
        messages.add('${_labelForWeek(change.weekNum)}调课信息不完整，请在“调课记录”查看详情');
        continue;
      }
      for (final raw in change.lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        if (!line.contains('调课到') || !line.contains('**')) {
          messages.add('${_labelForWeek(change.weekNum)}调课信息格式异常：$line');
          continue;
        }
        messages.add(line);
      }
    }
    return messages.toSet().toList();
  }

  void _dismissInlineNoticeAt(int index) {
    if (index < 0 || index >= _inlineNoticeMessages.length) return;
    final next = List<String>.from(_inlineNoticeMessages)..removeAt(index);
    _setState(() {
      _inlineNoticeMessages = next;
    });
  }

  void _clearInlineNotices() {
    if (_inlineNoticeMessages.isEmpty) return;
    _setState(() {
      _inlineNoticeMessages = const <String>[];
    });
  }
}
