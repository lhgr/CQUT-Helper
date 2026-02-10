import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cqut/api/api_service.dart';
import 'package:cqut/manager/theme_manager.dart';
import 'package:cqut/manager/update_manager.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class MineView extends StatefulWidget {
  const MineView({super.key});

  @override
  State<MineView> createState() => _MineViewState();
}

class _MineViewState extends State<MineView> {
  final ApiService _apiService = ApiService();
  String? _currentUserId;

  Map<String, dynamic>? _userInfo;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo({bool forceRefresh = false}) async {
    try {
      // 1. 尝试缓存
      final prefs = await SharedPreferences.getInstance();
      _currentUserId = prefs.getString('account');

      if (_currentUserId == null || _currentUserId!.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = "未登录";
          });
        }
        return;
      }

      final cacheKey = 'user_info_$_currentUserId';

      if (!forceRefresh) {
        final cachedJson = prefs.getString(cacheKey);

        if (cachedJson != null) {
          if (mounted) {
            setState(() {
              _userInfo = json.decode(cachedJson);
              _loading = false;
            });
          }
          return; //有缓存,停止
        }
      }

      // 2. 如果没有缓存或需要强制刷新，则从网络获取
      final info = await _apiService.user.getUserInfo();

      // 保存至缓存
      await prefs.setString(cacheKey, json.encode(info));

      if (mounted) {
        setState(() {
          _userInfo = info;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
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

    // Determine user data (fallback to "Unknown" only if _userInfo is null but we proceeded - shouldn't happen often with above checks)
    final username = _userInfo?['username'] ?? '未知账号';
    final realName = _userInfo?['userRealName'] ?? '未知姓名';
    final customSetting = _userInfo?['userCustomSetting'];
    final campusName = (customSetting is Map)
        ? customSetting['campusName'] ?? '未知校区'
        : '未知校区';

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
            _buildUserInfoCard(realName, username, campusName),
            SizedBox(height: 24),
            _buildMenuSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfoCard(
    String realName,
    String username,
    String campusName,
  ) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer.withAlpha(153),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.onPrimary,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      realName.isNotEmpty ? realName[0] : "?",
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ),
                SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        realName,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "学号: $username",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withAlpha(153),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          campusName,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuSection() {
    return Column(
      children: [
        _buildMenuItem(
          icon: Icons.settings,
          title: "主题设置",
          onTap: () {
            showModalBottomSheet(
              context: context,
              builder: (context) {
                return ListenableBuilder(
                  listenable: ThemeManager(),
                  builder: (context, _) {
                    final currentMode = ThemeManager().themeMode;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            "主题设置",
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        RadioGroup<ThemeMode>(
                          groupValue: currentMode,
                          onChanged: (value) {
                            if (value != null) {
                              ThemeManager().setThemeMode(value);
                              Navigator.pop(context);
                            }
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              RadioListTile<ThemeMode>(
                                title: Text("跟随系统"),
                                value: ThemeMode.system,
                              ),
                              RadioListTile<ThemeMode>(
                                title: Text("亮色模式"),
                                value: ThemeMode.light,
                              ),
                              RadioListTile<ThemeMode>(
                                title: Text("深色模式"),
                                value: ThemeMode.dark,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
        _buildMenuItem(
          icon: Icons.system_update,
          title: "检查更新",
          onTap: () {
            UpdateManager().checkUpdate(context, showNoUpdateToast: true);
          },
        ),
        _buildMenuItem(
          icon: Icons.info_outline,
          title: "关于我们",
          onTap: () async {
            PackageInfo packageInfo = await PackageInfo.fromPlatform();
            String version = packageInfo.version;
            // String buildNumber = packageInfo.buildNumber;

            if (!mounted) return;
            showAboutDialog(
              context: context,
              applicationName: "CQUT 助手",
              applicationVersion: version, // 使用获取到的版本号
              applicationIcon: Icon(
                Icons.school,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              children: [
                Text("CQUTer的小助手"),
                SizedBox(height: 24),
                Text("作者信息", style: Theme.of(context).textTheme.titleSmall),
                SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    await FirebaseAnalytics.instance.logEvent(
                      name: 'about_us_developer_click',
                    );
                    final Uri url = Uri.parse('https://github.com/lhgr');
                    if (!await launchUrl(
                      url,
                      mode: LaunchMode.externalApplication,
                    )) {
                      debugPrint('Could not launch \$url');
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          child: CachedNetworkImage(
                            imageUrl: 'https://github.com/lhgr.png',
                            imageBuilder: (context, imageProvider) => CircleAvatar(
                              radius: 24,
                              backgroundImage: imageProvider,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
                            ),
                            placeholder: (context, url) => CircleAvatar(
                              radius: 24,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
                              child: Icon(Icons.person),
                            ),
                            errorWidget: (context, url, error) => CircleAvatar(
                              radius: 24,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
                              child: Icon(Icons.person),
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Dawn Drizzle",
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              "开发者",
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    await FirebaseAnalytics.instance.logEvent(
                      name: 'about_us_mascot_click',
                    );
                    const String urlString =
                        'https://weibo.com/5401723589?refer_flag=1001030103_';
                    final Uri url = Uri.parse(urlString);
                    if (!await launchUrl(
                      url,
                      mode: LaunchMode.externalApplication,
                    )) {
                      debugPrint('Could not launch \$url');
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHigh,
                            backgroundImage: AssetImage(
                              'lib/assets/Wing.jpg',
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Wing",
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              "吉祥物",
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Text("开源地址", style: Theme.of(context).textTheme.titleSmall),
                SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    await FirebaseAnalytics.instance.logEvent(
                      name: 'click_repo_link',
                    );
                    final Uri url = Uri.parse(
                      'https://github.com/lhgr/CQUT-Helper',
                    );
                    if (!await launchUrl(url)) {
                      debugPrint('Could not launch \$url');
                    }
                  },
                  child: Text(
                    'https://github.com/lhgr/CQUT-Helper',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text("退出登录"),
                  content: Text("确定要退出当前账号吗？"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text("取消"),
                    ),
                    TextButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('account');
                        await prefs.remove('encrypted_password');
                        if (context.mounted) {
                          Navigator.pop(context); // 关闭弹窗
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text("已退出登录")));
                          Navigator.of(context).pushReplacementNamed('/login');
                        }
                      },
                      child: Text("确定"),
                    ),
                  ],
                ),
              );
            },
            icon: Icon(Icons.logout),
            label: Text("退出登录"),
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right,
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
