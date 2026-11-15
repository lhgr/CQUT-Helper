/// Generic key-based diff for two snapshots of the same typed list.
///
/// Both [ScheduleNoticeRefreshPipeline] (via notice IDs) and
/// [ExamRepository] (via exam keys) follow the same detect-add/remove/change
/// pattern. This utility captures that pattern once so each caller only needs
/// to supply a key extractor and a field-equality predicate.
class KeyedSnapshotDiff<T> {
  const KeyedSnapshotDiff({
    required this.added,
    required this.removed,
    required this.changed,
  });

  final List<T> added;
  final List<T> removed;
  final List<T> changed;

  bool get hasChanges =>
      added.isNotEmpty || removed.isNotEmpty || changed.isNotEmpty;
}

/// Computes the diff between [previous] and [current] using [keyOf] to
/// identify matching items and [differs] to detect field-level changes.
KeyedSnapshotDiff<T> diffByKey<T>({
  required List<T> previous,
  required List<T> current,
  required String Function(T) keyOf,
  required bool Function(T prev, T next) differs,
}) {
  final prevByKey = {for (final item in previous) keyOf(item): item};
  final currByKey = {for (final item in current) keyOf(item): item};

  final added = <T>[];
  final removed = <T>[];
  final changed = <T>[];

  for (final item in current) {
    final prev = prevByKey[keyOf(item)];
    if (prev == null) {
      added.add(item);
    } else if (differs(prev, item)) {
      changed.add(item);
    }
  }
  for (final item in previous) {
    if (!currByKey.containsKey(keyOf(item))) removed.add(item);
  }

  return KeyedSnapshotDiff(added: added, removed: removed, changed: changed);
}
