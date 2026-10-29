import 'package:cqut_helper/pages/Settings/app_settings_page.dart';
import 'package:cqut_helper/pages/MessageCenter/message_center_page.dart';
import 'package:material_ui/material_ui.dart';

import 'mine_logout_dialog.dart';
import 'mine_menu_item.dart';

class MineMenuSection extends StatelessWidget {
  const MineMenuSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              MineMenuItem(
                icon: Icons.notifications_none_rounded,
                title: '消息中心',
                subtitle: '课表变更记录与应用公告',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MessageCenterPage(),
                  ),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              MineMenuItem(
                icon: Icons.settings_outlined,
                title: '设置',
                subtitle: '课表、提醒、外观与存储',
                onTap: () => openAppSettings(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              showMineLogoutDialog(context);
            },
            icon: const Icon(Icons.logout),
            label: const Text("退出登录"),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
