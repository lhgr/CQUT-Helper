import 'package:material_ui/material_ui.dart';

class MineUserInfoCard extends StatelessWidget {
  final String realName;
  final String username;
  final String campusName;

  const MineUserInfoCard({
    super.key,
    required this.realName,
    required this.username,
    required this.campusName,
  });

  @override
  Widget build(BuildContext context) {
    final initial = realName.isNotEmpty
        ? String.fromCharCode(realName.runes.first)
        : '?';
    final initialStyle = Theme.of(context).textTheme.titleLarge
        ?.copyWith(color: Theme.of(context).colorScheme.onPrimary);
    final initialMetrics = TextPainter(
      text: TextSpan(
        text: initial,
        style: DefaultTextStyle.of(context).style.merge(initialStyle),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();
    final initialSize = initialMetrics.width > initialMetrics.height
        ? initialMetrics.width
        : initialMetrics.height;
    final avatarSize = (initialSize + 16).clamp(52.0, double.infinity);
    initialMetrics.dispose();
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: Center(child: Text(initial, style: initialStyle)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        realName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      SizedBox(height: 4),
                      Text(
                        "学号：$username",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (campusName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          campusName,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
