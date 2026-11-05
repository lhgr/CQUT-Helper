import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cqut_helper/api/update/update_api.dart';
import 'package:cqut_helper/utils/github_proxy.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _rawUri = Uri.parse(
  'https://api.github.com/repos/lhgr/CQUT-Helper/releases/latest',
);
final _proxyUri = GithubProxy.proxyUriOf(_rawUri);
final _time = DateTime(2026, 11, 5, 12);

Map<String, dynamic> _release([String tag = 'v1.2.3']) => {
  'tag_name': tag,
  'html_url': 'https://github.com/lhgr/CQUT-Helper/releases/tag/$tag',
  'body': 'Release notes',
  'assets': <dynamic>[],
};

String _cache({DateTime? at, String? etag = 'r1', Uri? uri}) => jsonEncode({
  'release': _release(),
  'validatedAt': (at ?? _time).millisecondsSinceEpoch,
  'etag': etag,
  'etagUri': (uri ?? _proxyUri).toString(),
});

ResponseBody _body(dynamic data, {int status = 200, String? etag}) =>
    ResponseBody.fromString(
      status == 304 ? '' : jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        if (etag != null) 'etag': [etag],
      },
    );

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final FutureOr<ResponseBody> Function(RequestOptions, Future<void>?) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return await respond(options, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  UpdateApi create(_Adapter adapter, {DateTime Function()? now}) {
    final dio = Dio()..httpClientAdapter = adapter;
    return UpdateApi(dio: dio, now: now ?? () => _time);
  }

  test(
    'persists raw release and serves a six-hour cache across API instances',
    () async {
      final adapter = _Adapter((_, _) => _body(_release(), etag: 'r1'));
      final first = await create(adapter).fetchLatest();
      final second = await create(adapter).fetchLatest();
      expect(first.networkValidated, isTrue);
      expect(second.fromCache, isTrue);
      expect(second.networkValidated, isFalse);
      expect(second.info?.body, 'Release notes');
      expect(adapter.requests, hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString(UpdateApi.cacheKey)!);
      expect(stored['release'], _release());
      expect(stored['etagUri'], _proxyUri.toString());
      expect(stored['validatedAt'], _time.millisecondsSinceEpoch);
    },
  );

  test('expiry at six hours and manual checks reach the network', () async {
    SharedPreferences.setMockInitialValues({
      UpdateApi.cacheKey: _cache(at: _time.subtract(UpdateApi.cacheTtl)),
    });
    final adapter = _Adapter((_, _) => _body(_release()));
    final api = create(adapter);
    await api.fetchLatest();
    await api.fetchLatest(forceRefresh: true);
    expect(adapter.requests, hasLength(2));
  });

  test('coalesces overlapping network checks', () async {
    final gate = Completer<ResponseBody>();
    final adapter = _Adapter((_, _) => gate.future);
    final api = create(adapter);
    final first = api.fetchLatest();
    final second = api.fetchLatest(forceRefresh: true);
    await Future<void>.delayed(Duration.zero);
    gate.complete(_body(_release()));
    final results = await Future.wait([first, second]);
    expect(results.every((result) => result.networkValidated), isTrue);
    expect(adapter.requests, hasLength(1));
  });

  test('manual check joining an automatic cache hit still fetches', () async {
    SharedPreferences.setMockInitialValues({UpdateApi.cacheKey: _cache()});
    final adapter = _Adapter((_, _) => _body(_release('v1.2.4')));
    final api = create(adapter);
    final automatic = api.fetchLatest();
    final manual = api.fetchLatest(forceRefresh: true);
    expect((await automatic).fromCache, isTrue);
    expect((await manual).info?.tagName, 'v1.2.4');
    expect(adapter.requests, hasLength(1));
  });

  test('304 validates existing cache and advances its timestamp', () async {
    final old = _time.subtract(const Duration(days: 1));
    SharedPreferences.setMockInitialValues({
      UpdateApi.cacheKey: _cache(at: old),
    });
    final adapter = _Adapter((options, _) {
      expect(options.headers['If-None-Match'], 'r1');
      return _body(null, status: 304, etag: 'r2');
    });
    final result = await create(adapter).fetchLatest();
    expect(result.networkValidated, isTrue);
    expect(result.info?.tagName, 'v1.2.3');
    expect(result.validatedAt, _time);
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString(UpdateApi.cacheKey)!);
    expect(stored['etag'], 'r2');
    expect(stored['validatedAt'], _time.millisecondsSinceEpoch);
  });

  test('does not send proxy ETag to direct endpoint after fallback', () async {
    SharedPreferences.setMockInitialValues({UpdateApi.cacheKey: _cache()});
    final adapter = _Adapter((options, _) {
      if (options.uri == _proxyUri) {
        expect(options.headers['If-None-Match'], 'r1');
        return _body({}, status: 502);
      }
      expect(options.uri, _rawUri);
      expect(options.headers.containsKey('If-None-Match'), isFalse);
      return _body(_release('v1.2.4'), etag: 'direct1');
    });
    final result = await create(adapter).fetchLatest(forceRefresh: true);
    expect(result.networkValidated, isTrue);
    expect(adapter.requests, hasLength(2));
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString(UpdateApi.cacheKey)!);
    expect(stored['etagUri'], _rawUri.toString());
  });

  test('direct endpoint can validate its own cached ETag', () async {
    SharedPreferences.setMockInitialValues({
      UpdateApi.cacheKey: _cache(uri: _rawUri),
    });
    final adapter = _Adapter((options, _) {
      if (options.uri == _proxyUri) {
        expect(options.headers.containsKey('If-None-Match'), isFalse);
        return _body({}, status: 502);
      }
      expect(options.headers['If-None-Match'], 'r1');
      return _body(null, status: 304);
    });
    expect(
      (await create(adapter).fetchLatest(forceRefresh: true)).networkValidated,
      isTrue,
    );
  });

  test('failure retains stale release and does not renew its age', () async {
    final raw = _cache(at: _time.subtract(const Duration(days: 3)));
    SharedPreferences.setMockInitialValues({UpdateApi.cacheKey: raw});
    final adapter = _Adapter((_, _) => _body({}, status: 503));
    final result = await create(adapter).fetchLatest();
    expect(result.failure, isNotNull);
    expect(result.fromCache, isTrue);
    expect(result.networkValidated, isFalse);
    expect(result.info?.body, 'Release notes');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(UpdateApi.cacheKey), raw);
    expect(adapter.requests, hasLength(2));
  });

  test(
    'malformed response preserves valid cache and tries direct endpoint',
    () async {
      final raw = _cache();
      SharedPreferences.setMockInitialValues({UpdateApi.cacheKey: raw});
      final adapter = _Adapter((_, _) => _body({'tag_name': 'v1.3.0'}));
      final result = await create(adapter).fetchLatest(forceRefresh: true);
      expect(result.failure, isA<FormatException>());
      expect(result.info?.tagName, 'v1.2.3');
      expect(adapter.requests, hasLength(2));
      expect(
        (await SharedPreferences.getInstance()).getString(UpdateApi.cacheKey),
        raw,
      );
    },
  );

  test('corrupt cache is ignored and unsolicited 304 is rejected', () async {
    SharedPreferences.setMockInitialValues({UpdateApi.cacheKey: '{invalid'});
    final adapter = _Adapter((options, _) {
      expect(options.headers.containsKey('If-None-Match'), isFalse);
      return _body(null, status: 304);
    });
    final result = await create(adapter).fetchLatest();
    expect(result.failure, isNotNull);
    expect(result.info, isNull);
    expect(result.networkValidated, isFalse);
  });

  test('200 without ETag clears previous validator', () async {
    SharedPreferences.setMockInitialValues({UpdateApi.cacheKey: _cache()});
    final adapter = _Adapter((_, _) => _body(_release()));
    await create(adapter).fetchLatest(forceRefresh: true);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(UpdateApi.cacheKey)!)['etag'], isNull);
  });

  test('total budgets cancel actual requests before falling back', () async {
    final cancelled = <Uri>[];
    final adapter = _Adapter((options, cancelFuture) {
      unawaited(cancelFuture!.then((_) => cancelled.add(options.uri)));
      return Completer<ResponseBody>().future;
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final api = UpdateApi(
      dio: dio,
      now: () => _time,
      proxyBudget: const Duration(milliseconds: 20),
      directBudget: const Duration(milliseconds: 20),
    );
    final result = await api.fetchLatest();
    expect(result.failure, isA<DioException>());
    expect(cancelled, [_proxyUri, _rawUri]);
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.every((r) => r.cancelToken!.isCancelled), isTrue);
  });
}
