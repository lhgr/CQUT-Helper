import 'dart:io';

import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/manager/schedule_update_worker_state_store.dart';
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

  test('unknown task persists a matched start and skipped outcome', () async {
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
    expect(rows, hasLength(2));
    final start = rows.singleWhere((row) => row['kind'] == 'operation');
    expect(start['outcome'], 'started');
    expect((start['fields'] as Map)['lifecycle'], 'background_task');
    expect(
      (outcome['fields'] as Map)['lifecycle_id'],
      (start['fields'] as Map)['lifecycle_id'],
    );
    expect(outcome['outcome'], 'skipped');
    expect(outcome['reason'], 'skip_unknown_task');
    expect(outcome['errorCategory'], isNull);
    expect((outcome['fields'] as Map)['duration_ms'], isNonNegative);
  });

  test('disabled polling still records that it ran and skipped', () async {
    expect(
      await ScheduleUpdateWorker.runTaskForTesting(
        'schedule_notice_poll_task',
        {'trigger': 'daily_9am'},
      ),
      isTrue,
    );
    final rows = await storage.snapshot();
    expect(rows, hasLength(2));
    final outcome = rows.singleWhere(
      (row) => row['kind'] == 'operation_outcome',
    );
    expect(outcome['outcome'], 'skipped');
    expect(outcome['reason'], 'skip_disabled');
    expect((outcome['fields'] as Map)['network_outcome'], 'not_attempted');
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
      expect(outcome['causeEventId'], failure['eventId']);
      final state = await loadScheduleUpdateWorkerStoredState();
      expect(state.lastState?['status'], 'unhandled_failed');
      expect(
        (state.lastState?['fields'] as Map)['operation_id'],
        outcome['operationId'],
      );
      expect((outcome['fields'] as Map)['stage_durations_ms'], isNotEmpty);
    },
  );

  test(
    'separate runs sharing a refresh ID retain distinct lifecycle IDs',
    () async {
      for (var run = 0; run < 2; run++) {
        await ScheduleUpdateWorker.runTaskForTesting('unsupported_task', {
          'trigger': 'widget_manual',
          'refreshId': 'same-refresh',
        });
      }
      final rows = await storage.snapshot();
      final starts = rows.where((row) => row['kind'] == 'operation').toList();
      final outcomes = rows
          .where((row) => row['kind'] == 'operation_outcome')
          .toList();
      expect(starts, hasLength(2));
      expect(outcomes, hasLength(2));
      final ids = starts
          .map((row) => (row['fields'] as Map)['lifecycle_id'])
          .toSet();
      expect(ids, hasLength(2));
      expect(
        outcomes.map((row) => (row['fields'] as Map)['lifecycle_id']).toSet(),
        ids,
      );
      expect(
        outcomes.every((row) => row['operationId'] == 'same-refresh'),
        isTrue,
      );
    },
  );

  test(
    'follow-up failure has its own cause and preserves the main skipped result',
    () async {
      final followUpFailure = StateError('follow-up scheduling unavailable');
      await expectLater(
        ScheduleUpdateWorker.runTaskForTesting('academic_calendar_poll_task', {
          'trigger': 'academic_calendar_daily',
        }, followUp: () async => throw followUpFailure),
        throwsA(same(followUpFailure)),
      );
      final rows = await storage.snapshot();
      final lifecycleOutcomes = rows
          .where(
            (row) =>
                row['kind'] == 'operation_outcome' &&
                (row['fields'] as Map?)?['lifecycle'] == 'background_task',
          )
          .toList();
      expect(lifecycleOutcomes, hasLength(1));
      final main = lifecycleOutcomes.single;
      expect(main['outcome'], 'skipped');
      expect(main['reason'], 'calendar_skip_missing_term');
      expect(main['causeEventId'], isNull);
      expect((main['fields'] as Map)['follow_up_outcome'], 'failed');
      final followUp = rows.singleWhere(
        (row) =>
            row['kind'] == 'operation_outcome' &&
            row['stage'] == 'schedule_follow_up',
      );
      final cause = rows.singleWhere((row) => row['kind'] == 'incident');
      expect(followUp['outcome'], 'failed');
      expect(followUp['causeEventId'], cause['eventId']);
      final state = await loadScheduleUpdateWorkerStoredState();
      expect(state.lastState?['status'], 'calendar_skip_missing_term');
      expect(
        (state.lastState?['fields'] as Map)['follow_up_outcome'],
        'failed',
      );
    },
  );
}
