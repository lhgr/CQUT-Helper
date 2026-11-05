import 'package:cqut_helper/utils/document_file_service.dart';
import 'package:cqut_helper/utils/schedule_ics_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cqut/documents');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('iOS JSON import returns document text', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openTextDocument');
      expect(call.arguments, {'mimeType': 'application/json'});
      return '{"courses":[]}';
    });

    expect(await DocumentFileService.openText(), '{"courses":[]}');
  });

  test(
    'iOS ICS export uses the document picker and preserves cancellation',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'createTextDocument');
        expect(call.arguments, {
          'fileName': 'CQUT.ics',
          'mimeType': 'text/calendar',
          'content': 'BEGIN:VCALENDAR',
        });
        return null;
      });

      expect(
        await ScheduleIcsService.exportToDownloads(
          content: 'BEGIN:VCALENDAR',
          fileName: 'CQUT.ics',
        ),
        isNull,
      );
    },
  );

  test('iOS exports an existing log file and preserves cancellation', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'exportFile');
      expect(call.arguments, {
        'path': '/application/log/cqut.log',
        'fileName': 'cqut.log',
        'mimeType': 'text/plain',
      });
      return null;
    });

    expect(
      await DocumentFileService.exportFile(path: '/application/log/cqut.log'),
      isNull,
    );
  });

  test('document provider failures reach the caller', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'document_read_error',
        message: 'Read failed',
      );
    });

    await expectLater(
      DocumentFileService.openText(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'document_read_error',
        ),
      ),
    );
  });
}
