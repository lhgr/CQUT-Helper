import 'package:cqut_helper/manager/onboarding_manager.dart';
import 'package:material_ui/material_ui.dart';

class ScheduleOnboardingHintVisibility extends StatelessWidget {
  final OnboardingManager manager;
  final bool readyToShow;
  final bool hasInlineNotices;
  final bool Function() hasCourses;

  const ScheduleOnboardingHintVisibility({
    super.key,
    required this.manager,
    required this.readyToShow,
    required this.hasInlineNotices,
    required this.hasCourses,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: manager,
    builder: (context, _) {
      if (!readyToShow || hasInlineNotices || !manager.showScheduleHint) {
        return const SizedBox.shrink();
      }
      return ScheduleOnboardingHint(
        hasCourses: hasCourses(),
        onDismiss: () {
          manager.dismissScheduleHint();
        },
      );
    },
  );
}

class ScheduleOnboardingHint extends StatelessWidget {
  final bool hasCourses;
  final VoidCallback onDismiss;

  const ScheduleOnboardingHint({
    super.key,
    required this.hasCourses,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.lightbulb_outline,
                  color: colors.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasCourses ? '点顶部周次切换课表，点课程查看详情。' : '当前周没有课程，点顶部周次查看其他周。',
                  style: TextStyle(
                    color: colors.onSecondaryContainer,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 48),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('知道了'),
            ),
          ),
        ],
      ),
    );
  }
}
