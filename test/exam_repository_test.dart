import 'dart:async';
import 'dart:convert';

import 'package:cqut_helper/api/exam/exam_api.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:cqut_helper/manager/exam_repository.dart';
import 'package:cqut_helper/model/exam_model.dart';
import 'package:cqut_helper/utils/widget_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Secrets implements SecureSecretStore {
  @override
  Future<String?> read(String key) async => 'test-encrypted-value';
  @override
  Future<void> delete(String key) async {}
  @override
  Future<void> write({required String key, required String value}) async {}
}

class _Api extends ExamApi {
  final requests = <Completer<ExamSnapshot>>[];
  final users = <String>[];
  @override
  Future<ExamSnapshot> fetch({
    required String baseUrl,
    required String username,
    required String encryptedPassword,
  }) {
    users.add(username);
    final request = Completer<ExamSnapshot>();
    requests.add(request);
    return request.future;
  }
}

/// Independent callers reach a service that shares one in-flight result.
class _SharedResultApi extends ExamApi {
  int calls = 0;
  final running = Completer<ExamSnapshot>();
  @override
  Future<ExamSnapshot> fetch({
    required String baseUrl,
    required String username,
    required String encryptedPassword,
  }) {
    calls++;
    return running.future;
  }
}

ExamSnapshot _snapshot(String name, {bool valid = true}) => ExamSnapshot(
  generatedAt: DateTime.now(),
  fetchedAt: DateTime.now(),
  exams: [
    ExamRecord(
      key: name,
      courseName: name,
      timeText: '2026-11-18(09:00-11:00)',
      campus: '花溪',
      building: '一教',
      room: '101',
      startAt: valid ? DateTime.parse('2026-11-18T09:00:00+08:00') : null,
      endAt: valid ? DateTime.parse('2026-11-18T11:00:00+08:00') : null,
    ),
  ],
);

Future<void> _waitRequests(_Api api, int count) async {
  for (var index = 0; index < 100 && api.requests.length < count; index++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(api.requests.length, count);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'account': 'student'}));

  ExamRepository repository(
    _Api api, {
    Future<void> Function()? updateWidgets,
  }) => ExamRepository(
    api: api,
    credentialStore: CredentialStore(secureStore: _Secrets()),
    updateWidgets: updateWidgets ?? () async {},
  );

  test('first concurrent refreshes share one request while notice enhancement is disabled', () async {
    final api = _Api();
    final repo = repository(api);
    final first = repo.refresh();
    final second = repo.refresh();
    await _waitRequests(api, 1);
    api.requests.single.complete(_snapshot('exam'));
    await Future.wait([first, second]);
    expect(api.requests, hasLength(1));
    expect(repo.exams.single.key, 'exam');
    await repo.refresh();
    expect(api.requests, hasLength(1));
  });

  test('main entry, class cache load, exams entry, resume and manual refresh overlap into one request', () async {
    final api = _Api();
    final repo = repository(api);
    final mainEntry = repo.refresh();
    final classCacheLoad = repo.load();
    Future<void> openExamPage() async {
      await repo.load();
      await repo.refresh();
    }

    final examEntry = openExamPage();
    final resumed = repo.refresh();
    final manual = repo.refresh(force: true);
    await _waitRequests(api, 1);
    await classCacheLoad;
    expect(repo.refreshing, isTrue);
    expect(api.requests, hasLength(1));
    api.requests.single.complete(_snapshot('shared-entry'));
    await Future.wait([mainEntry, examEntry, resumed, manual]);
    expect(api.requests, hasLength(1));
    expect(repo.exams.single.key, 'shared-entry');
  });

  test('independent foreground and background repositories both persist the shared service result', () async {
    final api = _SharedResultApi();
    ExamRepository independent() => ExamRepository(
      api: api,
      credentialStore: CredentialStore(secureStore: _Secrets()),
      updateWidgets: () async {},
    );
    final foreground = independent();
    final background = independent();
    final mainEntry = foreground.refresh();
    for (var index = 0; index < 100 && api.calls == 0; index++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(api.calls, 1);
    final widgetRefresh = background.refresh(force: true);
    for (var index = 0; index < 100 && api.calls < 2; index++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(api.calls, 2);
    expect(foreground.refreshing, isTrue);
    expect(background.refreshing, isTrue);
    api.running.complete(_snapshot('foreground-result'));
    await Future.wait([mainEntry, widgetRefresh]);
    expect(foreground.exams.single.key, 'foreground-result');
    expect(background.exams.single.key, 'foreground-result');
    expect(foreground.error, isNull);
    expect(background.error, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(
        prefs.getString(ExamRepository.cacheKey('student'))!,
      )['exams'][0]['key'],
      'foreground-result',
    );
  });

  test(
    'late old session never removes a newer snapshot for the same account',
    () async {
      final api = _Api();
      final repo = repository(api);
      final old = repo.refresh();
      await _waitRequests(api, 1);
      repo.invalidate();
      await ExamRepository.clearAccountCache('student');
      final latest = repo.refresh();
      await _waitRequests(api, 2);
      api.requests[1].complete(_snapshot('new'));
      await latest;
      api.requests[0].complete(_snapshot('old'));
      await old;
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString(ExamRepository.cacheKey('student'))!,
        )['exams'][0]['key'],
        'new',
      );
      expect(repo.exams.single.key, 'new');
    },
  );

  test('widget delivery failure does not turn successful data into a query failure', () async {
    final api = _Api();
    final repo = repository(
      api,
      updateWidgets: () async => throw StateError('widget unavailable'),
    );
    final request = repo.refresh();
    await _waitRequests(api, 1);
    api.requests.single.complete(_snapshot('saved'));
    await request;
    expect(repo.error, isNull);
    expect(repo.exams.single.key, 'saved');
    expect(repo.refreshing, isFalse);
  });

  test(
    'failure retains cache and successful empty response clears it',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ExamRepository.cacheKey('student'),
        jsonEncode(_snapshot('cached').toJson()),
      );
      final api = _Api();
      final repo = repository(api);
      await repo.load();
      final failed = repo.refresh(force: true);
      await _waitRequests(api, 1);
      api.requests[0].completeError(const ExamAuthenticationException());
      await failed;
      expect(repo.requiresReauthentication, isTrue);
      expect(repo.exams.single.key, 'cached');
      final empty = repo.refresh(force: true);
      await _waitRequests(api, 2);
      api.requests[1].complete(
        ExamSnapshot(
          generatedAt: DateTime.now(),
          fetchedAt: DateTime.now(),
          exams: const [],
        ),
      );
      await empty;
      expect(repo.exams, isEmpty);
      expect(repo.error, isNull);
    },
  );

  test('account switch discards pending results and does not expose another account cache', () async {
    final api = _Api();
    final repo = repository(api);
    final first = repo.refresh();
    await _waitRequests(api, 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account', 'second');
    await repo.load();
    expect(repo.exams, isEmpty);
    api.requests.single.complete(_snapshot('private-first'));
    await first;
    expect(prefs.containsKey(ExamRepository.cacheKey('student')), isFalse);
    expect(repo.exams, isEmpty);
  });

  test(
    'load reloads a snapshot written outside the foreground preferences cache',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ExamRepository.cacheKey('student'),
        jsonEncode(_snapshot('old').toJson()),
      );
      final repo = ExamRepository(
        api: _Api(),
        credentialStore: CredentialStore(secureStore: _Secrets()),
        updateWidgets: () async {},
        prefsProvider: () async => prefs,
      );
      await repo.load();
      // Replacing the mock platform store models a background isolate write.
      SharedPreferences.setMockInitialValues({
        'account': 'student',
        ExamRepository.cacheKey('student'): jsonEncode(
          _snapshot('background').toJson(),
        ),
      });
      expect(
        jsonDecode(
          prefs.getString(ExamRepository.cacheKey('student'))!,
        )['exams'][0]['key'],
        'old',
      );
      await repo.load();
      expect(repo.exams.single.key, 'background');
    },
  );

  test(
    'refresh after external logout clears the in-memory account immediately',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ExamRepository.cacheKey('student'),
        jsonEncode(_snapshot('old').toJson()),
      );
      final repo = repository(_Api());
      await repo.load();
      await prefs.remove('account');
      await repo.refresh();
      expect(repo.exams, isEmpty);
      expect(repo.error, isNull);
    },
  );

  test('session cleared in another repository rejects a late failure without replacing current state', () async {
    final api = _Api();
    final repo = repository(api);
    final pending = repo.refresh();
    await _waitRequests(api, 1);
    await ExamRepository.clearAccountCache('student');
    api.requests.single.completeError(const ExamAuthenticationException());
    await pending;
    expect(repo.error, isNull);
    expect(repo.exams, isEmpty);
  });

  test('account changes during a request discard both its result and old in-memory exams', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      ExamRepository.cacheKey('student'),
      jsonEncode(_snapshot('old-cache').toJson()),
    );
    final api = _Api();
    final repo = repository(api);
    await repo.load();
    final request = repo.refresh(force: true);
    await _waitRequests(api, 1);
    await prefs.setString('account', 'second');
    api.requests.single.complete(_snapshot('old-network'));
    await request;
    expect(repo.exams, isEmpty);
  });

  test('widget exam payload is independent of teaching days and excludes unparsed records', () async {
    final prefs = await SharedPreferences.getInstance();
    final valid = _snapshot('valid');
    await prefs.setString(
      ExamRepository.cacheKey('student'),
      jsonEncode(
        ExamSnapshot(
          generatedAt: valid.generatedAt,
          fetchedAt: valid.fetchedAt,
          exams: [...valid.exams, ..._snapshot('unparsed', valid: false).exams],
        ).toJson(),
      ),
    );
    final json = jsonDecode(await WidgetSnapshot.encode()) as Map;
    expect(json['calendarProjection'], isNull);
    expect(json['exams'], hasLength(1));
    expect(json['exams'][0]['key'], 'valid');
    expect(json['examRefresh']['state'], 'normal');
    await prefs.remove('account');
    final loggedOut = jsonDecode(await WidgetSnapshot.encode()) as Map;
    expect(loggedOut['exams'], isEmpty);
  });

  group('buildChangeMessage', () {
    ExamRecord _exam(String key, {String? timeText, String? room}) =>
        ExamRecord(
          key: key,
          courseName: key,
          timeText: timeText ?? '2026-11-18(09:00-11:00)',
          campus: '花溪',
          building: '一教',
          room: room ?? '101',
          startAt: DateTime.parse('2026-11-18T09:00:00+08:00'),
          endAt: DateTime.parse('2026-11-18T11:00:00+08:00'),
        );

    test('returns null when nothing changed', () {
      final exam = _exam('math');
      expect(ExamRepository.buildChangeMessage([exam], [exam]), isNull);
    });

    test('detects added exams', () {
      final message = ExamRepository.buildChangeMessage(
        const [],
        [_exam('math')],
      );
      expect(message, contains('新增 1 门'));
      expect(message, contains('math'));
    });

    test('detects removed exams', () {
      final message = ExamRepository.buildChangeMessage(
        [_exam('math')],
        const [],
      );
      expect(message, contains('取消 1 门'));
      expect(message, contains('math'));
    });

    test('detects changed exam room', () {
      final message = ExamRepository.buildChangeMessage(
        [_exam('math', room: '101')],
        [_exam('math', room: '202')],
      );
      expect(message, contains('变更 1 门'));
      expect(message, contains('math'));
    });

    test('detects changed exam time', () {
      final message = ExamRepository.buildChangeMessage(
        [_exam('math', timeText: '2026-11-18(09:00-11:00)')],
        [_exam('math', timeText: '2026-11-18(14:00-16:00)')],
      );
      expect(message, contains('变更 1 门'));
    });

    test('combines multiple change kinds and truncates name list', () {
      final previous = [_exam('a'), _exam('b'), _exam('c')];
      final current = [
        _exam('a', room: '202'), // changed
        _exam('b'), // unchanged
        _exam('d'), // added; c is removed
      ];
      final message = ExamRepository.buildChangeMessage(previous, current);
      expect(message, contains('新增'));
      expect(message, contains('取消'));
      expect(message, contains('变更'));
      // 3 affected courses, name list capped at 3 → no "等" suffix
      expect(message, isNot(contains('等')));
    });
  });

  test('change detection fires a notification only when exams differ', () async {
    final notifications = <(String, String)>[];
    final api = _Api();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      ExamRepository.cacheKey('student'),
      jsonEncode(_snapshot('old').toJson()),
    );
    final repo = ExamRepository(
      api: api,
      credentialStore: CredentialStore(secureStore: _Secrets()),
      updateWidgets: () async {},
      notifyExamChange: (title, body) async {
        notifications.add((title, body));
      },
      prefsProvider: () async => prefs,
    );
    await repo.load();

    // No change in exam list -> no notification.
    final same = repo.refresh(force: true);
    await _waitRequests(api, 1);
    api.requests.single.complete(_snapshot('old'));
    await same;
    expect(notifications, isEmpty);

    // New exam key -> notification fires.
    final changed = repo.refresh(force: true);
    await _waitRequests(api, 2);
    api.requests[1].complete(_snapshot('new'));
    await changed;
    expect(notifications, hasLength(1));
    expect(notifications.single.$1, '考试安排更新');
    expect(notifications.single.$2, contains('新增'));
  });

  test('notification failure does not turn successful data into a query failure', () async {
    final api = _Api();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      ExamRepository.cacheKey('student'),
      jsonEncode(_snapshot('old').toJson()),
    );
    final repo = ExamRepository(
      api: api,
      credentialStore: CredentialStore(secureStore: _Secrets()),
      updateWidgets: () async {},
      notifyExamChange: (title, body) async => throw StateError('notify failed'),
      prefsProvider: () async => prefs,
    );
    await repo.load();
    final request = repo.refresh(force: true);
    await _waitRequests(api, 1);
    api.requests.single.complete(_snapshot('new'));
    await request;
    expect(repo.error, isNull);
    expect(repo.exams.single.key, 'new');
  });
}
