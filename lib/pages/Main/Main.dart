import 'package:cqut_helper/manager/announcement_manager.dart';
import 'package:cqut_helper/manager/schedule_update_intents.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/update_manager.dart';
import 'package:cqut_helper/pages/ClassSchedule/ClassSchedule.dart';
import 'package:cqut_helper/pages/Mine/Mine.dart';
import 'package:cqut_helper/pages/TodaySchedule/TodaySchedule.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:cqut_helper/utils/widget_navigation.dart';
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
  int _lastWidgetNavigationToken = 0;

  final List<Map<String, dynamic>> _tabList = const [
    {'icon': Icons.today_outlined, 'active_icon': Icons.today, 'text': '今日'},
    {
      'icon': Icons.calendar_today_outlined,
      'active_icon': Icons.calendar_today,
      'text': '课表',
    },
    {'icon': Icons.person_outline, 'active_icon': Icons.person, 'text': '我的'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ScheduleUpdateIntents.openFromSystemNotification.addListener(
      _onOpenFromSystemNotification,
    );
    WidgetNavigation.request.addListener(_onWidgetNavigation);
    _checkLoginStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onWidgetNavigation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ScheduleUpdateIntents.openFromSystemNotification.removeListener(
      _onOpenFromSystemNotification,
    );
    WidgetNavigation.request.removeListener(_onWidgetNavigation);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markActive();
      ScheduleUpdateWorker.syncFromPreferences();
      LocalNotifications.consumeOpenCourseReminderFlag().then((open) {
        if (open && mounted && _currentIndex != 0) {
          setState(() => _currentIndex = 0);
        }
      });
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
      _currentIndex =
          (prefs.getInt(ScheduleSettingsManager.defaultHomeTabKey) ?? 1).clamp(
            0,
            2,
          );
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
      final openCourse =
          await LocalNotifications.consumeOpenCourseReminderFlag();
      if (openCourse && mounted && _currentIndex != 0) {
        setState(() => _currentIndex = 0);
      }
    });
  }

  void _onOpenFromSystemNotification() {
    final token = ScheduleUpdateIntents.openFromSystemNotification.value;
    if (token == _lastOpenFromNotificationToken) return;
    _lastOpenFromNotificationToken = token;
    _openScheduleAndChanges();
  }

  void _onWidgetNavigation() {
    final navigation = WidgetNavigation.request.value;
    if (navigation == null ||
        navigation.token == _lastWidgetNavigationToken ||
        !mounted) {
      return;
    }
    _lastWidgetNavigationToken = navigation.token;
    if (_currentIndex != 0) {
      setState(() {
        _currentIndex = 0;
      });
    }
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
    return _tabList
        .map((item) {
          return NavigationDestination(
            icon: Icon(item['icon'] as IconData),
            selectedIcon: Icon(item['active_icon'] as IconData),
            label: item['text'] as String,
          );
        })
        .toList(growable: false);
  }

  List<Widget> _getStackChildren() {
    return const [TodayScheduleView(), ClassscheduleView(), MineView()];
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingLogin) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: _getStackChildren(),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorScheme.outlineVariant.withAlpha(120),
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withAlpha(
                    Theme.of(context).brightness == Brightness.dark ? 50 : 20,
                  ),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: NavigationBar(
                onDestinationSelected: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                selectedIndex: _currentIndex,
                destinations: _getDestinations(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
