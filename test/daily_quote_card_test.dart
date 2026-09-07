import 'package:cqut_helper/manager/daily_quote_manager.dart';
import 'package:cqut_helper/model/daily_quote_model.dart';
import 'package:cqut_helper/pages/TodaySchedule/widgets/daily_quote_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders a quote and lets the user switch to the next one', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final manager = DailyQuoteManager(
      fetchConfig: () async => const DailyQuoteConfig(
        enabled: true,
        revision: 1,
        rotationMode: 'daily',
        items: [
          DailyQuoteItem(
            id: 'first',
            text: '第一句',
            source: '来源一',
            priority: 100,
          ),
          DailyQuoteItem(id: 'second', text: '第二句'),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: [DailyQuoteCard(manager: manager)]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('第一句'), findsOneWidget);
    expect(find.text('—— 来源一'), findsOneWidget);
    expect(find.text('换一句'), findsOneWidget);

    await tester.tap(find.text('换一句'));
    await tester.pumpAndSettle();

    expect(find.text('第二句'), findsOneWidget);
    expect(find.text('第一句'), findsNothing);
  });

  testWidgets('stays hidden when the feature is globally disabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final manager = DailyQuoteManager(
      fetchConfig: () async => const DailyQuoteConfig(
        enabled: false,
        revision: 1,
        rotationMode: 'daily',
        items: [DailyQuoteItem(id: 'hidden', text: '不应显示')],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DailyQuoteCard(manager: manager)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('一言'), findsNothing);
    expect(find.text('不应显示'), findsNothing);
  });

  testWidgets('defers loading until the Today tab becomes active', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var fetchCount = 0;
    final manager = DailyQuoteManager(
      fetchConfig: () async {
        fetchCount++;
        return const DailyQuoteConfig(
          enabled: true,
          revision: 1,
          rotationMode: 'daily',
          items: [DailyQuoteItem(id: 'one', text: '激活后显示')],
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DailyQuoteCard(active: false, manager: manager)),
      ),
    );
    await tester.pumpAndSettle();
    expect(fetchCount, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DailyQuoteCard(manager: manager)),
      ),
    );
    await tester.pumpAndSettle();

    expect(fetchCount, 1);
    expect(find.text('激活后显示'), findsOneWidget);
  });
}
