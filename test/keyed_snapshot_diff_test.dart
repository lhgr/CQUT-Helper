import 'package:cqut_helper/utils/keyed_snapshot_diff.dart';
import 'package:flutter_test/flutter_test.dart';

class _Item {
  const _Item(this.key, this.value);
  final String key;
  final String value;

  @override
  String toString() => '$key=$value';
}

void main() {
  _Item i(String key, [String? value]) => _Item(key, value ?? key);

  test('all new items are added when previous is empty', () {
    final diff = diffByKey<_Item>(
      previous: const [],
      current: [i('a'), i('b')],
      keyOf: (e) => e.key,
      differs: (a, b) => a.value != b.value,
    );
    expect(diff.added, hasLength(2));
    expect(diff.removed, isEmpty);
    expect(diff.changed, isEmpty);
    expect(diff.hasChanges, isTrue);
  });

  test('no changes returns an empty diff', () {
    final diff = diffByKey<_Item>(
      previous: [i('a', 'x'), i('b', 'y')],
      current: [i('a', 'x'), i('b', 'y')],
      keyOf: (e) => e.key,
      differs: (a, b) => a.value != b.value,
    );
    expect(diff.hasChanges, isFalse);
  });

  test('removed items are detected', () {
    final diff = diffByKey<_Item>(
      previous: [i('a'), i('b'), i('c')],
      current: [i('a')],
      keyOf: (e) => e.key,
      differs: (a, b) => a.value != b.value,
    );
    expect(diff.removed.map((e) => e.key), {'b', 'c'});
    expect(diff.added, isEmpty);
    expect(diff.changed, isEmpty);
  });

  test('changed items are detected via differs predicate', () {
    final diff = diffByKey<_Item>(
      previous: [i('a', 'old')],
      current: [i('a', 'new')],
      keyOf: (e) => e.key,
      differs: (a, b) => a.value != b.value,
    );
    expect(diff.changed, hasLength(1));
    expect(diff.changed.single.value, 'new');
    expect(diff.added, isEmpty);
    expect(diff.removed, isEmpty);
  });

  test('added, removed, and changed can all appear together', () {
    final diff = diffByKey<_Item>(
      previous: [i('a', 'old'), i('b'), i('c')],
      current: [i('a', 'new'), i('b'), i('d')],
      keyOf: (e) => e.key,
      differs: (a, b) => a.value != b.value,
    );
    expect(diff.added.single.key, 'd');
    expect(diff.removed.single.key, 'c');
    expect(diff.changed.single.key, 'a');
  });
}
