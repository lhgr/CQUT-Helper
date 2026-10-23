import 'dart:convert';

/// Plain values only, so rendering can run outside the UI isolate.
class DiagnosticReportInput {
  const DiagnosticReportInput({
    required this.records,
    required this.budget,
    required this.now,
    required this.version,
    required this.device,
    required this.sessionId,
    required this.dropped,
    required this.writeErrors,
  });
  final List<Map<String, Object?>> records;
  final int budget, dropped, writeErrors;
  final DateTime now;
  final String version, device, sessionId;
}

Map<String, int> diagnosticReportStatistics(List<Map<String, Object?>> rows) {
  var original = 0,
      repeated = 0,
      warnings = 0,
      errors = 0,
      fatals = 0,
      unknown = 0,
      allWarnings = 0,
      allErrors = 0,
      allFatals = 0,
      attempts = 0,
      failedAttempts = 0;
  final roots = <String>{},
      operations = <String>{},
      inferredOperations = <String>{};
  const knownKinds = {
    'incident',
    'error',
    'outcome',
    'derived',
    'attempt',
    'operation',
    'operation_outcome',
    'recovery',
    'retry_decision',
    'breadcrumb',
    'diagnostic',
    'dropped',
  };
  for (final row in rows) {
    final kind = row['kind'];
    final summary = kind == 'summary';
    final count = summary ? (row['repeatCount'] as num?)?.toInt() ?? 0 : 1;
    if (kind != 'dropped') original += count;
    final countedKind = summary ? row['summarizedKind'] : kind;
    var countRootLevel = true;
    if (!knownKinds.contains(countedKind)) {
      unknown += count;
    }
    if (countedKind == 'attempt') {
      attempts += count;
      if (row['outcome'] == 'failed') failedAttempts += count;
    }
    switch (row['level']) {
      case 'warn':
        allWarnings += count;
      case 'error':
        allErrors += count;
      case 'fatal':
        allFatals += count;
    }
    if (countedKind == 'error' || countedKind == 'incident') {
      if (summary) {
        // Legacy compressed roots cannot be recovered as individual IDs.
        repeated += count;
      } else {
        final id =
            (row['rootEventId'] ?? row['eventId'] ?? 'unknown-${roots.length}')
                .toString();
        countRootLevel = roots.add(id);
        if (countRootLevel && countedKind == 'incident') {
          final attemptCount = (row['attempts'] as num?)?.toInt() ?? 1;
          if (attemptCount > 1) repeated += attemptCount - 1;
        }
      }
      if (countRootLevel) {
        switch (row['level']) {
          case 'warn':
            warnings += count;
          case 'error':
            errors += count;
          case 'fatal':
            fatals += count;
        }
      }
    }
    if ({'error', 'incident', 'outcome', 'derived'}.contains(countedKind) ||
        (countedKind == 'attempt' && row['outcome'] == 'failed')) {
      final id = row['operationId'];
      if (id is String && id.isNotEmpty) {
        if (row['operationInferred'] == true) {
          inferredOperations.add(id);
        } else {
          operations.add(id);
        }
      }
    }
  }
  return {
    'originalEventCount': original,
    'rootErrorCount': roots.length,
    'repeatedOccurrenceCount': repeated,
    'affectedOperationCount': operations.length,
    'inferredOperationCount': inferredOperations.length,
    'warning': warnings,
    'error': errors,
    'fatal': fatals,
    'unknownEventCount': unknown,
    'allEventWarningCount': allWarnings,
    'allEventErrorCount': allErrors,
    'allEventFatalCount': allFatals,
    'attemptCount': attempts,
    'failedAttemptCount': failedAttempts,
  };
}

String renderDiagnosticReport(DiagnosticReportInput input) {
  if (input.budget < 1024) throw ArgumentError('诊断导出上限至少需要 1 KiB');
  final cutoff = input.now.subtract(const Duration(days: 3));
  final records = input.records.where((row) {
    final at = DateTime.tryParse(row['timestamp']?.toString() ?? '');
    return at != null && !at.isBefore(cutoff);
  }).toList()..sort(_compare);
  final stats = diagnosticReportStatistics(records);
  final groups = <String, Map<String, Object?>>{};
  final categories = <String, int>{}, modules = <String, int>{};
  final groupedRootIds = <String>{};
  for (final row in records.where(
    (r) => r['kind'] == 'error' || r['kind'] == 'incident',
  )) {
    final rootId = (row['rootEventId'] ?? row['eventId']).toString();
    if (!groupedRootIds.add(rootId)) continue;
    final key = (row['fingerprint'] ?? row['errorCategory'] ?? 'unknown')
        .toString();
    final group = groups.putIfAbsent(
      key,
      () => {
        'fingerprint': key,
        'category': row['errorCategory'] ?? 'UNKNOWN_ERROR',
        'module': row['module'],
        'stage': row['stage'],
        'rootCount': 0,
        'firstSeen': row['timestamp'],
        'lastSeen': row['timestamp'],
        'rootEventIds': <String>[],
        'operationIds': <String>[],
        'relatedEventIds': <String>[],
        'recoveryEventIds': <String>[],
        'attemptEventIds': <String>[],
      },
    );
    group['rootCount'] = (group['rootCount'] as int) + 1;
    group['lastSeen'] = row['timestamp'];
    final rootIds = group['rootEventIds'] as List<String>;
    if (rootIds.length < 12) rootIds.add(rootId);
    final operationIds = group['operationIds'] as List<String>;
    final operationId = row['operationId']?.toString();
    if (operationId != null &&
        operationIds.length < 12 &&
        !operationIds.contains(operationId)) {
      operationIds.add(operationId);
    }
    final category = (row['errorCategory'] ?? 'UNKNOWN_ERROR').toString();
    categories[category] = (categories[category] ?? 0) + 1;
    final module = (row['module'] ?? 'unknown').toString();
    modules[module] = (modules[module] ?? 0) + 1;
  }
  for (final group in groups.values.take(20)) {
    final rootIds = group['rootEventIds'] as List<String>;
    for (final row in records) {
      final recoveryRoot =
          row['resolvesIncidentId'] ??
          (row['fields'] as Map?)?['related_root_event_id'];
      if (row['kind'] == 'recovery' && rootIds.contains(recoveryRoot)) {
        final ids = group['recoveryEventIds'] as List<String>;
        if (ids.length < 12) ids.add(row['eventId'].toString());
      } else if (row['kind'] == 'attempt' &&
          rootIds.contains(row['rootEventId'])) {
        final ids = group['attemptEventIds'] as List<String>;
        if (ids.length < 12) ids.add(row['eventId'].toString());
      } else if ((row['kind'] == 'outcome' ||
              row['kind'] == 'derived' ||
              row['kind'] == 'retry_decision') &&
          rootIds.contains(row['rootEventId'])) {
        final ids = group['relatedEventIds'] as List<String>;
        if (ids.length < 12) ids.add(row['eventId'].toString());
      }
    }
  }
  // Attribution is intentionally bounded independently of the raw evidence.
  final attribution = groups.values.take(20).map(jsonEncode).join('\n');
  final header =
      'CQUT 完整诊断\n一、诊断摘要\n'
      '导出时间: ${input.now.toIso8601String()}\n版本: ${input.version}\n设备: ${input.device}\n'
      '会话: ${input.sessionId}\n保留期限: 3 天\n'
      '覆盖时间: ${records.isEmpty ? '无记录' : '${records.first['timestamp']} 至 ${records.last['timestamp']}'}\n'
      '错误汇总（根因等级）: warning=${stats['warning']} error=${stats['error']} fatal=${stats['fatal']}\n'
      '${jsonEncode(stats)}\n当前会话队列丢弃: ${input.dropped} 写入失败: ${input.writeErrors}\n'
      '保留记录中的队列丢弃合计: ${records.fold<int>(0, (n, row) => n + ((row['droppedCount'] as num?)?.toInt() ?? 0))}\n'
      '分类频率（根因）: ${jsonEncode(categories)}\n模块频率（根因）: ${jsonEncode(modules)}\n'
      '统计范围为当前保留记录；旧记录缺少语义时计入 unknownEventCount。\n'
      '二、错误分组与关联\n${attribution.isEmpty ? '暂无异常根因' : attribution}\n'
      '三、原始数据（JSONL）\n'
      'operationId 关联操作，rootEventId/causeEventId 关联异常根因，stackReferenceEventId 仅复用堆栈。\n';
  const omission = '\n[截断] 体积达到上限，已优先保留最近完整异常记录。\n';
  // For tiny caller budgets, keep the envelope and raw section usable.
  var prefix = header;
  if (_bytes(prefix) + _bytes(omission) >= input.budget) {
    prefix =
        'CQUT 完整诊断\n一、诊断摘要\n${jsonEncode(stats)}\n二、错误分组与关联\n[截断]\n三、原始数据（JSONL）\n';
  }
  final byId = {
    for (final row in records)
      if (row['eventId'] is String) row['eventId'] as String: row,
  };
  Map<String, Object?> annotated(Map<String, Object?> row) => {
    ...row,
    if (row['rootEventId'] != null && !byId.containsKey(row['rootEventId']))
      'rootMissing': row['kind'] == 'attempt'
          ? '重试尚未结束或根因未保留'
          : '根因已超出运行日志保留范围',
    if (row['stackReferenceEventId'] != null &&
        !byId.containsKey(row['stackReferenceEventId']))
      'stackReferenceMissing': '堆栈模板已超出运行日志保留范围',
    if (row['causeEventId'] != null && !byId.containsKey(row['causeEventId']))
      'causeMissing': '原因事件未保留或重试尚未结束',
    if ((row['fields'] as Map?)?['related_root_event_id'] != null &&
        !byId.containsKey((row['fields'] as Map?)?['related_root_event_id']))
      'recoveryRootMissing': '恢复关联的根因已超出运行日志保留范围',
  };
  final selected = <Map<String, Object?>>[],
      included = <Map<String, Object?>>{};
  var used = _bytes(prefix) + _bytes(omission);
  int priority(Map<String, Object?> row) {
    if ({'incident', 'error'}.contains(row['kind'])) return 0;
    if (row['rootEventId'] != null ||
        row['causeEventId'] != null ||
        row['kind'] == 'recovery') {
      return 1;
    }
    if (row['kind'] == 'operation_outcome') return 2;
    return 3;
  }

  final candidates = records.reversed.toList()
    ..sort((a, b) {
      final order = priority(a).compareTo(priority(b));
      return order != 0 ? order : _compare(b, a);
    });
  for (final row in candidates) {
    if (included.contains(row)) continue;
    final group = <Map<String, Object?>>[], visited = <Map<String, Object?>>{};
    void add(Map<String, Object?> entry) {
      if (included.contains(entry) || !visited.add(entry)) return;
      for (final key in [
        'rootEventId',
        'causeEventId',
        'stackReferenceEventId',
        'resolvesIncidentId',
        'firstAttemptEventId',
        'lastAttemptEventId',
      ]) {
        final dependency = byId[entry[key]];
        if (dependency != null && !identical(dependency, entry)) {
          add(dependency);
        }
      }
      final recoveryRoot =
          byId[(entry['fields'] as Map?)?['related_root_event_id']];
      if (recoveryRoot != null) add(recoveryRoot);
      group.add(entry);
    }

    add(row);
    final size = group.fold<int>(
      0,
      (n, entry) => n + _bytes('${jsonEncode(annotated(entry))}\n'),
    );
    if (used + size > input.budget) continue;
    used += size;
    selected.addAll(group);
    included.addAll(group);
  }
  selected.sort(_compare);
  return '$prefix${selected.map((row) => '${jsonEncode(annotated(row))}\n').join()}'
      '${selected.length < records.length ? omission : ''}';
}

int _bytes(String value) => utf8.encode(value).length;
int _compare(Map<String, Object?> a, Map<String, Object?> b) {
  final order = DateTime.parse(a['timestamp'].toString())
      .compareTo(DateTime.parse(b['timestamp'].toString()));
  if (order != 0) return order;
  if (a['sessionId'] != null &&
      a['sessionId'] == b['sessionId'] &&
      a['sequence'] is num &&
      b['sequence'] is num) {
    final sequenceOrder = (a['sequence'] as num).compareTo(
      b['sequence'] as num,
    );
    if (sequenceOrder != 0) return sequenceOrder;
  }
  return (a['eventId'] ?? '').toString().compareTo(
    (b['eventId'] ?? '').toString(),
  );
}
