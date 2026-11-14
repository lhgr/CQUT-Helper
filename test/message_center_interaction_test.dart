import 'package:cqut_helper/manager/schedule_message_center_manager.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_intents.dart';
import 'package:cqut_helper/model/schedule_week_change.dart';
import 'package:cqut_helper/pages/MessageCenter/message_center_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'account': 'u1',
      ScheduleSettingsManager.backgroundPollingEnabledKey: true,
      ScheduleSettingsManager.noticePrivacyConsentVersionKey:
          ScheduleSettingsManager.currentNoticePrivacyConsentVersion,
    });
    ScheduleUpdateIntents.openWeek.value = null;
  });
  tearDown(() => ScheduleUpdateIntents.openWeek.value = null);

  Future<void> add(String week, {String term = 'old-term'}) =>
      ScheduleMessageCenterManager.appendChanges(
        userId: 'u1',
        yearTerm: term,
        changes: [
          ScheduleWeekChange(weekNum: week, lines: ['change-$week']),
        ],
      );

  testWidgets(
    'opening and refreshing preserve unread until a record is expanded',
    (tester) async {
      await add('1');
      await add('2');
      await tester.pumpWidget(const MaterialApp(home: MessageCenterPage()));
      await tester.pumpAndSettle();
      expect(
        (await ScheduleMessageCenterManager.load('u1'))
            .every((record) => !record.read),
        isTrue,
      );
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(
        (await ScheduleMessageCenterManager.load('u1'))
            .every((record) => !record.read),
        isTrue,
      );
      await tester.tap(find.text('第1周课表有变更'));
      await tester.pumpAndSettle();
      final records = await ScheduleMessageCenterManager.load('u1');
      expect(
        records
            .singleWhere((record) => record.changes.single.weekNum == '1')
            .read,
        isTrue,
      );
      expect(
        records
            .singleWhere((record) => record.changes.single.weekNum == '2')
            .read,
        isFalse,
      );
      expect(find.text('· change-1'), findsOneWidget);
      await add('3');
      await tester.pumpAndSettle();
      expect(find.text('· change-1'), findsOneWidget);
      await tester.tap(find.byTooltip('全部已读'));
      await tester.pumpAndSettle();
      expect(
        (await ScheduleMessageCenterManager.load('u1'))
            .every((record) => record.read),
        isTrue,
      );
      expect(find.byTooltip('全部已读'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'each changed week closes messages and publishes exact destination',
    (tester) async {
      await ScheduleMessageCenterManager.appendChanges(
        userId: 'u1',
        yearTerm: 'old-term',
        changes: const [
          ScheduleWeekChange(weekNum: '2', lines: ['two']),
          ScheduleWeekChange(weekNum: '3', lines: ['three']),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MessageCenterPage(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2周课表有变更'));
      await tester.pumpAndSettle();
      final button = find.text('查看该周课表').last;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(MessageCenterPage), findsNothing);
      final request = ScheduleUpdateIntents.openWeek.value!;
      expect(request.userId, 'u1');
      expect(request.yearTerm, 'old-term');
      expect(request.weekNum, '3');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('record without term cannot silently open a current-term week', (
    tester,
  ) async {
    await add('2', term: '');
    await tester.pumpWidget(const MaterialApp(home: MessageCenterPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第2周课表有变更'));
    await tester.pumpAndSettle();
    expect(find.text('查看该周课表'), findsNothing);
    expect(find.text('该记录缺少学期或周次，无法定位课表'), findsOneWidget);
    expect(ScheduleUpdateIntents.openWeek.value, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
