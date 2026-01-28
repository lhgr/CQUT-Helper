import 'package:flutter/material.dart';

class ScheduleTimeColumn extends StatelessWidget {
  final double width;
  final double sessionHeight;
  final int sessionCount;

  const ScheduleTimeColumn({
    Key? key,
    this.width = 30.0,
    this.sessionHeight = 60.0,
    this.sessionCount = 12,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: List.generate(sessionCount, (index) {
          return Container(
            height: sessionHeight,
            alignment: Alignment.center,
            child: Text(
              "${index + 1}",
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }),
      ),
    );
  }
}
