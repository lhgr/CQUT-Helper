import 'package:cqut_helper/manager/announcement_manager.dart';
import 'package:cqut_helper/manager/schedule_update_intents.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/manager/update_manager.dart';
import 'package:cqut_helper/pages/ClassSchedule/ClassSchedule.dart';
import 'package:cqut_helper/pages/Mine/Mine.dart';
import 'package:cqut_helper/pages/TodaySchedule/TodaySchedule.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  bool _isCheckingLogin = true;
  int _lastOpenFromNotificationToken = 0;
  int _currentIndex = 1;

  final List<Map<String, dynamic>> _tabList = const [
    {
      'icon': Icons.today_outlined,
      'active_icon': Icons.today,
      'text': '今日',
    },
    {
      'icon': Icons.calendar_today_outlined,
      'active_icon': Icons.calendar_today,
      'text': '课表',
    },
    {
      'icon': Icons.person_outline,
      'active_icon': Icons.person,
      'text': '我的',
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ScheduleUpdateIntents.openFromSystemNotification.addListener(
      _onOpenFromSystemNotification,
    );
    _checkLoginStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ScheduleUpdateIntents.openFromSystemNotification.removeListener(
      _onOpenFromSystemNotification,
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markActive();
      ScheduleUpdateWorker.syncFromPreferences();
    }
  }

  Future<void> _markActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'app_last_active_at',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final account = prefs.getString('account');

    if (account == null || account.isEmpty) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isCheckingLogin = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      UpdateManager().checkUpdate(context);
      AnnouncementManager().checkAndShow(context);
      ScheduleUpdateWorker.syncFromPreferences();
      _markActive();
      final open = await LocalNotifications.consumeOpenScheduleUpdateFlag();
      if (open) {
        _openScheduleAndChanges();
      }
    });
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

  List<NavigationDestination> _getDestinations() {
    return _tabList.map((item) {
      return NavigationDestination(
        icon: Icon(item['icon'] as IconData),
        selectedIcon: Icon(item['active_icon'] as IconData),
        label: item['text'] as String,
      );
    }).toList(growable: false);
  }

  List<Widget> _getStackChildren() {
    return const [TodayScheduleView(), ClassscheduleView(), MineView()];
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingLogin) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: _getStackChildren(),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (index) {
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
