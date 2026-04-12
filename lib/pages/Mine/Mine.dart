import 'package:cqut_helper/api/api_service.dart';
import 'package:cqut_helper/manager/cache_cleanup_manager.dart';
import 'package:flutter/material.dart';

import 'mine_menu_section.dart';
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is MineNotLoggedInException ? e.toString() : e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // If loading and no data, show loading
    if (_loading && _userInfo == null) {
      return Scaffold(
        appBar: AppBar(title: Text("我的"), centerTitle: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 如果发生错误且没有数据，显示错误页面
    if (_error != null && _userInfo == null) {
      return Scaffold(
        appBar: AppBar(title: Text("我的"), centerTitle: true),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              SizedBox(height: 16),
              Text(
                "加载失败: $_error",
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _loadUserInfo();
                },
                icon: Icon(Icons.refresh),
                label: Text("重试"),
              ),
            ],
          ),
        ),
      );
    }

    final user = MineUserInfoViewModel.fromApi(_userInfo);

    return Scaffold(
      appBar: AppBar(
        title: Text("我的"),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadUserInfo(forceRefresh: true),
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            MineUserInfoCard(
              realName: user.realName,
              username: user.username,
              campusName: user.campusName,
            ),
            SizedBox(height: 24),
            const MineMenuSection(),
          ],
        ),
      ),
    );
  }
}
