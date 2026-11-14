import 'package:cqut_helper/api/api_service.dart';
import 'package:cqut_helper/manager/cache_cleanup_manager.dart';
import 'package:cqut_helper/manager/schedule_refresh_state.dart';
import 'package:cqut_helper/pages/Login/Login.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:material_ui/material_ui.dart';

import 'mine_menu_section.dart';
import 'mine_optional_features_card.dart';
import 'mine_user_info_card.dart';
import 'mine_user_info_loader.dart';
import 'mine_user_info_view_model.dart';

class MineView extends StatefulWidget {
  final MineUserInfoLoader? userInfoLoader;
  const MineView({super.key, this.userInfoLoader});

  @override
  State<MineView> createState() => _MineViewState();
}

class _MineViewState extends State<MineView> {
  final ApiService _apiService = ApiService();
  late final MineUserInfoLoader _userInfoLoader;

  Map<String, dynamic>? _userInfo;
  bool _loading = true;
  String? _error;
  bool _refreshing = false;
  bool _requiresLogin = false;
  bool _authenticating = false;
  int _loadVersion = 0;
  int _lastUserInfoCacheEpoch = CacheCleanupManager.userInfoCacheEpoch.value;

  @override
  void initState() {
    super.initState();
    _userInfoLoader = widget.userInfoLoader ?? MineUserInfoLoader(_apiService);
    CacheCleanupManager.userInfoCacheEpoch.addListener(_onUserInfoCacheCleared);
    _loadUserInfo();
  }

  @override
  void dispose() {
    CacheCleanupManager.userInfoCacheEpoch.removeListener(
      _onUserInfoCacheCleared,
    );
    super.dispose();
  }

  void _onUserInfoCacheCleared() {
    final epoch = CacheCleanupManager.userInfoCacheEpoch.value;
    if (epoch == _lastUserInfoCacheEpoch) return;
    _lastUserInfoCacheEpoch = epoch;
    if (!mounted) return;
    setState(() {
      _loadVersion++;
      _refreshing = false;
      _userInfo = null;
      _loading = true;
      _error = null;
    });
    _loadUserInfo(forceRefresh: true);
  }

  Future<void> _loadUserInfo({bool forceRefresh = false}) async {
    if (_refreshing) return;
    final version = ++_loadVersion;
    setState(() => _refreshing = true);
    try {
      final result = await _userInfoLoader.load(forceRefresh: forceRefresh);
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _userInfo = result.userInfo;
        _loading = false;
        _error = null;
        _requiresLogin = false;
      });
    } catch (e, stackTrace) {
      AppLogger.I.logOperationFailure(
        'Mine',
        'load user info failed',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _requiresLogin =
            e is MineNotLoggedInException ||
            ScheduleRefreshState.looksLikeCredentialFailure(e) ||
            e.toString().contains('鉴权');
        _error = _requiresLogin
            ? '请重新登录后更新个人信息'
            : _userInfo == null
            ? '个人信息加载失败'
            : '个人信息更新失败，请重试';
        _loading = false;
      });
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _reauthenticate() async {
    if (_authenticating || _refreshing) return;
    setState(() => _authenticating = true);
    try {
      if (!await requestReauthentication(context) || !mounted) return;
      await _loadUserInfo(forceRefresh: true);
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  Widget _buildLoadFeedback({required bool hasSavedInfo}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_error!),
          if (hasSavedInfo) const Text('正在显示已保存的个人信息'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _refreshing || _authenticating
                  ? null
                  : _requiresLogin
                  ? _reauthenticate
                  : () => _loadUserInfo(forceRefresh: true),
              icon: Icon(_requiresLogin ? Icons.login : Icons.refresh),
              label: Text(
                _refreshing
                    ? '更新中…'
                    : _requiresLogin
                    ? '重新登录'
                    : '重试',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final user = MineUserInfoViewModel.fromApi(_userInfo);

    return Scaffold(
      appBar: AppBar(title: Text("我的"), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: () => _loadUserInfo(forceRefresh: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
          children: [
            _buildProfileSection(user),
            if (_error != null && _userInfo != null) ...[
              const SizedBox(height: 12),
              _buildLoadFeedback(hasSavedInfo: true),
            ],
            const MineOptionalFeaturesCard(),
            const SizedBox(height: 24),
            const MineMenuSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection(MineUserInfoViewModel user) {
    if (_loading && _userInfo == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_error != null && _userInfo == null) {
      return _buildLoadFeedback(hasSavedInfo: false);
    }
    return MineUserInfoCard(
      realName: user.realName,
      username: user.username,
      campusName: user.campusName,
    );
  }
}
