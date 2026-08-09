import 'package:cqut_helper/utils/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final logger = AppLogger.I;

  setUp(() async {
    await logger.init(
      minLevel: LogLevel.debug,
      enableConsole: false,
      enableFile: false,
    );
  });

  tearDown(() async {
    await logger.dispose();
  });

  test('日志事件自动携带会话、序号和稳定错误指纹', () {
    logger.warn(
      'Schedule',
      'load failed for task 123456',
      error: StateError('bad state'),
      fields: {
        'token': 'secret-value',
        'session_id': 'spoofed-session',
        'url': 'https://example.test/data?token=secret-value&page=2',
      },
    );
    logger.warn(
      'Schedule',
      'load failed for task 999999',
      error: StateError('another state'),
    );

    final first = logger.recent[logger.recent.length - 2];
    final second = logger.recent.last;

    expect(first.sessionId, hasLength(16));
    expect(first.eventId, startsWith('${first.sessionId}-'));
    expect(second.sequence, first.sequence + 1);
    expect(first.fields?['schema'], 2);
    expect(first.fields?['session_id'], first.sessionId);
    expect(first.fields?['event_id'], first.eventId);
    expect(first.fields?['token'], '<redacted>');
    expect(first.fields?['url'], contains('token=<redacted>'));
    expect(first.fields?['url'], contains('page=<redacted>'));
    expect(first.fields?['error_type'], 'StateError');
    expect(first.fields?['fingerprint'], hasLength(16));
    expect(second.fields?['fingerprint'], first.fields?['fingerprint']);
  });

  test('字段过长时仍保留排障信封', () async {
    await logger.init(
      minLevel: LogLevel.debug,
      enableConsole: false,
      enableFile: false,
      maxFieldsChars: 350,
    );

    logger.error(
      'Schedule',
      'oversized payload',
      error: StateError('bad state'),
      fields: {
        'payload': List.filled(4000, 'x').join(),
        'trace_id': 'trace-oversized',
      },
    );

    final event = logger.recent.last;
    expect(event.fields?['fields_truncated'], isTrue);
    expect(event.fields?['session_id'], event.sessionId);
    expect(event.fields?['event_id'], event.eventId);
    expect(event.fields?['trace_id'], 'trace-oversized');
    expect(event.fields?['fingerprint'], hasLength(16));
    expect(event.fields?['payload'], isNull);
  });

  test('网络日志 URI 移除凭证、查询值和片段', () {
    final uri = Uri.parse(
      'https://student:password@example.test/api/schedule'
      '?account=20260001&token=secret#details',
    );

    expect(sanitizeUriForLogging(uri), 'https://example.test/api/schedule');
  });

  test('异步追踪保留 trace id，并在异常时记录 fatal', () async {
    const traceId = 'trace-for-test';

    await expectLater(
      logger.runWithTraceIdAsync<void>(traceId, () async {
        throw ArgumentError('boom');
      }),
      throwsArgumentError,
    );

    final event = logger.recent.last;
    expect(event.level, LogLevel.fatal);
    expect(event.tag, 'Zone');
    expect(event.fields?['trace_id'], traceId);
    expect(event.fields?['error_type'], 'ArgumentError');
  });
}
