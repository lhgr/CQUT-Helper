import 'package:cqut_helper/api/api_service.dart';
import 'package:cqut_helper/manager/cache_cleanup_manager.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:material_ui/material_ui.dart';

import 'mine_menu_section.dart';
import 'mine_optional_features_card.dart';
import 'mine_user_info_card.dart';
import 'mine_user_info_loader.dart';
import 'mine_user_info_view_model.dart';

class MineView extends StatefulWidget {
  const MineView({super.key});

  @override
  State<MineView> createState() => _MineViewState();
}

class _MineViewState extends State<MineView> {
  final ApiService _apiService = ApiService();
  late final MineUserInfoLoader _userInfoLoader;

  Map<String, dynamic>? _userInfo;
  bool _loading = true;
  String? _error;
  int _lastUserInfoCacheEpoch = CacheCleanupManager.userInfoCacheEpoch.value;

  @override
  void initState() {
    super.initState();
    _userInfoLoader = MineUserInfoLoader(_apiService);
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
      _userInfo = null;
      _loading = true;
      _error = null;
    });
    _loadUserInfo(forceRefresh: true);
  }

  Future<void> _loadUserInfo({bool forceRefresh = false}) async {
    try {
      final result = await _userInfoLoader.load(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _userInfo = result.userInfo;
        _loading = false;
        _error = null;
      });
    } catch (e, stackTrace) {
      AppLogger.I.logOperationFailure(
        'Mine',
        'load user info failed',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _error = e is MineNotLoggedInException ? '请先登录后查看个人信息' : '个人信息加载失败';
        _loading = false;
      });
    }
  }

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
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_error!)),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _loadUserInfo();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return MineUserInfoCard(
      realName: user.realName,
      username: user.username,
      campusName: user.campusName,
    );
  }
}
