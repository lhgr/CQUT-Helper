import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/pages/Settings/query_service_settings_page.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_settings_sheet.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('cancel or back dismisses custom confirmation without saving', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'schedule_notice_api_base_url': 'https://saved.example',
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const QueryServiceSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://draft.example');
    for (final cancelWithButton in [true, false]) {
      await tester.ensureVisible(find.text('保存地址'));
      await tester.tap(find.text('保存地址'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (cancelWithButton) {
        await tester.ensureVisible(find.text('取消'));
        await tester.tap(find.text('取消'));
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        await ScheduleSettingsManager.loadNoticeApiBaseUrl(),
        'https://saved.example',
      );
      expect(find.text('教务查询服务地址已保存'), findsNothing);
    }
    await tester.ensureVisible(find.text('保存地址'));
    await tester.tap(find.text('保存地址'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认并保存'));
    await tester.tap(find.text('确认并保存'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      await ScheduleSettingsManager.loadNoticeApiBaseUrl(),
      'https://draft.example',
    );
  });

  testWidgets(
    'schedule sheet uses the shared service page while notice enhancement is disabled',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScheduleSettingsSheet(
              userId: '',
              yearTerm: '',
              initialShowWeekend: false,
              initialTimeInfoEnabled: true,
              initialBackgroundPollingEnabled: false,
              initialNoticeApiBaseUrl:
                  ScheduleSettingsManager.officialNoticeApiBaseUrl,
              onSave: ({
                required showWeekend,
                required timeInfoEnabled,
                required backgroundPollingEnabled,
                required noticeApiBaseUrl,
              }) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('教务查询服务'));
      await tester.tap(find.text('教务查询服务'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义服务'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'https://shared.example');
      await tester.tap(find.text('保存地址'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认并保存'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('https://shared.example'), findsOneWidget);
      expect(
        await ScheduleSettingsManager.isNoticeEnhancementEnabled(),
        isFalse,
      );
    },
  );
  testWidgets(
    'shared query address saves while notice enhancement remains disabled',
    (tester) async {
      SharedPreferences.setMockInitialValues({'account': 'student'});
      await tester.pumpWidget(
        const MaterialApp(home: QueryServiceSettingsPage()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义服务'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'https://query.example');
      await tester.tap(find.text('保存地址'));
      await tester.pumpAndSettle();
      expect(find.text('使用自定义服务'), findsOneWidget);
      expect(
        find.text(
          '考试与调课查询将通过此服务进行，你的学号和登录验证信息会发送给该服务。使用不可信的服务可能导致账号信息泄露，请确认地址及服务提供方可信。',
        ),
        findsOneWidget,
      );
      expect(
        await ScheduleSettingsManager.loadNoticeApiBaseUrl(),
        ScheduleSettingsManager.officialNoticeApiBaseUrl,
      );
      await tester.tap(find.text('确认并保存'));
      await tester.pumpAndSettle();
      expect(
        await ScheduleSettingsManager.loadNoticeApiBaseUrl(),
        'https://query.example',
      );
      expect(
        await ScheduleSettingsManager.isNoticeEnhancementEnabled(),
        isFalse,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('教务查询服务地址已保存'), findsOneWidget);
    },
  );
  testWidgets('mode changes are drafts and preserve custom input', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: QueryServiceSettingsPage()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('自定义服务'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://draft.example/');
    await tester.tap(find.text('官方服务'));
    await tester.pumpAndSettle();
    expect(
      await ScheduleSettingsManager.loadNoticeApiBaseUrl(),
      ScheduleSettingsManager.officialNoticeApiBaseUrl,
    );
    await tester.tap(find.text('自定义服务'));
    await tester.pumpAndSettle();
    expect(find.text('https://draft.example/'), findsOneWidget);
    await tester.tap(find.text('保存地址'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认并保存'));
    await tester.pumpAndSettle();
    expect(find.text('https://draft.example'), findsOneWidget);
    await tester.tap(find.text('官方服务'));
    await tester.pumpAndSettle();
    expect(
      await ScheduleSettingsManager.loadNoticeApiBaseUrl(),
      'https://draft.example',
    );
    await tester.tap(find.text('保存地址'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      await ScheduleSettingsManager.loadNoticeApiBaseUrl(),
      ScheduleSettingsManager.officialNoticeApiBaseUrl,
    );
  });

  testWidgets('empty or invalid custom address cannot replace saved address', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'schedule_notice_api_base_url': 'https://saved.example/',
    });
    await tester.pumpWidget(
      const MaterialApp(home: QueryServiceSettingsPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('https://saved.example'), findsOneWidget);
    for (final value in [
      '',
      'http://insecure.example',
      'https://path.example/api',
    ]) {
      await tester.enterText(find.byType(TextField), value);
      await tester.tap(find.text('保存地址'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.errorText,
        isNotNull,
      );
      expect(
        await ScheduleSettingsManager.loadNoticeApiBaseUrl(),
        'https://saved.example',
      );
    }
  });

  testWidgets('custom official address normalizes back to official mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: QueryServiceSettingsPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义服务'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      '${ScheduleSettingsManager.officialNoticeApiBaseUrl}/',
    );
    await tester.tap(find.text('保存地址'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认并保存'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(
      await ScheduleSettingsManager.loadNoticeApiBaseUrl(),
      ScheduleSettingsManager.officialNoticeApiBaseUrl,
    );
  });
}
