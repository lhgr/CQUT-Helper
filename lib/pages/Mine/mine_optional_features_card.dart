import 'package:cqut_helper/manager/onboarding_manager.dart';
import 'package:cqut_helper/pages/Guide/usage_guide_page.dart';
import 'package:cqut_helper/pages/Settings/app_settings_page.dart';
import 'package:material_ui/material_ui.dart';

class MineOptionalFeaturesCard extends StatelessWidget {
  const MineOptionalFeaturesCard({super.key, this.manager});

  final OnboardingManager? manager;

  @override
  Widget build(BuildContext context) {
    final onboarding = manager ?? OnboardingManager.instance;
    return AnimatedBuilder(
      animation: onboarding,
      builder: (context, _) {
        if (!onboarding.showOptionalFeatures) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '按需设置',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭推荐',
                        onPressed: onboarding.dismissOptionalFeatures,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  _OptionalFeatureEntry(
                    icon: Icons.notifications_active_outlined,
                    title: '课前提醒',
                    description: '上课前收到提醒。',
                    action: '去设置',
                    onTap: () => openAppSettings(
                      context,
                      section: AppSettingsSection.notifications,
                    ),
                  ),
                  const Divider(height: 1),
                  _OptionalFeatureEntry(
                    icon: Icons.widgets_outlined,
                    title: '桌面小组件',
                    description: '在手机桌面查看课程。',
                    action: '查看添加方法',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const UsageGuidePage(
                          initialChapter: UsageGuideChapter.widgets,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OptionalFeatureEntry extends StatelessWidget {
  const _OptionalFeatureEntry({
    required this.icon,
    required this.title,
    required this.description,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, color: colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        action,
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: colors.primary),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: colors.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
