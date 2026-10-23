import 'dart:io';

import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/diagnostics_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InvalidTrigger {
  @override
  String toString() => throw const FormatException('invalid task trigger');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late FileDiagnosticStorage storage;
  final logger = AppLogger.I;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp(
      'cqut-worker-diagnostics-',
    );
    storage = FileDiagnosticStorage(
      Directory('${temporary.path}/records'),
      'background',
    );
    await logger.init(
      enableConsole: false,
      storage: storage,
      exportDirectory: Directory('${temporary.path}/exports'),
    );
  });

  tearDown(() async {
    await logger.dispose();
    await temporary.delete(recursive: true);
  });

  test(
    'unknown task writes one compact skipped outcome without a failure',
    () async {
      expect(
        await ScheduleUpdateWorker.runTaskForTesting('unsupported_task', {
          'trigger': 'immediate',
        }),
        isTrue,
      );
      final rows = await storage.snapshot();
      final outcome = rows.singleWhere(
        (row) => row['kind'] == 'operation_outcome',
      );
      expect(rows, hasLength(1));
      expect(outcome['outcome'], 'skipped');
      expect(outcome['reason'], 'skip_unknown_task');
      expect(outcome['errorCategory'], isNull);
      expect(outcome['context'], anyOf(isNull, isEmpty));
      expect((outcome['fields'] as Map)['duration_ms'], isNonNegative);
    },
  );

  test('disabled polling still records that it ran and skipped', () async {
    expect(
      await ScheduleUpdateWorker.runTaskForTesting(
        'schedule_notice_poll_task',
        {'trigger': 'daily_9am'},
      ),
      isTrue,
    );
    final rows = await storage.snapshot();
    expect(rows, hasLength(1));
    expect(rows.single['kind'], 'operation_outcome');
    expect(rows.single['outcome'], 'skipped');
    expect(rows.single['reason'], 'skip_disabled');
  });

  test(
    'uncaught task exception retains its cause and exactly one failed outcome',
    () async {
      await expectLater(
        ScheduleUpdateWorker.runTaskForTesting('schedule_notice_poll_task', {
          'trigger': _InvalidTrigger(),
        }),
        throwsFormatException,
      );
      final rows = await storage.snapshot();
      final failure = rows.singleWhere((row) => row['kind'] == 'incident');
      final outcome = rows.singleWhere(
        (row) => row['kind'] == 'operation_outcome',
      );
      expect(failure['errorType'], 'FormatException');
      expect(outcome['outcome'], 'failed');
      expect(outcome['reason'], 'unhandled_failure');
      expect(outcome['operationId'], failure['operationId']);
      expect(outcome['errorType'], isNull);
    },
  );
}
