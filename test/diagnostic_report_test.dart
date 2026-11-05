import 'dart:convert';

import 'package:cqut_helper/utils/diagnostic_report.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 11, 5, 12);

Map<String, Object?> _row(
  String id,
  int seconds, {
  String kind = 'incident',
  String? outcome,
  String session = 'old-session',
  String operation = 'operation',
  Map<String, Object?> fields = const {},
}) => {
  'timestamp': _now.add(Duration(seconds: seconds)).toIso8601String(),
  'sessionId': session,
  'eventId': id,
  'operationId': operation,
  'kind': kind,
  'level': kind == 'incident' ? 'error' : 'info',
  if (kind == 'incident') 'rootEventId': id,
  'outcome': ?outcome,
  if (outcome == null && kind == 'incident') 'outcome': 'failed',
  if (kind == 'operation_outcome') 'stage': 'service_response',
  'fields': {
    'service': 'CalendarApi',
    'origin': 'https://api.example.test:8443',
    'route': '/calendar',
    'method': 'GET',
    ...fields,
  },
};

Map<String, Object?> _success(
  String id,
  int seconds, {
  Map<String, Object?> fields = const {},
}) => _row(
  id,
  seconds,
  kind: 'operation_outcome',
  outcome: 'succeeded',
  session: 'new-session',
  fields: {'network_validated': true, ...fields},
);

String _render(List<Map<String, Object?>> rows, {int budget = 1024 * 1024}) =>
    renderDiagnosticReport(
      DiagnosticReportInput(
        records: rows,
        budget: budget,
        now: _now,
        version: 'test',
        device: 'test',
        sessionId: 'export-session',
        dropped: 0,
        writeErrors: 0,
      ),
    );

List<Map<String, Object?>> _raw(String report) => report
    .split('三、原始数据（JSONL）')
    .last
    .split('\n')
    .where((line) => line.startsWith('{'))
    .map((line) => (jsonDecode(line) as Map).cast<String, Object?>())
    .toList();

void main() {
  test(
    'validated success derives stable cross-session recovery for all roots',
    () {
      final rows = [
        _row('root-a', -20),
        _row('root-b', -10),
        _success('success', 0),
      ];
      final report = _render(rows);
      final recovered = _raw(report)
          .where((row) => row['kind'] == 'recovery')
          .toList();
      expect(recovered, hasLength(2));
      expect(
        recovered.map((row) => row['resolvesIncidentId']),
        unorderedEquals(['root-a', 'root-b']),
      );
      for (final row in recovered) {
        expect(row['derivedBy'], 'report');
        expect(row['recoveryScope'], 'api_request');
        expect(row['evidenceEventId'], 'success');
        expect(row['rootEventId'], row['causeEventId']);
      }
      expect(_render(rows), report);
      expect(rows, hasLength(3));
      expect(report, contains('"originalEventCount":3'));
      expect(report, contains('"reportDerivedRecoveryCount":2'));
      expect(report, contains('"failedOperationCount":1'));
      expect(report, contains('"operationSucceededCount":0'));
    },
  );

  test('recovery key isolates service origin scheme port method and route', () {
    for (final mismatch in [
      {'service': 'NoticeApi'},
      {'origin': 'https://other.example.test:8443'},
      {'origin': 'http://api.example.test:8443'},
      {'origin': 'https://api.example.test'},
      {'method': 'POST'},
      {'route': '/notice'},
      {'service': null},
    ]) {
      final rows = [_row('root', -1), _success('success', 0, fields: mismatch)];
      expect(
        _raw(_render(rows)).where((r) => r['kind'] == 'recovery'),
        isEmpty,
      );
    }
  });

  test(
    'cache HTTP attempts worker success and nonlater evidence do not recover',
    () {
      final candidates = [
        _success('unvalidated', 0, fields: {'network_validated': false}),
        {..._success('cache', 0), 'outcome': 'cache_used'},
        {..._success('http', 0), 'kind': 'attempt'},
        {..._success('worker', 0), 'stage': 'worker'},
        _success('same-time', -1),
        _success('earlier', -2),
      ];
      expect(
        _raw(_render([_row('root', -1), ...candidates]))
            .where((r) => r['kind'] == 'recovery'),
        isEmpty,
      );
      expect(
        _raw(
          _render([
            _row('expired', -3 * 24 * 3600 - 1),
            _success('success', 0),
          ]),
        ).where((r) => r['kind'] == 'recovery'),
        isEmpty,
      );
    },
  );

  test('runtime recovery takes precedence over report derivation', () {
    final rows = [
      _row('root', -2),
      _success('success', 0),
      _row(
        'runtime-recovery',
        -1,
        kind: 'recovery',
        fields: {'related_root_event_id': 'root'},
      ),
    ];
    final recovered = _raw(_render(rows)).where((r) => r['kind'] == 'recovery');
    expect(recovered.single['eventId'], 'runtime-recovery');
  });

  test('bounded recovery always includes root and success evidence', () {
    final rows = [
      {..._row('root', -2), 'stackTrace': '中' * 300},
      _success('evidence', -1),
      for (var i = 0; i < 20; i++)
        {..._row('noise-$i', i, kind: 'breadcrumb'), 'message': 'x' * 150},
    ];
    for (final budget in [1024, 2048, 4096, 8192]) {
      final report = _render(rows, budget: budget);
      expect(utf8.encode(report).length, lessThanOrEqualTo(budget));
      final raw = _raw(report);
      if (raw.any((row) => row['kind'] == 'recovery')) {
        final ids = raw.map((r) => r['eventId']);
        expect(ids, containsAll(['root', 'evidence']));
      }
    }
  });

  test('failure statistics deduplicate real operations and unknown roots', () {
    final root = _row('root', -2);
    final unknown = {..._row('unknown', -1), 'operationInferred': true};
    final stats = diagnosticReportStatistics([
      root,
      {...root},
      unknown,
      {...unknown},
      {..._row('propagation', 0, kind: 'derived'), 'outcome': 'failed'},
      {
        ..._row('failed', 0, kind: 'operation_outcome', operation: 'worker'),
        'stage': 'worker',
        'outcome': 'failed',
      },
      {
        ..._row(
          'skip',
          0,
          kind: 'operation_outcome',
          operation: 'skipped-worker',
        ),
        'stage': 'worker',
        'outcome': 'skipped',
      },
      _success('success', 0),
    ]);
    expect(stats['rootErrorCount'], 2);
    expect(stats['failedOperationCount'], 2);
    expect(stats['unknownOperationRootCount'], 1);
    expect(stats['operationFailedCount'], 1);
    expect(stats['operationSkippedCount'], 1);
    expect(stats['operationSucceededCount'], 0);
  });

  test('recovered roots and successful business terminals are not failed operations', () {
    final stats = diagnosticReportStatistics([
      {..._row('retry-root', -2), 'outcome': 'recovered'},
      _row('root', -1, operation: 'succeeded-operation'),
      {
        ..._row(
          'done',
          0,
          kind: 'operation_outcome',
          operation: 'succeeded-operation',
        ),
        'stage': 'worker',
        'outcome': 'succeeded',
      },
      _row('resolved-root', -1, operation: 'resolved-operation'),
      {
        ..._row('recovery', 0, kind: 'recovery'),
        'resolvesIncidentId': 'resolved-root',
      },
    ]);
    expect(stats['failedOperationCount'], 0);
    expect(stats['affectedOperationCount'], 3);
    expect(stats['operationSucceededCount'], 1);
  });

  test('concurrent worker starts match their lifecycle and preserve missing evidence', () {
    Map<String, Object?> worker(
      String id,
      int seconds,
      String lifecycle, {
      bool terminal = false,
    }) => {
      ..._row(
        id,
        seconds,
        kind: terminal ? 'operation_outcome' : 'operation',
        outcome: terminal ? 'succeeded' : 'started',
        fields: {'lifecycle': 'background_task', 'lifecycle_id': lifecycle},
      ),
      'stage': 'worker',
    };
    final raw = _raw(
      _render([
        worker('start-a', -3, 'a'),
        worker('start-b', -2, 'b'),
        worker('end-b', -1, 'b', terminal: true),
      ]),
    );
    expect(
      raw.singleWhere((r) => r['eventId'] == 'start-a')['terminalStatus'],
      'terminal_missing',
    );
    expect(
      raw
          .singleWhere((r) => r['eventId'] == 'start-b')
          .containsKey('terminalStatus'),
      isFalse,
    );
    expect(
      raw.singleWhere((r) => r['eventId'] == 'end-b')['startEventId'],
      'start-b',
    );
    expect(
      raw.singleWhere((r) => r['eventId'] == 'start-a')['terminalEvidence'],
      '保留记录中未见匹配终态',
    );
  });

  test('legacy overlapping worker starts never guess a terminal owner', () {
    Map<String, Object?> worker(String id, int seconds, bool terminal) => {
      ..._row(
        id,
        seconds,
        kind: terminal ? 'operation_outcome' : 'operation',
        outcome: terminal ? 'failed' : 'started',
        fields: {'lifecycle': 'background_task'},
      ),
      'stage': 'worker',
    };
    final raw = _raw(
      _render([
        worker('start-a', -3, false),
        worker('start-b', -2, false),
        worker('end', -1, true),
      ]),
    );
    expect(
      raw.where((r) => r['terminalStatus'] == 'terminal_missing'),
      hasLength(2),
    );
    expect(
      raw.singleWhere((r) => r['eventId'] == 'end').containsKey('startEventId'),
      isFalse,
    );
  });

  test('budget keeps worker start and terminal together or omits both', () {
    final rows = [
      _row(
        'start',
        -2,
        kind: 'operation',
        outcome: 'started',
        fields: {'lifecycle': 'background_task', 'lifecycle_id': 'task'},
      ),
      {
        ..._row(
          'terminal',
          -1,
          kind: 'operation_outcome',
          outcome: 'succeeded',
          fields: {'lifecycle': 'background_task', 'lifecycle_id': 'task'},
        ),
        'stage': 'worker',
        'message': '中' * 500,
      },
    ];
    final full = _raw(_render(rows));
    expect(
      full.singleWhere((r) => r['eventId'] == 'start')['terminalEventId'],
      'terminal',
    );
    var omitted = false;
    var retained = false;
    for (final budget in [1024, 2048, 4096, 8192]) {
      final report = _render(rows, budget: budget);
      expect(utf8.encode(report).length, lessThanOrEqualTo(budget));
      final ids = _raw(report).map((r) => r['eventId']).toSet();
      expect(ids.contains('start'), ids.contains('terminal'));
      omitted |= ids.isEmpty;
      retained |= ids.contains('start');
    }
    expect(omitted, isTrue);
    expect(retained, isTrue);
  });
}
