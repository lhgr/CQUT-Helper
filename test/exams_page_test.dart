import 'dart:async';
import 'dart:convert';

import 'package:cqut_helper/manager/exam_repository.dart';
import 'package:cqut_helper/model/exam_model.dart';
import 'package:cqut_helper/pages/Mine/mine_menu_section.dart';
import 'package:cqut_helper/pages/Exams/exams_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repository extends ExamRepository {
  int refreshCalls = 0;
  ExamSnapshot? data;
  Completer<ExamSnapshot?>? pending;
  @override
  ExamSnapshot? get snapshot => data;
  @override
  List<ExamRecord> get exams => data?.exams ?? const [];
  @override
  Future<ExamSnapshot?> load() async => null;
  @override
  Future<ExamSnapshot?> refresh({bool force = false}) async {
    refreshCalls++;
    return pending == null ? data : await pending!.future;
  }
}

void main() {
  testWidgets('first query stays loading until the refresh completes', (
    tester,
  ) async {
    final repo = _Repository()..pending = Completer<ExamSnapshot?>();
    await tester.pumpWidget(MaterialApp(home: ExamsPage(repository: repo)));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('暂无考试安排'), findsNothing);
    repo.pending!.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('暂无考试安排'), findsOneWidget);
  });

  testWidgets(
    'long exams and details scroll on a short screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final course = '高级计算机网络与分布式系统课程' * 4;
      final rawTime = '具体考试时间由学院另行通知，请关注最新安排' * 4;
      final location = '花溪校区第一教学楼长名称考场' * 5;
      final repo = _Repository()
        ..data = ExamSnapshot(
          generatedAt: DateTime(2026),
          fetchedAt: DateTime(2026),
          exams: [
            ExamRecord(
              key: 'long',
              courseName: course,
              timeText: rawTime,
              campus: location,
              building: '',
              room: '',
            ),
          ],
        );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: ExamsPage(repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(course));
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭'), findsOneWidget);
      final sheetSurface = find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Material),
          )
          .first;
      expect(tester.getSize(sheetSurface).height, lessThanOrEqualTo(480 * 0.8));
      expect(tester.takeException(), isNull);
      final scroll = find.byType(SingleChildScrollView);
      await tester.drag(scroll, const Offset(0, -1800));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(location).last);
      expect(find.text(location).last.hitTestable(), findsOneWidget);
      expect(find.text(rawTime), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.drag(scroll, const Offset(0, 2500));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(SingleChildScrollView), findsNothing);
    },
  );

  testWidgets('returning to a visible exam page checks the shared repository', (
    tester,
  ) async {
    final repo = _Repository();
    await tester.pumpWidget(MaterialApp(home: ExamsPage(repository: repo)));
    await tester.pumpAndSettle();
    final initial = repo.refreshCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repo.refreshCalls, initial + 1);
  });
  testWidgets(
    'mine entry opens cached exams and unparsed exams retain their details',
    (tester) async {
      final snapshot = ExamSnapshot(
        generatedAt: DateTime.now(),
        fetchedAt: DateTime.now(),
        exams: const [
          ExamRecord(
            key: 'pending',
            courseName: '计算机网络',
            timeText: '时间待公布',
            campus: '花溪',
            building: '一教',
            room: '101',
          ),
        ],
      );
      SharedPreferences.setMockInitialValues({
        'account': 'student',
        ExamRepository.cacheKey('student'): jsonEncode(snapshot.toJson()),
      });
      ExamRepository.instance.invalidate();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MineMenuSection())),
      );
      await tester.tap(find.text('考试安排'));
      await tester.pumpAndSettle();
      expect(find.text('计算机网络'), findsOneWidget);
      expect(find.textContaining('时间待公布'), findsOneWidget);
      await tester.tap(find.text('计算机网络'));
      await tester.pumpAndSettle();
      expect(find.text('计算机网络'), findsNWidgets(2));
      expect(find.text('花溪 · 一教 · 101'), findsNWidgets(2));
    },
  );
}
