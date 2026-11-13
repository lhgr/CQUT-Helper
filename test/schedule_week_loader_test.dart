import 'dart:async';

import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_week_loader.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeWeekLoaderScheduleApi extends ScheduleApi {
  ScheduleData? cacheResult;
  final Map<String, ScheduleData> cacheResults = <String, ScheduleData>{};
  ScheduleData? networkResult;
  Object? networkError;
  Completer<ScheduleData>? networkCompleter;
  final Map<String, Completer<ScheduleData>> pending = {};
  int cacheCalls = 0;
  int networkCalls = 0;
  String? lastEncryptedPassword;

  @override
  Future<ScheduleData?> loadFromCache({
    required String userId,
    String? weekNum,
    String? yearTerm,
    bool waitForSideEffects = true,
  }) async {
    cacheCalls++;
    return cacheResults[weekNum] ?? cacheResult;
  }

  @override
  Future<ScheduleData> loadFromNetwork({
    required String userId,
    required String encryptedPassword,
    String? weekNum,
    String? yearTerm,
    bool persistLastViewed = true,
    bool updateWidgetPins = false,
    bool notifyWidget = true,
    bool refreshReminders = true,
    bool waitForSideEffects = true,
    String? refreshId,
  }) async {
    networkCalls++;
    if (networkError != null) throw networkError!;
    lastEncryptedPassword = encryptedPassword;
    final request = pending['$userId|$yearTerm|$weekNum'] ?? networkCompleter;
    if (request != null) return request.future;
    return networkResult!;
  }
}

class _FakeWeekLoaderCredentialStore extends CredentialStore {
  _FakeWeekLoaderCredentialStore({this.value, this.readError})
    : super(secureStore: _NoopSecureSecretStore());

  final String? value;
  final Object? readError;
  int readCalls = 0;

  @override
  Future<String?> readEncryptedPassword() async {
    readCalls++;
    if (readError != null) throw readError!;
    return value;
  }
}

class _NoopSecureSecretStore implements SecureSecretStore {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write({required String key, required String value}) async {}
}

void main() {
  group('ScheduleWeekLoader', () {
    late Map<int, ScheduleData> weekCache;
    String? currentTerm;
    List<String>? weekList;
    String? actualCurrentWeek;
    String? actualCurrentTerm;

    ScheduleWeekLoader buildLoader(
      _FakeWeekLoaderScheduleApi api, {
      CredentialStore? credentialStore,
    }) {
      return ScheduleWeekLoader(
        service: api,
        credentialStore: credentialStore,
        getWeekCache: () => weekCache,
        setWeekCache: (value) => weekCache = value,
        getCurrentTerm: () => currentTerm,
        setCurrentTerm: (value) => currentTerm = value,
        setWeekList: (value) => weekList = value,
        setActualCurrentWeekStr: (value) => actualCurrentWeek = value,
        setActualCurrentTermStr: (value) => actualCurrentTerm = value,
        setNowInTeachingWeek: (_) {},
        setNowStatusLabel: (_) {},
      );
    }

    setUp(() {
      weekCache = {};
      currentTerm = null;
      weekList = null;
      actualCurrentWeek = null;
      actualCurrentTerm = null;
    });

    ScheduleData week(String number, String term) => ScheduleData(
      weekNum: number,
      yearTerm: term,
      weekList: const ['1', '2', '3'],
      eventList: const [],
    );

    test(
      'later foreground selection owns last-viewed when responses reverse',
      () async {
        SharedPreferences.setMockInitialValues({'account': 'u1'});
        final api = _FakeWeekLoaderScheduleApi();
        final loader = buildLoader(
          api,
          credentialStore: _FakeWeekLoaderCredentialStore(value: 'p1'),
        );
        final secondWeek = Completer<ScheduleData>();
        final thirdWeek = Completer<ScheduleData>();
        api.pending['u1|term|2'] = secondWeek;
        api.pending['u1|term|3'] = thirdWeek;
        final old = loader.loadFromNetwork(weekNum: '2', yearTerm: 'term');
        await Future<void>.delayed(Duration.zero);
        final latest = loader.loadFromNetwork(weekNum: '3', yearTerm: 'term');
        await Future<void>.delayed(Duration.zero);
        thirdWeek.complete(week('3', 'term'));
        await latest;
        secondWeek.complete(week('2', 'term'));
        await old;
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('schedule_last_week_u1'), '3');
        expect(prefs.getString('schedule_last_term_u1'), 'term');
      },
    );

    test(
      'late background response cannot restore previous term or cache',
      () async {
        SharedPreferences.setMockInitialValues({'account': 'u1'});
        final api = _FakeWeekLoaderScheduleApi();
        final loader = buildLoader(
          api,
          credentialStore: _FakeWeekLoaderCredentialStore(value: 'p1'),
        );
        final pending = Completer<ScheduleData>();
        api.pending['u1|old|2'] = pending;
        loader.selectWeek('1', 'old');
        final old = loader.ensureWeekLoaded('2', 'old');
        await Future<void>.delayed(Duration.zero);
        loader.selectWeek('1', 'new');
        loader.processLoadedData(week('1', 'new'));
        pending.complete(week('2', 'old'));
        expect(await old, isFalse);
        expect(currentTerm, 'new');
        expect(weekCache.keys, [1]);
        expect(weekCache[1]!.yearTerm, 'new');
      },
    );

    test(
      'account switch rejects old response and accepts first new-account load',
      () async {
        SharedPreferences.setMockInitialValues({'account': 'u1'});
        final api = _FakeWeekLoaderScheduleApi();
        final loader = buildLoader(
          api,
          credentialStore: _FakeWeekLoaderCredentialStore(value: 'p1'),
        );
        final pending = Completer<ScheduleData>();
        api.pending['u1|term|2'] = pending;
        final old = loader.ensureWeekLoaded('2', 'term');
        await Future<void>.delayed(Duration.zero);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('account', 'u2');
        api.networkResult = week('1', 'term');
        final latest = await loader.loadFromNetwork(
          weekNum: '1',
          yearTerm: 'term',
        );
        loader.processLoadedData(latest);
        pending.complete(week('2', 'term'));
        expect(await old, isFalse);
        expect(loader.userId, 'u2');
        expect(weekCache.keys, [1]);
        expect(prefs.getString('schedule_last_week_u2'), '1');
        expect(prefs.getString('schedule_last_week_u1'), isNull);
      },
    );

    test(
      'memory hit must match term and remembers selected cached week',
      () async {
        SharedPreferences.setMockInitialValues({'account': 'u1'});
        final api = _FakeWeekLoaderScheduleApi()
          ..cacheResult = week('2', 'new');
        final loader = buildLoader(api);
        weekCache[2] = week('2', 'old');
        expect(
          await loader.ensureWeekLoaded('2', 'new', updateLastViewed: true),
          isTrue,
        );
        expect(weekCache[2]!.yearTerm, 'new');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('schedule_last_week_u1'), '2');
        expect(prefs.getString('schedule_last_term_u1'), 'new');
      },
    );

    test('processLoadedData 在学期变化时清空旧缓存', () {
      final api = _FakeWeekLoaderScheduleApi();
      final loader = buildLoader(api);
      weekCache[1] = ScheduleData(weekNum: '1', yearTerm: '2024-2025-1');
      currentTerm = '2024-2025-1';

      final changed = loader.processLoadedData(
        ScheduleData(
          weekNum: '2',
          yearTerm: '2024-2025-2',
          weekList: const ['1', '2', '3'],
        ),
      );

      expect(changed, isTrue);
      expect(currentTerm, '2024-2025-2');
      expect(weekCache.keys, [2]);
      expect(weekList, ['1', '2', '3']);
    });

    for (final signedIn in [false, true]) {
      test(
        'prefetch skips ${signedIn ? 'missing credentials' : 'signed out'} without warning',
        () async {
          SharedPreferences.setMockInitialValues({
            if (signedIn) 'account': 'u1',
          });
          final logger = AppLogger.I;
          await logger.init(enableFile: false, enableConsole: false);
          addTearDown(logger.dispose);
          final previous = logger.recent.isEmpty
              ? 0
              : logger.recent.last.sequence;
          final api = _FakeWeekLoaderScheduleApi();
          final loader = buildLoader(
            api,
            credentialStore: _FakeWeekLoaderCredentialStore(),
          );

          expect(await loader.ensureWeekLoaded('2', '2024-2025-2'), isFalse);
          expect(api.networkCalls, 0);
          expect(
            logger.recent
                .where((event) => event.sequence > previous)
                .any((event) => event.level.priority >= LogLevel.warn.priority),
            isFalse,
          );
        },
      );
    }

    test(
      'prefetch cancellation remains a breadcrumb and returns false',
      () async {
        SharedPreferences.setMockInitialValues({'account': 'u1'});
        final logger = AppLogger.I;
        await logger.init(enableFile: false, enableConsole: false);
        addTearDown(logger.dispose);
        final previous = logger.recent.isEmpty
            ? 0
            : logger.recent.last.sequence;
        final api = _FakeWeekLoaderScheduleApi()
          ..networkError = DioException(
            requestOptions: RequestOptions(path: '/schedule'),
            type: DioExceptionType.cancel,
          );
        final loader = buildLoader(
          api,
          credentialStore: _FakeWeekLoaderCredentialStore(value: 'secure-p1'),
        );

        expect(await loader.ensureWeekLoaded('2', '2024-2025-2'), isFalse);
        final events = logger.recent
            .where((event) => event.sequence > previous)
            .toList();
        expect(
          events.any((event) => event.level.priority >= LogLevel.warn.priority),
          isFalse,
        );
        expect(events.last.fields?['outcome'], 'cancelled');
      },
    );

    test(
      'foreground missing week metadata logs cause and keeps UI error',
      () async {
        SharedPreferences.setMockInitialValues({'account': 'u1'});
        final logger = AppLogger.I;
        await logger.init(enableFile: false, enableConsole: false);
        addTearDown(logger.dispose);
        final previous = logger.recent.isEmpty
            ? 0
            : logger.recent.last.sequence;
        final api = _FakeWeekLoaderScheduleApi()
          ..networkResult = ScheduleData(weekNum: '', weekList: []);
        final loader = buildLoader(
          api,
          credentialStore: _FakeWeekLoaderCredentialStore(value: 'secure-p1'),
        );

        await expectLater(
          loader.loadFromNetwork(),
          throwsA(
            predicate<Object>(
              (error) => error.toString() == 'Exception: 课表鉴权失败，请重新登录',
            ),
          ),
        );
        final failure = logger.recent.singleWhere(
          (event) =>
              event.sequence > previous &&
              event.fields?['stage'] == 'validate_schedule',
        );
        expect(failure.fields?['stage'], 'validate_schedule');
        expect(failure.fields?['trace_id'], isNotEmpty);
        expect(failure.stackTrace.toString(), contains('_loadFromNetwork'));
      },
    );

    test(
      'credential storage read error is diagnosed before requesting a week',
      () async {
        SharedPreferences.setMockInitialValues({'account': 'u1'});
        final logger = AppLogger.I;
        await logger.init(enableFile: false, enableConsole: false);
        addTearDown(logger.dispose);
        final previous = logger.recent.isEmpty
            ? 0
            : logger.recent.last.sequence;
        final error = StateError('credential storage unavailable');
        final api = _FakeWeekLoaderScheduleApi();
        final loader = buildLoader(
          api,
          credentialStore: _FakeWeekLoaderCredentialStore(readError: error),
        );

        await expectLater(loader.loadFromNetwork(), throwsA(same(error)));
        expect(api.networkCalls, 0);
        final failure = logger.recent.singleWhere(
          (event) => event.sequence > previous && event.level == LogLevel.error,
        );
        expect(failure.fields?['stage'], 'load_week');
        expect(
          failure.stackTrace.toString(),
          contains('readEncryptedPassword'),
        );
        expect(failure.fields?['trace_id'], isNotEmpty);
      },
    );

    test('ensureWeekLoaded 优先命中内存缓存', () async {
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        'encrypted_password': 'p1',
      });
      final api = _FakeWeekLoaderScheduleApi();
      final loader = buildLoader(api);
      weekCache[2] = ScheduleData(weekNum: '2', yearTerm: '2024-2025-2');

      final success = await loader.ensureWeekLoaded('2', '2024-2025-2');

      expect(success, isTrue);
      expect(api.cacheCalls, 0);
      expect(api.networkCalls, 0);
    });

    test('ensureWeekLoaded 在磁盘缓存命中时不走网络', () async {
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        'encrypted_password': 'p1',
      });
      final api = _FakeWeekLoaderScheduleApi()
        ..cacheResult = ScheduleData(weekNum: '2', yearTerm: '2024-2025-2');
      final loader = buildLoader(api);

      final success = await loader.ensureWeekLoaded('2', '2024-2025-2');

      expect(success, isTrue);
      expect(api.cacheCalls, 1);
      expect(api.networkCalls, 0);
      expect(weekCache[2], isNotNull);
    });

    test('从桌面组件锚点恢复实际本周，供返回本周按钮使用', () async {
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        'schedule_widget_week_u1': '6',
        'schedule_widget_term_u1': '2026-2027-1',
      });
      final api = _FakeWeekLoaderScheduleApi()
        ..cacheResult = ScheduleData(
          weekNum: '3',
          yearTerm: '2026-2027-1',
          weekList: const ['1', '2', '3', '4', '5', '6'],
        );
      final loader = buildLoader(api);

      await loader.loadFromCache(weekNum: '3', yearTerm: '2026-2027-1');

      expect(actualCurrentWeek, '6');
      expect(actualCurrentTerm, '2026-2027-1');
    });

    test('个性化变化会从本地重新应用到所有内存周缓存', () async {
      SharedPreferences.setMockInitialValues({'account': 'u1'});
      final api = _FakeWeekLoaderScheduleApi();
      final loader = buildLoader(api);
      weekCache[1] = ScheduleData(
        weekNum: '1',
        yearTerm: '2024-2025-2',
        eventList: [EventItem(eventName: '高等数学')],
      );
      weekCache[2] = ScheduleData(
        weekNum: '2',
        yearTerm: '2024-2025-2',
        eventList: [EventItem(eventName: '高等数学')],
      );
      api.cacheResults['1'] = ScheduleData(
        weekNum: '1',
        yearTerm: '2024-2025-2',
        eventList: const [],
      );
      api.cacheResults['2'] = ScheduleData(
        weekNum: '2',
        yearTerm: '2024-2025-2',
        eventList: const [],
      );

      final count = await loader.reloadMemoryCacheFromDisk(
        yearTerm: '2024-2025-2',
      );

      expect(count, 2);
      expect(api.cacheCalls, 2);
      expect(api.networkCalls, 0);
      expect(weekCache[1]!.eventList, isEmpty);
      expect(weekCache[2]!.eventList, isEmpty);
    });

    test('ensureWeekLoaded 在无缓存时通过凭证存储读取密码并写入缓存', () async {
      SharedPreferences.setMockInitialValues({'account': 'u1'});
      final api = _FakeWeekLoaderScheduleApi()
        ..networkResult = ScheduleData(
          weekNum: '2',
          yearTerm: '2024-2025-2',
          weekList: const ['1', '2', '3'],
          eventList: const [],
        );
      final credentialStore = _FakeWeekLoaderCredentialStore(
        value: 'secure-p1',
      );
      final loader = buildLoader(api, credentialStore: credentialStore);

      final success = await loader.ensureWeekLoaded('2', '2024-2025-2');

      expect(success, isTrue);
      expect(api.cacheCalls, 1);
      expect(api.networkCalls, 1);
      expect(api.lastEncryptedPassword, 'secure-p1');
      expect(credentialStore.readCalls, 1);
      expect(weekCache[2], isNotNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('schedule_fp_u1_2024-2025-2_2'), isNotNull);
      expect(prefs.getInt('schedule_fetch_at_u1_2024-2025-2_2'), isNotNull);
    });

    test('ensureWeekLoaded 网络失败时返回 false', () async {
      SharedPreferences.setMockInitialValues({'account': 'u1'});
      final api = _FakeWeekLoaderScheduleApi();
      final credentialStore = _FakeWeekLoaderCredentialStore(
        value: 'secure-p1',
      );
      final loader = buildLoader(api, credentialStore: credentialStore);

      final success = await loader.ensureWeekLoaded('2', '2024-2025-2');

      expect(success, isFalse);
      expect(weekCache, isEmpty);
    });

    test(
      'strict affected-week refresh preserves the original exception',
      () async {
        SharedPreferences.setMockInitialValues({'account': 'u1'});
        final failure = StateError('original week transport failure');
        final api = _FakeWeekLoaderScheduleApi()..networkError = failure;
        final loader = buildLoader(
          api,
          credentialStore: _FakeWeekLoaderCredentialStore(value: 'secure-p1'),
        );
        await expectLater(
          loader.ensureWeekLoaded(
            '2',
            '2024-2025-2',
            forceRefresh: true,
            rethrowOnFailure: true,
          ),
          throwsA(same(failure)),
        );
        expect(weekCache, isEmpty);
      },
    );

    test('并发加载同一周时复用同一个请求', () async {
      SharedPreferences.setMockInitialValues({'account': 'u1'});
      final pending = Completer<ScheduleData>();
      final api = _FakeWeekLoaderScheduleApi()..networkCompleter = pending;
      final loader = buildLoader(
        api,
        credentialStore: _FakeWeekLoaderCredentialStore(value: 'secure-p1'),
      );

      final first = loader.ensureWeekLoaded('2', '2024-2025-2');
      final second = loader.ensureWeekLoaded('2', '2024-2025-2');
      await Future<void>.delayed(Duration.zero);
      pending.complete(
        ScheduleData(
          weekNum: '2',
          yearTerm: '2024-2025-2',
          weekList: const ['1', '2', '3'],
          eventList: const [],
        ),
      );

      expect(await Future.wait([first, second]), [isTrue, isTrue]);
      expect(api.cacheCalls, 1);
      expect(api.networkCalls, 1);
    });

    test('strict and ordinary concurrent waiters share a failed request across traces', () async {
      SharedPreferences.setMockInitialValues({'account': 'u1'});
      final pending = Completer<ScheduleData>();
      final failure = StateError('shared week failure');
      final api = _FakeWeekLoaderScheduleApi()..networkCompleter = pending;
      final loader = buildLoader(
        api,
        credentialStore: _FakeWeekLoaderCredentialStore(value: 'secure-p1'),
      );
      final ordinary = AppLogger.I.runWithTraceIdAsync(
        'ordinary-waiter',
        () => loader.ensureWeekLoaded('2', '2024-2025-2', forceRefresh: true),
      );
      final strict = AppLogger.I.runWithTraceIdAsync(
        'strict-waiter',
        () => loader.ensureWeekLoaded(
          '2',
          '2024-2025-2',
          forceRefresh: true,
          rethrowOnFailure: true,
        ),
      );
      final strictCheck = expectLater(strict, throwsA(same(failure)));
      await Future<void>.delayed(Duration.zero);
      pending.completeError(failure, StackTrace.current);
      expect(await ordinary, isFalse);
      await strictCheck;
      expect(api.networkCalls, 1);
      expect(weekCache, isEmpty);
    });
  });
}
