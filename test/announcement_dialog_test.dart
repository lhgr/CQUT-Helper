import 'dart:async';

import 'package:cqut_helper/manager/announcement_manager.dart';
import 'package:cqut_helper/model/announcement_model.dart';
import 'package:cqut_helper/widgets/announcement_dialog.dart';
import 'package:cqut_helper/widgets/release_notes_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

AnnouncementModel announcement(String id, {bool force = false}) {
  return AnnouncementModel(
    id: id,
    title: '公告 $id',
    contentMarkdown: '> [!NOTE]\n> 正文',
    createdAt: '2026-11-05T00:00:00Z',
    updatedAt: '2026-11-05T00:00:00Z',
    force: force,
    linkUrl: 'https://example.com',
  );
}

Future<BuildContext> pumpHost(WidgetTester tester) async {
  late BuildContext host;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          host = context;
          return const Scaffold(body: Text('主页'));
        },
      ),
    ),
  );
  return host;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'latest requests share one request and include the legacy read ID',
    () async {
      SharedPreferences.setMockInitialValues({
        'announcement_latest_popup_id_v1': 'old',
      });
      final response = Completer<AnnouncementModel?>();
      var calls = 0;
      final manager = AnnouncementManager.forTesting(
        loadLatest: () {
          calls++;
          return response.future;
        },
      );
      final first = manager.fetchPendingAnnouncement();
      final second = manager.fetchPendingAnnouncement();
      expect(identical(first, second), isTrue);
      expect(calls, 1);
      response.complete(announcement('old'));
      expect(await first, isNull);
      expect(await second, isNull);
    },
  );

  testWidgets('dismissed ordinary announcements remain read after another ID', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    final manager = AnnouncementManager.forTesting(
      loadLatest: () async => null,
    );
    final first = manager.showPendingAnnouncement(context, announcement('a'));
    await tester.pumpAndSettle();
    expect(find.byType(ReleaseNotesMarkdown), findsOneWidget);
    expect(find.text('打开链接'), findsOneWidget);
    expect(
      tester
          .widget<AlertDialog>(find.byType(AlertDialog))
          .constraints
          ?.maxWidth,
      560,
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await first, isTrue);

    final second = manager.showPendingAnnouncement(context, announcement('b'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(await second, isTrue);
    expect(
      await manager.showPendingAnnouncement(context, announcement('a')),
      isTrue,
    );
    expect(find.byType(AnnouncementDialog), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('announcement_read_ids_v1'),
      containsAll(['a', 'b']),
    );
  });

  testWidgets(
    'force requires its confirmation button and blocks concurrent presentation',
    (tester) async {
      final context = await pumpHost(tester);
      final manager = AnnouncementManager.forTesting(
        loadLatest: () async => null,
      );
      final showing = manager.showPendingAnnouncement(
        context,
        announcement('force', force: true),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('我已知晓'), findsOneWidget);
      expect(
        await manager.showPendingAnnouncement(context, announcement('other')),
        isFalse,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('announcement_read_ids_v1'), isNull);
      await tester.tap(find.text('我已知晓'));
      await tester.pumpAndSettle();
      expect(await showing, isTrue);
      expect(prefs.getStringList('announcement_read_ids_v1'), ['force']);
    },
  );

  testWidgets('repeated close callbacks only pop the announcement', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const Scaffold(body: Text('保留的页面')),
      ),
    );
    await tester.pumpAndSettle();
    final pageContext = tester.element(find.text('保留的页面'));
    final showing = showAnnouncementDialog(
      context: pageContext,
      item: announcement('a'),
    );
    await tester.pumpAndSettle();
    final close = tester
        .widget<FilledButton>(find.byType(FilledButton))
        .onPressed!;
    close();
    close();
    await tester.pumpAndSettle();
    expect(await showing, isTrue);
    expect(find.text('保留的页面'), findsOneWidget);
  });

  testWidgets(
    'long announcement keeps its close action visible on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold();
            },
          ),
        ),
      );
      final showing = showAnnouncementDialog(
        context: host,
        item: AnnouncementModel(
          id: 'long',
          title: '这是一条需要在窄屏和大字体下完整呈现的长标题公告',
          contentMarkdown: List.filled(
            40,
            '公告正文需要支持滚动阅读，同时关闭按钮应当始终可见。',
          ).join('\n\n'),
          createdAt: '2026-11-05T00:00:00Z',
          updatedAt: '2026-11-05T00:00:00Z',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('关闭').hitTestable(), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(await showing, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'presentation gate is rechecked and manual detail stays freely dismissible',
    (tester) async {
      final context = await pumpHost(tester);
      final manager = AnnouncementManager.forTesting(
        loadLatest: () async => null,
      );
      expect(
        await manager.showPendingAnnouncement(
          context,
          announcement('a'),
          canShow: () => false,
        ),
        isFalse,
      );
      expect(find.byType(AnnouncementDialog), findsNothing);
      final detail = showAnnouncementDialog(
        context: context,
        item: announcement('force', force: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('关闭'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await detail;
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('announcement_read_ids_v1'), isNull);
    },
  );
}
