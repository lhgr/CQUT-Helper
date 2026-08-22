import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_week_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeWeekLoaderScheduleApi extends ScheduleApi {
  ScheduleData? cacheResult;
  final Map<String, ScheduleData> cacheResults = <String, ScheduleData>{};
  ScheduleData? networkResult;
  int cacheCalls = 0;
  int networkCalls = 0;
  String? lastEncryptedPassword;

  @override
  Future<ScheduleData?> loadFromCache({
    required String userId,
    String? weekNum,
    String? yearTerm,
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
    String? refreshId,
  }) async {
    networkCalls++;
    lastEncryptedPassword = encryptedPassword;
    return networkResult!;
  }
}

class _FakeWeekLoaderCredentialStore extends CredentialStore {
  _FakeWeekLoaderCredentialStore({this.value})
    : super(secureStore: _NoopSecureSecretStore());

  final String? value;
  int readCalls = 0;

  @override
  Future<String?> readEncryptedPassword() async {
    readCalls++;
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
  });
}
