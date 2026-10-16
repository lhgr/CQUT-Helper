import 'dart:convert';
import 'dart:typed_data';

import 'package:cqut_helper/api/auth/auth_api.dart';
import 'package:cqut_helper/api/core/api_client.dart';
import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CredentialStore extends CredentialStore {
  _CredentialStore(this.value) : super(secureStore: _NoopSecretStore());

  final String? value;

  @override
  Future<String?> readEncryptedPassword() async => value;
}

class _NoopSecretStore implements SecureSecretStore {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write({required String key, required String value}) async {}
}

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(Object body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpClientAdapter originalAdapter;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'account': 'test-account'});
    originalAdapter = ApiClient().dio.httpClientAdapter;
    await AuthApi().resetLoginContext();
  });

  tearDown(() async {
    ApiClient().dio.httpClientAdapter = originalAdapter;
    await AuthApi().resetLoginContext();
  });

  test('time info POST waits for CAS login and carries its cookie', () async {
    late _ResponseAdapter adapter;
    adapter = _ResponseAdapter((options) {
      if (options.path.endsWith('/sso/doLogin')) {
        return _jsonResponse({'code': 200, 'msg': '登录成功！'});
      }
      if (options.path.contains('/YF8A4013/cas/login')) {
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['https://timetable-cfc.cqut.edu.cn/api/auth/casLogin'],
          },
        );
      }
      if (options.path.endsWith('/api/auth/casLogin')) {
        return ResponseBody.fromString(
          jsonEncode({'ok': true}),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
            'set-cookie': ['time-info-session=present; Path=/; HttpOnly'],
          },
        );
      }
      if (options.path.endsWith('/api/courseSchedule/getCampusTimeInfo')) {
        return _jsonResponse([
          {
            'campusName': '两江校区',
            'sessionNum': 1,
            'startTime': '08:00',
            'endTime': '08:45',
          },
        ]);
      }
      throw StateError('Unexpected request path');
    });
    ApiClient().dio.httpClientAdapter = adapter;

    final scheduleApi = ScheduleApi(
      credentialStore: _CredentialStore('test-encrypted-password'),
    );
    final result = await scheduleApi.fetchCampusTimeInfo('两江校区');
    final repeatedResult = await scheduleApi.fetchCampusTimeInfo('两江校区');

    final timeRequest = adapter.requests.firstWhere(
      (options) =>
          options.path.endsWith('/api/courseSchedule/getCampusTimeInfo'),
    );
    expect(result.single.startTime, '08:00');
    expect(repeatedResult.single.startTime, '08:00');
    expect(
      adapter.requests.where(
        (options) => options.path.endsWith('/sso/doLogin'),
      ),
      hasLength(1),
    );
    expect(
      adapter.requests.where(
        (options) =>
            options.path.endsWith('/api/courseSchedule/getCampusTimeInfo'),
      ),
      hasLength(2),
    );
    expect(
      adapter.requests.indexOf(timeRequest),
      greaterThan(
        adapter.requests.indexWhere(
          (options) => options.path.endsWith('/api/auth/casLogin'),
        ),
      ),
    );
    expect(
      timeRequest.headers['cookie'],
      contains('time-info-session=present'),
    );
    final repeatedTimeRequest = adapter.requests.last;
    expect(
      repeatedTimeRequest.headers['cookie'],
      contains('time-info-session=present'),
    );
  });

  test('failed CAS login does not request time info', () async {
    final adapter = _ResponseAdapter((options) {
      if (options.path.endsWith('/sso/doLogin')) {
        return _jsonResponse({'code': 401, 'msg': '登录失败'});
      }
      throw StateError('Unexpected request path');
    });
    ApiClient().dio.httpClientAdapter = adapter;

    await expectLater(
      ScheduleApi(credentialStore: _CredentialStore('test-encrypted-password'))
          .fetchCampusTimeInfo('两江校区'),
      throwsException,
    );
    expect(
      adapter.requests.any(
        (options) =>
            options.path.endsWith('/api/courseSchedule/getCampusTimeInfo'),
      ),
      isFalse,
    );
  });
}
