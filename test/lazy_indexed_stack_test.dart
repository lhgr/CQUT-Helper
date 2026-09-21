import 'package:cqut_helper/pages/Main/Main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('仅初始化当前页，切换后初始化一次并保留已初始化页', (tester) async {
    final initializedIndexes = <int>[];
    final builders = List<Widget Function()>.generate(3, (index) {
      return () => _InitTracker(
        index: index,
        onInit: () => initializedIndexes.add(index),
      );
    });

    await tester.pumpWidget(
      MaterialApp(home: LazyIndexedStack(index: 1, childBuilders: builders)),
    );

    expect(initializedIndexes, [1]);

    await tester.pumpWidget(
      MaterialApp(home: LazyIndexedStack(index: 2, childBuilders: builders)),
    );
    expect(initializedIndexes, [1, 2]);

    await tester.pumpWidget(
      MaterialApp(home: LazyIndexedStack(index: 0, childBuilders: builders)),
    );
    expect(initializedIndexes, [1, 2, 0]);

    await tester.pumpWidget(
      MaterialApp(home: LazyIndexedStack(index: 1, childBuilders: builders)),
    );
    expect(initializedIndexes, [1, 2, 0]);
  });
}

class _InitTracker extends StatefulWidget {
  final int index;
  final VoidCallback onInit;

  const _InitTracker({required this.index, required this.onInit});

  @override
  State<_InitTracker> createState() => _InitTrackerState();
}

class _InitTrackerState extends State<_InitTracker> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => Text('${widget.index}');
}
