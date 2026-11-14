part of 'ClassSchedule.dart';

extension _ClassScheduleNavigation on _ClassscheduleViewState {
  void _cancelLocation() {
    _locationTarget = null;
    _locationLoading = false;
    _locationError = null;
    _locationNeedsLogin = false;
  }

  void _onOpenWeek() {
    final target = ScheduleUpdateIntents.openWeek.value;
    if (!_locationReady || target == null || !mounted) return;
    ScheduleUpdateIntents.consumeOpenWeek(target);
    unawaited(_openLocatedWeek(target));
  }

  Future<void> _openLocatedWeek(ScheduleLocationRequest target) async {
    final generation = ++_viewGeneration;
    _resetDeferredWork();
    _setState(() {
      _locationTarget = target;
      _locationLoading = true;
      _locationError = null;
      _locationNeedsLogin = false;
    });
    bool current() =>
        mounted &&
        generation == _viewGeneration &&
        _locationTarget?.token == target.token;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!current()) return;
      if ((prefs.getString('account') ?? '').trim() != target.userId) {
        _setState(_cancelLocation);
        return;
      }
      if (target.yearTerm.isEmpty || (int.tryParse(target.weekNum) ?? 0) <= 0) {
        throw StateError('该记录缺少有效的学期或周次');
      }
      final memory = _currentTerm == target.yearTerm
          ? _weekCache[int.parse(target.weekNum)]
          : null;
      final data =
          memory ??
          await _controller.loadWeekForNavigation(
            target.weekNum,
            target.yearTerm,
          );
      if (!current()) return;
      final latestPrefs = await SharedPreferences.getInstance();
      if (!current()) return;
      if ((latestPrefs.getString('account') ?? '').trim() != target.userId) {
        _setState(_cancelLocation);
        return;
      }
      if ((data.yearTerm ?? '').trim() != target.yearTerm ||
          (data.weekNum ?? '').trim() != target.weekNum ||
          !(data.weekList?.contains(target.weekNum) ?? false)) {
        throw StateError('该学期周次的课表已不可用');
      }
      _followDeviceWeek = false;
      _controller.selectWeek(target.weekNum, target.yearTerm);
      _failedWeeks.clear();
      _processLoadedData(data);
      _setState(() {
        _loading = false;
        _error = null;
        _cancelLocation();
      });
      await _controller.rememberSelection(data);
    } catch (error, stackTrace) {
      if (!current()) return;
      SharedPreferences? prefs;
      try {
        prefs = await SharedPreferences.getInstance();
      } catch (_) {
        // A storage failure must still leave a recoverable destination error.
      }
      if (!current()) return;
      if (prefs != null &&
          (prefs.getString('account') ?? '').trim() != target.userId) {
        _setState(_cancelLocation);
        return;
      }
      AppLogger.I.warn(
        'ClassSchedule',
        'Unable to open message week',
        error: error,
        stackTrace: stackTrace,
      );
      _setState(() {
        _locationLoading = false;
        _locationNeedsLogin =
            ScheduleRefreshState.looksLikeCredentialFailure(error) ||
            error.toString().toLowerCase().contains('login');
        _locationError = _locationNeedsLogin
            ? '请重新登录后查看${target.yearTerm}学期第${target.weekNum}周课表。'
            : '无法打开${target.yearTerm}学期第${target.weekNum}周课表。';
      });
    }
  }

  Future<void> _retryLocatedWeek() async {
    final target = _locationTarget;
    if (target == null || _locationLoading || _locationAuthenticating) return;
    if (_locationNeedsLogin) {
      _setState(() => _locationAuthenticating = true);
      try {
        if (!await requestReauthentication(context) ||
            !mounted ||
            _locationTarget?.token != target.token) {
          return;
        }
      } finally {
        if (mounted) _setState(() => _locationAuthenticating = false);
      }
    }
    await _openLocatedWeek(target);
  }

  Widget _buildLocationNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_locationLoading) const LinearProgressIndicator(),
          Text(_locationLoading ? '正在打开对应周课表…' : _locationError!),
          if (!_locationLoading)
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _locationAuthenticating ? null : _retryLocatedWeek,
                  child: Text(_locationNeedsLogin ? '重新登录' : '重试'),
                ),
                TextButton(
                  onPressed: () => _setState(_cancelLocation),
                  child: const Text('关闭'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
