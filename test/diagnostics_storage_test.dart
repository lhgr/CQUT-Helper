import 'dart:convert';
import 'dart:io';

import 'package:cqut_helper/utils/diagnostics_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 15, 12);
  late Directory directory;

  Map<String, Object?> event(String id, {DateTime? at}) => {
    'eventId': id,
    'timestamp': (at ?? now).toIso8601String(),
    'level': 'error',
    'kind': 'error',
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cqut-storage-worker-');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'snapshot stays between queued writes while worker reads files',
    () async {
      final storage = FileDiagnosticStorage(
        directory,
        'foreground',
        now: () => now,
      );
      await storage.initialize();
      final before = storage.write(event('before'));
      final snapshot = storage.snapshot();
      final after = storage.write(event('after'));
      await before;
      expect((await snapshot).map((row) => row['eventId']), ['before']);
      await after;
      expect((await storage.snapshot()).map((row) => row['eventId']), [
        'before',
        'after',
      ]);
    },
  );

  test(
    'snapshot includes foreground and background writers in one directory',
    () async {
      final foreground = FileDiagnosticStorage(
        directory,
        'foreground',
        now: () => now,
      );
      final background = FileDiagnosticStorage(
        directory,
        'background',
        now: () => now,
      );
      await foreground.initialize();
      await Future.wait([
        foreground.write(event('foreground')),
        background.write(event('background')),
      ]);
      expect(
        (await foreground.snapshot()).map((row) => row['eventId']).toSet(),
        {'foreground', 'background'},
      );
    },
  );

  test(
    'snapshot skips bad JSON records and expired timestamps individually',
    () async {
      final storage = FileDiagnosticStorage(
        directory,
        'foreground',
        now: () => now,
      );
      await storage.initialize();
      await storage.write(event('valid'));
      final file = File('${directory.path}/foreground-0.jsonl');
      await file.writeAsString(
        '{incomplete\n'
        '[]\n'
        '${jsonEncode(event('expired', at: now.subtract(const Duration(days: 4))))}\n'
        '${jsonEncode(event('later-valid'))}\n',
        mode: FileMode.append,
      );
      expect((await storage.snapshot()).map((row) => row['eventId']), [
        'valid',
        'later-valid',
      ]);
    },
  );

  test(
    'Android snapshot decodes JSON and maps while ignoring one corrupt row',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(AndroidDiagnosticStorage.channel, (
        call,
      ) async {
        expect(call.method, 'snapshot');
        return [
          jsonEncode(event('json')),
          '{incomplete',
          event('map'),
          ['not-a-record'],
        ];
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          AndroidDiagnosticStorage.channel,
          null,
        ),
      );
      expect(
        (await AndroidDiagnosticStorage(
          'foreground',
        ).snapshot()).map((row) => row['eventId']),
        ['json', 'map'],
      );
    },
  );
}
