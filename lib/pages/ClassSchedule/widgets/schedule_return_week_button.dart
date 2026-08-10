import 'package:flutter/material.dart';

class ScheduleReturnWeekButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool transparentBackground;

  const ScheduleReturnWeekButton({
    super.key,
    required this.onPressed,
    required this.transparentBackground,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FloatingActionButton(
      onPressed: onPressed,
      tooltip: '返回本周',
      backgroundColor: transparentBackground ? Colors.transparent : null,
      foregroundColor: transparentBackground
          ? colorScheme.onSurfaceVariant
          : null,
      shape: transparentBackground
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: colorScheme.outlineVariant.withAlpha(120),
              ),
            )
          : null,
      child: const Icon(Icons.today),
    );
  }
}
