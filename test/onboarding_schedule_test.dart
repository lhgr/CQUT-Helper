import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_onboarding_hint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cqut_helper/manager/onboarding_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<OnboardingManager> readyManager() async {
    SharedPreferences.setMockInitialValues({'onboarding_is_new_user': true});
    final manager = OnboardingManager();
    await manager.initialize();
    await manager.markScheduleReady();
    return manager;
  }

  Widget buildVisibility({
    required OnboardingManager manager,
    bool readyToShow = true,
    bool hasInlineNotices = false,
    bool hasCourses = true,
    bool Function()? resolveHasCourses,
  }) => MaterialApp(
    home: Scaffold(
      body: ScheduleOnboardingHintVisibility(
        manager: manager,
        readyToShow: readyToShow,
        hasInlineNotices: hasInlineNotices,
        hasCourses: resolveHasCourses ?? () => hasCourses,
      ),
    ),
  );

  Widget buildHint({
    required bool hasCourses,
    required VoidCallback onDismiss,
  }) => MaterialApp(
    home: Scaffold(
      body: ScheduleOnboardingHint(
        hasCourses: hasCourses,
        onDismiss: onDismiss,
      ),
    ),
  );

  testWidgets('有课时展示周次与课程详情提示', (tester) async {
    await tester.pumpWidget(buildHint(hasCourses: true, onDismiss: () {}));

    expect(find.text('点顶部周次切换课表，点课程查看详情。'), findsOneWidget);
    expect(find.text('知道了'), findsOneWidget);
  });

  testWidgets('空周提示用户查看其他周', (tester) async {
    await tester.pumpWidget(buildHint(hasCourses: false, onDismiss: () {}));

    expect(find.text('当前周没有课程，点顶部周次查看其他周。'), findsOneWidget);
    expect(find.text('点顶部周次切换课表，点课程查看详情。'), findsNothing);
  });

  testWidgets('知道了触发持久化关闭回调且卡片不自行超时', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(
      buildHint(hasCourses: true, onDismiss: () => dismissed = true),
    );

    await tester.pump(const Duration(minutes: 1));
    expect(find.byType(ScheduleOnboardingHint), findsOneWidget);
    await tester.tap(find.text('知道了'));
    expect(dismissed, isTrue);
  });

  testWidgets('manager未ready、加载中或错误态均不显示卡片', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_is_new_user': true});
    final manager = OnboardingManager();
    await manager.initialize();
    await tester.pumpWidget(buildVisibility(manager: manager));
    expect(find.byType(ScheduleOnboardingHint), findsNothing);

    await manager.markScheduleReady();
    await tester.pump();
    expect(find.byType(ScheduleOnboardingHint), findsOneWidget);

    await tester.pumpWidget(
      buildVisibility(manager: manager, readyToShow: false),
    );
    expect(find.byType(ScheduleOnboardingHint), findsNothing);
  });

  testWidgets('同时有调课通知时优先显示调课通知', (tester) async {
    final manager = await readyManager();
    await tester.pumpWidget(
      buildVisibility(manager: manager, hasInlineNotices: true),
    );

    expect(find.byType(ScheduleOnboardingHint), findsNothing);
  });

  testWidgets('卡片隐藏时不计算本周课程', (tester) async {
    var resolved = false;
    SharedPreferences.setMockInitialValues({'onboarding_is_new_user': true});
    final manager = OnboardingManager();
    await manager.initialize();
    await tester.pumpWidget(
      buildVisibility(
        manager: manager,
        resolveHasCourses: () {
          resolved = true;
          return true;
        },
      ),
    );
    expect(resolved, isFalse);

    await manager.markScheduleReady();
    await tester.pump();
    expect(resolved, isTrue);
  });

  testWidgets('关闭后manager持久状态隐藏卡片', (tester) async {
    final manager = await readyManager();
    await tester.pumpWidget(buildVisibility(manager: manager));

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleOnboardingHint), findsNothing);
    expect(manager.showScheduleHint, isFalse);
  });

  testWidgets('窄屏大字时提示文案可换行且关闭按钮保留触控尺寸', (tester) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: ScheduleOnboardingHint(hasCourses: false, onDismiss: () {}),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final button = tester.getSize(find.widgetWithText(TextButton, '知道了'));
    expect(button.height, greaterThanOrEqualTo(48));
    expect(button.width, greaterThanOrEqualTo(64));
  });
}
