import 'package:flutter/material.dart';

bool shouldShowScheduleReturnWeekButton({
  required String displayedWeek,
  required String? displayedTerm,
  required String? actualCurrentWeek,
  required String? actualCurrentTerm,
  required bool displayedScheduleCoversToday,
}) {
  final actualWeek = (actualCurrentWeek ?? '').trim();
  final actualTerm = (actualCurrentTerm ?? '').trim();
  if (actualWeek.isEmpty) return !displayedScheduleCoversToday;
  if (displayedWeek.trim() != actualWeek) return true;
  return actualTerm.isNotEmpty && (displayedTerm ?? '').trim() != actualTerm;
}

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
