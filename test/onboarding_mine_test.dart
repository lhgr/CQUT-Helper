import 'package:cqut_helper/api/core/api_client.dart';
import 'package:cqut_helper/manager/onboarding_manager.dart';
import 'package:cqut_helper/pages/Guide/usage_guide_page.dart';
import 'package:cqut_helper/pages/Mine/Mine.dart';
import 'package:cqut_helper/pages/Mine/mine_optional_features_card.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cqut_helper/utils/course_reminder_mode.dart';

const _courseReminderChannel = MethodChannel('cqut/course_reminders');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OnboardingManager manager;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CourseReminderMode.debugIsAndroidOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_courseReminderChannel, (call) async {
          if (call.method == 'getStatus') {
            return <String, Object?>{
              'supported': true,
              'notificationGranted': true,
              'exactAlarmGranted': true,
              'dndGranted': true,
              'batteryOptimizationIgnored': false,
              'autoModeActive': false,
              'autoModeStatus': null,
            };
          }
          return false;
        });
    manager = OnboardingManager();
  });

  tearDown(() {
    CourseReminderMode.debugIsAndroidOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_courseReminderChannel, null);
  });

  testWidgets('推荐入口导航不会关闭卡片，只有关闭操作会持久隐藏', (tester) async {
    await manager.initialize();
    await manager.markScheduleReady();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [MineOptionalFeaturesCard(manager: manager)],
          ),
        ),
      ),
    );

    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();
    expect(find.text('通知与提醒'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看添加方法'));
    await tester.pumpAndSettle();
    expect(find.text('使用指南'), findsOneWidget);
    expect(find.textContaining('长按手机桌面空白处'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('按需设置'), findsOneWidget);

    final closeButton = find.byTooltip('关闭推荐');
    await tester.ensureVisible(closeButton);
    await tester.tap(closeButton);
    await tester.pumpAndSettle();
    expect(manager.showOptionalFeatures, isFalse);
    expect(find.text('按需设置'), findsNothing);
    final restored = OnboardingManager();
    await restored.initialize();
    expect(restored.showOptionalFeatures, isFalse);
  });

  testWidgets('指南小组件入口打开时定位到小组件章节', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UsageGuidePage(initialChapter: UsageGuideChapter.widgets),
      ),
    );
    await tester.pumpAndSettle();

    final widgetsHeading = find.text('桌面小组件');
    final guideViewport = tester.getRect(find.byType(SingleChildScrollView));
    final widgetsDescription = find.textContaining('长按手机桌面空白处');
    expect(widgetsHeading, findsOneWidget);
    expect(guideViewport.contains(tester.getTopLeft(widgetsHeading)), isTrue);
    expect(
      guideViewport.contains(tester.getBottomRight(widgetsDescription)),
      isTrue,
    );
    expect(find.text('不同桌面的入口名称可能不同。'), findsOneWidget);
  });

  testWidgets('指南与推荐卡片在窄屏大字下可滚动且无布局异常', (tester) async {
    await manager.initialize();
    await manager.markScheduleReady();
    tester.view.physicalSize = const Size(640, 1400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            children: [MineOptionalFeaturesCard(manager: manager)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('上课前收到提醒。'), findsOneWidget);
    expect(find.text('查看添加方法'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const UsageGuidePage(initialChapter: UsageGuideChapter.widgets),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('不同桌面的入口名称可能不同。'), findsOneWidget);
  });

  testWidgets('个人资料请求失败时设置菜单仍可用且不显示常驻指南入口', (tester) async {
    SharedPreferences.setMockInitialValues({'account': 'test-user'});
    final previousAdapter = ApiClient().dio.httpClientAdapter;
    ApiClient().dio.httpClientAdapter = _FailingAdapter();
    addTearDown(() => ApiClient().dio.httpClientAdapter = previousAdapter);

    await tester.pumpWidget(const MaterialApp(home: MineView()));
    await tester.pumpAndSettle();

    expect(find.text('个人信息加载失败'), findsOneWidget);
    expect(find.text('使用指南'), findsNothing);
    expect(find.text('设置'), findsOneWidget);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('外观与启动'), findsOneWidget);
  });
}

class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'test offline',
    );
  }

  @override
  void close({bool force = false}) {}
}
