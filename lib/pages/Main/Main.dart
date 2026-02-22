import 'package:cqut/manager/update_manager.dart';
import 'package:cqut/manager/announcement_manager.dart';
import 'package:cqut/pages/ClassSchedule/ClassSchedule.dart';
import 'package:cqut/manager/schedule_update_worker.dart';
import 'package:cqut/manager/schedule_update_intents.dart';
import 'package:cqut/pages/Data/Data.dart';
import 'package:cqut/pages/Mine/Mine.dart';
import 'package:cqut/utils/local_notifications.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool _isCheckingLogin = true;
  int _lastOpenFromNotificationToken = 0;

  @override
  void initState() {
    super.initState();
    ScheduleUpdateIntents.openFromSystemNotification.addListener(
      _onOpenFromSystemNotification,
    );
    _checkLoginStatus();
  }

  @override
  void dispose() {
    ScheduleUpdateIntents.openFromSystemNotification.removeListener(
      _onOpenFromSystemNotification,
    );
    super.dispose();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final account = prefs.getString('account');

    if (account == null || account.isEmpty) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } else {
      if (mounted) {
        setState(() {
          _isCheckingLogin = false;
        });
        // 登录成功后，自动检查更新
        // 使用 addPostFrameCallback 确保在当前帧绘制完成后执行，避免构建冲突
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          UpdateManager().checkUpdate(context);
          AnnouncementManager().checkAndShow(context);
          ScheduleUpdateWorker.syncFromPreferences();
          final open = await LocalNotifications.consumeOpenScheduleUpdateFlag();
          if (open) {
            _openScheduleAndChanges();
          }
        });
      }
    }
  }

  void _onOpenFromSystemNotification() {
    final token = ScheduleUpdateIntents.openFromSystemNotification.value;
    if (token == _lastOpenFromNotificationToken) return;
    _lastOpenFromNotificationToken = token;
    _openScheduleAndChanges();
  }

  void _openScheduleAndChanges() {
    if (!mounted) return;
    if (_currentIndex != 1) {
      setState(() {
        _currentIndex = 1;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScheduleUpdateIntents.requestOpenChangesSheet();
    });
  }

  final List<Map<String, dynamic>> _tabList = [
    {"icon": Icons.folder_outlined, "active_icon": Icons.folder, "text": "资料"},
    {
      "icon": Icons.calendar_today_outlined,
      "active_icon": Icons.calendar_today,
      "text": "课表",
    },
    {"icon": Icons.person_outline, "active_icon": Icons.person, "text": "我的"},
  ];

  int _currentIndex = 1;

  List<NavigationDestination> _getDestinations() {
    return _tabList.map((item) {
      return NavigationDestination(
        icon: Icon(item["icon"]),
        selectedIcon: Icon(item["active_icon"]),
        label: item["text"],
      );
    }).toList();
  }

  List<Widget> _getStackChildren() {
    return const [DataView(), ClassscheduleView(), MineView()];
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingLogin) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: _getStackChildren(),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (int index) async {
          await FirebaseAnalytics.instance.logEvent(
            name: 'tab_switch',
            parameters: {'tab_name': _tabList[index]['text']},
          );
          setState(() {
            _currentIndex = index;
          });
        },
        selectedIndex: _currentIndex,
        destinations: _getDestinations(),
      ),
    );
  }
}
